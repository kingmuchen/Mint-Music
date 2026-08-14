import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../../player/domain/models/song.dart';

class TagWriteService {
  static const _channel = MethodChannel('com.mintmusic/tag_writer');

  Future<void> processSongFiles(
    String songPath,
    Song songInfo, {
    required bool basicInfo,
    required bool cover,
    required bool lyrics,
    required bool downloadLyrics,
    required String lyricFormat,
  }) async {
    final file = File(songPath);
    if (!await file.exists()) return;
    if (!_isAudioFile(songPath)) return;

    debugPrint('[TagWriteService] processSongFiles: path=$songPath, basicInfo=$basicInfo, cover=$cover, lyrics=$lyrics, downloadLyrics=$downloadLyrics, lyricFormat=$lyricFormat');

    final baseName = _baseNameWithoutExt(songPath);
    final dirName = file.parent.path;
    String? coverPath;
    Uint8List? coverBytes;

    try {
      if (cover && songInfo.coverUrl != null && songInfo.coverUrl!.isNotEmpty) {
        try {
          final coverRes = await Dio().get<List<int>>(
            songInfo.coverUrl!,
            options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 15)),
          );
          final rawBytes = coverRes.data;
          if (rawBytes != null && rawBytes.isNotEmpty) {
            coverBytes = Uint8List.fromList(rawBytes);
            final coverExt = _resolveCoverExt(
              songInfo.coverUrl!,
              coverRes.headers.value('content-type'),
            );
            coverPath = '$dirName${Platform.pathSeparator}$baseName$coverExt';
            await File(coverPath).writeAsBytes(coverBytes!);
            debugPrint('[TagWriteService] 封面已下载: $coverPath (${coverBytes!.length} bytes)');
          }
        } catch (e) {
          debugPrint('[TagWriteService] 下载封面失败: $e');
          coverPath = null;
          coverBytes = null;
        }
      }

      if (downloadLyrics && songInfo.lrc != null && songInfo.lrc!.isNotEmpty) {
        try {
          final lrcPath = '$dirName${Platform.pathSeparator}$baseName.lrc';
          final lrcContent = lyricFormat == 'word-by-word'
              ? _convertLrcFormat(songInfo.lrc!)
              : _convertToStandardLrc(songInfo.lrc!);
          if (lrcContent.isNotEmpty) {
            await File(lrcPath).writeAsString(lrcContent);
            debugPrint('[TagWriteService] 歌词文件已保存: $lrcPath');
          }
        } catch (e) {
          debugPrint('[TagWriteService] 单独下载歌词文件失败: $e');
        }
      }

      String? lrcToEmbed;
      if (lyrics && songInfo.lrc != null && songInfo.lrc!.isNotEmpty) {
        lrcToEmbed = lyricFormat == 'word-by-word'
            ? _convertLrcFormat(songInfo.lrc!)
            : _convertToStandardLrc(songInfo.lrc!);
      }

      // 对齐 CeruMusic: basic info 始终写入（title, artist, album, albumArtist）
      final useBasicInfo = basicInfo;
      final useArtwork = cover && coverBytes != null;

      final titleStr = useBasicInfo
          ? (songInfo.title.isNotEmpty ? songInfo.title : '未知曲目')
          : null;
      final artistStr = useBasicInfo
          ? (songInfo.artist.isNotEmpty ? songInfo.artist : '未知艺术家')
          : null;
      final albumStr = useBasicInfo
          ? (songInfo.album.isNotEmpty ? songInfo.album : '未知专辑')
          : null;
      final albumArtistStr = useBasicInfo
          ? (songInfo.artist.isNotEmpty ? songInfo.artist : '未知艺术家')
          : null;

