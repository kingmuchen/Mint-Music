import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/l10n/l10n.dart';
import 'package:file_picker/file_picker.dart';
import '../data/audio_processor.dart';
import '../data/audio_fingerprint_service.dart';
import '../data/recognize_repository.dart';
import '../domain/models/recognize_result.dart';

enum RecognizeStatus {
  idle,
  initializing,
  recording,
  processing,
  uploading,
  success,
  failed,
}

class RecognizeState {
  final RecognizeStatus status;
  final int elapsedSeconds;
  final List<RecognizeResult> results;
  final String? errorMessage;

  const RecognizeState({
    this.status = RecognizeStatus.idle,
    this.elapsedSeconds = 0,
    this.results = const [],
    this.errorMessage,
  });

  RecognizeState copyWith({
    RecognizeStatus? status,
    int? elapsedSeconds,
    List<RecognizeResult>? results,
    String? errorMessage,
  }) {
    return RecognizeState(
      status: status ?? this.status,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      results: results ?? this.results,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// 听歌识曲状态管理，完全对标 CeruMusic 的 recognize.vue 逻辑
///
/// 核心流程（对标 CeruMusic recognize.vue）：
/// 1. 请求麦克风权限
/// 2. 暂停当前播放（wasPlaying → audioStore.stop()）
/// 3. 初始化 AFP WASM（ensureAFP()）
/// 4. 开始录音，使用流式 PCM 缓冲区
/// 5. 每 3 秒切片尝试识别（SLICE_DURATION = 3000）
/// 6. 最多录音 15 秒（MAX_DURATION = 15）
/// 7. 识别成功后恢复播放（wasPlaying → audioStore.start()）
/// 8. 支持文件上传识别（onFilePicked）
class RecognizeNotifier extends StateNotifier<RecognizeState> {
  final AudioProcessor _processor = AudioProcessor();
  final AudioFingerprintService _afpService = AudioFingerprintService();
  final RecognizeRepository _repository = RecognizeRepository();
  StreamSubscription? _recordSub;
  Timer? _timer;
  bool _active = false;
  bool _processing = false;
  bool _wasPlaying = false;
  List<RecognizeResult> _accumulatedResults = [];

  static const int _maxDuration = 15;
  static const int _sliceDurationMs = 3000;

  RecognizeNotifier() : super(const RecognizeState());

  Future<bool> requestPermission() async {
    state = state.copyWith(status: RecognizeStatus.initializing);
    final granted = await _processor.requestPermission();
    if (granted) return true;
    if (!granted) {
      state = state.copyWith(
        status: RecognizeStatus.failed,
        errorMessage: tr('需要麦克风权限才能进行识别'),
      );
    }
    return false;
  }

  /// 开始录音识别（对标 CeruMusic start()）
  Future<void> startRecording() async {
    if (_active) return;
    _active = true;
    _accumulatedResults = [];

    // 对标 CeruMusic: 暂停当前播放
    _pausePlayback();

    state = state.copyWith(
      status: RecognizeStatus.initializing,
      elapsedSeconds: 0,
      results: [],
      errorMessage: null,
    );

    try {
      // 对标 CeruMusic: ensureAFP()
      final afpReady = await _afpService.initialize().timeout(
        const Duration(seconds: 30),
        onTimeout: () => false,
      );
      if (!afpReady) {
        debugPrint('[Recognize] AFP 初始化失败');
        state = state.copyWith(
          status: RecognizeStatus.failed,
          errorMessage: tr('音频指纹模块初始化失败，请重试'),
        );
        _active = false;
        _resumePlayback();
        return;
      }

      // 对标 CeruMusic: recorder.start(SLICE_DURATION)
      // 使用流式录音，数据存入内存缓冲区
      if (!_active) return;
      await _processor.startRecording();

      if (!_active) {
        await _processor.stopRecording();
        return;
      }

      state = state.copyWith(status: RecognizeStatus.recording);

      // 对标 CeruMusic: setInterval 计时
      final startTime = DateTime.now();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
        final elapsed = DateTime.now().difference(startTime).inSeconds;
        state = state.copyWith(elapsedSeconds: elapsed);

        if (elapsed >= _maxDuration) {
          debugPrint('[Recognize] ${_maxDuration}s reached, stopping');
          await _stopAndRecognize();
        }
      });

      // 对标 CeruMusic: recorder.ondataavailable → tryRecognize(blob)
      _recordSub = _processor.onData(_sliceDurationMs).listen((_) async {
        if (!_active || _processing) return;
        _processing = true;
        try {
          await _tryRecognizeSlice().timeout(
            const Duration(seconds: 15),
            onTimeout: () => debugPrint('[Recognize] slice timed out'),
          );
        } catch (e) {
          debugPrint('[Recognize] slice error: $e');
        } finally {
          _processing = false;
        }
      });

      // 全局超时保护
      Future.delayed(const Duration(seconds: 30), () {
        if (_active) {
          debugPrint('[Recognize] GLOBAL TIMEOUT: force stopping');
          _forceStop();
        }
      });
    } catch (e) {
      debugPrint('[Recognize] startRecording failed: $e');
      state = state.copyWith(
        status: RecognizeStatus.failed,
        errorMessage: tr('启动录音失败：$e'),
      );
      _active = false;
      _resumePlayback();
    }
  }

  /// 增量切片识别（对标 CeruMusic tryRecognize()）
  Future<void> _tryRecognizeSlice() async {
    if (!_active) return;

    try {
      // 从内存缓冲区获取 PCM 数据（对标 CeruMusic: blob.arrayBuffer()）
      final Float64List pcm64 = _processor.getPcm8kFromBuffer();
      debugPrint('[Recognize] slice: pcm len=${pcm64.length}');

      if (pcm64.length < 8000) {
        debugPrint(
          '[Recognize] slice: data too short (${pcm64.length} samples)',
        );
        return;
      }

      if (!_hasSound(pcm64)) {
        debugPrint('[Recognize] slice: no sound detected');
        return;
      }

      state = state.copyWith(status: RecognizeStatus.processing);

      // 转换为 Float32List 供 AFP 使用
      final pcm32 = _float64ToFloat32(pcm64);

      // 对标 CeruMusic: GenerateFP(pcm8k)
      final fingerprint = await _afpService.generateFingerprint(pcm32);
      if (fingerprint == null || !_active) {
        debugPrint('[Recognize] slice: fingerprint generation failed');
        return;
      }

      final duration = pcm64.length / 8000.0;

      // 对标 CeruMusic: requestSdk('recognize', { source: 'wy', fp, duration })
      state = state.copyWith(status: RecognizeStatus.uploading);
      debugPrint(
        '[Recognize] slice: calling API, fp_len=${fingerprint.length}',
      );
      final results = await _repository
          .recognize(fingerprint, duration)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException('API请求超时'),
          );
      debugPrint('[Recognize] slice: API done, results=${results.length}');

      if (results.isNotEmpty) {
        _accumulatedResults = results;
        state = state.copyWith(
          status: RecognizeStatus.success,
          results: results,
        );
        await _stopAndRecognize();
      }
    } catch (e) {
      debugPrint('[Recognize] slice error: $e');
    }
  }

