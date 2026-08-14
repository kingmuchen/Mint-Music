import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../domain/models/song.dart';
import '../domain/models/playback_state.dart';
import '../domain/models/play_mode.dart';
import '../platform/audio_handler.dart';
import '../platform/audio_effect_service.dart';
import '../../../core/services/audio_service_init.dart';
import '../../library/application/recently_played_providers.dart';
import '../../plugin/application/music_source_manager.dart';
import '../../plugin/application/plugin_providers.dart';
import '../../plugin/domain/plugin_types.dart';
import '../../settings/application/settings_providers.dart';
import 'auto_switch_source_service.dart';

final audioHandlerProvider = Provider<MusicAudioHandler>((ref) {
  return audioHandler;
});

bool _hasPlayableUrl(String? url) => url != null && url.isNotEmpty;

final playbackControllerProvider =
    StateNotifierProvider<PlaybackController, PlaybackState>((ref) {
      final audioHandler = ref.watch(audioHandlerProvider);
      final musicSourceManager = ref.watch(musicSourceManagerProvider);
      final controller = PlaybackController(
        audioHandler,
        musicSourceManager,
        audioEffectService,
      );
      controller.onSongPlayed = (song) {
        ref.read(recentlyPlayedProvider.notifier).addToHistory(song);
      };

      controller.getQualityForSource = (sourceId) {
        final sourceQuality = ref.read(sourceQualityProvider);
        final globalQuality = ref.read(globalQualityProvider);
        final sourceName = kSourceIdToName[sourceId];
        if (sourceName != null && sourceQuality.containsKey(sourceName)) {
          return sourceQuality[sourceName]!;
        }
        return globalQuality;
      };
      controller.setAutoQualityDowngrade(
        ref.read(autoQualityDowngradeProvider),
      );
      controller.onEnsureMusicSourcesReady = () =>
          ref.read(pluginInitializedProvider.future);

      final sourceQuality = ref.read(sourceQualityProvider);
      final activeIds = _chineseNamesToSourceIds(sourceQuality.keys.toList());
      controller.setActiveSourceIds(activeIds);
      ref.listen(sourceQualityProvider, (prev, next) {
        controller.setActiveSourceIds(
          _chineseNamesToSourceIds(next.keys.toList()),
        );
      });

      ref.listen(rememberProgressProvider, (prev, next) {
        controller.setRememberProgress(next);
      });

      ref.listen(autoQualityDowngradeProvider, (prev, next) {
        controller.setAutoQualityDowngrade(next);
      });

      void syncAudioEffects() {
        controller.setAudioEffects(
          AudioEffectsConfig(
            masterEnabled: ref.read(audioEffectEnabledProvider),
            equalizerEnabled: ref.read(equalizerEnabledProvider),
            equalizerBands: List<double>.from(ref.read(equalizerBandsProvider)),
            bassBoostEnabled: ref.read(bassBoostEnabledProvider),
            bassBoostGain: ref.read(bassBoostGainProvider),
            surroundEnabled: ref.read(surroundEnabledProvider),
            surroundMode: ref.read(surroundModeProvider),
            balanceEnabled: ref.read(balanceEnabledProvider),
            balance: ref.read(balanceValueProvider),
            visualizerEnabled: ref.read(audioVisualizerEnabledProvider),
          ),
        );
      }

      ref.listen(audioEffectEnabledProvider, (_, __) => syncAudioEffects());
      ref.listen(equalizerEnabledProvider, (_, __) => syncAudioEffects());
      ref.listen(equalizerBandsProvider, (_, __) => syncAudioEffects());
      ref.listen(bassBoostEnabledProvider, (_, __) => syncAudioEffects());
      ref.listen(bassBoostGainProvider, (_, __) => syncAudioEffects());
      ref.listen(surroundEnabledProvider, (_, __) => syncAudioEffects());
      ref.listen(surroundModeProvider, (_, __) => syncAudioEffects());
      ref.listen(balanceEnabledProvider, (_, __) => syncAudioEffects());
      ref.listen(balanceValueProvider, (_, __) => syncAudioEffects());
      syncAudioEffects();

      // 播放记忆：保存／恢复进度
      ref
          .read(settingsServiceProvider.future)
          .then((svc) async {
            controller.setRememberProgress(svc.getRememberProgress());
            controller.setAutoQualityDowngrade(svc.getAutoQualityDowngrade());
            unawaited(controller.setSpeed(svc.getPlaybackSpeed()));
            controller.onSavePlaybackState = (data) {
              svc.setLastPlaybackStateJson(jsonEncode(data));
            };
            controller.onRestorePlaybackState = () {
              final raw = svc.getLastPlaybackStateJson();
              if (raw == null || raw.isEmpty) return null;
              try {
                return jsonDecode(raw) as Map<String, dynamic>;
              } catch (_) {
                return null;
              }
            };
            controller.onClearPlaybackState = () =>
                svc.clearLastPlaybackState();
            // 回调就绪后自动恢复上次播放会话
            // 直接从 SharedPreferences 读取音质，避免 provider 未初始化的竞态
            final persistedQuality = svc.getGlobalQuality();
            final persistedSourceQuality = svc.getSourceQuality();
            await controller.restoreLastSession(
              autoPlay: svc.getAutoPlay(),
              rememberProgress: svc.getRememberProgress(),
              quality: persistedQuality,
              sourceQualities: persistedSourceQuality,
            );
          })
          .catchError((e) {
            debugPrint('[PlaybackController] settingsService error: $e');
          });

      ref.onDispose(() => controller.dispose());
      return controller;
    });

// Song equality intentionally uses the stable queue ID. Cross-source fallback
// keeps that ID, so UI consumers need a separate signal for visible song
// metadata. Quality switching replaces only the transient audio URL, so it
// must not make player pages behave as if a new song was selected.
final currentSongIdentityProvider = Provider<int>((ref) {
  final song = ref.watch(playbackControllerProvider).currentSong;
  if (song == null) return 0;
  return Object.hashAll([
    song.id,
    song.source,
    song.title,
    song.artist,
    song.album,
    song.coverUrl,
    song.lyricUrl,
    song.lrc,
  ]);
});

const _chineseNameToSourceId = {
  '网易云': 'wy',
  'QQ音乐': 'tx',
  '酷狗': 'kg',
  '酷我': 'kw',
  '咪咕': 'mg',
};

const _sourceIdToChineseName = {
  'wy': '网易云音乐',
  'tx': 'QQ音乐',
  'kg': '酷狗音乐',
  'kw': '酷我音乐',
  'mg': '咪咕音乐',
  'local': '本地音乐',
};

String _getSourceName(String sourceId) {
  return _sourceIdToChineseName[sourceId] ?? sourceId;
}

List<String> _chineseNamesToSourceIds(List<String> names) {
  return names
      .map((n) => _chineseNameToSourceId[n] ?? '')
      .where((id) => id.isNotEmpty)
      .toList();
}

class PlaybackController extends StateNotifier<PlaybackState> {
  final MusicAudioHandler _audioHandler;
  final MusicSourceManager _musicSourceManager;
  final AudioEffectService _audioEffectService;
  late final AutoSwitchSourceService _autoSwitchService;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _bufferedSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription? _errorListenerSub;
  StreamSubscription<int?>? _audioSessionSub;

  void Function(Song)? onSongPlayed;
  void Function(String message, {Color? backgroundColor})? onMessage;
  String Function(String sourceId)? getQualityForSource;
  void Function(Map<String, dynamic> data)? onSavePlaybackState;
  Map<String, dynamic>? Function()? onRestorePlaybackState;
  VoidCallback? onClearPlaybackState;
  Future<void> Function()? onEnsureMusicSourcesReady;

  int _currentPlayRequestId = 0;
  int? _qualitySwitchRequestId;
  int _autoNextCount = 0;
  List<String> _activeSourceIds = [];
  bool _settingQueue = false;
  Duration _lastEmittedPosition = Duration.zero;
  static const Duration _positionThrottle = Duration(milliseconds: 200);

  bool _rememberProgress = true;
  bool _autoQualityDowngrade = false;
  bool _needsUrlRefresh = false;
  int? _pendingRestorePosition;
  String? _pendingRestoreSongId;
  Timer? _saveTimer;
  Timer? _loadingTimer;
  static const Duration _saveInterval = Duration(seconds: 5);
  static const Duration _loadingTimeout = Duration(seconds: 30);

  bool get _isSwitchingQuality =>
      _qualitySwitchRequestId != null &&
      _qualitySwitchRequestId == _currentPlayRequestId &&
      state.isLoading;

  /// 歌曲刚刚 natural complete 的标志。
  /// 设为 true 后，_playerStateSub 会在 completed→ready 过渡事件中
  /// 跳过 isPlaying 更新（因为 ExoPlayer 在 ENDED 状态下 playWhenReady
  /// 保持 true，seek(0) 后会错误地发出 playing=true 事件）。
  /// 带一个微任务周期后由 _playerStateSub 或 next() 清除。
  bool _justCompleted = false;

