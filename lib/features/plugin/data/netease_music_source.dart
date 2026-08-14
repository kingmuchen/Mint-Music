import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../../core/network/music_api_service.dart';
import '../../../core/network/netease_crypto.dart';
import '../../player/domain/models/song.dart';
import '../../player/domain/models/lyric_line.dart';
import '../../discover/domain/models/playlist.dart';
import '../../discover/domain/models/leaderboard.dart';
import '../domain/music_source_provider.dart';

enum _ApiType { weapi, eapi, linuxapi }

class _DirectApiConfig {
  final _ApiType type;
  final String path;
  final Map<String, dynamic> body;

  const _DirectApiConfig(this.type, this.path, this.body);
}

class NeteaseMusicSource implements MusicSourceProvider {
  final MusicApiService _apiService = MusicApiService.shared;

  @override
  String get name => 'NeteaseCloudMusic';

  @override
  String get version => '1.0.0';

  // Direct NetEase API
  static const _neteaseHost = 'https://music.163.com';
  static const _interface3Host = 'https://interface3.music.163.com';
  static const _linuxApiUrl = 'https://music.163.com/api/linux/forward';

  static const _neteaseHeaders = {
    'User-Agent':
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/60.0.3112.90 Safari/537.36',
    'Referer': 'https://music.163.com/',
    'Origin': 'https://music.163.com',
  };

  // Proxy fallback
  static const _proxyPrimary = 'https://netease-cloud-music-api.fe-mm.com';
  static const _proxyFallback = 'https://ncmapi.btwoa.com';

  String _currentProxyBase = _proxyPrimary;

  static const _encryptMagic = '3go8&\$8*3*3h0k(2)2';

  String _encryptPicId(String picId) {
    final magicBytes = utf8.encode(_encryptMagic);
    final idBytes = utf8.encode(picId);
    final result = <int>[];
    for (var i = 0; i < idBytes.length; i++) {
      result.add(idBytes[i] ^ magicBytes[i % magicBytes.length]);
    }
    final md5Hash = md5.convert(result);
    final base64Str = base64.encode(md5Hash.bytes);
    return base64Str.replaceAll('/', '_').replaceAll('+', '-');
  }

  String? _buildCoverUrl(dynamic item, {bool includePicId = true}) {
    final info = item is Map ? item : const <String, dynamic>{};
    final album = info['al'] is Map
        ? info['al'] as Map
        : (info['album'] is Map ? info['album'] as Map : null);

    String? coverUrl = _normalizeCoverUrl(album?['picUrl']);
    coverUrl ??= _normalizeCoverUrl(album?['pic_url']);
    coverUrl ??= _normalizeCoverUrl(album?['blurPicUrl']);
    coverUrl ??= _normalizeCoverUrl(info['picUrl']);
    coverUrl ??= _normalizeCoverUrl(info['pic_url']);
    coverUrl ??= _normalizeCoverUrl(info['cover']);
    coverUrl ??= _normalizeCoverUrl(info['blurPicUrl']);

    if (includePicId && (coverUrl == null || coverUrl.isEmpty)) {
      final picId =
          album?['picId'] ??
          album?['pic_id'] ??
          info['picId'] ??
          info['pic_id'];
      if (picId != null) {
        final encryptedId = _encryptPicId(picId.toString());
        coverUrl = 'https://p1.music.126.net/$encryptedId/$picId.jpg';
      }
    }

    return coverUrl;
  }

  String? _normalizeCoverUrl(dynamic value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    final normalized = raw.startsWith('//')
        ? 'https:$raw'
        : raw.startsWith('http://')
        ? 'https://${raw.substring(7)}'
        : raw;
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    return normalized;
  }

