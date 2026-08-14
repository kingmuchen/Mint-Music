import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/models/song.dart';

class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<int?> get currentIndexStream => _player.currentIndexStream;
  Stream<String> get playbackErrorStream => _errorController.stream;

  PlayerState? get currentPlayerState => _player.playerState;
  ProcessingState get processingState => _player.processingState;

  ProcessingState _lastProcessingState = ProcessingState.idle;
  bool _errorMonitoring = false;

  void startErrorMonitoring() {
    if (_errorMonitoring) return;
    _errorMonitoring = true;

    _player.playerStateStream.listen((state) {
      final current = state.processingState;
      debugPrint(
        '[AudioPlayerService] processingState: $_lastProcessingState → $current, playing=${state.playing}',
      );

      if (_lastProcessingState == ProcessingState.loading &&
          current == ProcessingState.idle &&
          !state.playing) {
        _errorController.add('playback_load_failed');
        debugPrint('[AudioPlayerService] 检测到播放错误: loading→idle (加载失败)');
      }

      if (_lastProcessingState == ProcessingState.buffering &&
          current == ProcessingState.idle) {
        _errorController.add('playback_buffering_failed');
        debugPrint('[AudioPlayerService] 检测到播放错误: buffering→idle (缓冲失败)');
      }

      if (_lastProcessingState == ProcessingState.ready &&
          current == ProcessingState.idle) {
        _errorController.add('playback_unexpected_stop');
        debugPrint('[AudioPlayerService] 检测到播放错误: ready→idle (异常停止)');
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

    return MediaItem(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: Duration(seconds: song.duration),
      artUri: artUri,
    );
  }

  AudioSource _songToAudioSource(Song song) {
    final mediaItem = _songToMediaItem(song);
    final uri = song.sourceUrl!.startsWith('http')
        ? Uri.parse(song.sourceUrl!)
        : Uri.file(song.sourceUrl!);

    if (song.sourceUrl!.startsWith('http')) {
      final headers = _headersForUrl(
        song.sourceUrl!,
        songHeaders: song.sourceHeaders,
      );
      return headers.isEmpty
          ? AudioSource.uri(uri, tag: mediaItem)
          : AudioSource.uri(uri, tag: mediaItem, headers: headers);
    }

    return AudioSource.uri(uri, tag: mediaItem);
  }

  Future<void> setQueue(List<Song> songs, int startIndex) async {
    debugPrint(
      'AudioPlayerService: 设置播放队列 - ${songs.length}首, 起始索引: $startIndex',
    );

    final processedSongs = await _prepareLocalCovers(songs);
    final children = processedSongs.map(_songToAudioSource).toList();

    try {
      await _player.setAudioSource(
        ConcatenatingAudioSource(children: children),
        initialIndex: startIndex,
      );
      debugPrint('AudioPlayerService: 队列设置成功');
    } catch (e) {
      debugPrint('AudioPlayerService: 队列设置失败: $e');
      rethrow;
    }
  }

  Future<List<Song>> _prepareLocalCovers(List<Song> songs) async {
    final List<Song> result = [];
    Directory? coverDir;

    for (final song in songs) {
      if (song.coverUrl == null && song.mediaStoreId != null) {
        try {
          coverDir ??= await _getCoverCacheDir();
          final bytes = await _audioQuery.queryArtwork(
            song.mediaStoreId!,
            ArtworkType.AUDIO,
            quality: 100,
            size: 400,
          );
          if (bytes != null && bytes.isNotEmpty) {
            final coverPath = '${coverDir.path}/${song.id}.jpg';
            await File(coverPath).writeAsBytes(bytes);
            result.add(song.copyWith(coverUrl: coverPath));
            debugPrint('AudioPlayerService: 提取封面成功 ${song.title}');
            continue;
          }
        } catch (e) {
          debugPrint('AudioPlayerService: 提取封面失败 ${song.title}: $e');
        }
      }
      result.add(song);
    }
    return result;
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
    debugPrint('AudioPlayerService: 开始设置音源 - 歌曲: ${song.title}');

    if (song.sourceUrl != null) {
      debugPrint('AudioPlayerService: 音源URL: ${song.sourceUrl}');

      try {
        await _player.setAudioSource(
          ConcatenatingAudioSource(children: [_songToAudioSource(song)]),
        );
        debugPrint('AudioPlayerService: 音源设置成功');
      } catch (e) {
        debugPrint('AudioPlayerService: 设置音源失败: $e');
        rethrow;
      }
    } else {
      debugPrint('AudioPlayerService: 错误 - 歌曲没有音源URL');
    }
  }

  Future<void> setAudioSource(String url, {Song? song}) async {
    debugPrint(
      'AudioPlayerService: 设置音频源: ${url.substring(0, url.length > 60 ? 60 : url.length)}...',
    );

    final mediaItem = song != null
        ? _songToMediaItem(song)
        : MediaItem(
            id: url,
            title: song?.title ?? 'Unknown',
            artist: song?.artist,
          );

    final uri = url.startsWith('http') ? Uri.parse(url) : Uri.file(url);

    try {
      if (url.startsWith('http')) {
        final headers = _headersForUrl(url, songHeaders: song?.sourceHeaders);
        await _player.setAudioSource(
          ConcatenatingAudioSource(
            children: [
              headers.isEmpty
                  ? AudioSource.uri(uri, tag: mediaItem)
                  : AudioSource.uri(uri, tag: mediaItem, headers: headers),
            ],
          ),
        );
      } else {
        await _player.setAudioSource(
          ConcatenatingAudioSource(
            children: [AudioSource.uri(uri, tag: mediaItem)],
          ),
        );
      }
      debugPrint('AudioPlayerService: 音频源设置成功');
    } catch (e) {
      debugPrint('AudioPlayerService: 设置音频源失败: $e');
      rethrow;
    }
  }

  Map<String, String> _headersForUrl(
    String url, {
    Map<String, String>? songHeaders,
  }) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    final isKuwoMediaCdn =
        host == 'car-er.kuwo.cn' || host.endsWith('.car-er.kuwo.cn');
    if (isKuwoMediaCdn) return const <String, String>{};

    final headers = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': '*/*',
      'Accept-Encoding': 'identity',
      'Connection': 'keep-alive',
    };

    final lowerUrl = url.toLowerCase();
    if (lowerUrl.contains('kuwo') || lowerUrl.contains('kugou')) {
      headers['Referer'] = 'https://www.kuwo.cn/';
    } else if (lowerUrl.contains('migu')) {
      headers['Referer'] = 'https://music.migu.cn/';
    } else if (lowerUrl.contains('qq.com') || lowerUrl.contains('qqmusic')) {
      headers['Referer'] = 'https://y.qq.com/';
    } else if (lowerUrl.contains('163') || lowerUrl.contains('netease')) {
      headers['Referer'] = 'https://music.163.com/';
    }

    if (songHeaders != null) headers.addAll(songHeaders);
    return headers;
  }

  Future<void> skipToIndex(int index) async {
    debugPrint('AudioPlayerService: 跳转到索引 $index');
    await _player.seek(Duration.zero, index: index);
  }

  Future<void> play() async {
    debugPrint('AudioPlayerService: 开始播放');

    unawaited(
      _player.play().catchError((Object e, StackTrace stackTrace) {
        debugPrint('AudioPlayerService: 播放失败: $e');
        if (!_errorController.isClosed) {
          _errorController.add('playback_play_failed');
        }
      }),
    );
    debugPrint('AudioPlayerService: 播放指令已发送');
  }

  Future<void> pause() async {
    debugPrint('AudioPlayerService: 暂停播放');
    await _player.pause();
  }

  Future<void> stop() async {
    debugPrint('AudioPlayerService: 停止播放');
    await _player.stop();
  }

  Future<void> seek(Duration position) async {
    debugPrint('AudioPlayerService: 跳转到 ${position.inSeconds}秒');
    await _player.seek(position);
  }

  Future<void> updateQueueItem(int index, Song song) async {
    debugPrint('AudioPlayerService: 更新队列项 $index: ${song.title}');

    final audioSource = _player.audioSource;
    if (audioSource is ConcatenatingAudioSource &&
        index >= 0 &&
        index < audioSource.length) {
      await audioSource.removeAt(index);
      await audioSource.insert(index, _songToAudioSource(song));
      debugPrint('AudioPlayerService: 队列项更新成功');
    }
  }

  Future<void> dispose() async {
    debugPrint('AudioPlayerService: 释放资源');
    _errorController.close();
    await _player.dispose();
  }

  bool get playing => _player.playing;
}