  /// CeruMusic 风格的自动下一首防重入标志。
  /// completed 事件中设为 true，Future.microtask 排空后执行 next()
  /// 前检查此标志。任何用户操作通过 _cancelPendingAutoNext() 清 false，
  /// 避免已入队的 microtask 仍然执行过期的 next()。
  bool _pendingAutoNext = false;

  void _cancelPendingAutoNext() {
    _pendingAutoNext = false;
  }

  PlaybackController(
    this._audioHandler,
    this._musicSourceManager,
    this._audioEffectService,
  ) : super(const PlaybackState()) {
    _autoSwitchService = AutoSwitchSourceService(
      musicSourceManager: _musicSourceManager,
      showMessage: (message, {backgroundColor}) {
        onMessage?.call(message, backgroundColor: backgroundColor);
      },
    );
    _init();
  }

  void setActiveSourceIds(List<String> sourceIds) {
    _activeSourceIds = sourceIds;
  }

  void setRememberProgress(bool enabled) {
    _rememberProgress = enabled;
    if (!enabled) {
      _stopSaveTimer();
    } else if (state.isPlaying) {
      _startSaveTimer();
    }
  }

  void setAutoQualityDowngrade(bool enabled) {
    _autoQualityDowngrade = enabled;
  }

  void setAudioEffects(AudioEffectsConfig config) {
    unawaited(_audioEffectService.apply(config));
  }

  void _savePlaybackState() {
    if (!_rememberProgress) return;
    final song = state.currentSong;
    if (song == null) return;
    final positionMs = state.position.inMilliseconds;
    if (positionMs <= 0) return;
    final persistedSong = _stripTransientPlaybackData(song);
    final persistedQueue = state.queue
        .map(_stripTransientPlaybackData)
        .toList();
    onSavePlaybackState?.call({
      'song': persistedSong.toJson(),
      'positionMs': positionMs,
      'queue': persistedQueue.map((s) => s.toJson()).toList(),
      'currentIndex': state.currentIndex,
      'currentQuality': state.currentQuality,
    });
  }

  /// Online music URLs and their headers often contain short-lived tokens.
  /// They must never survive process death; playback restoration always
  /// resolves a fresh URL from the original source metadata.
  Song _stripTransientPlaybackData(Song song) {
    if (song.source == 'local') return song;
    return song.copyWith(clearSourceUrl: true, clearSourceHeaders: true);
  }

  void _startSaveTimer() {
    _stopSaveTimer();
    _saveTimer = Timer.periodic(_saveInterval, (_) => _savePlaybackState());
  }

  void _stopSaveTimer() {
    _saveTimer?.cancel();
    _saveTimer = null;
  }

  /// 启动时恢复上次播放会话（CeruMusic 风格：仅恢复队列+UI，不获取 URL）
  Future<void> restoreLastSession({
    required bool autoPlay,
    required bool rememberProgress,
    String quality = '320k',
    Map<String, String> sourceQualities = const {},
  }) async {
    _loadingTimer?.cancel();
    _loadingTimer = null;
    if (!autoPlay && !rememberProgress) return;
    if (state.queue.isNotEmpty) return;

    final data = onRestorePlaybackState?.call();
    if (data == null) return;

    final songJson = data['song'] as Map<String, dynamic>?;
    if (songJson == null) return;

    final positionMs = data['positionMs'] as int? ?? 0;
    final savedSong = Song.fromJson(songJson);

    // 恢复完整队列
    List<Song> queue;
    final queueJson = data['queue'] as List<dynamic>?;
    int currentIndex = data['currentIndex'] as int? ?? 0;
    if (queueJson != null && queueJson.isNotEmpty) {
      queue = queueJson
          .map((s) => Song.fromJson(s as Map<String, dynamic>))
          .toList();
      if (currentIndex < 0 || currentIndex >= queue.length) {
        currentIndex = queue.indexWhere((s) => s.id == savedSong.id);
        if (currentIndex < 0) currentIndex = 0;
      }
    } else {
      queue = [savedSong];
      currentIndex = 0;
    }

    // 清除所有在线歌曲的临时 URL 和请求头，避免重启后复用已过期的
    // token。历史版本的记录也在此统一清理。
    queue = queue.map(_stripTransientPlaybackData).toList();
    final restoredSong = queue[currentIndex];

    // 恢复队列和 UI 状态（含音质），不获取 URL 不设音源（延迟到用户点击播放时）
    final restoredQuality = (data['currentQuality'] as String?) ?? quality;
    state = state.copyWith(
      queue: queue,
      currentIndex: currentIndex,
      currentSong: restoredSong,
      currentQuality: restoredQuality,
      isLoading: false,
      isPlaying: false,
    );

    // 保存待恢复的进度位置（CeruMusic: pendingRestorePosition）
    if (positionMs > 0) {
      _pendingRestorePosition = positionMs;
      _pendingRestoreSongId = restoredSong.id;
    }

    // 标记首次播放需刷新 URL
    _needsUrlRefresh = true;

    // 清除已恢复的记忆，只保留待恢复位置（由 _pendingRestorePosition 携带）
    // 注意：不清除 SharedPrefs，让进度持续保留到用户实际播放时才清除
    // 这样即使用户下次打开不播放，再下次也能继续进度

    // autoPlay：直接走 play() → _needsUrlRefresh → playSongAt → 获取最新 URL
    if (autoPlay) {
      await play();
    }
  }

  Future<void> _restoreAndPlay(Song song) async {
    // 用户实际开始播放时，清除已恢复的记忆（确保下次启动重新读取 SharedPrefs）
    onClearPlaybackState?.call();
    if (_rememberProgress) {
      // 照搬 CeruMusic：仅消费 restoreLastSession 设置的一次性进度标记
      // _pendingRestorePosition → 在 restoreLastSession 中设置，
      // 由 onClearPlaybackState 清除 SharedPrefs，仅在首次播放时可用。
      // 不设回退读取 SharedPrefs 的路径，避免重新播放同源同首歌时误续进度。
      if (_pendingRestorePosition != null && _pendingRestoreSongId == song.id) {
        final savedPos = _pendingRestorePosition!;
        _pendingRestorePosition = null;
        _pendingRestoreSongId = null;
        if (savedPos > 0) {
          await _audioHandler.seek(Duration(milliseconds: savedPos));
        }
      } else {
        // 照搬 CeruMusic（else 分支 pendingRestorePosition = 0）：
        // 非恢复目标歌曲播放时立即清除待恢复进度，避免后续误用
        _pendingRestorePosition = null;
        _pendingRestoreSongId = null;
      }
    }
    await _audioHandler.play();
  }

  Future<void> _ensureMusicSourcesReady() async {
    final ensureReady = onEnsureMusicSourcesReady;
    if (ensureReady == null) return;

    try {
      await ensureReady().timeout(_musicSourceReadyTimeout);
    } catch (error) {
      // Built-in sources are still available if a plugin has a load problem,
      // so do not block playback forever. The current-source URL resolver
      // below will perform its own controlled retry.
      debugPrint(
        '[PlaybackController] music source initialization wait failed: $error',
      );
    }
  }

  Future<List<PluginMusicUrlResult>> _resolveCurrentSourceUrlCandidates(
    Song song, {
    required String quality,
    required int requestId,
    Set<String> excludedUrls = const <String>{},
  }) async {
    Future<List<PluginMusicUrlResult>> resolveOnce() async {
      try {
        return await _musicSourceManager
            .getMusicUrlResultCandidates(
              song,
              quality: quality,
              excludedUrls: excludedUrls,
            )
            .timeout(_urlFetchTimeout);
      } catch (error) {
        debugPrint(
          '[PlaybackController] current-source URL resolve failed: '
          'source=${song.source} error=$error',
        );
        return const <PluginMusicUrlResult>[];
      }
    }

    var candidates = await resolveOnce();
    if (candidates.isNotEmpty || _currentPlayRequestId != requestId) {
      return candidates;
    }

    // A cold launch can race plugin engine startup or hit a transient
    // provider request failure. Retry the original source once before the
    // cross-source fallback declares that source unavailable.
    await Future.delayed(const Duration(milliseconds: 400));
    if (_currentPlayRequestId != requestId) {
      return const <PluginMusicUrlResult>[];
    }

    debugPrint(
      '[PlaybackController] retrying current-source URL: '
      'source=${song.source} quality=$quality',
    );
    candidates = await resolveOnce();
    return candidates;
  }

  /// 换源后从原进度继续播放（如暂停期间 URL 过期，恢复时触发换源的场景），
  /// 避免重头播放。resumePosition 为 0 或已超过歌曲时长时跳过。
  Future<void> _resumeFromPosition(Duration resumePosition) async {
    if (resumePosition <= Duration.zero) return;
    final duration = _audioHandler.currentDuration;
    if (duration != null && resumePosition >= duration) return;
    await _audioHandler.seek(resumePosition);
  }

  int get _autoNextLimit {
    if (state.queue.isEmpty) return 1;
    final limit = (state.queue.length * 0.3).floor();
    return limit < 1 ? 1 : limit;
  }