      if (useArtwork) {
        debugPrint('[TagWriteService] 写入标签+封面: title=$titleStr, artist=$artistStr, album=$albumStr, hasLyrics=${lrcToEmbed != null}, artworkSize=${coverBytes?.length}');
        await _writeTagsAndArtwork(
          songPath,
          title: titleStr,
          artist: artistStr,
          album: albumStr,
          albumArtist: albumArtistStr,
          lyrics: lrcToEmbed,
          artwork: coverBytes!,
        );
      } else if (useBasicInfo || lrcToEmbed != null) {
        debugPrint('[TagWriteService] 写入标签: title=$titleStr, artist=$artistStr, album=$albumStr, hasLyrics=${lrcToEmbed != null}');
        await _writeTags(
          songPath,
          title: titleStr,
          artist: artistStr,
          album: albumStr,
          albumArtist: albumArtistStr,
          lyrics: lrcToEmbed,
        );
      } else {
        debugPrint('[TagWriteService] 无需写入标签');
      }
    } catch (e) {
      debugPrint('[TagWriteService] 写入音乐元信息或LRC文件失败: $e');
    } finally {
      if (coverPath != null) {
        final coverFile = File(coverPath);
        if (await coverFile.exists()) {
          await coverFile.delete().catchError((_) {});
          debugPrint('[TagWriteService] 临时封面文件已删除: $coverPath');
        }
      }
    }
  }

  Future<void> _writeTags(
    String filePath, {
    String? title,
    String? artist,
    String? album,
    String? albumArtist,
    String? lyrics,
  }) async {
    try {
      final args = <String, dynamic>{
        'filePath': filePath,
        if (title != null) 'title': title,
        if (artist != null) 'artist': artist,
        if (album != null) 'album': album,
        if (albumArtist != null) 'albumArtist': albumArtist,
        if (lyrics != null) 'lyrics': lyrics,
      };
      debugPrint('[TagWriteService] _writeTags args: $args');
      await _channel.invokeMethod<bool>('writeTags', args);
      debugPrint('[TagWriteService] _writeTags 成功');
    } on PlatformException catch (e) {
      debugPrint('[TagWriteService] writeTags PlatformException: ${e.code} - ${e.message}');
      rethrow;
    }
  }

  Future<void> _writeArtwork(String filePath, Uint8List artwork) async {
    try {
      debugPrint('[TagWriteService] _writeArtwork: path=$filePath, size=${artwork.length}');
      await _channel.invokeMethod<bool>('writeArtwork', {
        'filePath': filePath,
        'artwork': artwork,
      });
      debugPrint('[TagWriteService] _writeArtwork 成功');
    } on PlatformException catch (e) {
      debugPrint('[TagWriteService] writeArtwork PlatformException: ${e.code} - ${e.message}');
      rethrow;
    }
  }

  Future<void> _writeTagsAndArtwork(
    String filePath, {
    String? title,
    String? artist,
    String? album,
    String? albumArtist,
    String? lyrics,
    Uint8List? artwork,
  }) async {
    try {
      final args = <String, dynamic>{
        'filePath': filePath,
        if (title != null) 'title': title,
        if (artist != null) 'artist': artist,
        if (album != null) 'album': album,
        if (albumArtist != null) 'albumArtist': albumArtist,
        if (lyrics != null) 'lyrics': lyrics,
        if (artwork != null) 'artwork': artwork,
      };
      debugPrint('[TagWriteService] _writeTagsAndArtwork args: filePath=$filePath, title=$title, artist=$artist, album=$album, albumArtist=$albumArtist, hasLyrics=${lyrics != null}, hasArtwork=${artwork != null}');
      await _channel.invokeMethod<bool>('writeTagsAndArtwork', args);
      debugPrint('[TagWriteService] _writeTagsAndArtwork 成功');
    } on PlatformException catch (e) {
      debugPrint('[TagWriteService] writeTagsAndArtwork PlatformException: ${e.code} - ${e.message}');
      rethrow;
    }
  }

  bool _isAudioFile(String filePath) {
    final ext = filePath.substring(filePath.lastIndexOf('.')).toLowerCase();
    return ['.mp3', '.flac', '.wav', '.aac', '.m4a', '.ogg', '.wma'].contains(ext);
  }

  String _baseNameWithoutExt(String filePath) {
    final lastSep = filePath.lastIndexOf(Platform.pathSeparator);
    final lastDot = filePath.lastIndexOf('.');
    if (lastDot <= lastSep) return filePath.substring(lastSep + 1);
    return filePath.substring(lastSep + 1, lastDot);
  }

  String _resolveCoverExt(String imgUrl, String? contentType) {
    final validExts = {'.jpg', '.jpeg', '.png', '.webp', '.bmp'};
    String? urlExt;
    try {
      final uri = Uri.parse(imgUrl);
      final pathname = uri.path;
      final i = pathname.lastIndexOf('.');
      if (i != -1) {
        urlExt = pathname.substring(i).toLowerCase();
      }
    } catch (_) {}

    if (urlExt != null && validExts.contains(urlExt)) {
      return urlExt == '.jpeg' ? '.jpg' : urlExt;
    }

    if (contentType != null) {
      if (contentType.contains('image/png')) return '.png';
      if (contentType.contains('image/webp')) return '.webp';
      if (contentType.contains('image/jpeg') || contentType.contains('image/jpg')) return '.jpg';
      if (contentType.contains('image/bmp')) return '.bmp';
    }

    return '.jpg';
  }

  String _convertLrcFormat(String lrc) {
    return lrc;
  }

  String _convertToStandardLrc(String lrc) {
    final lines = lrc.split('\n');
    final standardLines = <String>[];
    for (final line in lines) {
      final timeTagRegex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\]');
      final match = timeTagRegex.firstMatch(line);
      if (match != null) {
        standardLines.add(line);
      } else if (line.startsWith('[') && !line.contains(':')) {
        standardLines.add(line);
      }
    }
    return standardLines.isNotEmpty ? standardLines.join('\n') : lrc;
  }
}