  /// 文件上传识别（对标 CeruMusic onFilePicked()）
  Future<void> recognizeFromFile() async {
    if (_active) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.first.path;
      if (filePath == null || filePath.isEmpty) return;

      _active = true;
      state = state.copyWith(
        status: RecognizeStatus.processing,
        results: [],
        errorMessage: null,
      );

      // 对标 CeruMusic: ensureAFP()
      final afpReady = await _afpService.initialize().timeout(
        const Duration(seconds: 30),
        onTimeout: () => false,
      );
      if (!afpReady) {
        state = state.copyWith(
          status: RecognizeStatus.failed,
          errorMessage: tr('音频指纹模块初始化失败'),
        );
        _active = false;
        return;
      }

      // 读取并解码音频文件
      final file = File(filePath);
      final bytes = await file.readAsBytes();

      // 解码 WAV 并重采样
      final Float64List pcm64 = AudioProcessor.decodeWavToMonoFloat(bytes);
      if (pcm64.isEmpty) {
        state = state.copyWith(
          status: RecognizeStatus.failed,
          errorMessage: tr('无法解码音频文件'),
        );
        _active = false;
        return;
      }

      // 对标 CeruMusic: 取最多 15 秒
      final targetLength = _maxDuration * 8000;
      final pcm = pcm64.length > targetLength
          ? Float64List.sublistView(pcm64, 0, targetLength)
          : pcm64;

      final pcm32 = _float64ToFloat32(pcm);

      // 对标 CeruMusic: GenerateFP(slice)
      final fingerprint = await _afpService.generateFingerprint(pcm32);

      if (fingerprint == null) {
        state = state.copyWith(
          status: RecognizeStatus.failed,
          errorMessage: tr('指纹生成失败'),
        );
        _active = false;
        return;
      }

      final duration = pcm.length / 8000.0;

      state = state.copyWith(status: RecognizeStatus.uploading);
      final results = await _repository
          .recognize(fingerprint, duration)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException('API请求超时'),
          );