  bool get hasQueue => state.queue.isNotEmpty;

  void _init() {
    _audioSessionSub = _audioHandler.audioSessionIdStream.listen((sessionId) {
      unawaited(_audioEffectService.setSessionId(sessionId));
    });
    final currentSessionId = _audioHandler.currentAudioSessionId;
    if (currentSessionId != null) {
      unawaited(_audioEffectService.setSessionId(currentSessionId));
    }
    _positionSub = _audioHandler.positionStream.listen((position) {
      if (mounted) {
        final diff = (position - _lastEmittedPosition).abs();
        if (diff >= _positionThrottle) {
          _lastEmittedPosition = position;
          state = state.copyWith(position: position);
        }
      }
    });
    _bufferedSub = _audioHandler.bufferedPositionStream.listen((buffered) {
      if (mounted) {
        final diff = (buffered - state.buffered).abs();
        if (diff >= const Duration(seconds: 1)) {
          state = state.copyWith(buffered: buffered);
        }
      }
    });
    _durationSub = _audioHandler.durationStream.listen((duration) {
      if (mounted && duration != null && duration != Duration.zero) {
        state = state.copyWith(actualDuration: duration);
      }
    });
    _playerStateSub = _audioHandler.playerStateStream.listen((playerState) {
      if (!mounted) return;
      // 注意：这里不再用 _settingQueue 门控整个监听器。
      // 之前在 setQueue / playSongAt 期间整体忽略 playerStateStream，
      // 会导致 ready 等关键事件被丢弃，isPlaying / isLoading 长期错乱
      // （按钮卡在转圈、迷你播放器显示暂停态等）。
      // 这里改为始终响应 just_audio 的真实状态，仅在「当前歌曲尚未确定」的
      // 极短窗口内跳过 completed 自动切歌逻辑，避免误触发。
      final processingState = playerState.processingState;
      final isLoading = processingState == ProcessingState.loading;

      if (isLoading) {
        _loadingTimer ??= Timer(_loadingTimeout, () {
          if (mounted && state.isLoading) {
            debugPrint(
              '[PlaybackController] 加载超时（${_loadingTimeout.inSeconds}s），尝试跳过',
            );
            state = state.copyWith(isLoading: false, isPlaying: false);
            _tryAutoNext('播放加载超时');
          }
        });
      } else {
        _loadingTimer?.cancel();
        _loadingTimer = null;
      }

      final wasPlaying = state.isPlaying;

      if (processingState == ProcessingState.ready ||
          processingState == ProcessingState.buffering) {
        // _justCompleted 在 completed 处理器中设置。
        // 后续可能收到两类 ready 事件：
        //   A. ready(playing=false) — 单曲队列 next() 中 seek(0) 触发，
        //      不应更新 isPlaying（ExoPlayer 在 ENDED 下 playWhenReady
        //      保持 true，seek 后误报 playing=true）。
        //   B. ready(playing=true)  — 正常切歌后 play() 的确认信号，
        //      必须用于更新 isPlaying。
        //
        // 区分：playing=true 时清除标记并继续正常处理；
        // playing=false 时跳过 isPlaying 更新（只清 isLoading）。
        if (_justCompleted) {
          if (playerState.playing) {
            // 播放器确认正在播放 → 清除 completed 标记，继续正常处理
            _justCompleted = false;
          } else {
            state = state.copyWith(isLoading: false);
            return;
          }
        }
        // 关键修复：ready(playing=true) 也必须突破 _settingQueue 守卫。
        //
        // playSongAt 内 setAudioSource() 发出 ready(playing=false)，
        // 然后 _restoreAndPlay → play() 发出 ready(playing=true)。
        // 这两个事件都是微任务，在 _settingQueue 仍为 true 时被处理：
        //   · ready(playing=false) → 被守卫拦住 ✅（不应覆盖 isLoading:true）
        //   · ready(playing=true)  → 也被拦住 ❌ —— 这是 play() 的确认信号，
        //     丢了它 isPlaying 永远 false、isLoading 永远 true，
        //     只有等下次用户操作（如点击通知栏按钮）触发新事件才能恢复。
        //
        // 解决方案：playing=true 的事件总是处理，不受 _settingQueue 门控。
        if ((!_settingQueue && !_isSwitchingQuality) || playerState.playing) {
          state = state.copyWith(
            isPlaying: playerState.playing,
            isLoading: false,
          );
        }
      } else if (processingState == ProcessingState.loading) {
        state = state.copyWith(isLoading: true);
        // isPlaying 不变（play()/playSongAt() 已乐观设置）
      } else if (processingState == ProcessingState.completed) {
        debugPrint('[PlaybackController] 歌曲播放完成');
        _justCompleted = true;
        state = state.copyWith(isPlaying: false, isLoading: false);
        // 使用 Future.microtask 延迟 next() 到所有 pending 的
        // playerStateStream 事件（idle/loading 等）处理完毕之后。
        // 直接调用 next() 可能与之竞态，导致 playSongAt 被中断。
        if (!_settingQueue && !_pendingAutoNext) {
          _pendingAutoNext = true;
          Future.microtask(() {
            if (mounted && _pendingAutoNext) {
              _pendingAutoNext = false;
              next();
            }
          });
        }
        // 注意：不在设 _justCompleted=false；由 next() 或下次
        // playSongAt/seek 等明确清除，防止 seek 触发的 ready 事件
        // 用错误的 playing=true 覆盖 UI。
      } else if (processingState == ProcessingState.idle &&
          !playerState.playing) {
        // idle 但 playing=false 通常是停止 / 重置。
        // _settingQueue 期间（切歌、换源）just_audio 会短暂回到 idle，
        // 此时保留 playSongAt 设置的乐观 isPlaying / isLoading，避免提前清零导致
        // 按钮状态与实际播放不一致。
        if (!_settingQueue && !_isSwitchingQuality) {
          state = state.copyWith(isPlaying: false, isLoading: false);
        }
      }

      if (state.isPlaying != wasPlaying) {
        if (state.isPlaying) {
          _startSaveTimer();
        } else {
          _savePlaybackState();
          _stopSaveTimer();
        }
      }
    });

    // 通知栏控制回调（通知栏下一首/上一首按钮）
    _audioHandler.onSkipNext = () => next();
    _audioHandler.onSkipPrevious = () => previous();
  }

  int get _currentIndex {
    if (state.currentSong == null || state.queue.isEmpty) return -1;
    return state.queue.indexWhere((s) => s.id == state.currentSong!.id);
  }

  // ==================== 核心播放方法 ====================

  /// 播放指定索引的歌曲（照搬 CeruMusic playSong 逻辑）
  ///
  /// CeruMusic 的三层容错：
  /// 1. 原源 URL 获取成功 → 直接播放
  /// 2. 原源 URL 获取失败 → getCandidateSongs 换源
  /// 3. 播放器运行时 error → error listener 中 getCandidateSongs 换源
  static const Duration _urlFetchTimeout = Duration(seconds: 12);
  static const Duration _audioSetTimeout = Duration(seconds: 10);
  static const Duration _musicSourceReadyTimeout = Duration(seconds: 12);

