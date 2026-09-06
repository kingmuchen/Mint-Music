import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../player/domain/models/song.dart';

class ScanProgress {
  final int processed;
  final int total;
  final bool running;

  const ScanProgress({this.processed = 0, this.total = 0, this.running = false});

  ScanProgress copyWith({int? processed, int? total, bool? running}) {
    return ScanProgress(
      processed: processed ?? this.processed,
      total: total ?? this.total,
      running: running ?? this.running,
    );
  }
}

class BatchMatchProgress {
  final int processed;
  final int total;
  final int matched;
  final bool running;

  const BatchMatchProgress({
    this.processed = 0,
    this.total = 0,
    this.matched = 0,
    this.running = false,
  });

  BatchMatchProgress copyWith({
    int? processed,
    int? total,
    int? matched,
    bool? running,
  }) {
    return BatchMatchProgress(
      processed: processed ?? this.processed,
      total: total ?? this.total,
      matched: matched ?? this.matched,
      running: running ?? this.running,
    );
  }
}

typedef ScanProgressCallback = void Function(ScanProgress progress);
typedef BatchMatchProgressCallback = void Function(BatchMatchProgress progress);

class LocalMusicRepository {
  static const _dirsKey = 'local_music_dirs';
  static const _songsKey = 'local_music_songs';

  final OnAudioQuery _audioQuery = OnAudioQuery();

  final Set<String> _scannedDirs = {};
  final Map<String, Song> _songsMap = {};
  bool _isScanning = false;
  ScanProgressCallback? onScanProgress;
  BatchMatchProgressCallback? onBatchMatchProgress;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final dirsJson = prefs.getStringList(_dirsKey) ?? [];
    _scannedDirs.addAll(dirsJson);