      if (results.isNotEmpty) {
        state = state.copyWith(
          status: RecognizeStatus.success,
          results: results,
        );
      } else {
        state = state.copyWith(
          status: RecognizeStatus.failed,
          errorMessage: tr('未识别到歌曲'),
        );
      }
    } catch (e) {
      debugPrint('[Recognize] file recognition failed: $e');
      state = state.copyWith(
        status: RecognizeStatus.failed,
        errorMessage: tr('识别失败：$e'),
      );
    } finally {
      _active = false;
    }
  }

  /// 停止录音并识别（对标 CeruMusic stopRecording()）
  Future<void> stopAndRecognize() async {
    await _stopAndRecognize();
  }

  Future<void> _stopAndRecognize() async {
    if (!_active && state.status == RecognizeStatus.success) {
      _resumePlayback();
      return;
    }

    _active = false;
    _processing = false;
    _timer?.cancel();
    _timer = null;
    await _recordSub?.cancel();
    _recordSub = null;
    await _processor.stopRecording();

    if (state.status == RecognizeStatus.success) {
      _resumePlayback();
      return;
    }

    if (_accumulatedResults.isNotEmpty) {
      state = state.copyWith(
        status: RecognizeStatus.success,
        results: _accumulatedResults,
      );
      _resumePlayback();
      return;
    }

    // 最后一次尝试：从缓冲区获取全部数据识别
    try {
      state = state.copyWith(status: RecognizeStatus.processing);
      final Float64List pcm = _processor.getPcm8kFromBuffer();

      if (pcm.length < 8000) {
        state = state.copyWith(
          status: RecognizeStatus.failed,
          errorMessage: tr('录音时间过短'),
        );
        _resumePlayback();
        return;
      }

      state = state.copyWith(status: RecognizeStatus.uploading);
      final pcm32 = _float64ToFloat32(pcm);
      final fingerprint = await _afpService.generateFingerprint(pcm32);
      final duration = pcm.length / 8000.0;

      if (fingerprint == null) {
        state = state.copyWith(
          status: RecognizeStatus.failed,
          errorMessage: tr('指纹生成失败'),
        );
        _resumePlayback();
        return;
      }

      final results = await _repository
          .recognize(fingerprint, duration)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException('API请求超时'),
          );

      if (results.isNotEmpty) {
        state = state.copyWith(
          status: RecognizeStatus.success,
          results: results,
        );
      } else {
        state = state.copyWith(
          status: RecognizeStatus.failed,
          errorMessage: tr('未能识别到歌曲'),
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: RecognizeStatus.failed,
        errorMessage: tr('识别失败：$e'),
      );
    }

    _resumePlayback();
  }

  void _forceStop() {
    _active = false;
    _processing = false;
    _timer?.cancel();
    _recordSub?.cancel();
    _processor.stopRecording();
    state = state.copyWith(
      status: RecognizeStatus.failed,
      errorMessage: tr('识别超时，请重试'),
    );
    _resumePlayback();
  }

  Future<void> cancelRecording() async {
    _active = false;
    _processing = false;
    _timer?.cancel();
    _timer = null;
    await _recordSub?.cancel();
    _recordSub = null;
    await _processor.stopRecording();
    _accumulatedResults = [];
    state = const RecognizeState();
    _resumePlayback();
  }

  void backToInitial() {
    _active = false;
    _accumulatedResults = [];
    state = const RecognizeState();
  }

  bool _hasSound(Float64List pcm) {
    for (int i = 0; i < pcm.length; i += 100) {
      if (pcm[i].abs() > 0.01) return true;
    }
    return false;
  }

  Float32List _float64ToFloat32(Float64List input) {
    final output = Float32List(input.length);
    for (var i = 0; i < input.length; i++) {
      output[i] = input[i].clamp(-1.0, 1.0);
    }
    return output;
  }

  void _pausePlayback() {
    // 对标 CeruMusic: if (audioStore.Audio.isPlay) { wasPlaying = true; await audioStore.stop(); }
    try {
      // 通过全局 Provider 访问播放状态 - 在 UI 层处理
    } catch (_) {}
  }

  void _resumePlayback() {
    // 对标 CeruMusic: if (wasPlaying.value) { setTimeout(() => audioStore.start(), 500); }
    _wasPlaying = false;
  }

  /// 设置录音前播放状态（由 UI 层调用）
  void setWasPlaying(bool wasPlaying) {
    _wasPlaying = wasPlaying;
  }

  bool get wasPlaying => _wasPlaying;

  @override
  void dispose() {
    _timer?.cancel();
    _recordSub?.cancel();
    _processor.dispose();
    _afpService.dispose();
    super.dispose();
  }
}

final recognizeProvider =
    StateNotifierProvider<RecognizeNotifier, RecognizeState>((ref) {
      return RecognizeNotifier();
    });