  Future<void> playSongAt(int index) async {
    if (index < 0 || index >= state.queue.length) return;

    _cancelPendingAutoNext();
    // playSongAt 总是会重新加载音源（setAudioSource），恢复会话的
    // _needsUrlRefresh 标记随之失效。
    // 否则：启动恢复会话 → 搜索播放（setQueue 不清此标记）→ 暂停 →
    // play() 误判需要刷新 URL → 重新 playSongAt 加载音源 → 进度归零
    // （_pendingRestorePosition 已被 setQueue 清空，无法 seek 回原进度）。
    _needsUrlRefresh = false;
    _loadingTimer?.cancel();
    _loadingTimer = null;

    _savePlaybackState();

    _settingQueue = true;
    // 清除 completed 标记：新歌开始播放，后续的 ready 事件应正常处理
    _justCompleted = false;
    final requestId = ++_currentPlayRequestId;
    final song = state.queue[index];

    debugPrint(
      '[PlaybackController] playSongAt: ${song.title}, index=$index, requestId=$requestId',
    );

    // 照搬 CeruMusic：300ms 防抖，防止快速切歌导致并发请求混乱
    await Future.delayed(const Duration(milliseconds: 300));
    if (_currentPlayRequestId != requestId) return;

    _errorListenerSub?.cancel();
    _errorListenerSub = null;

    final sourceId = song.source ?? 'wy';
    final isLocal = sourceId == 'local';
    if (!isLocal) {
      await _ensureMusicSourcesReady();
      if (_currentPlayRequestId != requestId) return;
    }
    final initialDisplayCover = sourceId == 'kw'
        ? _musicSourceManager.getHighResolutionCoverUrl(song)
        : null;
    final initialSong =
        initialDisplayCover == null || initialDisplayCover == song.coverUrl
        ? song
        : song.copyWith(coverUrl: initialDisplayCover);
    if (!identical(initialSong, song)) {
      _replaceSongInQueue(index, initialSong);
    }
    final pendingCoverFuture =
        !isLocal &&
            ((song.coverUrl == null || song.coverUrl!.isEmpty) ||
                sourceId == 'kw')
        ? _musicSourceManager.getPic(
            song,
            preferBuiltIn: sourceId == 'kw',
            bypassCache: sourceId == 'kw',
          )
        : null;
    final defaultQuality = isLocal
        ? _getQualityFromSong(song)
        : (getQualityForSource?.call(sourceId) ?? _getQualityFromSong(song));
    // 仅当处于待恢复状态（重启后首次播放）时使用恢复的音质，否则走默认
    final isRestorePlay =
        _pendingRestorePosition != null && _pendingRestoreSongId == song.id;
    final quality = isRestorePlay && state.currentQuality.isNotEmpty
        ? state.currentQuality
        : defaultQuality;
    final availableQualities = isLocal
        ? <String>[quality]
        : _musicSourceManager.getSupportedQualitiesForSourceId(sourceId);
    if (!availableQualities.contains(quality)) {
      final fallback = availableQualities.isNotEmpty
          ? availableQualities.last
          : '320k';
      state = state.copyWith(
        currentIndex: index,
        currentSong: initialSong,
        position: Duration.zero,
        isLoading: true,
        currentQuality: fallback,
        availableQualities: availableQualities,
      );
    } else {
      state = state.copyWith(
        currentIndex: index,
        currentSong: initialSong,
        position: Duration.zero,
        isLoading: true,
        currentQuality: quality,
        availableQualities: availableQualities,
      );
    }

    try {
      Song currentSongToPlay = initialSong;
      // A previously resolved Kuwo URL may be the provider's permission
      // prompt. Re-resolve it so the normal MP3 candidate and duration check
      // can select a real song URL.
      String? urlToPlay = sourceId == 'kw' ? null : song.sourceUrl;
      var resolvedUrlCandidates = <PluginMusicUrlResult>[];

      if (isLocal && urlToPlay != null && urlToPlay.isNotEmpty) {
        try {
          await _audioHandler
              .setAudioSource(urlToPlay, song: currentSongToPlay)
              .timeout(_audioSetTimeout);
          await _restoreAndPlay(currentSongToPlay);
        } catch (_) {
          state = state.copyWith(isLoading: false, isPlaying: false);
          return;
        }
        _autoNextCount = 0;
        // 遵循 CeruMusic：不乐观设 isPlaying=true。
        // 由 _playerStateSub 的 ready(playing=true) 或
        // finally 中的 Future.microtask 根据实际播放器状态同步。
        state = state.copyWith(
          isLoading: false,
          currentSong: currentSongToPlay,
        );
        onSongPlayed?.call(currentSongToPlay);
        return;
      }

      if (!_hasPlayableUrl(urlToPlay)) {
        debugPrint('[PlaybackController] URL 为空，正在解析: ${song.title}');
        resolvedUrlCandidates = await _resolveCurrentSourceUrlCandidates(
          currentSongToPlay,
          quality: state.currentQuality,
          requestId: requestId,
        );
        urlToPlay = resolvedUrlCandidates.isEmpty
            ? null
            : resolvedUrlCandidates.first.url;
        if (_currentPlayRequestId != requestId) {
          // 已被新的播放请求取代；isLoading 由新请求管理，不在此重置以免覆盖。
          return;
        }

        if (urlToPlay != null && urlToPlay.isNotEmpty) {
          final result = resolvedUrlCandidates.firstWhere(
            (candidate) => candidate.url == urlToPlay,
            orElse: () => const PluginMusicUrlResult(url: ''),
          );
          currentSongToPlay = currentSongToPlay.copyWith(
            sourceUrl: urlToPlay,
            sourceHeaders: result.headers.isEmpty ? null : result.headers,
            sourceQuality: result.quality.isEmpty ? null : result.quality,
            clearSourceHeaders: result.headers.isEmpty,
            clearSourceQuality: result.quality.isEmpty,
          );
          _replaceSongInQueue(index, currentSongToPlay);
          if (result.quality.isNotEmpty) {
            state = state.copyWith(currentQuality: result.quality);
          }
        }
      }

      if ((urlToPlay == null || urlToPlay.isEmpty) &&
          _autoQualityDowngrade &&
          !isLocal) {
        final qualityFallbackSong = await _tryQualityFallbackAfterFailure(
          song: currentSongToPlay,
          index: index,
          requestId: requestId,
          resumePosition: Duration.zero,
          excludedUrls: const <String>{},
        );
        if (qualityFallbackSong != null) {
          onSongPlayed?.call(qualityFallbackSong);
          _errorListenerSub = _mountOneTimeErrorListener(
            requestId,
            index,
            qualityFallbackSong,
          );
          return;
        }

        // Only after every lower quality has been requested and verified may
        // playback fall through to the cross-source resolver.
        if (urlToPlay == null || urlToPlay.isEmpty) {
          await _tryPlayFromAlternateSources(
            originalSong: song,
            index: index,
            requestId: requestId,
            quality: state.currentQuality,
          );
          return;
        }
      }

      if ((urlToPlay == null || urlToPlay.isEmpty) && !isLocal) {
        await _tryPlayFromAlternateSources(
          originalSong: song,
          index: index,
          requestId: requestId,
          quality: state.currentQuality,
        );
        return;
      }

      if (urlToPlay != null && urlToPlay.isNotEmpty) {
        try {
          await _audioHandler
              .setAudioSource(urlToPlay, song: currentSongToPlay)
              .timeout(_audioSetTimeout);
          await _restoreAndPlay(currentSongToPlay);
        } catch (_) {
          if (_currentPlayRequestId != requestId) return;

          // 先尝试同一歌曲的其他洛雪脚本/音质 URL，再进入跨平台换源。
          // 这能覆盖“接口返回 URL，但该 URL 的音频响应不可播放”的情况。
          final failedUrl = urlToPlay;
          final failedUrls = <String>{if (failedUrl.isNotEmpty) failedUrl};
          for (final candidate in resolvedUrlCandidates) {
            final candidateUrl = candidate.url;
            if (_currentPlayRequestId != requestId ||
                failedUrls.contains(candidateUrl)) {
              continue;
            }

            failedUrls.add(candidateUrl);

            try {
              final fallbackSong = currentSongToPlay.copyWith(
                sourceUrl: candidateUrl,
                sourceHeaders: candidate.headers.isEmpty
                    ? null
                    : candidate.headers,
                sourceQuality: candidate.quality.isEmpty
                    ? null
                    : candidate.quality,
                clearSourceHeaders: candidate.headers.isEmpty,
                clearSourceQuality: candidate.quality.isEmpty,
              );
              await _audioHandler
                  .setAudioSource(candidateUrl, song: fallbackSong)
                  .timeout(_audioSetTimeout);
              await _restoreAndPlay(fallbackSong);
              currentSongToPlay = fallbackSong;
              _replaceSongInQueue(index, fallbackSong);
              final fallbackQuality = candidate.quality.isEmpty
                  ? state.currentQuality
                  : candidate.quality;
              _autoNextCount = 0;
              state = state.copyWith(
                isLoading: false,
                currentSong: fallbackSong,
                currentQuality: fallbackQuality,
              );
              onMessage?.call('原播放链接失败，已切换到备用播放链接');
              onSongPlayed?.call(fallbackSong);
              _errorListenerSub = _mountOneTimeErrorListener(
                requestId,
                index,
                fallbackSong,
              );
              return;
            } catch (_) {
              continue;
            }
          }

          // 原源与同源候选都失败，再按 CeruMusic 的方式跨平台换源。
          try {
            if (_autoQualityDowngrade && !isLocal) {
              final qualityFallbackSong = await _tryQualityFallbackAfterFailure(
                song: currentSongToPlay,
                index: index,
                requestId: requestId,
                resumePosition: Duration.zero,
                excludedUrls: failedUrls,
              );
              if (qualityFallbackSong != null) {
                onSongPlayed?.call(qualityFallbackSong);
                _errorListenerSub = _mountOneTimeErrorListener(
                  requestId,
                  index,
                  qualityFallbackSong,
                );
                return;
              }
            }

            final candidates = await _autoSwitchService.getCandidateSongs(
              song,
              activeSourceIds: _activeSourceIds,
            );
            if (_currentPlayRequestId != requestId) return;

            var playSuccess = false;
            for (final candidate in candidates) {
              if (_currentPlayRequestId != requestId) return;

              try {
                final result = await _musicSourceManager
                    .getMusicUrlResult(candidate, quality: state.currentQuality)
                    .timeout(_urlFetchTimeout);
                if (_currentPlayRequestId != requestId) return;
                if (result == null || result.url.isEmpty) continue;
                final url = result.url;
                // 避免重试刚刚失败的 URL
                if (url == urlToPlay) continue;

                // 照搬 CeruMusic：保留原始 song 的 id，确保队列索引一致
                final switchedSong = candidate.copyWith(
                  id: song.id,
                  sourceUrl: url,
                  sourceHeaders: result.headers.isEmpty ? null : result.headers,
                  sourceQuality: result.quality.isEmpty ? null : result.quality,
                  clearSourceHeaders: result.headers.isEmpty,
                  clearSourceQuality: result.quality.isEmpty,
                );
                _replaceSongInQueue(index, switchedSong);

                await _audioHandler
                    .setAudioSource(url, song: switchedSong)
                    .timeout(_audioSetTimeout);
                await _restoreAndPlay(switchedSong);

                // CeruMusic：只有播放成功后（waitForAudioReady/setAudioSource 成功）
                // 才显示切换成功消息，避免切换消息显示后播放又失败
                onMessage?.call(
                  '已自动切换到 ${_getSourceName(candidate.source ?? '')} 源播放',
                );
                _autoNextCount = 0;
                playSuccess = true;
                // CeruMusic: 不乐观设 isPlaying, 由播放器事件驱动
                state = state.copyWith(
                  isLoading: false,
                  currentSong: switchedSong,
                );
                onSongPlayed?.call(switchedSong);
                _errorListenerSub = _mountOneTimeErrorListener(
                  requestId,
                  index,
                  switchedSong,
                );
                break;
              } catch (_) {
                continue;
              }
            }

            if (_currentPlayRequestId != requestId) return;

            if (!playSuccess) {
              _tryAutoNext('自动换源失败：所有源均无法播放');
            }
          } catch (e) {
            if (_currentPlayRequestId != requestId) return;
            _tryAutoNext('自动换源失败，原因: $e');
          }
          return;
        }

        _autoNextCount = 0;
        // CeruMusic: 不乐观设 isPlaying
        state = state.copyWith(
          isLoading: false,
          currentSong: currentSongToPlay,
        );
        onSongPlayed?.call(currentSongToPlay);

        _errorListenerSub = _mountOneTimeErrorListener(
          requestId,
          index,
          currentSongToPlay,
        );
      } else {
        try {
          final candidates = await _autoSwitchService.getCandidateSongs(
            song,
            activeSourceIds: _activeSourceIds,
          );
          if (_currentPlayRequestId != requestId) return;

          var playSuccess = false;
          for (final candidate in candidates) {
            if (_currentPlayRequestId != requestId) return;

            try {
              final result = await _musicSourceManager
                  .getMusicUrlResult(candidate, quality: state.currentQuality)
                  .timeout(_urlFetchTimeout);
              if (_currentPlayRequestId != requestId) return;
              if (result == null || result.url.isEmpty) continue;
              final url = result.url;

              // 照搬 CeruMusic：保留原始 song 的 id，确保队列索引一致
              final switchedSong = candidate.copyWith(
                id: song.id,
                sourceUrl: url,
                title: song.title,
                artist: song.artist,
                album: song.album,
                sourceHeaders: result.headers.isEmpty ? null : result.headers,
                sourceQuality: result.quality.isEmpty ? null : result.quality,
                clearSourceHeaders: result.headers.isEmpty,
                clearSourceQuality: result.quality.isEmpty,
              );
              _replaceSongInQueue(index, switchedSong);

              await _audioHandler
                  .setAudioSource(url, song: switchedSong)
                  .timeout(_audioSetTimeout);
              await _restoreAndPlay(switchedSong);

              onMessage?.call(
                '已自动切换到 ${_getSourceName(candidate.source ?? '')} 源播放',
              );
              _autoNextCount = 0;
              playSuccess = true;
              // CeruMusic: 不乐观设 isPlaying
              state = state.copyWith(
                isLoading: false,
                currentSong: switchedSong,
              );
              onSongPlayed?.call(switchedSong);
              _errorListenerSub = _mountOneTimeErrorListener(
                requestId,
                index,
                switchedSong,
              );
              break;
            } catch (_) {
              continue;
            }
          }

          if (_currentPlayRequestId != requestId) return;

          if (!playSuccess) {
            _tryAutoNext('自动换源失败：所有源均无法播放');
          }
        } catch (e) {
          if (_currentPlayRequestId != requestId) return;
          _tryAutoNext('自动换源失败，原因: $e');
        }
      }
    } catch (e) {
      debugPrint('[PlaybackController] playSongAt error: $e');
      if (_currentPlayRequestId != requestId) return;
      _tryAutoNext('播放歌曲失败');
    } finally {
      if (pendingCoverFuture != null && _currentPlayRequestId == requestId) {
        unawaited(
          _applyResolvedCover(
            song: initialSong,
            index: index,
            requestId: requestId,
            coverFuture: pendingCoverFuture,
          ),
        );
      }
      _settingQueue = false;
      if (_rememberProgress && state.isPlaying) {
        _startSaveTimer();
      }
      // 兜底（CeruMusic 风格）：若所有微任务事件处理完后 isLoading
      // 仍有残留且播放器实际在播放，强制清除。
      Future.microtask(() {
        if (!mounted) return;
        if (state.isLoading && _audioHandler.playing) {
          debugPrint('[PlaybackController] 修复 isLoading 残留: 强制设为 false');
          state = state.copyWith(isLoading: false);
        }
      });
    }
  }

