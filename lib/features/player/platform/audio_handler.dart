import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/models/song.dart';

class MusicAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  DateTime? _lastPositionBroadcast;
  static const _positionBroadcastInterval = Duration(milliseconds: 200);

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Duration? get currentDuration => _player.duration;
  Stream<int?> get currentIndexStream => _player.currentIndexStream;
  Stream<int?> get audioSessionIdStream => _player.androidAudioSessionIdStream;
  int? get currentAudioSessionId => _player.androidAudioSessionId;
  Stream<String> get playbackErrorStream => _errorController.stream;

  PlayerState? get currentPlayerState => _player.playerState;
  ProcessingState get processingState => _player.processingState;
  bool get playing => _player.playing;

  ProcessingState _lastProcessingState = ProcessingState.idle;
  bool _errorMonitoring = false;

  /// 通知栏控制回调（由 PlaybackController 设置）
  VoidCallback? onSkipNext;
  VoidCallback? onSkipPrevious;

  MusicAudioHandler() {
    _init();
  }

  Future<void> _init() async {
    _player.playbackEventStream.listen((event) {
      _broadcastState();
    });

    _player.positionStream.listen((position) {
      final now = DateTime.now();
      if (_lastPositionBroadcast == null ||
          now.difference(_lastPositionBroadcast!) >=
              _positionBroadcastInterval) {
        _lastPositionBroadcast = now;
        _broadcastState();
      }
    });

    _player.durationStream.listen((duration) {
      if (duration != null && duration > Duration.zero) {
        _updateMediaItemDuration(duration);
      }
    });

    await _initAudioSession();

    _player.currentIndexStream.listen((index) {
      if (index != null &&
          queue.value.isNotEmpty &&
          index < queue.value.length) {
        mediaItem.add(queue.value[index]);
        _tryUpdateDurationFromPlayer();
      }
    });
  }

  void _broadcastState() {
    final processingState = _mapProcessingState(_player.processingState);
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          _player.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
        playing: _player.playing,
        processingState: processingState,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _player.currentIndex,
      ),
    );
  }

  void _updateMediaItemDuration(Duration duration) {
    final currentItem = mediaItem.value;
    if (currentItem == null) return;
    if (currentItem.duration == duration) return;

    final updatedItem = currentItem.copyWith(duration: duration);
    mediaItem.add(updatedItem);

    final currentQueue = queue.value;
    final index = _player.currentIndex;
    if (index != null && index >= 0 && index < currentQueue.length) {
      final queueItem = currentQueue[index];
      if (queueItem.duration != duration) {
        final newQueue = List<MediaItem>.from(currentQueue);
        newQueue[index] = queueItem.copyWith(duration: duration);
        queue.add(newQueue);
      }
    }

    debugPrint('[MusicAudioHandler] duration updated: ${duration.inSeconds}s');
  }

  void _tryUpdateDurationFromPlayer() {
    final duration = _player.duration;
    if (duration != null && duration > Duration.zero) {
      _updateMediaItemDuration(duration);
    }
  }

  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    session.becomingNoisyEventStream.listen((_) {
      pause();
    });
  }

  void startErrorMonitoring() {
    if (_errorMonitoring) return;
    _errorMonitoring = true;

    _player.playerStateStream.listen((state) {
      final current = state.processingState;
      debugPrint(
        '[MusicAudioHandler] processingState: $_lastProcessingState → $current, playing=${state.playing}',
      );

      if (_lastProcessingState == ProcessingState.loading &&
          current == ProcessingState.idle &&
          !state.playing) {
        _errorController.add('playback_load_failed');
        debugPrint('[MusicAudioHandler] 检测到播放错误: loading→idle (加载失败)');
      }

      if (_lastProcessingState == ProcessingState.buffering &&
          current == ProcessingState.idle) {
        _errorController.add('playback_buffering_failed');
        debugPrint('[MusicAudioHandler] 检测到播放错误: buffering→idle (缓冲失败)');
      }

      if (_lastProcessingState == ProcessingState.ready &&
          current == ProcessingState.idle) {
        _errorController.add('playback_unexpected_stop');
        debugPrint('[MusicAudioHandler] 检测到播放错误: ready→idle (异常停止)');
      }

      _lastProcessingState = current;
    });
  }

  void stopErrorMonitoring() {
    _errorMonitoring = false;
  }

  void emitError(String error) {
    _errorController.add(error);
  }

  MediaItem _songToMediaItem(Song song) {
    Uri? artUri;
    if (song.coverUrl != null && song.coverUrl!.isNotEmpty) {
      if (song.coverUrl!.startsWith('http')) {
        artUri = Uri.parse(song.coverUrl!);
      } else if (song.coverUrl!.startsWith('content://')) {
        artUri = Uri.parse(song.coverUrl!);
      } else {
        artUri = Uri.file(song.coverUrl!);
      }
    }

    final duration = song.duration > 0
        ? Duration(seconds: song.duration)
        : null;

    debugPrint(
      '[MusicAudioHandler] _songToMediaItem: ${song.title}, song.duration=${song.duration}s, mediaItem.duration=${duration?.inSeconds}s',
    );

    return MediaItem(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: duration,
      artUri: artUri,
    );
  }

  AudioSource _songToAudioSource(Song song) {
    final mediaItem = _songToMediaItem(song);

    // 如果没有 sourceUrl，使用一个不会导致立即失败的临时方案
    // 我们使用一个简短的本地静音音频或者保持为 null，但为了队列完整性，
    // 我们暂时使用一个特殊的标记，让 PlaybackController 处理
    if (song.sourceUrl == null || song.sourceUrl!.isEmpty) {
      debugPrint('[MusicAudioHandler] 歌曲无 sourceUrl: ${song.title}');
      // 这里我们仍然需要返回一个有效的 AudioSource，
      // 所以我们先使用一个特殊的 URL 占位，
      // PlaybackController 的后台解析会更新它
      final placeholderUri = Uri.parse('https://example.com/placeholder');
      return AudioSource.uri(placeholderUri, tag: mediaItem);
    }

    final uri = song.sourceUrl!.startsWith('http')
        ? Uri.parse(song.sourceUrl!)
        : Uri.file(song.sourceUrl!);

    if (song.sourceUrl!.startsWith('http')) {
      final headers = _headersForUrl(
        song.sourceUrl!,
        songHeaders: song.sourceHeaders,
      );
      return AudioSource.uri(uri, tag: mediaItem, headers: headers);
    }

    return AudioSource.uri(uri, tag: mediaItem);
  }

  Future<void> setQueue(List<Song> songs, int startIndex) async {
    debugPrint(
      'MusicAudioHandler: 设置播放队列 - ${songs.length}首, 起始索引: $startIndex',
    );

    final processedSongs = await _prepareLocalCovers(
      songs,
      currentIndex: startIndex,
    );
    final children = processedSongs.map(_songToAudioSource).toList();
    final mediaItems = processedSongs.map(_songToMediaItem).toList();
    queue.add(mediaItems);

    try {
      final playlist = ConcatenatingAudioSource(children: children);
      await _player.setAudioSource(playlist, initialIndex: startIndex);

      if (startIndex >= 0 && startIndex < mediaItems.length) {
        mediaItem.add(mediaItems[startIndex]);
      }

      _tryUpdateDurationFromPlayer();

      debugPrint('MusicAudioHandler: 队列设置成功');
    } catch (e) {
      debugPrint('MusicAudioHandler: 队列设置失败: $e');
      rethrow;
    }
  }

  Future<List<Song>> _prepareLocalCovers(
    List<Song> songs, {
    int currentIndex = -1,
  }) async {
    final result = List<Song?>.filled(songs.length, null);
    Directory? coverDir;

    Future<Song> processSong(Song song) async {
      if (song.coverUrl == null && song.mediaStoreId != null) {
        try {
          coverDir ??= await _getCoverCacheDir();
          final coverPath = '${coverDir!.path}/${song.id}.jpg';
          if (await File(coverPath).exists()) {
            return song.copyWith(coverUrl: coverPath);
          }
          final bytes = await _audioQuery.queryArtwork(
            song.mediaStoreId!,
            ArtworkType.AUDIO,
            quality: 100,
            size: 400,
          );
          if (bytes != null && bytes.isNotEmpty) {
            await File(coverPath).writeAsBytes(bytes);
            return song.copyWith(coverUrl: coverPath);
          }
        } catch (e) {
          debugPrint('MusicAudioHandler: 提取封面失败 ${song.title}: $e');
        }
      }
      return song;
    }

    if (currentIndex >= 0 && currentIndex < songs.length) {
      result[currentIndex] = await processSong(songs[currentIndex]);
    }

    final futures = <Future<void>>[];
    for (int i = 0; i < songs.length; i++) {
      if (i != currentIndex) {
        futures.add(
          processSong(songs[i]).then((s) {
            result[i] = s;
          }),
        );
      }
    }
    if (futures.isNotEmpty) {
      unawaited(Future.wait(futures));
    }

    for (int i = 0; i < songs.length; i++) {
      result[i] ??= songs[i];
    }

    return result.cast<Song>();
  }

  Future<Directory> _getCoverCacheDir() async {
    final cacheDir = await getApplicationCacheDirectory();
    final coverDir = Directory('${cacheDir.path}/covers');
    if (!await coverDir.exists()) {
      await coverDir.create(recursive: true);
    }
    return coverDir;
  }

  Future<void> setSource(Song song) async {
    debugPrint('MusicAudioHandler: 开始设置音源 - 歌曲: ${song.title}');

    if (song.sourceUrl != null) {
      debugPrint('MusicAudioHandler: 音源URL: ${song.sourceUrl}');

      try {
        final prepared = await _prepareLocalCovers([song], currentIndex: 0);
        final preparedSong = prepared[0];
        final mediaItem = _songToMediaItem(preparedSong);
        queue.add([mediaItem]);

        await _player.setAudioSource(
          ConcatenatingAudioSource(
            children: [_songToAudioSource(preparedSong)],
          ),
        );

        this.mediaItem.add(mediaItem);
        debugPrint('MusicAudioHandler: 音源设置成功');
      } catch (e) {
        debugPrint('MusicAudioHandler: 设置音源失败: $e');
        rethrow;
      }
    } else {
      debugPrint('MusicAudioHandler: 错误 - 歌曲没有音源URL');
    }
  }

  Future<void> setAudioSource(
    String url, {
    Song? song,
    Map<String, String>? headers,
  }) async {
    debugPrint(
      'MusicAudioHandler: 设置音频源: ${url.substring(0, url.length > 60 ? 60 : url.length)}...',
    );

    var preparedSong = song;
    if (preparedSong != null) {
      final prepared = await _prepareLocalCovers([
        preparedSong,
      ], currentIndex: 0);
      preparedSong = prepared[0];
    }

    final mediaItem = preparedSong != null
        ? _songToMediaItem(preparedSong)
        : MediaItem(
            id: url,
            title: song?.title ?? 'Unknown',
            artist: song?.artist,
          );

    final uri = url.startsWith('http') ? Uri.parse(url) : Uri.file(url);

    try {
      if (url.startsWith('http')) {
        final requestHeaders = _headersForUrl(
          url,
          songHeaders: song?.sourceHeaders,
          extraHeaders: headers,
        );

        final audioSource = requestHeaders.isEmpty
            ? AudioSource.uri(uri, tag: mediaItem)
            : AudioSource.uri(uri, tag: mediaItem, headers: requestHeaders);
        await _player.setAudioSource(
          ConcatenatingAudioSource(children: [audioSource]),
        );
        await _validateRemoteSongDuration(preparedSong, url);
      } else {
        await _player.setAudioSource(
          ConcatenatingAudioSource(
            children: [AudioSource.uri(uri, tag: mediaItem)],
          ),
        );
      }

      queue.add([mediaItem]);
      this.mediaItem.add(mediaItem);
      debugPrint('MusicAudioHandler: 音频源设置成功');
    } catch (e) {
      debugPrint('MusicAudioHandler: 设置音频源失败: $e');
      rethrow;
    }
  }

  Future<void> _validateRemoteSongDuration(Song? song, String url) async {
    if (song?.source != 'kw') return;

    var actual = _player.duration;
    if (actual == null || actual <= Duration.zero) {
      try {
        actual = await _player.durationStream
            .firstWhere(
              (duration) => duration != null && duration > Duration.zero,
            )
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        throw const FormatException('Unable to verify Kuwo media duration');
      }
    }
    if (actual == null || actual <= Duration.zero) {
      throw const FormatException('Unable to verify Kuwo media duration');
    }

    final expectedSeconds = song!.duration;
    final actualSeconds = actual.inSeconds;

    // 没有预期时长时，用绝对阈值拦截明显的提示音/错误音频。
    if (expectedSeconds <= 0) {
      const minRealSongSeconds = 25;
      if (actualSeconds < minRealSongSeconds) {
        debugPrint(
          '[MusicAudioHandler] rejected short Kuwo media without expected duration: '
          'actual=${actualSeconds}s urlHost=${Uri.tryParse(url)?.host ?? 'invalid'}',
        );
        throw const FormatException('Kuwo media too short to be a real song');
      }
      return;
    }

    // Search results can differ by a few seconds because of intro/outro
    // edits. A short prompt, however, is far outside this tolerance.
    final tolerance = max(8, (expectedSeconds * 0.12).round());
    if ((actualSeconds - expectedSeconds).abs() > tolerance) {
      debugPrint(
        '[MusicAudioHandler] rejected mismatched Kuwo media: '
        'expected=${expectedSeconds}s actual=${actualSeconds}s '
        'urlHost=${Uri.tryParse(url)?.host ?? 'invalid'}',
      );
      throw const FormatException('Kuwo media duration does not match song');
    }
  }

  Map<String, String> _headersForUrl(
    String url, {
    Map<String, String>? songHeaders,
    Map<String, String>? extraHeaders,
  }) {
    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase() ?? '';
    // 酷我车机 CDN 对所有 `car-*.kuwo.cn` 域名都敏感，额外请求头可能导致
    // 返回 11 秒免费试听提示音，因此这些地址保持无请求头。
    final isKuwoMediaCdn = host.startsWith('car-') && host.endsWith('.kuwo.cn');
    final headers = <String, String>{};

    // CeruMusic/LX Music assign Kuwo media URLs directly to an audio element.
    // Extra request headers can make this signed CDN return the 11-second
    // free-listening prompt, so keep this host header-free by default.
    if (!isKuwoMediaCdn) {
      headers.addAll({
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': '*/*',
        'Accept-Encoding': 'identity',
        'Connection': 'keep-alive',
      });
    }

    if (!isKuwoMediaCdn && (url.contains('kuwo') || url.contains('kugou'))) {
      headers['Referer'] = 'https://www.kuwo.cn/';
    } else if (!isKuwoMediaCdn && url.contains('migu')) {
      headers['Referer'] = 'https://music.migu.cn/';
    } else if (!isKuwoMediaCdn &&
        (url.contains('qq.com') || url.contains('qqmusic'))) {
      headers['Referer'] = 'https://y.qq.com/';
    } else if (!isKuwoMediaCdn &&
        (url.contains('163') || url.contains('netease'))) {
      headers['Referer'] = 'https://music.163.com/';
    }

    // Kuwo's signed media CDN is sensitive to request headers. A Referer,
    // browser defaults, or plugin-provided headers can make it return the
    // short free-listening prompt. CeruMusic/LX assign these URLs directly
    // without forcing headers, so keep this host completely header-free.
    if (!isKuwoMediaCdn) {
      if (songHeaders != null) headers.addAll(songHeaders);
      if (extraHeaders != null) headers.addAll(extraHeaders);
    }
    return headers;
  }

  Future<void> skipToIndex(int index) async {
    debugPrint('MusicAudioHandler: 跳转到索引 $index');
    await _player.seek(Duration.zero, index: index);
  }

  Future<void> onPlay() async {
    debugPrint('MusicAudioHandler: onPlay callback');
    await play();
  }

  Future<void> onPause() async {
    debugPrint('MusicAudioHandler: onPause callback');
    await pause();
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
  }

  @override
  Future<void> play() async {
    unawaited(
      _player.play().catchError((Object e, StackTrace stackTrace) {
        debugPrint('[MusicAudioHandler] play() error: $e');
        if (!_errorController.isClosed) {
          _errorController.add('playback_play_failed');
        }
      }),
    );
    _tryUpdateDurationFromPlayer();
  }

  @override
  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (e) {
      debugPrint('[MusicAudioHandler] pause() error: $e');
    }
  }

  @override
  Future<void> stop() async {
    debugPrint('MusicAudioHandler: 停止播放');
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    debugPrint('MusicAudioHandler: 跳转到 ${position.inSeconds}秒');
    await _player.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    debugPrint('MusicAudioHandler: 下一首（通知栏）');
    onSkipNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    debugPrint('MusicAudioHandler: 上一首（通知栏）');
    onSkipPrevious?.call();
  }

  Future<void> updateQueueItem(int index, Song song) async {
    debugPrint('MusicAudioHandler: 更新队列项 $index: ${song.title}');

    final newQueue = List<MediaItem>.from(queue.value);
    if (index >= 0 && index < newQueue.length) {
      newQueue[index] = _songToMediaItem(song);
      queue.add(newQueue);
    }

    final currentPlaylist = _player.audioSource as ConcatenatingAudioSource?;
    if (currentPlaylist != null &&
        index >= 0 &&
        index < currentPlaylist.length) {
      await currentPlaylist.removeAt(index);
      await currentPlaylist.insert(index, _songToAudioSource(song));

      if (_player.currentIndex == index) {
        await _player.setAudioSource(currentPlaylist, initialIndex: index);
      }
    }

    debugPrint('MusicAudioHandler: 队列项更新成功');
  }

  /// Refreshes notification artwork without rebuilding the active audio
  /// source. Replacing a source solely for a late cover response can interrupt
  /// playback on some Android devices.
  void updateCurrentMediaItem(Song song) {
    final index = _player.currentIndex;
    final updatedItem = _songToMediaItem(song);
    mediaItem.add(updatedItem);

    if (index != null && index >= 0 && index < queue.value.length) {
      final updatedQueue = List<MediaItem>.from(queue.value);
      updatedQueue[index] = updatedItem;
      queue.add(updatedQueue);
    }
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  Future<void> dispose() async {
    debugPrint('MusicAudioHandler: 释放资源');
    _errorController.close();
    await _player.dispose();
  }
}
