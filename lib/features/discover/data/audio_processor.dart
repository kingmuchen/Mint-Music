import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';

class AudioProcessor {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;

  /// 录音期间的内存 PCM 缓冲区（16kHz 16bit 单声道原始数据）
  final List<int> _pcmBuffer = [];

  /// 录音流订阅
  StreamSubscription? _streamSub;

  /// 原始录音采样率
  int _sourceSampleRate = 16000;

  /// 切片通知控制器
  final StreamController<void> _sliceController = StreamController<void>.broadcast();
  Timer? _sliceTimer;

  bool get isRecording => _isRecording;

  /// 获取当前缓冲区中的 PCM 样本数
  int get bufferSampleCount => _pcmBuffer.length ~/ 2;

  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// 开始流式录音（对标 CeruMusic: MediaRecorder.start(SLICE_DURATION)）
  ///
  /// 使用 startStream 获取 PCM16 流式数据，避免文件锁定问题。
  /// 录音数据存入内存缓冲区，切片识别时从缓冲区读取。
  Future<void> startRecording() async {
    _pcmBuffer.clear();
    _sourceSampleRate = 16000;

    // 使用 startStream 获取 PCM16 流式数据
    final stream = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sourceSampleRate,
        numChannels: 1,
      ),
    );

    _isRecording = true;

    // 监听流式数据，存入内存缓冲区
    _streamSub = stream.listen(
      (Uint8List data) {
        // PCM16 数据：每个样本 2 字节
        _pcmBuffer.addAll(data);
      },
      onError: (e) {
        debugPrint('[AudioProcessor] stream error: $e');
      },
      onDone: () {
        debugPrint('[AudioProcessor] stream done');
      },
    );
  }

  /// 定时切片通知（对标 CeruMusic: recorder.ondataavailable）
  Stream<void> onData(int sliceMs) {
    _sliceTimer = Timer.periodic(Duration(milliseconds: sliceMs), (_) {
      if (_isRecording) {
        _sliceController.add(null);
      }
    });
    return _sliceController.stream;
  }

  /// 停止录音
  Future<void> stopRecording() async {
    _isRecording = false;
    _sliceTimer?.cancel();
    _sliceTimer = null;
    await _streamSub?.cancel();
    _streamSub = null;
    await _recorder.stop();
  }

  /// 从内存缓冲区获取重采样到 8kHz 的 PCM 数据
  ///
  /// 对标 CeruMusic: 每次切片时从累积的录音数据中取最后 15 秒
  Float64List getPcm8kFromBuffer({int targetRate = 8000, int maxSeconds = 15}) {
    if (_pcmBuffer.isEmpty) return Float64List(0);

    // 将 PCM16 字节转换为 Float64 样本
    final sampleCount = _pcmBuffer.length ~/ 2;
    if (sampleCount == 0) return Float64List(0);

    final samples = Float64List(sampleCount);
    for (var i = 0; i < sampleCount; i++) {
      final lo = _pcmBuffer[i * 2];
      final hi = _pcmBuffer[i * 2 + 1];
      // 16-bit signed little-endian
      int val = (hi << 8) | lo;
      if (val >= 32768) val -= 65536;
      samples[i] = val / 32768.0;
    }

    // 重采样到目标采样率
    final resampled = _resample(samples, _sourceSampleRate, targetRate);

    // 取最后 maxSeconds 秒的数据
    final maxSamples = maxSeconds * targetRate;
    if (resampled.length > maxSamples) {
      return Float64List.sublistView(resampled, resampled.length - maxSamples);
    }
    return resampled;
  }

  /// 从文件加载并重采样为 8kHz 单声道 Float64 PCM（用于文件上传识别）
  Future<Float64List> loadAndResampleFromFile(String wavPath, {int targetRate = 8000}) async {
    final file = File(wavPath);
    if (!await file.exists()) {
      debugPrint('[AudioProcessor] WAV file not found: $wavPath');
      return Float64List(0);
    }

    try {
      final bytes = await file.readAsBytes();
      return decodeWavToMonoFloat(bytes, targetRate: targetRate);
    } catch (e) {
      debugPrint('[AudioProcessor] loadAndResample error: $e');
      return Float64List(0);
    }
  }

  /// 解码 WAV 字节为单声道 Float64 PCM 并重采样
  static Float64List decodeWavToMonoFloat(Uint8List wavBytes, {int targetRate = 8000}) {
    if (wavBytes.length < 44) return Float64List(0);

    // 查找 "data" chunk（WAV 文件可能有额外的 chunk）
    int dataOffset = 12;
    int dataSize = 0;
    int fmtOffset = -1;

    while (dataOffset < wavBytes.length - 8) {
      final chunkId = String.fromCharCodes(wavBytes.sublist(dataOffset, dataOffset + 4));
      final chunkSize = _readLeUint32(wavBytes, dataOffset + 4);

      if (chunkId == 'fmt ') {
        fmtOffset = dataOffset + 8;
      } else if (chunkId == 'data') {
        dataSize = chunkSize;
        dataOffset += 8;
        break;
      }

      dataOffset += 8 + chunkSize;
      if (chunkSize % 2 != 0) dataOffset++;
    }

    if (fmtOffset < 0 || dataSize == 0) {
      return _decodeWavSimple(wavBytes, targetRate);
    }

    final numChannels = _readLeUint16(wavBytes, fmtOffset + 2);
    final sampleRate = _readLeUint32(wavBytes, fmtOffset + 4);
    final bitsPerSample = _readLeUint16(wavBytes, fmtOffset + 14);

    if (bitsPerSample <= 0 || numChannels <= 0) return Float64List(0);

    final bytesPerSample = bitsPerSample ~/ 8;
    if (bytesPerSample <= 0) return Float64List(0);

    final fileDataSize = wavBytes.length - dataOffset;
    final actualDataSize = dataSize > 0 ? min(dataSize, fileDataSize) : fileDataSize;
    if (actualDataSize <= 0) return Float64List(0);

    final totalSamples = actualDataSize ~/ (bytesPerSample * numChannels);

    final channelData = Float64List(totalSamples);
    for (var i = 0; i < totalSamples; i++) {
      final byteOffset = dataOffset + i * bytesPerSample * numChannels;
      if (byteOffset + bytesPerSample > wavBytes.length) break;

      double sample;
      if (bitsPerSample == 16) {
        sample = _readLeInt16(wavBytes, byteOffset).toDouble() / 32768.0;
      } else if (bitsPerSample == 32) {
        sample = _readLeInt32(wavBytes, byteOffset).toDouble() / 2147483648.0;
      } else if (bitsPerSample == 24) {
        sample = _readLeInt24(wavBytes, byteOffset).toDouble() / 8388608.0;
      } else if (bitsPerSample == 8) {
        sample = (wavBytes[byteOffset].toDouble() - 128.0) / 128.0;
      } else {
        sample = 0.0;
      }
      channelData[i] = sample;
    }

    return _resample(channelData, sampleRate, targetRate);
  }

  /// 简单 WAV 解析（回退方案）
  static Float64List _decodeWavSimple(Uint8List wavBytes, int targetRate) {
    if (wavBytes.length < 44) return Float64List(0);
    final numChannels = _readLeUint16(wavBytes, 22);
    final sampleRate = _readLeUint32(wavBytes, 24);
    final bitsPerSample = _readLeUint16(wavBytes, 34);
    if (bitsPerSample <= 0) return Float64List(0);
    final bytesPerSample = bitsPerSample ~/ 8;
    if (bytesPerSample <= 0 || numChannels <= 0) return Float64List(0);

    final dataSize = _readLeUint32(wavBytes, 40);
    final fileDataSize = wavBytes.length - 44;
    final actualDataSize = dataSize > 0 ? min(dataSize, fileDataSize) : fileDataSize;
    if (actualDataSize <= 0) return Float64List(0);

    final totalSamples = actualDataSize ~/ (bytesPerSample * numChannels);

    final channelData = Float64List(totalSamples);
    for (var i = 0; i < totalSamples; i++) {
      final byteOffset = 44 + i * bytesPerSample * numChannels;
      if (byteOffset + bytesPerSample > wavBytes.length) break;

      double sample;
      if (bitsPerSample == 16) {
        sample = _readLeInt16(wavBytes, byteOffset).toDouble() / 32768.0;
      } else if (bitsPerSample == 32) {
        sample = _readLeInt32(wavBytes, byteOffset).toDouble() / 2147483648.0;
      } else if (bitsPerSample == 8) {
        sample = (wavBytes[byteOffset].toDouble() - 128.0) / 128.0;
      } else {
        sample = 0.0;
      }
      channelData[i] = sample;
    }

    return _resample(channelData, sampleRate, targetRate);
  }

  /// 线性插值重采样
  static Float64List _resample(Float64List input, int fromRate, int toRate) {
    if (fromRate == toRate) return input;
    final ratio = toRate / fromRate;
    final outputLength = (input.length * ratio).round();
    final output = Float64List(outputLength);

    for (var i = 0; i < outputLength; i++) {
      final srcPos = i / ratio;
      final srcIndex = srcPos.floor();
      final frac = srcPos - srcIndex;
      if (srcIndex + 1 < input.length) {
        output[i] = input[srcIndex] * (1 - frac) + input[srcIndex + 1] * frac;
      } else if (srcIndex < input.length) {
        output[i] = input[srcIndex];
      }
    }
    return output;
  }

  static int _readLeUint16(Uint8List bytes, int offset) {
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  static int _readLeUint32(Uint8List bytes, int offset) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }

  static int _readLeInt16(Uint8List bytes, int offset) {
    final val = _readLeUint16(bytes, offset);
    if (val >= 32768) return val - 65536;
    return val;
  }

  static int _readLeInt24(Uint8List bytes, int offset) {
    final val = bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
    if (val >= 8388608) return val - 16777216;
    return val;
  }

  static int _readLeInt32(Uint8List bytes, int offset) {
    return _readLeUint32(bytes, offset);
  }

  void dispose() {
    _sliceTimer?.cancel();
    _sliceController.close();
    _streamSub?.cancel();
    _recorder.dispose();
  }
}