    final songsJson = prefs.getString(_songsKey);
    if (songsJson != null) {
      final list = jsonDecode(songsJson) as List;
      for (final s in list) {
        final song = Song.fromJson(s as Map<String, dynamic>);
        _songsMap[song.id] = song;
      }
    }
  }

  List<Song> getLocalSongs() {
    return List.unmodifiable(_songsMap.values.toList());
  }

  Song? getSongById(String id) {
    return _songsMap[id];
  }

  List<Song> searchLocal(String query) {
    if (query.isEmpty) return getLocalSongs();
    final q = query.toLowerCase();
    return _songsMap.values
        .where((s) =>
            s.title.toLowerCase().contains(q) ||
            s.artist.toLowerCase().contains(q) ||
            s.album.toLowerCase().contains(q))
        .toList();
  }

  List<String> getScannedDirectories() {
    return List.unmodifiable(_scannedDirs);
  }

  String _genId(String filePath) {
    final normalized = filePath.replaceAll('\\', '/');
    return md5.convert(utf8.encode(normalized)).toString().substring(0, 16);
  }

  String _genCoverKey(String filePath) {
    final normalized = filePath.replaceAll('\\', '/');
    return md5.convert(utf8.encode('cover_$normalized')).toString().substring(0, 16);
  }

  /// 根据文件扩展名推断音频比特率（用于本地音乐音质显示）
  int? _inferBitrateFromExtension(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    switch (ext) {
      case '.flac':
        return 1411000;
      case '.mp3':
        return 320000;
      case '.m4a':
      case '.aac':
        return 320000;
      case '.wav':
      case '.ape':
      case '.dsd':
      case '.dff':
      case '.dsf':
        return 1411000;
      case '.ogg':
      case '.wma':
        return 320000;
      default:
        return null;
    }
  }

  Future<void> addDirectory(String dirPath) async {
    if (_scannedDirs.contains(dirPath)) return;
    _scannedDirs.add(dirPath);
    await _saveIndex();
  }

  Future<void> removeDirectory(String dirPath) async {
    _scannedDirs.remove(dirPath);
    final normalized = dirPath.replaceAll('\\', '/');
    _songsMap.removeWhere((_, s) {
      final fp = (s.filePath ?? '').replaceAll('\\', '/');
      return fp.startsWith(normalized);
    });
    await _saveIndex();
  }

  Future<void> setDirectories(List<String> dirs) async {
    _scannedDirs.clear();
    _scannedDirs.addAll(dirs.where((d) => d.isNotEmpty));
    await _saveDirs();
  }

  Future<bool> requestPermission() async {
    return await _audioQuery.permissionsRequest();
  }

  Future<bool> checkPermission() async {
    return await _audioQuery.permissionsStatus();
  }

  Future<void> scanAll({ScanProgressCallback? onProgress}) async {
    if (_isScanning) return;
    _isScanning = true;

    try {
      final alreadyGranted = await checkPermission();
      if (!alreadyGranted) {
        final hasPermission = await requestPermission();
        if (!hasPermission) return;
      }

      final startProgress = ScanProgress(processed: 0, total: 0, running: true);
      onScanProgress?.call(startProgress);
      onProgress?.call(startProgress);

      try {
        final songs = await _audioQuery.querySongs(
          sortType: SongSortType.TITLE,
          orderType: OrderType.ASC_OR_SMALLER,
        );

        final musicSongs = songs.where((s) => s.isMusic == true || s.isMusic == null).toList();

        final total = musicSongs.length;
        onScanProgress?.call(ScanProgress(processed: 0, total: total, running: true));
        onProgress?.call(ScanProgress(processed: 0, total: total, running: true));

        final newSongsMap = <String, Song>{};
        int processed = 0;

        for (final audio in musicSongs) {
          final filePath = audio.data;
          if (filePath.isEmpty) {
            processed++;
            continue;
          }

          final shouldFilter = _scannedDirs.isNotEmpty
              ? !_scannedDirs.any((dir) {
                  final normalized = filePath.replaceAll('\\', '/');
                  final normalizedDir = dir.replaceAll('\\', '/');
                  return normalized.startsWith(normalizedDir);
                })
              : false;

          if (shouldFilter) {
            processed++;
            continue;
          }

          final id = _genId(filePath);
          final title = audio.title.isNotEmpty ? audio.title : p.basenameWithoutExtension(filePath);
          final artist = audio.artist ?? '未知艺术家';
          final album = audio.album ?? '未知专辑';
          final duration = (audio.duration ?? 0) ~/ 1000;

          final song = Song(
            id: id,
            title: title,
            artist: artist == '<unknown>' ? '未知艺术家' : artist,
            album: album == '<unknown>' ? '未知专辑' : album,
            duration: duration > 0 ? duration : 0,
            source: 'local',
            filePath: filePath,
            sourceUrl: filePath,
            hasCover: false,
            coverKey: _genCoverKey(filePath),
            mediaStoreId: audio.id,
            bitrate: _inferBitrateFromExtension(filePath),
          );

          final existing = _songsMap[id];
          if (existing != null) {
            newSongsMap[id] = _mergePreferFilled(existing, song);
          } else {
            newSongsMap[id] = song;
          }

          processed++;
          if (processed % 20 == 0 || processed == total) {
            final progress = ScanProgress(processed: processed, total: total, running: true);
            onScanProgress?.call(progress);
            onProgress?.call(progress);
          }
        }

        _songsMap.clear();
        _songsMap.addAll(newSongsMap);
        await _saveIndex();

        final doneProgress = ScanProgress(processed: total, total: total, running: false);
        onScanProgress?.call(doneProgress);
        onProgress?.call(doneProgress);
      } catch (e) {
        final errorProgress = ScanProgress(processed: 0, total: 0, running: false);
        onScanProgress?.call(errorProgress);
        onProgress?.call(errorProgress);
      }
    } finally {
      _isScanning = false;
    }
  }

  Future<Uint8List?> getCoverData(int mediaStoreId) async {
    try {
      return await _audioQuery.queryArtwork(
        mediaStoreId,
        ArtworkType.AUDIO,
        quality: 100,
        size: 400,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clearIndex() async {
    _songsMap.clear();
    await _saveIndex();
  }

  /// [forceOverwrite] 为 true 时直接覆盖所有字段（用于精准匹配等用户主动操作），
  /// 为 false 时使用合并策略保留已有非空值（用于批量匹配等自动操作）。
  Future<void> upsertSong(Song song, {bool forceOverwrite = false}) async {
    if (forceOverwrite) {
      _songsMap[song.id] = song;
    } else {
      final existing = _songsMap[song.id];
      if (existing != null) {
        _songsMap[song.id] = _mergePreferFilled(existing, song);
      } else {
        _songsMap[song.id] = song;
      }
    }
    await _saveIndex();
  }

  /// 从本地音乐库删除歌曲，并尽力删除磁盘上的音频文件。
  /// 磁盘文件删除失败（如权限不足）不影响索引移除，返回是否成功从索引移除。
  Future<bool> deleteSong(String id) async {
    final song = _songsMap[id];
    if (song == null) return false;
    _songsMap.remove(id);
    await _saveIndex();

    final filePath = song.filePath;
    if (filePath != null && filePath.isNotEmpty) {
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('[LocalMusic] 删除文件失败: $filePath ($e)');
      }
    }
    return true;
  }

  Song _mergePreferFilled(Song a, Song b) {
    String pick(String? x, String? y, [String fallback = '']) {
      if (x != null && x.isNotEmpty && x != '未知艺术家' && x != '未知曲目' && x != '未知专辑') return x;
      if (y != null && y.isNotEmpty && y != '未知艺术家' && y != '未知曲目' && y != '未知专辑') return y;
      return fallback;
    }

    return Song(
      id: a.id,
      title: pick(a.title, b.title, '未知曲目'),
      artist: pick(a.artist, b.artist, '未知艺术家'),
      album: pick(a.album, b.album, '未知专辑'),
      duration: a.duration > 0 ? a.duration : b.duration,
      coverUrl: a.coverUrl ?? b.coverUrl,
      sourceUrl: a.sourceUrl ?? b.sourceUrl,
      lyricUrl: a.lyricUrl ?? b.lyricUrl,
      source: a.source ?? b.source ?? 'local',
      filePath: a.filePath ?? b.filePath,
      hasCover: a.hasCover || b.hasCover,
      coverKey: a.coverKey ?? b.coverKey,
      lrc: a.lrc ?? b.lrc,
      bitrate: a.bitrate ?? b.bitrate,
      sampleRate: a.sampleRate ?? b.sampleRate,
      channels: a.channels ?? b.channels,
      year: a.year ?? b.year,
      mediaStoreId: a.mediaStoreId ?? b.mediaStoreId,
    );
  }

  Future<void> _saveIndex() async {
    await _saveDirs();
    final prefs = await SharedPreferences.getInstance();
    final songsJson = jsonEncode(_songsMap.values.map((s) => s.toJson()).toList());
    await prefs.setString(_songsKey, songsJson);
  }

  Future<void> _saveDirs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_dirsKey, _scannedDirs.toList());
  }
}