  // ==================== 下一首 / 上一首（照搬 CeruMusic 逻辑） ====================

  /// 下一首（照搬 CeruMusic playNext）
  /// - singleLoop: 重置到 0，重新播放当前歌曲
  /// - 队列仅一首且非单曲循环 → 暂停
  /// - listLoop: (currentIndex + 1) % length
  /// - shuffle: 随机索引
  Future<void> next() async {
    _cancelPendingAutoNext();
    if (state.queue.isEmpty) return;

    // 队列仅一首且非单曲循环 → 播放完毕直接暂停，不重播
    if (state.queue.length == 1 && state.playMode != PlayMode.singleLoop) {
      debugPrint('[PlaybackController] 队列仅一首，暂停');
      // 遵循 CeruMusic/Sollin-Music 的 ExoPlayer 行为认知：
      // 歌曲 normal complete 后 ExoPlayer 保持 playWhenReady=true，
      // 直接调用 pause() 在 STATE_ENDED 下可能被忽略。
      // 必须先 seek(0) 让播放器离开 ENDED(→READY)，
      // 再 pause() 才能真正停止播放。
      await _audioHandler.seek(Duration.zero);
      await _audioHandler.pause();
      // 排空 seek/pause 触发的 playerStateStream 微任务事件
      await Future.microtask(() {});
      // 清除 completed 标记 & 强制同步 UI 状态
      _justCompleted = false;
      state = state.copyWith(isPlaying: false);
      return;
    }

    try {
      // singleLoop 模式：重新播放当前歌曲
      if (state.playMode == PlayMode.singleLoop && state.currentSong != null) {
        debugPrint('[PlaybackController] singleLoop: 重新播放当前歌曲');
        await _audioHandler.seek(Duration.zero);
        await _audioHandler.play();
        return;
      }

      final currentIndex = _currentIndex;
      int nextIndex;

      if (state.playMode == PlayMode.shuffle) {
        // shuffle 模式：随机索引（可能与当前相同）
        nextIndex = Random().nextInt(state.queue.length);
      } else {
        // listLoop 模式：顺序播放，到末尾后循环
        nextIndex = (currentIndex + 1) % state.queue.length;
      }

      if (nextIndex >= 0 && nextIndex < state.queue.length) {
        await playSongAt(nextIndex);
      }
    } catch (e) {
      debugPrint('[PlaybackController] next() error: $e');
      onMessage?.call('播放下一首失败', backgroundColor: Colors.red);
    }
  }

  /// 上一首（照搬 CeruMusic playPrevious）
  /// - shuffle: 随机索引
  /// - listLoop/singleLoop: currentIndex - 1（到开头后循环到末尾）
  Future<void> previous() async {
    _cancelPendingAutoNext();
    if (state.queue.isEmpty) return;

    try {
      final currentIndex = _currentIndex;
      int prevIndex;

      if (state.playMode == PlayMode.shuffle) {
        // shuffle 模式：随机索引
        prevIndex = Random().nextInt(state.queue.length);
      } else {
        // 顺序模式：上一首，到开头后循环到末尾
        prevIndex = currentIndex <= 0
            ? state.queue.length - 1
            : currentIndex - 1;
      }

      if (prevIndex >= 0 && prevIndex < state.queue.length) {
        await playSongAt(prevIndex);
      }
    } catch (e) {
      debugPrint('[PlaybackController] previous() error: $e');
      onMessage?.call('播放上一首失败', backgroundColor: Colors.red);
    }
  }

  // ==================== 播放控制 ====================

