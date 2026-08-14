import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../../core/network/music_api_service.dart';
import '../domain/models/recognize_result.dart';

class RecognizeRepository {
  final MusicApiService _api;
  final Uuid _uuid = const Uuid();

  RecognizeRepository() : _api = MusicApiService();

  /// 对标 CeruMusic wy/recognize.js: 参数通过 URL query string 传递，POST 请求
  Future<List<RecognizeResult>> recognize(
    String fingerprint,
    double duration,
  ) async {
    final sessionId = _uuid.v4();

    // 对标 CeruMusic: new URLSearchParams({...}) - 使用 URI 编码确保特殊字符正确传递
    final params = {
      'sessionId': sessionId,
      'algorithmCode': 'shazam_v2',
      'duration': duration.floor().toString(),
      'rawdata': fingerprint,
      'times': '1',
      'decrypt': '1',
    };

    final queryString = params.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');

    final url =
        'https://interface.music.163.com/api/music/audio/match?$queryString';

    try {
      // 对标 CeruMusic: httpFetch(url, { method: 'POST' }) - 参数在 URL 上，POST 空 body
      final response = await _api.post(
        url,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/60.0.3112.90 Safari/537.36',
          'origin': 'https://music.163.com',
          'referer': 'https://music.163.com',
        },
      );

      final body = _decodeJson(response.data);
      debugPrint('[RecognizeRepo] raw response: $body');

      final data = body?['data'];
      final rawResults = data is Map ? data['result'] : null;
      if (rawResults is List) {
        final results = rawResults;
        final tasks = <Future<RecognizeResult?>>[];

        for (final item in results) {
          if (item is! Map) continue;
          tasks.add(_parseResultItem(item));
        }

        final parsed = await Future.wait(tasks);
        return parsed.whereType<RecognizeResult>().toList();
      }
      return [];
    } catch (e) {
      debugPrint('[RecognizeRepo] error: $e');
      return [];
    }
  }

  Future<RecognizeResult?> _parseResultItem(Map item) async {
    try {
      final rawSong = item['song'];
      if (rawSong == null) return null;

      final artists = rawSong['artist'] ?? rawSong['artists'] ?? [];
      final artistName = _formatSingerName(artists, 'name');
      final album = rawSong['album'] ?? <String, dynamic>{};
      final startTime = (item['startTime'] as num?)?.toDouble() ?? 0;
      final rawDuration = (rawSong['duration'] as num?)?.toDouble() ?? 0;

      final detailResult = await _fetchSongDetail(
        rawSong['id']?.toString() ?? '',
      );
      List<Map<String, String>> types = [];
      if (detailResult != null) {
        types = _parseQualityTypes(detailResult);
      }

      return RecognizeResult(
        songmid: rawSong['id']?.toString() ?? '',
        name: rawSong['name']?.toString() ?? '',
        singer: artistName,
        albumName: album['name']?.toString() ?? '',
        albumId: album['id']?.toString() ?? '',
        source: 'wy',
        interval: _formatPlayTime(rawDuration / 1000),
        img:
            album['picUrl']?.toString() ??
            album['blurPicUrl']?.toString() ??
            '',
        startTime: startTime,
        lrc: null,
        types: types,
      );
    } catch (e) {
      debugPrint('[RecognizeRepo] parse error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchSongDetail(String songId) async {
    if (songId.isEmpty) return null;
    try {
      final response = await _api.get(
        'https://music.163.com/api/song/music/detail/get?songId=$songId',
        headers: {
          'User-Agent':
              'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/60.0.3112.90 Safari/537.36',
          'origin': 'https://music.163.com',
        },
      );
      final body = _decodeJson(response.data);
      if (body?['code'] == 200 && body?['data'] is Map) {
        return Map<String, dynamic>.from(body!['data'] as Map);
      }
    } catch (e) {
      debugPrint('[RecognizeRepo] detail fetch error: $e');
    }
    return null;
  }

  List<Map<String, String>> _parseQualityTypes(Map<String, dynamic> data) {
    final types = <Map<String, String>>[];
    void addType(String key, String label) {
      final size = data[key]?['size'];
      if (size != null && size is num) {
        types.add({'type': label, 'size': _sizeFormate(size)});
      }
    }

    addType('jm', 'master');
    addType('db', 'dolby');
    addType('hr', 'hires');
    addType('sq', 'flac');
    addType('h', '320k');
    addType('m', '128k');
    if (types.where((t) => t['type'] == '128k').isEmpty) {
      addType('l', '128k');
    }
    return types.reversed.toList();
  }

  String _formatPlayTime(double time) {
    final m = time ~/ 60;
    final s = time % 60;
    if (m == 0 && s == 0) return '--/--';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _sizeFormate(num size) {
    if (size <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    final number = (log(size.toDouble()) / log(1024)).floor();
    final value = size / pow(1024, number);
    return '${value.toStringAsFixed(2)} ${units[number]}';
  }

  String _formatSingerName(List<dynamic> artists, String key) {
    return artists
        .map((a) => a is Map ? a[key]?.toString() ?? '' : '')
        .join(' / ');
  }

  Map<String, dynamic>? _decodeJson(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