  Map<String, dynamic> _normalizeSearchSong(Map item) {
    final baseInfo = item['baseInfo'];
    final simpleSongData = baseInfo is Map && baseInfo['simpleSongData'] is Map
        ? Map<String, dynamic>.from(baseInfo['simpleSongData'] as Map)
        : null;
    final songInfo = item['songInfo'] is Map
        ? Map<String, dynamic>.from(item['songInfo'] as Map)
        : null;

    // The search endpoint wraps the real song in simpleSongData. songInfo is
    // a resource-level object and can contain a different/partial album.
    final result = <String, dynamic>{
      ...(simpleSongData ?? songInfo ?? Map<String, dynamic>.from(item)),
    };

    // Only fill missing fields from the wrapper. Keep the canonical song
    // object's album and cover together to prevent cross-album covers.
    for (final fallback in [songInfo, item]) {
      if (fallback == null) continue;
      for (final key in [
        'id',
        'name',
        'dt',
        'duration',
        'ar',
        'artists',
        'al',
        'album',
        'picUrl',
        'pic_url',
        'cover',
        'blurPicUrl',
        'picId',
        'pic_id',
      ]) {
        final value = result[key];
        if ((value == null || (value is String && value.trim().isEmpty)) &&
            fallback[key] != null) {
          result[key] = fallback[key];
        }
      }
    }

    final artists = result['ar'] ?? result['artists'];
    if (artists is List) {
      result['ar'] = artists
          .whereType<Map>()
          .map((artist) => {'id': artist['id'], 'name': artist['name']})
          .toList();
    }

    final album = result['al'] ?? result['album'];
    if (album is Map) {
      result['al'] = {
        ...Map<String, dynamic>.from(album),
        'id': album['id'],
        'name': album['name'],
        'picUrl': album['picUrl'] ?? album['pic_url'],
      };
    }

    // Some responses omit the cover from simpleSongData while keeping it in
    // the same resource's songInfo. Use that only as a missing-field fallback.
    final currentCoverUrl = _buildCoverUrl(result);
    final coverUrl =
        currentCoverUrl ??
        _buildCoverUrl(simpleSongData) ??
        _buildCoverUrl(songInfo);
    if (coverUrl != null && currentCoverUrl == null) {
      final currentAlbum = result['al'];
      if (currentAlbum is Map) {
        result['al'] = {
          ...Map<String, dynamic>.from(currentAlbum),
          'picUrl': coverUrl,
        };
      } else {
        result['picUrl'] = coverUrl;
      }
    }
    result['dt'] = result['dt'] ?? result['duration'] ?? 0;
    return result;
  }

  // ── Direct API (encrypted) ──────────────────────────────────────

  Future<Map?> _directRequest(_DirectApiConfig config) async {
    late String url;
    late Map<String, String> formData;

    switch (config.type) {
      case _ApiType.weapi:
        url = '$_neteaseHost${config.path}';
        formData = NeteaseCrypto.weapi(config.body);
        break;
      case _ApiType.eapi:
        url = '$_interface3Host${config.path}';
        formData = NeteaseCrypto.eapi(config.path, config.body);
        break;
      case _ApiType.linuxapi:
        url = _linuxApiUrl;
        formData = NeteaseCrypto.linuxapi(config.body);
        break;
    }

    final response = await _apiService.post(
      url,
      headers: _neteaseHeaders,
      form: formData,
    );

    final data = response.data;
    if (data is Map && data['code'] == 200) {
      return data;
    }
    throw Exception(
      'Direct API error: url=$url, code=${data is Map ? data['code'] : '?'}',
    );
  }

  /// Normalize direct API responses to match proxy-style structure
  /// so downstream parsing code works unchanged.
  Map? _normalizeDirectResponse(Map raw, _DirectApiConfig config) {
    // eapi search: {data: {resources: [{songInfo: {...}},...]}}
    // → proxy style: {result: {songs: [{id, name, ar, al, dt}]}}
    if (config.type == _ApiType.eapi &&
        config.path == '/api/search/song/list/page') {
      final resources = raw['data']?['resources'] as List?;
      if (resources == null || resources.isEmpty) return raw;
      final songs = resources.map((item) {
        final itemMap = item is Map ? item : const <String, dynamic>{};
        return _normalizeSearchSong(itemMap);
      }).toList();
      return {
        'code': 200,
        'result': {'songs': songs},
      };
    }

    // eapi hot search: {data: {itemList: [{searchWord: ...}]}}
    // → proxy style: {result: {hots: [{first: ...}]}}
    if (config.type == _ApiType.eapi &&
        config.path == '/api/search/chart/detail') {
      final items = raw['data']?['itemList'] as List?;
      if (items == null || items.isEmpty) return raw;
      final hots = items
          .map((item) => {'first': item['searchWord']?.toString() ?? ''})
          .toList();
      return {
        'code': 200,
        'result': {'hots': hots},
      };
    }

    return raw;
  }

  // ── Proxy fallback ──────────────────────────────────────────────

  Future<dynamic> _proxyRequest(
    String path, {
    Map<String, String>? queryParams,
  }) async {
    final uri = Uri.parse(
      '$_currentProxyBase$path',
    ).replace(queryParameters: queryParams);

    try {
      final response = await _apiService.get(uri.toString());
      final data = response.data;
      if (data is Map && data['code'] == 200) {
        return data;
      }
      if (_currentProxyBase == _proxyPrimary) {
        _currentProxyBase = _proxyFallback;
        final fallbackUri = Uri.parse(
          '$_currentProxyBase$path',
        ).replace(queryParameters: queryParams);
        final fallbackResponse = await _apiService.get(fallbackUri.toString());
        final fallbackData = fallbackResponse.data;
        if (fallbackData is Map && fallbackData['code'] == 200) {
          return fallbackData;
        }
      }
      return data;
    } catch (e) {
      if (_currentProxyBase == _proxyPrimary) {
        _currentProxyBase = _proxyFallback;
        try {
          final fallbackUri = Uri.parse(
            '$_currentProxyBase$path',
          ).replace(queryParameters: queryParams);
          final fallbackResponse = await _apiService.get(
            fallbackUri.toString(),
          );
          final fallbackData = fallbackResponse.data;
          if (fallbackData is Map && fallbackData['code'] == 200) {
            return fallbackData;
          }
          return fallbackData;
        } catch (e2) {
          rethrow;
        }
      }
      rethrow;
    }
  }