  Future<void> play() async {
    _cancelPendingAutoNext();
    // 用户主动播放，清除 completed 标记
    _justCompleted = false;
    // 首次恢复后播放：强制刷新 URL（CeruMusic 从不保存 URL，每次播放都重新获取）
    if (_needsUrlRefresh && state.currentSong != null) {
      _needsUrlRefresh = false;
      final idx = _currentIndex;
      if (idx >= 0) {
        final currentSong = state.currentSong!;
        if (currentSong.source != 'local') {
          _replaceSongInQueue(
            idx,
            currentSong.copyWith(
              clearSourceUrl: true,
              clearSourceHeaders: true,
            ),
          );
        }
        await playSongAt(idx);
        return;
      }
    }
    await _audioHandler.play();
    // 遵循 CeruMusic：不乐观设 isPlaying=true。
    // 由 _playerStateSub 的 ready(playing=true) 或微任务兜底同步。
    if (_rememberProgress) _startSaveTimer();
  }

  Future<void> pause() async {
    _cancelPendingAutoNext();
    // 遵循 CeruMusic stop()：先立即设 isPlay=false，再调 audio.pause()。
    // 这样即使 audio.pause() 异步延迟或失败，UI 状态也已正确更新。
    _justCompleted = false;
    state = state.copyWith(isPlaying: false);
    await _audioHandler.pause();
    _savePlaybackState();
    _stopSaveTimer();
  }

  Future<void> togglePlayPause() async {
    // 遵循 CeruMusic：以实际播放器状态判断按钮意图，
    // 不依赖可能滞后的 state.isPlaying。
    // CeruMusic 的 togglePlayPause:
    //   const isActuallyPlaying = a ? !a.paused : Audio.value.isPlay
    final isActuallyPlaying = _audioHandler.playing;
    if (isActuallyPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seek(Duration position) async {
    _cancelPendingAutoNext();
    // 用户主动拖拽进度条，清除 completed 标记
    _justCompleted = false;
    await _audioHandler.seek(position);
  }

  Future<void> setSpeed(double speed) async {
    await _audioHandler.setSpeed(speed);
  }

  // ==================== 播放模式 ====================

  void cyclePlayMode() {
    final modes = PlayMode.values;
    final currentIndex = modes.indexOf(state.playMode);
    final nextIndex = (currentIndex + 1) % modes.length;
    state = state.copyWith(playMode: modes[nextIndex]);
  }

  Future<void> setPlayMode(PlayMode mode) async {
    state = state.copyWith(playMode: mode);
  }

  // ==================== 队列管理 ====================

  /// 设置播放队列（照搬 CeruMusic replacePlaylist）
  Future<void> setQueue(List<Song> songs, {int startIndex = 0}) async {
    _cancelPendingAutoNext();
    if (songs.isEmpty) return;
    // 用户主动切换队列（搜索/歌单等），不应用待恢复进度
    _pendingRestorePosition = null;
    _pendingRestoreSongId = null;
    onClearPlaybackState?.call();
    _settingQueue = true;
    final index = startIndex.clamp(0, songs.length - 1);

    // 更新队列状态
    state = state.copyWith(
      queue: List.from(songs),
      currentIndex: index,
      currentSong: songs[index],
      position: Duration.zero,
      isLoading: true,
    );

    _settingQueue = false;

    // 播放指定索引的歌曲
    await playSongAt(index);
  }

  /// 添加到队列末尾（照搬 CeruMusic addToPlaylistEnd）
  Future<void> appendToQueue(List<Song> songs) async {
    if (songs.isEmpty) return;
    // Remote URLs are transient. Resolve lazily when a song becomes current.
    final newQueue = [...state.queue, ...songs];
    state = state.copyWith(queue: newQueue);
  }

  /// 插入到当前歌曲之后（照搬 CeruMusic addToPlaylistAndPlay 的插入逻辑）
  Future<void> insertNext(List<Song> songs) async {
    if (songs.isEmpty) return;
    final insertIndex = _currentIndex + 1;
    final newQueue = List<Song>.from(state.queue);
    newQueue.insertAll(insertIndex, songs);
    state = state.copyWith(queue: newQueue);
  }

  /// 插入到队列首位并播放（照搬 CeruMusic addSongToFirst + playSong）
  Future<void> prependAndPlay(Song song) async {
    // 用户主动插播，不应用待恢复进度
    _pendingRestorePosition = null;
    _pendingRestoreSongId = null;
    onClearPlaybackState?.call();
    final resolved = [song];
    final newQueue = List<Song>.from(state.queue);
    newQueue.insertAll(0, resolved);
    state = state.copyWith(
      queue: newQueue,
      currentIndex: 0,
      currentSong: resolved.first,
      position: Duration.zero,
    );
    await playSongAt(0);
  }

  /// 从队列中移除歌曲
  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= state.queue.length) return;
    final newQueue = List<Song>.from(state.queue);
    final removedSong = newQueue.removeAt(index);
    int newIndex = _currentIndex;

    if (index < newIndex) {
      newIndex--;
    } else if (removedSong.id == state.currentSong?.id) {
      // 移除的是当前歌曲，播放下一首
      if (newQueue.isEmpty) {
        await clearQueue();
        return;
      }
      if (newIndex >= newQueue.length) {
        newIndex = newQueue.length - 1;
      }
    }

    final newCurrentSong = newIndex >= 0 && newIndex < newQueue.length
        ? newQueue[newIndex]
        : null;

    state = state.copyWith(
      queue: newQueue,
      currentIndex: newIndex,
      currentSong: newCurrentSong,
    );

    // 如果移除的是当前歌曲，播放新的当前歌曲
    if (removedSong.id == state.currentSong?.id && newCurrentSong != null) {
      await playSongAt(newIndex);
    }
  }

  /// 清空队列
  Future<void> clearQueue() async {
    await _audioHandler.stop();
    state = const PlaybackState();
  }

  // ==================== 音质切换 ====================

  void _finishQualitySwitch(int requestId) {
    if (_qualitySwitchRequestId == requestId) {
      _qualitySwitchRequestId = null;
    }
  }

  Future<void> setQuality(String quality) async {
    if (state.currentQuality == quality) return;

    final currentSong = state.currentSong;
    if (currentSong == null) return;

    final requestId = ++_currentPlayRequestId;
    _qualitySwitchRequestId = requestId;
    state = state.copyWith(isLoading: true);
    final currentPosition = state.position;
    final originalUrl = currentSong.sourceUrl;

    try {
      final result = await _musicSourceManager.getMusicUrlResult(
        currentSong,
        quality: quality,
      );
      if (_currentPlayRequestId != requestId) return;

      if (result == null || result.url.isEmpty) {
        state = state.copyWith(isLoading: false);
        _finishQualitySwitch(requestId);
        onMessage?.call('无法获取该音质的播放链接，当前音质保持不变', backgroundColor: Colors.red);
        return;
      }

      final updatedSong = currentSong.copyWith(
        sourceUrl: result.url,
        sourceHeaders: result.headers.isEmpty ? null : result.headers,
        sourceQuality: result.quality.isEmpty ? quality : result.quality,
        clearSourceHeaders: result.headers.isEmpty,
      );
      await _audioHandler.setAudioSource(result.url, song: updatedSong);
      await _audioHandler.seek(currentPosition);
      await _audioHandler.play();
      state = state.copyWith(
        isLoading: false,
        isPlaying: true,
        currentQuality: quality,
        currentSong: updatedSong,
      );
      _finishQualitySwitch(requestId);
      onMessage?.call('已切换到 ${_getQualityDisplayName(quality)}');
    } catch (e) {
      if (_currentPlayRequestId != requestId) return;
      // 恢复原音源
      try {
        if (originalUrl != null && originalUrl.isNotEmpty) {
          await _audioHandler.setAudioSource(originalUrl, song: currentSong);
          await _audioHandler.seek(currentPosition);
          await _audioHandler.play();
        }
      } catch (_) {}
      state = state.copyWith(isLoading: false);
      _finishQualitySwitch(requestId);
      onMessage?.call('切换音质失败，当前音质保持不变: $e', backgroundColor: Colors.red);
    }
  }

  // ==================== 内部辅助方法 ====================

  void _replaceSongInQueue(int index, Song newSong) {
    final newQueue = List<Song>.from(state.queue);
    newQueue[index] = newSong;
    state = state.copyWith(queue: newQueue);
  }

  Future<void> _applyResolvedCover({
    required Song song,
    required int index,
    required int requestId,
    required Future<String?> coverFuture,
  }) async {
    try {
      final coverUrl = await coverFuture;
      if (!mounted ||
          _currentPlayRequestId != requestId ||
          coverUrl == null ||
          coverUrl.isEmpty) {
        return;
      }

      final currentSong = state.currentSong;
      if (currentSong == null ||
          currentSong.id != song.id ||
          currentSong.source != song.source) {
        return;
      }

      final shouldRefreshKuwoCover = currentSong.source == 'kw';
      if (!shouldRefreshKuwoCover &&
          (currentSong.coverUrl?.isNotEmpty ?? false)) {
        return;
      }
      if (currentSong.coverUrl == coverUrl) return;

      final enrichedSong = currentSong.copyWith(coverUrl: coverUrl);
      if (index >= 0 &&
          index < state.queue.length &&
          state.queue[index].id == currentSong.id) {
        _replaceSongInQueue(index, enrichedSong);
      }
      state = state.copyWith(currentSong: enrichedSong);
      _audioHandler.updateCurrentMediaItem(enrichedSong);
    } catch (error) {
      debugPrint('[PlaybackController] cover resolution failed: $error');
    }
  }

  /// 照搬 CeruMusic tryAutoNext：
  /// autoNextCount 超过限制则停止，否则自动切到下一首
  ///
  /// CeruMusic 关键保护：如果原因包含"频率"或"限制"（如 API 限频），
  /// 直接返回不触发自动下一首，防止无限循环。
  Future<bool> _tryPlayFromAlternateSources({
    required Song originalSong,
    required int index,
    required int requestId,
    required String quality,
  }) async {
    try {
      final candidates = await _autoSwitchService.getCandidateSongs(
        originalSong,
        activeSourceIds: _activeSourceIds,
      );
      if (_currentPlayRequestId != requestId) return false;

      for (final candidate in candidates) {
        if (_currentPlayRequestId != requestId) return false;
        try {
          final result = await _musicSourceManager
              .getMusicUrlResult(candidate, quality: quality)
              .timeout(_urlFetchTimeout);
          if (result == null || result.url.isEmpty) continue;

          final switchedSong = candidate.copyWith(
            id: originalSong.id,
            sourceUrl: result.url,
            sourceHeaders: result.headers.isEmpty ? null : result.headers,
            sourceQuality: result.quality.isEmpty ? quality : result.quality,
            clearSourceHeaders: result.headers.isEmpty,
            clearSourceQuality: false,
          );
          await _audioHandler
              .setAudioSource(result.url, song: switchedSong)
              .timeout(_audioSetTimeout);
          await _restoreAndPlay(switchedSong);
          _replaceSongInQueue(index, switchedSong);
          state = state.copyWith(
            currentSong: switchedSong,
            currentQuality: switchedSong.sourceQuality ?? quality,
            isLoading: false,
          );
          onMessage?.call(
            '已自动切换到 ${_getSourceName(candidate.source ?? '')} 源播放',
          );
          onSongPlayed?.call(switchedSong);
          _errorListenerSub = _mountOneTimeErrorListener(
            requestId,
            index,
            switchedSong,
          );
          return true;
        } catch (e) {
          debugPrint('[PlaybackController] alternate source failed: $e');
        }
      }
    } catch (e) {
      debugPrint('[PlaybackController] alternate source lookup failed: $e');
    }

    if (_currentPlayRequestId == requestId) {
      _tryAutoNext('所有音质均不可用，自动换源失败');
    }
    return false;
  }