  // ── Unified request: direct → proxy fallback ───────────────────

  Future<dynamic> _request(
    String proxyPath, {
    Map<String, String>? proxyParams,
    _DirectApiConfig? direct,
  }) async {
    if (direct != null) {
      try {
        final raw = await _directRequest(direct);
        if (raw != null) {
          final normalized = _normalizeDirectResponse(raw, direct);
          if (normalized != null) return normalized;
        }
      } catch (e) {
        print('[NeteaseMusicSource] 直连API失败, 回退代理: $e');
      }
    }
    return _proxyRequest(proxyPath, queryParams: proxyParams);
  }

  // ── MusicSourceProvider implementation ──────────────────────────

  @override
  Future<List<Song>> search(
    String query, {
    int page = 1,
    int limit = 20,
  }) async {
    if (query.isEmpty) return [];

    try {
      final offset = limit * (page - 1);

      final data = await _request(
        '/search',
        proxyParams: {
          'keywords': query,
          'limit': '$limit',
          'offset': '$offset',
        },
        direct: _DirectApiConfig(_ApiType.eapi, '/api/search/song/list/page', {
          'keyword': query,
          'needCorrect': '1',
          'channel': 'typing',
          'offset': offset,
          'scene': 'normal',
          'total': true,
          'limit': limit,
        }),
      );

      if (data == null || data['code'] != 200) return [];

      final result = data['result'];
      if (result == null) return [];

      final songs = result['songs'] as List? ?? [];
      if (songs.isEmpty) return [];

      final songsNeedingExactCover = <String>[];
      final resultSongs = songs.map((item) {
        final songId = item['id'].toString();
        // Use the search response immediately. A single batch detail request
        // below only corrects results whose cover is exposed as a lossy picId.
        final coverUrl = _buildCoverUrl(item);
        if (_buildCoverUrl(item, includePicId: false) == null) {
          songsNeedingExactCover.add(songId);
        }
        final rawDt = item['dt'] ?? item['duration'] ?? 0;
        final durationMs = rawDt is int
            ? rawDt
            : (int.tryParse(rawDt.toString()) ?? 0);
        return Song(
          id: 'wy_$songId',
          title: item['name']?.toString() ?? '',
          artist: _getArtists(item['ar'] ?? item['artists']),
          album:
              item['al']?['name']?.toString() ??
              item['album']?['name']?.toString() ??
              '',
          duration: durationMs ~/ 1000,
          coverUrl: coverUrl,
          source: 'wy',
        );
      }).toList();

      if (songsNeedingExactCover.isEmpty) return resultSongs;

      final exactCovers = await _getBatchCoverUrls(songsNeedingExactCover);
      if (exactCovers.isEmpty) return resultSongs;

      return resultSongs
          .map(
            (song) => exactCovers[song.id] == null
                ? song
                : song.copyWith(coverUrl: exactCovers[song.id]),
          )
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, String>> _getBatchCoverUrls(List<String> songIds) async {
    if (songIds.isEmpty) return const <String, String>{};

    try {
      final data = await _proxyRequest(
        '/song/detail',
        queryParams: {'ids': songIds.join(',')},
      ).timeout(const Duration(seconds: 5));
      if (data is! Map || data['code'] != 200) {
        return const <String, String>{};
      }

      final details = data['songs'] as List? ?? [];
      final covers = <String, String>{};
      for (final item in details) {
        if (item is! Map) continue;
        final id = item['id']?.toString();
        final cover = _buildCoverUrl(item, includePicId: false);
        if (id != null && cover != null && cover.isNotEmpty) {
          covers['wy_$id'] = cover;
        }
      }
      return covers;
    } catch (e) {
      print('[NeteaseMusicSource] batch cover lookup failed: $e');
      return const <String, String>{};
    }
  }

  @override
  Future<Playlist?> getPlaylistDetail(String playlistId) async {
    try {
      final cleanId = playlistId.replaceAll('wy_', '');

      final data = await _request(
        '/playlist/detail',
        proxyParams: {'id': cleanId, 'n': '100000', 's': '8'},
        direct: _DirectApiConfig(_ApiType.linuxapi, '/api/v3/playlist/detail', {
          'method': 'POST',
          'url': 'https://music.163.com/api/v3/playlist/detail',
          'params': {'id': cleanId, 'n': 100000, 's': 8},
        }),
      );

      if (data == null) return null;
      if (data['code'] != 200) return null;

      final playlist = data['playlist'];
      if (playlist == null) return null;

      final songs = _parsePlaylistSongs(playlist);

      return Playlist(
        id: playlistId,
        title: playlist['name']?.toString() ?? '',
        description: playlist['description']?.toString() ?? '',
        coverUrl: _normalizeCoverUrl(playlist['coverImgUrl']),
        songCount: playlist['trackCount'] ?? songs.length,
        songs: songs,
        source: 'wy',
      );
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<Playlist>> getHotPlaylists() async {
    try {
      final data = await _request(
        '/top/playlist',
        proxyParams: {'limit': '20', 'order': 'hot'},
        direct: _DirectApiConfig(_ApiType.weapi, '/weapi/playlist/list', {
          'cat': '全部',
          'order': 'hot',
          'limit': 20,
          'offset': 0,
          'total': true,
        }),
      );

      if (data == null || data['code'] != 200) return [];

      final playlists = data['playlists'] as List? ?? [];
      return playlists.map((pl) {
        return Playlist(
          id: 'wy_${pl['id']}',
          title: pl['name']?.toString() ?? '',
          description: pl['description']?.toString() ?? '',
          coverUrl: _normalizeCoverUrl(pl['coverImgUrl']),
          songCount: pl['trackCount'] ?? 0,
          playCount: _formatPlayCount(pl['playCount']),
          author: pl['creator']?['nickname']?.toString(),
          source: 'wy',
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<Song>> getPlaylistSongs(String playlistId) async {
    final playlist = await getPlaylistDetail(playlistId);
    return playlist?.songs ?? [];
  }

  @override
  Future<String?> getSongUrl(String songId) async {
    try {
      final cleanId = songId.replaceAll('wy_', '');

      // Try direct weapi first (may require cookie for some songs)
      try {
        final directData = await _directRequest(
          _DirectApiConfig(
            _ApiType.weapi,
            '/weapi/song/enhance/player/url/v1',
            {
              'ids': '[${int.tryParse(cleanId) ?? cleanId}]',
              'level': 'standard',
              'encodeType': 'aac',
              'csrf_token': '',
            },
          ),
        );
        final songs = directData?['data'] as List? ?? [];
        if (songs.isNotEmpty) {
          final url = songs.first['url']?.toString();
          if (url != null && url.isNotEmpty && url != '') {
            return url;
          }
        }
      } catch (_) {}

      // Fallback to proxy
      final data = await _proxyRequest(
        '/song/url/v1',
        queryParams: {'id': cleanId, 'level': 'standard'},
      );

      if (data == null || data['code'] != 200) return null;

      final songs = data['data'] as List? ?? [];
      if (songs.isEmpty) return null;

      return songs.first['url']?.toString();
    } catch (e) {
      return null;
    }
  }

  @override
  Future<String?> getLyric(String songId) async {
    final result = await getLyricResult(songId);
    final wordLyric = result?.crlyric?.trim();
    if (wordLyric != null && wordLyric.isNotEmpty) return result!.crlyric;
    return result?.lrc;
  }

  @override
  Future<LyricResult?> getLyricResult(String songId) async {
    try {
      final cleanId = songId.replaceAll('wy_', '');

      final data = await _requestLyricData(cleanId);

      if (data == null || data['code'] != 200) return null;

      final lrc = _readLyricText(data, 'lrc');
      var yrc = _readLyricText(data, 'yrc');
      final tlyric = _readLyricText(data, 'tlyric');
      final rlyric = _readLyricText(data, 'romalrc');

      if ((yrc == null || yrc.trim().isEmpty) &&
          lrc != null &&
          lrc.trim().isNotEmpty) {
        final nonEmpty = lrc
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .toList();
        final yrcMatchCount = nonEmpty
            .take(10)
            .where((l) => RegExp(r'^\[\d+,\d+\]\(.*\)').hasMatch(l.trim()))
            .length;
        if (yrcMatchCount >= 2) {
          yrc = lrc;
        }
      }

      if (yrc != null && yrc.trim().isNotEmpty) {
        final converted = _convertNeteaseYrc(yrc, lrcText: lrc);
        if (converted != null) {
          yrc = converted;
        } else {
          yrc = null;
        }
      }

      if ((lrc == null || lrc.isEmpty) && (yrc == null || yrc.isEmpty)) {
        return null;
      }

      return LyricResult(
        lrc: lrc,
        crlyric: (yrc != null && yrc.isNotEmpty) ? yrc : null,
        tlyric: tlyric,
        rlyric: rlyric,
      );
    } catch (e) {
      return null;
    }
  }

  Future<dynamic> _requestLyricData(String cleanId) async {
    dynamic fallbackData;

    // Try direct eapi first
    try {
      final directData = await _directRequest(
        _DirectApiConfig(_ApiType.eapi, '/eapi/song/lyric/v1', {
          'id': cleanId,
          'cp': false,
          'tv': 0,
          'lv': 0,
          'rv': 0,
          'kv': 0,
          'yv': 0,
          'ytv': 0,
          'yrv': 0,
        }),
      );
      if (directData != null && directData['code'] == 200) {
        final yrc = _readLyricText(directData, 'yrc');
        if (yrc != null && yrc.trim().isNotEmpty) return directData;
        fallbackData ??= directData;
      }
    } catch (_) {}

    // Fallback to proxy
    final requests = [
      (
        path: '/lyric/new',
        params: {
          'id': cleanId,
          'cp': 'false',
          'tv': '0',
          'lv': '0',
          'rv': '0',
          'kv': '0',
          'yv': '0',
          'ytv': '0',
          'yrv': '0',
        },
      ),
      (path: '/lyric', params: {'id': cleanId}),
    ];

    for (final request in requests) {
      final data = await _proxyRequest(
        request.path,
        queryParams: request.params,
      );
      if (data == null || data['code'] != 200) continue;
      final yrc = _readLyricText(data, 'yrc');
      if (yrc != null && yrc.trim().isNotEmpty) return data;
      fallbackData ??= data;
    }

    return fallbackData;
  }

  String? _readLyricText(dynamic data, String key) {
    final section = data?[key];
    if (section is Map) {
      final lyric = section['lyric']?.toString();
      if (lyric != null && lyric.trim().isNotEmpty) return lyric;
      return null;
    }
    if (section is String && section.trim().isNotEmpty && section != 'null') {
      return section;
    }
    return null;
  }

  Map<int, String> _parseLrcSimple(String lrcText) {
    final result = <int, String>{};
    final regex = RegExp(r'\[(\d+):(\d+)(?:[\.:](\d+))?\](.*)');
    for (final line in lrcText.split('\n')) {
      final match = regex.firstMatch(line.trim());
      if (match == null) continue;
      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      final ms = match.group(3) != null && match.group(3)!.isNotEmpty
          ? int.parse(match.group(3)!.padRight(3, '0').substring(0, 3))
          : 0;
      final text = match.group(4)?.trim() ?? '';
      if (text.isEmpty) continue;
      result[minutes * 60000 + seconds * 1000 + ms] = text;
    }
    return result;
  }

  List<_YrcItem>? _injectSpacesFromLrc(
    List<_YrcItem> items,
    String lrcLineText,
  ) {
    if (items.any((i) => i.tx == ' ')) return null;

    final yrcText = items.map((i) => i.tx).join('');

    String stripForCompare(String s) =>
        s.replaceAll(RegExp(r'[^a-zA-Z0-9\u4e00-\u9fff]'), '').toLowerCase();
    if (stripForCompare(yrcText) != stripForCompare(lrcLineText)) {
      return null;
    }

    final lrcAlphaPositions = <int>[];
    for (int i = 0; i < lrcLineText.length; i++) {
      if (RegExp(r'[a-zA-Z0-9\u4e00-\u9fff]').hasMatch(lrcLineText[i])) {
        lrcAlphaPositions.add(i);
      }
    }

    if (lrcAlphaPositions.length != items.length) return null;

    final result = <_YrcItem>[];
    for (int j = 0; j < items.length; j++) {
      final lrcPos = lrcAlphaPositions[j];
      if (j > 0 && lrcPos > 0 && lrcLineText[lrcPos - 1] == ' ') {
        final prevEnd = items[j - 1].relStart + 80;
        final nextStart = items[j].relStart;
        final spaceTime = prevEnd < nextStart
            ? prevEnd + (nextStart - prevEnd) ~/ 2
            : nextStart;
        result.add(_YrcItem(' ', spaceTime));
      }
      result.add(items[j]);
    }

    return result;
  }

  List<_YrcItem>? _injectSpacesFromGaps(List<_YrcItem> items) {
    if (items.any((i) => i.tx == ' ')) return null;
    if (items.length < 4) return null;

    final gaps = <int>[];
    for (int i = 1; i < items.length; i++) {
      gaps.add(items[i].relStart - items[i - 1].relStart);
    }
    if (gaps.isEmpty) return null;

    gaps.sort();
    final medianGap = gaps[gaps.length ~/ 2];

    final threshold = (medianGap * 1.5).toInt();
    if (threshold < 60) return null;

    final result = <_YrcItem>[];
    int injectedCount = 0;
    for (int i = 0; i < items.length; i++) {
      if (i > 0) {
        final gap = items[i].relStart - items[i - 1].relStart;
        if (gap > threshold) {
          final spaceTime = items[i - 1].relStart + gap ~/ 2;
          result.add(_YrcItem(' ', spaceTime));
          injectedCount++;
        }
      }
      result.add(items[i]);
    }

    return injectedCount == 0 ? null : result;
  }

  List<_YrcItem> _injectSpacesForLine(
    List<_YrcItem> items,
    int lineStart,
    Map<int, String>? lrcMap,
  ) {
    if (items.length < 2) return items;
    if (items.any((i) => i.tx == ' ')) return items;

    if (lrcMap != null && lrcMap.isNotEmpty) {
      String? lrcLine;
      int minDiff = 5000;
      for (final entry in lrcMap.entries) {
        final diff = (lineStart - entry.key).abs();
        if (diff < minDiff) {
          minDiff = diff;
          lrcLine = entry.value;
        }
      }
      if (lrcLine != null) {
        final result = _injectSpacesFromLrc(items, lrcLine);
        if (result != null) return result;
      }
    }

    final gapResult = _injectSpacesFromGaps(items);
    if (gapResult != null) return gapResult;

    return items;
  }

  String? _convertNeteaseYrc(String yrcText, {String? lrcText}) {
    try {
      final rawLines = yrcText.split('\n');
      final lrcMap = lrcText != null ? _parseLrcSimple(lrcText) : null;

      final outputItems = <_ConvertedLine>[];

      for (final rawLine in rawLines) {
        final trimmed = rawLine.trim();
        if (trimmed.isEmpty) continue;

        if (!trimmed.startsWith('{')) {
          outputItems.add(_ConvertedLine.raw(trimmed));
          continue;
        }

        final json = jsonDecode(trimmed) as Map?;
        if (json == null) continue;
        final lineStartRaw = json['t'];
        if (lineStartRaw is! num) continue;
        final int lineStart = lineStartRaw is double
            ? (lineStartRaw < 100000
                  ? (lineStartRaw * 1000).round()
                  : lineStartRaw.round())
            : lineStartRaw as int;
        final chars = json['c'] as List?;
        if (chars == null || chars.isEmpty) continue;

        final items = <_YrcItem>[];
        for (final char in chars) {
          if (char is! Map) continue;
          final tx = char['tx']?.toString() ?? '';
          if (tx.isEmpty) continue;
          final tStr = char['t']?.toString();
          int relStart;
          if (tStr != null && tStr.isNotEmpty) {
            relStart = _parseNeteaseCharTime(tStr);
          } else {
            relStart = items.isEmpty ? 0 : items.last.relStart + 200;
          }
          items.add(_YrcItem(tx, relStart));
        }
        if (items.isNotEmpty) {
          final processedItems = _injectSpacesForLine(items, lineStart, lrcMap);
          outputItems.add(_ConvertedLine.json(lineStart, processedItems));
        }
      }

      final resultLines = <String>[];

      for (int i = 0; i < outputItems.length; i++) {
        final item = outputItems[i];
        if (item.type == 'raw') {
          resultLines.add(item.text!);
          continue;
        }

        final lineStart = item.start!;
        final items = item.items!;

        int nextLineStart = lineStart + 5000;
        for (int k = i + 1; k < outputItems.length; k++) {
          if (outputItems[k].start != null &&
              outputItems[k].start! > lineStart) {
            nextLineStart = outputItems[k].start!;
            break;
          }
        }

        final itemEnds = <int>[];
        for (int j = 0; j < items.length; j++) {
          itemEnds.add(
            j < items.length - 1
                ? lineStart + items[j + 1].relStart
                : nextLineStart,
          );
        }

        final yrcWords = <String>[];
        int wordStartRel = -1;
        int wordEndMs = -1;
        final wordBuf = StringBuffer();

        for (int j = 0; j < items.length; j++) {
          final itemX = items[j];
          if (itemX.tx == ' ') {
            if (wordBuf.isNotEmpty) {
              final absStart = lineStart + wordStartRel;
              final dur = wordEndMs - absStart;
              yrcWords.add(
                '($absStart,${dur > 0 ? dur : 100},0)${wordBuf.toString()} ',
              );
              wordBuf.clear();
              wordStartRel = -1;
            }
          } else {
            if (wordBuf.isEmpty) wordStartRel = itemX.relStart;
            wordBuf.write(itemX.tx);
            wordEndMs = itemEnds[j];
          }
        }
        if (wordBuf.isNotEmpty) {
          final absStart = lineStart + wordStartRel;
          final dur = wordEndMs - absStart;
          yrcWords.add(
            '($absStart,${dur > 0 ? dur : 100},0)${wordBuf.toString()} ',
          );
        }

        if (yrcWords.isEmpty) continue;

        var maxEnd = lineStart;
        for (final w in yrcWords) {
          final m = RegExp(r'\((\d+),(\d+),0\)').firstMatch(w);
          if (m != null) {
            final end = int.parse(m.group(1)!) + int.parse(m.group(2)!);
            if (end > maxEnd) maxEnd = end;
          }
        }
        resultLines.add(
          '[$lineStart,${maxEnd - lineStart}]${yrcWords.join('')}',
        );
      }

      if (resultLines.isEmpty) return null;
      return resultLines.join('\n');
    } catch (e) {
      return null;
    }
  }

  int _parseNeteaseCharTime(String timeStr) {
    try {
      final parts = timeStr.split(':');
      if (parts.length != 2) return 0;
      final minutes = int.tryParse(parts[0]) ?? 0;
      final secParts = parts[1].split('.');
      final seconds = int.tryParse(secParts[0]) ?? 0;
      final ms = secParts.length > 1
          ? int.tryParse(secParts[1].padRight(3, '0').substring(0, 3)) ?? 0
          : 0;
      return minutes * 60000 + seconds * 1000 + ms;
    } catch (e) {
      return 0;
    }
  }

  @override
  Future<String?> getCoverUrl(String songId) async {
    try {
      final cleanId = songId.replaceAll('wy_', '');

      final data = await _request(
        '/song/detail',
        proxyParams: {'ids': cleanId},
        direct: _DirectApiConfig(_ApiType.weapi, '/weapi/v3/song/detail', {
          'c': jsonEncode([
            {'id': int.tryParse(cleanId) ?? 0},
          ]),
          'ids': '[$cleanId]',
        }),
      );

      if (data == null || data['code'] != 200) return null;

      final songs = data['songs'] as List? ?? [];
      if (songs.isEmpty) return null;

      return _buildCoverUrl(songs.first);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<String>> getHotSearchTags() async {
    try {
      final data = await _request(
        '/search/hot',
        direct: _DirectApiConfig(_ApiType.eapi, '/api/search/chart/detail', {
          'id': 'HOT_SEARCH_SONG#@#',
        }),
      );

      if (data == null || data['code'] != 200) return [];

      final hots = data['result']?['hots'] as List? ?? [];
      return hots
          .map((h) => h['first']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .take(10)
          .toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<String>> getSearchSuggestions(String query) async {
    if (query.isEmpty) return [];

    try {
      final data = await _request(
        '/search/suggest',
        proxyParams: {'keywords': query},
        direct: _DirectApiConfig(_ApiType.weapi, '/weapi/search/suggest/web', {
          's': query,
        }),
      );

      if (data == null || data['code'] != 200) return [];

      final result = data['result'];
      if (result == null) return [];

      // Support both proxy and direct response structure
      final songs =
          result['songs'] as List? ?? result['suggests'] as List? ?? [];
      if (songs.isEmpty) return [];

      return songs.map((s) {
        final name = s['name']?.toString() ?? '';
        final artists = _getArtists(s['artists'] ?? s['ar']);
        return '$name - $artists';
      }).toList();
    } catch (e) {
      return [];
    }
  }

  String _getArtists(dynamic ar) {
    if (ar == null) return '';
    if (ar is List) {
      return ar.map((a) => a['name']?.toString() ?? '').join('、');
    }
    return ar.toString();
  }

  List<Song> _parsePlaylistSongs(dynamic playlist) {
    final tracks = playlist['tracks'] as List? ?? [];
    final trackIds = playlist['trackIds'] as List? ?? [];

    if (tracks.isNotEmpty) {
      return tracks.map((track) {
        return Song(
          id: 'wy_${track['id']}',
          title: track['name']?.toString() ?? '',
          artist: _getArtists(track['ar']),
          album: track['al']?['name']?.toString() ?? '',
          duration: ((track['dt'] ?? track['duration'] ?? 0) ~/ 1000),
          coverUrl: _buildCoverUrl(track),
          source: 'wy',
        );
      }).toList();
    }

    return trackIds.map((t) {
      return Song(
        id: 'wy_${t['id']}',
        title: '',
        artist: '',
        album: '',
        duration: 0,
        source: 'wy',
      );
    }).toList();
  }

  @override
  Future<List<PlaylistTagGroup>> getPlaylistTags() async {
    try {
      final data = await _request(
        '/playlist/catlist',
        direct: _DirectApiConfig(
          _ApiType.weapi,
          '/weapi/playlist/catalogue',
          {},
        ),
      );

      if (data == null || data['code'] != 200) return [];

      final sub = data['sub'] as List? ?? [];
      final categories = data['categories'] as Map<String, dynamic>? ?? {};

      final subMap = <int, List<PlaylistTag>>{};
      for (final item in sub) {
        final category = item['category'] as int? ?? 0;
        subMap.putIfAbsent(category, () => []);
        subMap[category]!.add(
          PlaylistTag(
            id: item['name']?.toString() ?? '',
            name: item['name']?.toString() ?? '',
            source: 'wy',
          ),
        );
      }

      final groups = <PlaylistTagGroup>[];
      for (final entry in categories.entries) {
        final key = int.tryParse(entry.key) ?? -1;
        groups.add(
          PlaylistTagGroup(
            name: entry.value?.toString() ?? '',
            tags: subMap[key] ?? [],
          ),
        );
      }

      return groups;
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<PlaylistTag>> getHotPlaylistTags() async {
    try {
      final data = await _request(
        '/playlist/hot',
        direct: _DirectApiConfig(_ApiType.weapi, '/weapi/playlist/hottags', {}),
      );

      if (data == null || data['code'] != 200) return [];

      final tags = data['tags'] as List? ?? [];
      return tags
          .map(
            (t) => PlaylistTag(
              id:
                  t['playlistTag']?['name']?.toString() ??
                  t['name']?.toString() ??
                  '',
              name:
                  t['playlistTag']?['name']?.toString() ??
                  t['name']?.toString() ??
                  '',
              source: 'wy',
            ),
          )
          .toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<Playlist>> getCategoryPlaylists({
    required String sortId,
    required String tagId,
    required int page,
    required int limit,
  }) async {
    try {
      final cat = tagId.isEmpty ? '全部' : tagId;
      final offset = limit * (page - 1);

      final data = await _request(
        '/top/playlist',
        proxyParams: {
          'cat': cat,
          'order': sortId,
          'limit': '$limit',
          'offset': '$offset',
        },
        direct: _DirectApiConfig(_ApiType.weapi, '/weapi/playlist/list', {
          'cat': cat,
          'order': sortId,
          'limit': limit,
          'offset': offset,
          'total': true,
        }),
      );

      if (data == null || data['code'] != 200) return [];

      final playlists = data['playlists'] as List? ?? [];
      return playlists.map((pl) {
        return Playlist(
          id: 'wy_${pl['id']}',
          title: pl['name']?.toString() ?? '',
          description: pl['description']?.toString() ?? '',
          coverUrl: _normalizeCoverUrl(pl['coverImgUrl']),
          songCount: pl['trackCount'] ?? 0,
          playCount: _formatPlayCount(pl['playCount']),
          author: pl['creator']?['nickname']?.toString(),
          source: 'wy',
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<Leaderboard>> getLeaderboards() async {
    try {
      final data = await _request(
        '/toplist',
        direct: _DirectApiConfig(_ApiType.weapi, '/weapi/toplist', {}),
      );

      if (data == null || data['code'] != 200) return [];

      final list = data['list'] as List? ?? [];
      return list.map((item) {
        return Leaderboard(
          id: 'wy_${item['id']}',
          name: item['name']?.toString() ?? '',
          coverUrl: _normalizeCoverUrl(item['coverImgUrl']),
          playCount: _formatPlayCount(item['playCount']),
          updateFrequency: item['updateFrequency']?.toString(),
          source: 'wy',
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<Playlist?> getLeaderboardDetail(String boardId, {int page = 1}) async {
    try {
      final cleanId = boardId.replaceAll('wy_', '');

      final data = await _request(
        '/playlist/detail',
        proxyParams: {'id': cleanId},
        direct: _DirectApiConfig(_ApiType.weapi, '/weapi/v3/playlist/detail', {
          'id': cleanId,
          'n': 100000,
          'p': page,
        }),
      );

      if (data == null || data['code'] != 200) return null;

      final playlist = data['playlist'];
      if (playlist == null) return null;

      return Playlist(
        id: 'wy_${playlist['id']}',
        title: playlist['name']?.toString() ?? '',
        description: playlist['description']?.toString() ?? '',
        coverUrl: _normalizeCoverUrl(playlist['coverImgUrl']),
        songCount: playlist['trackIds']?.length ?? 0,
        songs: _parsePlaylistSongs(playlist),
        playCount: _formatPlayCount(playlist['playCount']),
        author: playlist['creator']?['nickname']?.toString(),
        source: 'wy',
      );
    } catch (e) {
      return null;
    }
  }

  String _formatPlayCount(dynamic count) {
    if (count == null) return '';
    final n = count is int ? count : int.tryParse(count.toString()) ?? 0;
    if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    return n.toString();
  }

  void dispose() {
    _apiService.dispose();
  }
}

class _YrcItem {
  final String tx;
  final int relStart;
  const _YrcItem(this.tx, this.relStart);
}

class _ConvertedLine {
  final String type;
  final int? start;
  final List<_YrcItem>? items;
  final String? text;

  const _ConvertedLine.json(this.start, this.items)
    : type = 'json',
      text = null;
  const _ConvertedLine.raw(this.text)
    : type = 'raw',
      start = null,
      items = null;
}