  void _tryAutoNext(String reason) {
    debugPrint(
      '[PlaybackController] _tryAutoNext: $reason, count=$_autoNextCount',
    );

    // 照搬 CeruMusic：限频/限流时不自动跳转，防止无限循环
    if (reason.contains('频率') || reason.contains('限制')) {
      onMessage?.call('播放失败：$reason，请稍后重试', backgroundColor: Colors.red);
      return;
    }

    final limit = _autoNextLimit;

    onMessage?.call('自动跳过当前歌曲：原因：$reason', backgroundColor: Colors.red);

    if ((_autoNextCount >= limit || _autoNextCount >= 10) &&
        _autoNextCount > 2) {
      onMessage?.call(
        '自动下一首失败：$_autoNextCount/${limit > 10 ? 10 : limit}次。原因：$reason',
        backgroundColor: Colors.red,
      );
      _autoNextCount = 0;
      return;
    }

    _autoNextCount++;
    state = state.copyWith(isLoading: false);
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        next();
      }
    });
  }

  void resetAutoNextCount() {
    _autoNextCount = 0;
  }

  Future<List<PluginMusicUrlResult>> _getLowerQualityCandidates(
    Song song, {
    required Set<String> excludedUrls,
  }) async {
    if (!_autoQualityDowngrade ||
        song.source == null ||
        song.source == 'local') {
      return const <PluginMusicUrlResult>[];
    }

    final results = <PluginMusicUrlResult>[];
    final qualityChain = _musicSourceManager.getMusicQualityFallbacks(
      song,
      state.currentQuality,
    );
    for (final fallbackQuality in qualityChain) {
      if (fallbackQuality == state.currentQuality) continue;
      try {
        final candidates = await _musicSourceManager
            .getMusicUrlResultCandidates(
              song,
              quality: fallbackQuality,
              excludedUrls: excludedUrls,
            )
            .timeout(_urlFetchTimeout);
        for (final candidate in candidates) {
          if (candidate.url.isNotEmpty &&
              !excludedUrls.contains(candidate.url) &&
              !results.any((item) => item.url == candidate.url)) {
            results.add(
              candidate.quality.isEmpty
                  ? PluginMusicUrlResult(
                      url: candidate.url,
                      quality: fallbackQuality,
                      headers: candidate.headers,
                    )
                  : candidate,
            );
          }
        }
      } catch (e) {
        debugPrint(
          '[PlaybackController] quality fallback lookup failed: '
          'quality=$fallbackQuality error=$e',
        );
      }
    }
    return results;
  }

  Future<Song?> _tryQualityFallbackAfterFailure({
    required Song song,
    required int index,
    required int requestId,
    required Duration resumePosition,
    required Set<String> excludedUrls,
  }) async {
    if (!_autoQualityDowngrade ||
        song.source == null ||
        song.source == 'local') {
      return null;
    }

    final triedUrls = <String>{...excludedUrls};
    final qualityChain = _musicSourceManager.getMusicQualityFallbacks(
      song,
      state.currentQuality,
    );

    // Request one quality, verify its URLs immediately, then continue to the
    // next lower quality only when every URL at this level fails.
    for (final fallbackQuality in qualityChain) {
      if (_currentPlayRequestId != requestId ||
          fallbackQuality == state.currentQuality) {
        continue;
      }

      List<PluginMusicUrlResult> candidates;
      try {
        candidates = await _musicSourceManager
            .getMusicUrlResultCandidates(
              song,
              quality: fallbackQuality,
              excludedUrls: triedUrls,
            )
            .timeout(_urlFetchTimeout);
      } catch (e) {
        debugPrint(
          '[PlaybackController] quality fallback lookup failed: '
          'quality=$fallbackQuality error=$e',
        );
        continue;
      }

      for (final candidate in candidates) {
        if (_currentPlayRequestId != requestId ||
            candidate.url.isEmpty ||
            !triedUrls.add(candidate.url)) {
          continue;
        }

        final resolvedQuality = candidate.quality.isEmpty
            ? fallbackQuality
            : candidate.quality;
        final fallbackSong = song.copyWith(
          sourceUrl: candidate.url,
          sourceHeaders: candidate.headers.isEmpty ? null : candidate.headers,
          sourceQuality: resolvedQuality,
          clearSourceHeaders: candidate.headers.isEmpty,
          clearSourceQuality: false,
        );

        try {
          await _audioHandler
              .setAudioSource(candidate.url, song: fallbackSong)
              .timeout(_audioSetTimeout);
          await _restoreAndPlay(fallbackSong);
          await _resumeFromPosition(resumePosition);
          _replaceSongInQueue(index, fallbackSong);
          state = state.copyWith(
            currentSong: fallbackSong,
            currentQuality: resolvedQuality,
            isLoading: false,
          );
          onMessage?.call('已自动降级到 ${_getQualityDisplayName(resolvedQuality)}');
          return fallbackSong;
        } catch (e) {
          debugPrint(
            '[PlaybackController] quality fallback playback failed: '
            'quality=$resolvedQuality error=$e',
          );
        }
      }
    }
    return null;
  }

  // ignore: unused_element
  Future<Song?> _tryQualityFallbackAfterFailureLegacy({
    required Song song,
    required int index,
    required int requestId,
    required Duration resumePosition,
    required Set<String> excludedUrls,
  }) async {
    if (!_autoQualityDowngrade ||
        song.source == null ||
        song.source == 'local') {
      return null;
    }

    final candidates = await _getLowerQualityCandidates(
      song,
      excludedUrls: excludedUrls,
    );

    for (final candidate in candidates) {
      if (_currentPlayRequestId != requestId ||
          candidate.url.isEmpty ||
          excludedUrls.contains(candidate.url)) {
        continue;
      }

      final resolvedQuality = candidate.quality.isEmpty
          ? state.currentQuality
          : candidate.quality;
      final fallbackSong = song.copyWith(
        sourceUrl: candidate.url,
        sourceHeaders: candidate.headers.isEmpty ? null : candidate.headers,
        sourceQuality: resolvedQuality,
        clearSourceHeaders: candidate.headers.isEmpty,
        clearSourceQuality: false,
      );

      try {
        await _audioHandler
            .setAudioSource(candidate.url, song: fallbackSong)
            .timeout(_audioSetTimeout);
        await _restoreAndPlay(fallbackSong);
        await _resumeFromPosition(resumePosition);
        _replaceSongInQueue(index, fallbackSong);
        state = state.copyWith(
          currentSong: fallbackSong,
          currentQuality: resolvedQuality,
          isLoading: false,
        );
        onMessage?.call(
          '原音质播放失败，已降级到 ${_getQualityDisplayName(resolvedQuality)}',
        );
        return fallbackSong;
      } catch (e) {
        debugPrint(
          '[PlaybackController] quality fallback playback failed: '
          'quality=$resolvedQuality error=$e',
        );
      }
    }
    return null;
  }

  /// 一次性错误监听器（照搬 CeruMusic 的 error listener 机制）
  ///
  /// CeruMusic 使用 HTML5 Audio 元素的原生 error 事件（{ once: true }），
  /// 一次性检测播放错误并触发自动换源。这里用 just_audio 的 playerStateStream
  /// 模拟相同的语义：
  ///
  /// 1. 监听异常 processingState 过渡：ready/loading/buffering → idle
  /// 2. 至少播放 minPlayDuration 后才激活（避免启动阶段的误判）
  /// 3. 一次性：触发一次后自动取消订阅
  ///
  /// 换源逻辑（对齐 CeruMusic error handler）：
  /// - 先尝试原源重新获取 URL（可能只是 URL 过期）
  /// - 原源失败则遍历候选源
  /// - 全部失败 → tryAutoNext
  StreamSubscription _mountOneTimeErrorListener(
    int requestId,
    int index,
    Song song,
  ) {
    const minPlayDuration = Duration(seconds: 6);
    bool handled = false;
    ProcessingState? lastState;
    final startTime = DateTime.now();
    late final StreamSubscription sub;

    sub = _audioHandler.playerStateStream.listen((playerState) async {
      if (_currentPlayRequestId != requestId || handled) return;

      final current = playerState.processingState;

      // 自然完成 → 不触发换源
      if (current == ProcessingState.completed) {
        handled = true;
        sub.cancel();
        return;
      }

      // 至少播放 minPlayDuration 后才检测错误（CeruMusic 风格）
      final elapsed = DateTime.now().difference(startTime);
      if (elapsed < minPlayDuration) {
        lastState = current;
        return;
      }

      // 检测异常过渡：ready/loading/buffering → idle（播放中断）
      final isErrorTransition =
          current == ProcessingState.idle &&
          !playerState.playing &&
          lastState != null &&
          lastState != ProcessingState.idle &&
          lastState != ProcessingState.completed;

      if (!isErrorTransition) {
        lastState = current;
        return;
      }

      // 一次性触发
      handled = true;
      sub.cancel();

      debugPrint('[PlaybackController] 检测到播放错误: $lastState → idle, 开始换源');

      // 捕获出错/暂停前的播放进度，换源成功后 seek 回去，避免重头播放
      // （如暂停期间 URL 过期，恢复播放时报错触发换源的情况）
      final resumePosition = state.position;

      // 乐观更新 UI
      state = state.copyWith(isLoading: true);

      try {
        // 1) 先尝试原源重新获取 URL（可能是 URL 过期 / token 失效）
        final excludedUrls = song.sourceUrl == null || song.sourceUrl!.isEmpty
            ? const <String>{}
            : <String>{song.sourceUrl!};
        final resolved = await _musicSourceManager
            .resolveSingleSongUrl(song, excludedUrls: excludedUrls)
            .timeout(_urlFetchTimeout, onTimeout: () => song);
        if (_currentPlayRequestId != requestId) return;

        if (resolved.sourceUrl != null &&
            resolved.sourceUrl!.isNotEmpty &&
            resolved.sourceUrl != song.sourceUrl) {
          // 原源新 URL 成功 → 直接播放
          _replaceSongInQueue(index, resolved);
          try {
            await _audioHandler
                .setAudioSource(resolved.sourceUrl!, song: resolved)
                .timeout(_audioSetTimeout);
            await _restoreAndPlay(resolved);
            await _resumeFromPosition(resumePosition);
            state = state.copyWith(currentSong: resolved, isLoading: false);
            onMessage?.call(
              '已重新获取 ${_getSourceName(resolved.source ?? '')} 源 URL，继续播放',
            );
            return;
          } catch (_) {
            debugPrint('[PlaybackController] 原源新 URL 播放失败，尝试换源');
          }
        }

        // 原源重新获取失败后，按开关决定是否尝试更低音质。
        final qualityFallbackSong = await _tryQualityFallbackAfterFailure(
          song: song,
          index: index,
          requestId: requestId,
          resumePosition: resumePosition,
          excludedUrls: excludedUrls,
        );
        if (qualityFallbackSong != null) {
          _errorListenerSub = _mountOneTimeErrorListener(
            requestId,
            index,
            qualityFallbackSong,
          );
          return;
        }

        // 2) 原源重试失败 → 遍历候选源
        final candidates = await _autoSwitchService.getCandidateSongs(
          song,
          activeSourceIds: _activeSourceIds,
        );
        if (_currentPlayRequestId != requestId) return;

        for (final candidate in candidates) {
          if (_currentPlayRequestId != requestId) return;

          try {
            final result = await _musicSourceManager
                .getMusicUrlResult(candidate, quality: state.currentQuality)
                .timeout(_urlFetchTimeout);
            if (_currentPlayRequestId != requestId) return;
            if (result == null || result.url.isEmpty) continue;
            final url = result.url;
            if (url == song.sourceUrl) continue;

            // 照搬 CeruMusic：保留原始 song 的 id，确保队列索引一致
            final switchedSong = candidate.copyWith(
              id: song.id,
              sourceUrl: url,
              sourceHeaders: result.headers.isEmpty ? null : result.headers,
              sourceQuality: result.quality.isEmpty ? null : result.quality,
              clearSourceHeaders: result.headers.isEmpty,
              clearSourceQuality: result.quality.isEmpty,
            );
            _replaceSongInQueue(index, switchedSong);

            await _audioHandler
                .setAudioSource(url, song: switchedSong)
                .timeout(_audioSetTimeout);
            await _restoreAndPlay(switchedSong);
            await _resumeFromPosition(resumePosition);

            onMessage?.call(
              '已自动切换到 ${_getSourceName(candidate.source ?? '')} 源播放',
            );
            state = state.copyWith(currentSong: switchedSong, isLoading: false);
            return;
          } catch (_) {
            continue;
          }
        }

        // 3) 全部失败
        if (_currentPlayRequestId != requestId) return;
        if (state.queue.length <= 1) {
          await _audioHandler.pause();
          state = state.copyWith(isPlaying: false, isLoading: false);
          onMessage?.call('播放中断，请手动重试', backgroundColor: Colors.orange);
        } else {
          _tryAutoNext('所有自动换源尝试均失败');
        }
      } catch (e) {
        debugPrint('[PlaybackController] 处理播放错误时出错: $e');
        if (_currentPlayRequestId != requestId) return;
        if (state.queue.length <= 1) {
          await _audioHandler.pause();
          state = state.copyWith(isPlaying: false, isLoading: false);
        } else {
          _tryAutoNext('播放出错且自动换源失败');
        }
      }
    });

    return sub;
  }

  String _getQualityDisplayName(String quality) {
    return getQualityDisplayName(quality);
  }

  String _getQualityFromSong(Song song) {
    final filePath = song.filePath?.toLowerCase() ?? '';
    final bitrate = song.bitrate;
    final sampleRate = song.sampleRate;

    if (filePath.endsWith('.flac')) {
      if (sampleRate != null && sampleRate > 48000) {
        return 'hires';
      }
      return 'flac';
    }

    if (filePath.endsWith('.wav') ||
        filePath.endsWith('.ape') ||
        filePath.endsWith('.dsd') ||
        filePath.endsWith('.dff') ||
        filePath.endsWith('.dsf')) {
      return 'hires';
    }

    if (filePath.endsWith('.m4a') || filePath.endsWith('.aac')) {
      if (bitrate != null && bitrate > 0) {
        if (bitrate <= 128000) return '128k';
        if (bitrate <= 320000) return '320k';
      }
      return '320k';
    }

    if (filePath.endsWith('.ogg') || filePath.endsWith('.wma')) {
      if (bitrate != null && bitrate > 0) {
        if (bitrate <= 128000) return '128k';
        if (bitrate <= 320000) return '320k';
      }
      return '320k';
    }

    if (bitrate == null || bitrate <= 0) {
      if (filePath.endsWith('.mp3')) {
        return '320k';
      }
      return '320k';
    }

    if (bitrate <= 128000) {
      return '128k';
    } else if (bitrate <= 320000) {
      return '320k';
    } else if (sampleRate != null && sampleRate > 48000) {
      return 'hires';
    } else {
      return 'flac';
    }
  }

  List<String> getAvailableQualities() {
    return state.availableQualities;
  }

  @override
  void dispose() {
    _audioSessionSub?.cancel();
    _loadingTimer?.cancel();
    _loadingTimer = null;
    _stopSaveTimer();
    _positionSub?.cancel();
    _bufferedSub?.cancel();
    _durationSub?.cancel();
    _playerStateSub?.cancel();
    _errorListenerSub?.cancel();
    super.dispose();
  }
}
