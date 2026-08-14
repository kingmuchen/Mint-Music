import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart' as pc;
import '../../../core/network/music_api_service.dart';
import '../../player/domain/models/song.dart';
import '../../player/domain/models/lyric_line.dart';
import '../../player/domain/services/lyric_parser.dart';
import '../../discover/domain/models/playlist.dart';
import '../../discover/domain/models/leaderboard.dart';
import '../domain/music_source_provider.dart';

dynamic _decodeQqJson(dynamic raw) {
  if (raw is Map || raw is List) return raw;
  if (raw is String) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }
  return null;
}

class QQMusicSource implements MusicSourceProvider {
  final MusicApiService _apiService = MusicApiService();
  final Map<String, bool> _searchHasMore = {};

  @override
  String get name => 'QQMusic';

  @override
  String get version => '1.0.0';

  int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static const _searchBaseUrl = 'https://u.y.qq.com/cgi-bin/musicu.fcg';
  static const _signedSearchBaseUrl = 'https://u.y.qq.com/cgi-bin/musics.fcg';

  /// Returns the pagination state recorded by the most recent search request.
  ///
  /// QQ's search API provides an explicit next page / total count. Keeping it
  /// here prevents the UI from treating a short server page as the last page.
  bool? getSearchHasMore(String query, {int page = 1, int limit = 30}) {
    return _searchHasMore[_searchCacheKey(query, page, limit)];
  }

  String _searchCacheKey(String query, int page, int limit) =>
      '${query.trim()}:$page:$limit';

  String _generateSearchId() {
    final now = DateTime.now();
    final rand = DateTime.now().microsecondsSinceEpoch % 20 + 1;
    final msInDay = now.millisecondsSinceEpoch % (24 * 60 * 60 * 1000);
    return '${rand * 18014398509481984 + (DateTime.now().microsecondsSinceEpoch % 4194304) * 4294967296 + msInDay}';
  }

  String _zzcSign(String text) {
    const part1Indexes = [23, 14, 6, 36, 16, 40, 7, 19];
    const part2Indexes = [16, 1, 32, 12, 19, 27, 8, 5];
    const scrambleValues = [
      89,
      39,
      179,
      150,
      218,
      82,
      58,
      252,
      177,
      52,
      186,
      123,
      120,
      64,
      242,
      133,
      143,
      161,
      121,
      179,
    ];

    final hash = sha1.convert(utf8.encode(text)).toString().toUpperCase();

    final part1 = part1Indexes
        .map((idx) => idx < hash.length ? hash[idx] : '')
        .join('');
    final part2 = part2Indexes
        .map((idx) => idx < hash.length ? hash[idx] : '')
        .join('');

    final part3 = <int>[];
    for (
      var i = 0;
      i < scrambleValues.length && i * 2 + 2 <= hash.length;
      i++
    ) {
      final hexStr = hash.substring(i * 2, i * 2 + 2);
      part3.add(scrambleValues[i] ^ int.parse(hexStr, radix: 16));
    }

    final b64Part = base64Encode(part3).replaceAll(RegExp(r'[\\/+ =]'), '');

    return 'zzc$part1$b64Part$part2'.toLowerCase();
  }

  @override
  Future<Playlist?> getPlaylistDetail(String playlistId) async {
    try {
      final cleanId = playlistId.replaceAll('tx_', '');
      final url =
          'https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg?type=1&json=1&utf8=1&onlysong=0&new_format=1&disstid=$cleanId&loginUin=0&hostUin=0&format=json&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq.json&needNewCode=0';

      final response = await _apiService.get(
        url,
        headers: {
          'Origin': 'https://y.qq.com',
          'Referer': 'https://y.qq.com/n/yqq/playsquare/$cleanId.html',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      );

      final respData = response.data;
      print('[QQMusicSource] 响应数据: ${jsonEncode(respData)}');
      if (respData == null || respData['code'] != 0) return null;

      final cdlist = respData['cdlist'] as List? ?? [];
      if (cdlist.isEmpty) return null;

      final cd = cdlist[0];
      final songList = cd['songlist'] as List? ?? [];
      print('[QQMusicSource] 歌曲列表长度: ${songList.length}');

      final songs = songList
          .map((item) {
            try {
              print('[QQMusicSource] 处理歌曲项: ${jsonEncode(item)}');
              final singersRaw = item['singer'];
              String singerName = '';
              if (singersRaw is List) {
                singerName = singersRaw
                    .map((s) => s is Map ? (s['name']?.toString() ?? '') : '')
                    .where((s) => s.isNotEmpty)
                    .join('、');
              } else if (singersRaw is String) {
                singerName = singersRaw;
              }

              final albumMid = item['album']?['mid']?.toString() ?? '';
              final singerMid = singersRaw is List && singersRaw.isNotEmpty
                  ? (singersRaw[0] is Map
                        ? singersRaw[0]['mid']?.toString() ?? ''
                        : '')
                  : '';

              String coverUrl = '';
              if (albumMid.isNotEmpty) {
                coverUrl =
                    'https://y.gtimg.cn/music/photo_new/T002R300x300M000$albumMid.jpg';
              } else if (singerMid.isNotEmpty) {
                coverUrl =
                    'https://y.gtimg.cn/music/photo_new/T001R300x300M000$singerMid.jpg';
              }

              return Song(
                id: 'tx_${item['mid']?.toString() ?? ''}',
                title:
                    item['title']?.toString() ?? item['name']?.toString() ?? '',
                artist: singerName,
                album: item['album']?['name']?.toString() ?? '',
                duration: _parseInt(item['interval']),
                coverUrl: coverUrl,
                source: 'tx',
                lyricUrl: item['id']?.toString(),
              );
            } catch (e) {
              print('[QQMusicSource] 处理歌曲项失败: $e, 歌曲数据: ${jsonEncode(item)}');
              return null;
            }
          })
          .where((song) => song != null)
          .cast<Song>()
          .toList();

      String playlistCoverUrl = cd['logo']?.toString() ?? '';
      if (playlistCoverUrl.isNotEmpty && !playlistCoverUrl.startsWith('http')) {
        playlistCoverUrl =
            'https://y.gtimg.cn/music/photo_new/$playlistCoverUrl';
      }

      return Playlist(
        id: playlistId,
        title: cd['dissname']?.toString() ?? '未知歌单',
        description: cd['desc']?.toString() ?? '',
        songCount: songs.length,
        songs: songs,
        coverUrl: playlistCoverUrl,
        source: 'tx',
      );
    } catch (e) {
      print('[QQMusicSource] getPlaylistDetail error: $e');
      return null;
    }
  }

  @override
  Future<List<Playlist>> getHotPlaylists() async {
    try {
      final data = {
        'comm': {'cv': 1602, 'ct': 20},
        'playlist': {
          'method': 'get_playlist_by_tag',
          'param': {
            'id': 10000000,
            'sin': 0,
            'size': 20,
            'order': 5,
            'cur_page': 1,
          },
          'module': 'playlist.PlayListPlazaServer',
        },
      };

      final url =
          'https://u.y.qq.com/cgi-bin/musicu.fcg?loginUin=0&hostUin=0&format=json&inCharset=utf-8&outCharset=utf-8&notice=0&platform=wk_v15.json&needNewCode=0&data=${Uri.encodeQueryComponent(jsonEncode(data))}';

      final response = await _apiService.get(
        url,
        headers: {
          'Referer': 'https://y.qq.com/',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36',
        },
      );

      dynamic respData = response.data;
      if (respData is String) respData = jsonDecode(respData);
      if (respData == null || respData['code'] != 0) {
        return [];
      }

      final playlistData = respData['playlist']?['data'];
      if (playlistData == null) return [];

      final list = playlistData['v_playlist'] as List? ?? [];
      return list.map((item) {
        return Playlist(
          id: 'tx_${item['tid']?.toString() ?? ''}',
          title: item['title']?.toString() ?? '',
          description: item['desc']?.toString().replaceAll('<br>', '\n') ?? '',
          songCount: _parseSongCount(item['song_ids']),
          coverUrl: item['cover_url_medium']?.toString() ?? '',
          playCount: _formatPlayCount(item['access_num']),
          author: _readMapString(item['creator_info'], 'nick'),
          source: 'tx',
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
      final cleanId = songId.replaceAll('tx_', '');
      final data = {
        'req_0': {
          'module': 'vkey.GetVkeyServer',
          'method': 'CgiGetVkey',
          'param': {
            'guid': _generateSearchId(),
            'songmid': [cleanId],
            'songtype': [0],
            'uin': '0',
            'loginflag': 1,
            'platform': '20',
          },
        },
        'comm': {'ct': 24, 'cv': 0},
      };
      final sign = _zzcSign(jsonEncode(data));
      final response = await _apiService.post(
        '$_searchBaseUrl?sign=$sign',
        headers: {'User-Agent': 'QQMusic 14090508(android 12)'},
        data: data,
      );
      final respData = response.data;
      if (respData == null || respData['code'] != 0) return null;
      final midurlinfo = respData['req_0']?['data']?['midurlinfo'] as List?;
      if (midurlinfo == null || midurlinfo.isEmpty) return null;
      final purl = midurlinfo.first['purl']?.toString();
      if (purl == null || purl.isEmpty) return null;
      final sipList = respData['req_0']?['data']?['sip'] as List?;
      final sip = (sipList != null && sipList.isNotEmpty)
          ? sipList.first.toString()
          : 'http://isure6.stream.qqmusic.qq.com/';
      return '$sip$purl';
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

  dynamic _decodeJsonResponse(dynamic data) {
    if (data is String) {
      try {
        return jsonDecode(data);
      } catch (_) {
        return null;
      }
    }
    return data;
  }

  String? _firstLyricPayload(Iterable<dynamic> values) {
    for (final value in values) {
      if (value is! String) continue;
      final text = value.trim();
      if (text.isEmpty || text == 'null') continue;
      if (text.length < 16 && int.tryParse(text) != null) continue;
      return text;
    }
    return null;
  }

  @override
  Future<LyricResult?> getLyricResult(String songId) async {
    final cleanId = songId.replaceAll('tx_', '');
    LyricResult? plainFallback;
    try {
      print('[TxMusicSource] getLyricResult: songId=$songId, cleanId=$cleanId');

      final numericCleanId = int.tryParse(cleanId);
      if (numericCleanId == null) {
        final legacyResult = await _getLegacyBase64LyricResult(cleanId);
        if (legacyResult != null &&
            (legacyResult.lrc?.trim().isNotEmpty ?? false)) {
          plainFallback = legacyResult;
        }
      }
      final numericId = numericCleanId ?? await _getNumericSongId(cleanId);
      final fallbackSongMid = numericCleanId == null ? cleanId : null;
      print('[TxMusicSource] getLyricResult: numericId=$numericId');
      if (numericId == null) {
        if (plainFallback != null) return plainFallback;
        return _getPlainLyricResult(songMid: cleanId);
      }

      final data = {
        'comm': {'ct': '19', 'cv': '1859', 'uin': '0'},
        'req': {
          'method': 'GetPlayLyricInfo',
          'module': 'music.musichallSong.PlayLyricInfo',
          'param': {
            'format': 'json',
            'crypt': 1,
            'ct': 19,
            'cv': 1873,
            'interval': 0,
            'lrc_t': 0,
            'qrc': 1,
            'qrc_t': 0,
            'roma': 1,
            'roma_t': 0,
            'songID': numericId,
            'trans': 1,
            'trans_t': 0,
            'type': -1,
          },
        },
      };

      final response = await _apiService.post(
        'https://u.y.qq.com/cgi-bin/musicu.fcg',
        headers: {
          'referer': 'https://y.qq.com',
          'user-agent':
              'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/86.0.4240.198 Safari/537.36',
        },
        data: data,
      );

      final respData = _decodeJsonResponse(response.data);
      if (respData is! Map || respData['code'] != 0) {
        return _getPlainLyricResult(
          songId: numericId,
          songMid: fallbackSongMid,
        );
      }
      final reqData = respData['req'];
      if (reqData == null || reqData['code'] != 0) {
        return _getPlainLyricResult(
          songId: numericId,
          songMid: fallbackSongMid,
        );
      }
      final lyricData = reqData['data'];
      if (lyricData == null) {
        return _getPlainLyricResult(
          songId: numericId,
          songMid: fallbackSongMid,
        );
      }
      print(
        '[TxMusicSource] lyricData keys: ${lyricData is Map ? lyricData.keys.toList() : "not map"}',
      );
      for (final key in ['qrc', 'lyric', 'trans', 'roma']) {
        final val = lyricData[key];
        if (val != null) {
          final valStr = val.toString();
          print(
            '[TxMusicSource]   $key: type=${val.runtimeType} len=${valStr.length} head=${valStr.length > 60 ? valStr.substring(0, 60) : valStr}',
          );
        } else {
          print('[TxMusicSource]   $key: null');
        }
      }

      String? lrc;
      String? crlyric;
      String? tlyric;
      String? rlyric;

      final encryptedLyric = _firstLyricPayload([
        lyricData['qrc'],
        lyricData['lyric'],
      ]);
      print(
        '[TxMusicSource] encryptedLyric source: ${encryptedLyric != null ? "len=${encryptedLyric.length}" : "null"}',
      );
      if (encryptedLyric != null && encryptedLyric.isNotEmpty) {
        final decrypted = _qrcDecrypt(encryptedLyric);
        print(
          '[TxMusicSource] decrypt: ${decrypted != null ? "ok len=${decrypted.length}" : "null"}',
        );
        if (decrypted != null) {
          final cleaned = _removeQrcTag(decrypted);
          print(
            '[TxMusicSource] cleaned: len=${cleaned.length} head=${cleaned.length > 120 ? cleaned.substring(0, 120) : cleaned}',
          );
          // 确保 LyricContent= 包装已被剥离，再检测格式
          if (cleaned.contains('LyricContent=')) {
            final match = RegExp(
              r'''LyricContent\s*=\s*(["'])([\s\S]*?)\1''',
              caseSensitive: false,
            ).firstMatch(cleaned);
            final inner = match?.group(2);
            if (inner != null) {
              print(
                '[TxMusicSource] LyricContent= extracted: len=${inner.length} head=${inner.length > 80 ? inner.substring(0, 80) : inner}',
              );
              if (isYrcFormat(inner)) {
                crlyric = inner;
                final parsed = _parseQrcRaw(inner);
                lrc = parsed['lyric'];
                print(
                  '[TxMusicSource] -> YRC format, crlyric=${crlyric.length} lrc=${lrc?.length ?? 0}',
                );
              } else {
                lrc = inner;
                print(
                  '[TxMusicSource] -> not YRC, set lrc=${lrc?.length ?? 0}',
                );
              }
            } else {
              lrc = cleaned;
              print(
                '[TxMusicSource] -> LyricContent= match failed, set lrc=${lrc?.length ?? 0}',
              );
            }
          } else if (isYrcFormat(cleaned)) {
            crlyric = cleaned;
            final parsed = _parseQrcRaw(cleaned);
            lrc = parsed['lyric'];
            print(
              '[TxMusicSource] -> YRC format (direct), crlyric=${crlyric.length} lrc=${lrc?.length ?? 0}',
            );
          } else {
            lrc = cleaned;
            print('[TxMusicSource] -> not YRC, set lrc=${lrc?.length ?? 0}');
          }
        }
      }

      final encryptedTrans = _firstLyricPayload([lyricData['trans']]);
      if (encryptedTrans != null && encryptedTrans.isNotEmpty) {
        final decrypted = _qrcDecrypt(encryptedTrans);
        if (decrypted != null) {
          final cleaned = _removeQrcTag(decrypted);
          tlyric = _extractPlainText(cleaned);
        }
      }

      final encryptedRoma = _firstLyricPayload([lyricData['roma']]);
      if (encryptedRoma != null && encryptedRoma.isNotEmpty) {
        final decrypted = _qrcDecrypt(encryptedRoma);
        if (decrypted != null) {
          final cleaned = _removeQrcTag(decrypted);
          rlyric = _extractPlainText(cleaned);
        }
      }

      if ((lrc == null || lrc.isEmpty) &&
          (crlyric == null || crlyric.isEmpty)) {
        if (fallbackSongMid != null) {
          final legacyResult = await _getLegacyBase64LyricResult(
            fallbackSongMid,
          );
          if (legacyResult != null &&
              (legacyResult.lrc?.trim().isNotEmpty ?? false)) {
            plainFallback = legacyResult;
          }
        }
        if (plainFallback != null) return plainFallback;
        return _getPlainLyricResult(
          songId: numericId,
          songMid: fallbackSongMid,
        );
      }

      print(
        '[TxMusicSource] return: lrc=${lrc?.length ?? 0} crlyric=${crlyric?.length ?? 0} tlyric=${tlyric?.length ?? 0} rlyric=${rlyric?.length ?? 0}',
      );
      return LyricResult(
        lrc: lrc,
        crlyric: crlyric,
        tlyric: tlyric,
        rlyric: rlyric,
      );
    } catch (e) {
      final legacyResult = int.tryParse(cleanId) == null
          ? await _getLegacyBase64LyricResult(cleanId)
          : null;
      if (legacyResult != null &&
          (legacyResult.lrc?.trim().isNotEmpty ?? false)) {
        return legacyResult;
      }
      return _getPlainLyricResult(songMid: cleanId);
    }
  }

  Future<LyricResult?> _getLegacyBase64LyricResult(String songMid) async {
    try {
      final url =
          'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=$songMid&format=json&nobase64=0&g_tk=5381&loginUin=0&hostUin=0&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq.json&needNewCode=0';
      final response = await _apiService.get(
        url,
        headers: {
          'referer': 'https://y.qq.com/',
          'user-agent':
              'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36',
        },
      );
      dynamic data = response.data;
      if (data is String) data = jsonDecode(data);
      if (data == null || (data['code'] != 0 && data['retcode'] != 0)) {
        return null;
      }

      String? decodeField(String key) {
        final value = data[key]?.toString();
        if (value == null || value.isEmpty) return null;
        try {
          return utf8.decode(base64Decode(value), allowMalformed: true);
        } catch (_) {
          return value;
        }
      }

      final lrc = decodeField('lyric');
      if (lrc == null || lrc.trim().isEmpty) return null;
      return LyricResult(
        lrc: lrc,
        tlyric: decodeField('trans') ?? '',
        rlyric: '',
        crlyric: '',
      );
    } catch (_) {
      return null;
    }
  }

  Future<LyricResult?> _getPlainLyricResult({
    int? songId,
    String? songMid,
  }) async {
    try {
      final data = {
        'comm': {'ct': '19', 'cv': '1859', 'uin': '0'},
        'req': {
          'method': 'GetPlayLyricInfo',
          'module': 'music.musichallSong.PlayLyricInfo',
          'param': {
            'format': 'json',
            'crypt': 0,
            'ct': 19,
            'cv': 1873,
            'interval': 0,
            'lrc_t': 0,
            'qrc': 0,
            'qrc_t': 0,
            'roma': 0,
            'roma_t': 0,
            'songID': songId ?? 0,
            if (songMid != null && songMid.isNotEmpty) 'songMID': songMid,
            'trans': 0,
            'trans_t': 0,
            'type': -1,
          },
        },
      };

      final response = await _apiService.post(
        'https://u.y.qq.com/cgi-bin/musicu.fcg',
        headers: {
          'referer': 'https://y.qq.com',
          'user-agent':
              'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36',
        },
        data: data,
      );

      final respData = _decodeJsonResponse(response.data);
      if (respData is! Map || respData['code'] != 0) return null;
      final reqData = respData['req'];
      if (reqData == null || reqData['code'] != 0) return null;
      final encoded = reqData['data']?['lyric']?.toString();
      if (encoded == null || encoded.isEmpty) return null;

      final lyric = utf8.decode(base64Decode(encoded), allowMalformed: true);
      if (lyric.trim().isEmpty) return null;
      return LyricResult(lrc: lyric);
    } catch (e) {
      return null;
    }
  }

  Future<int?> _getNumericSongId(String songmid) async {
    try {
      final data = {
        'comm': {'ct': '19', 'cv': '1859', 'uin': '0'},
        'req': {
          'module': 'music.pf_song_detail_svr',
          'method': 'get_song_detail_yqq',
          'param': {'song_type': 0, 'song_mid': songmid},
        },
      };

      final response = await _apiService.post(
        'https://u.y.qq.com/cgi-bin/musicu.fcg',
        headers: {
          'User-Agent':
              'Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)',
        },
        data: data,
      );

      final respData = _decodeJsonResponse(response.data);
      if (respData is Map &&
          respData['code'] == 0 &&
          respData['req']?['code'] == 0) {
        final trackInfo = respData['req']?['data']?['track_info'];
        if (trackInfo != null) {
          final songId = trackInfo['id'];
          if (songId != null)
            return songId is int ? songId : int.tryParse(songId.toString());
        }
      }

      final lyricData = {
        'comm': {'ct': '19', 'cv': '1859', 'uin': '0'},
        'req': {
          'method': 'GetPlayLyricInfo',
          'module': 'music.musichallSong.PlayLyricInfo',
          'param': {
            'format': 'json',
            'crypt': 1,
            'ct': 19,
            'cv': 1873,
            'interval': 0,
            'lrc_t': 0,
            'qrc': 1,
            'qrc_t': 0,
            'roma': 0,
            'roma_t': 0,
            'songID': 0,
            'songMID': songmid,
            'trans': 0,
            'trans_t': 0,
            'type': -1,
          },
        },
      };

      final lyricResponse = await _apiService.post(
        'https://u.y.qq.com/cgi-bin/musicu.fcg',
        headers: {
          'referer': 'https://y.qq.com',
          'user-agent':
              'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36',
        },
        data: lyricData,
      );

      final lyricRespData = _decodeJsonResponse(lyricResponse.data);
      if (lyricRespData is Map && lyricRespData['code'] == 0) {
        final songId = lyricRespData['req']?['data']?['songID'];
        if (songId != null && songId is int && songId > 0) return songId;
      }

      final searchResult = await _apiService.get(
        '$_searchBaseUrl?sign=${_zzcSign(jsonEncode({
          "comm": {"ct": 24, "cv": 0},
          "req": {
            "method": "DoSearchForQQMusicDesktop",
            "module": "music.search.SearchCgiService",
            "param": {"query": songmid, "num_per_page": 1, "page_num": 1},
          },
        }))}',
        headers: {'User-Agent': 'QQMusic'},
      );
      final searchData = _decodeJsonResponse(searchResult.data);
      if (searchData is! Map) return null;
      final list = searchData?['req']?['data']?['body']?['item_song'] as List?;
      if (list != null && list.isNotEmpty) {
        final id = list.first['id'];
        if (id != null) return id is int ? id : int.tryParse(id.toString());
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  String? _qrcDecrypt(String encrypted) {
    try {
      final inputBuffer = _hexToBytes(encrypted);
      if (inputBuffer.isEmpty) return null;

      const keyString = '!@#)(*\$%123ZXC!@!@#)(NHL';
      final keyBytes = Uint8List.fromList(keyString.codeUnits);

      // 使用与CeruMusic完全一致的Triple-DES解密
      final standardDesResult = _qrcDecryptWithStandardTripleDes(
        inputBuffer,
        keyBytes,
      );
      if (standardDesResult != null && standardDesResult.isNotEmpty) {
        return standardDesResult;
      }

      const decrypt = 0;
      final schedule = _tripleDesKeySetup(keyBytes, decrypt);

      final decryptedChunks = <int>[];
      for (int i = 0; i < inputBuffer.length; i += 8) {
        if (i + 8 > inputBuffer.length) break;
        final chunk = inputBuffer.sublist(i, i + 8);
        final decrypted = _tripleDesCrypt(chunk, schedule);
        decryptedChunks.addAll(decrypted);
      }

      if (decryptedChunks.length >= 4) {
        print(
          '[TxMusicSource] manual DES first 4 hex bytes: ${decryptedChunks[0].toRadixString(16).padLeft(2, "0")} ${decryptedChunks[1].toRadixString(16).padLeft(2, "0")} ${decryptedChunks[2].toRadixString(16).padLeft(2, "0")} ${decryptedChunks[3].toRadixString(16).padLeft(2, "0")} (len=${decryptedChunks.length})',
        );
      }
      final unpadded = _removePkcs7Padding(decryptedChunks);
      final decompressed = _zlibDecompress(unpadded);
      return decompressed;
    } catch (e) {
      print('[TxMusicSource] _qrcDecrypt error: $e');
      return null;
    }
  }

  String? _qrcDecryptWithStandardTripleDes(
    Uint8List inputBuffer,
    Uint8List keyBytes,
  ) {
    try {
      // 注意：CeruMusic 的 Triple-DES 使用 K3-K2-K1 顺序 (E_K3(D_K2(E_K1(P))))
      // 而 pointycastle 的 DESedeEngine 使用标准 EDE 顺序 K1-K2-K3 (E_K1(D_K2(E_K3(P))))
      // 所以需要将 key 重排为 K3||K2||K1 以匹配 CeruMusic 的顺序
      final swappedKey = Uint8List(24)
        ..setRange(0, 8, keyBytes.sublist(16, 24))
        ..setRange(8, 16, keyBytes.sublist(8, 16))
        ..setRange(16, 24, keyBytes.sublist(0, 8));
      final cipher = pc.ECBBlockCipher(pc.DESedeEngine())
        ..init(false, pc.KeyParameter(swappedKey));
      final output = Uint8List(inputBuffer.length);
      for (var offset = 0; offset < inputBuffer.length; offset += 8) {
        if (offset + 8 > inputBuffer.length) break;
        cipher.processBlock(inputBuffer, offset, output, offset);
      }
      if (output.length >= 4) {
        print(
          '[TxMusicSource] pointycastle DES raw first 4 hex: ${output[0].toRadixString(16).padLeft(2, "0")} ${output[1].toRadixString(16).padLeft(2, "0")} ${output[2].toRadixString(16).padLeft(2, "0")} ${output[3].toRadixString(16).padLeft(2, "0")} (len=${output.length})',
        );
      }
      final unpadded = _removePkcs7Padding(output.toList());
      if (unpadded.length >= 4) {
        print(
          '[TxMusicSource] pointycastle DES unpadded first 4 hex: ${unpadded[0].toRadixString(16).padLeft(2, "0")} ${unpadded[1].toRadixString(16).padLeft(2, "0")} ${unpadded[2].toRadixString(16).padLeft(2, "0")} ${unpadded[3].toRadixString(16).padLeft(2, "0")} (len=${unpadded.length})',
        );
      }
      return _zlibDecompress(unpadded);
    } catch (e) {
      print('[TxMusicSource] _qrcDecryptWithStandardTripleDes error: $e');
      return null;
    }
  }

  Uint8List _hexToBytes(String hex) {
    final result = <int>[];
    for (int i = 0; i < hex.length - 1; i += 2) {
      final byte = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (byte != null) result.add(byte);
    }
    return Uint8List.fromList(result);
  }

  String? _zlibDecompress(List<int> data) {
    try {
      final compressed = Uint8List.fromList(data);
      try {
        // CeruMusic 使用 zlib.unzipSync，这是标准的 zlib 解压
        final decompressed = zlib.decode(compressed);
        return utf8.decode(decompressed);
      } catch (e) {
        try {
          // 回退：尝试 raw inflate
          final decompressed = ZLibDecoder(raw: true).convert(compressed);
          return utf8.decode(decompressed);
        } catch (e2) {
          try {
            final decompressed = gzip.decode(compressed);
            return utf8.decode(decompressed);
          } catch (e3) {
            return null;
          }
        }
      }
    } catch (e) {
      return null;
    }
  }

  List<int> _removePkcs7Padding(List<int> data) {
    if (data.isEmpty) return data;
    final padByte = data.last;
    if (padByte < 1 || padByte > 8) return data;
    // Verify all padding bytes are the same value
    for (int i = data.length - padByte; i < data.length; i++) {
      if (i < 0) return data;
      if (data[i] != padByte) return data;
    }
    return data.sublist(0, data.length - padByte);
  }

  // 完全按照CeruMusic实现的Triple-DES相关函数
  List<List<List<int>>> _tripleDesKeySetup(Uint8List key, int mode) {
    const encrypt = 1;
    const decrypt = 0;
    if (mode == encrypt) {
      return [
        _desKeySchedule(key.sublist(0, 8), encrypt),
        _desKeySchedule(key.sublist(8, 16), decrypt),
        _desKeySchedule(key.sublist(16, 24), encrypt),
      ];
    }
    return [
      _desKeySchedule(key.sublist(16, 24), decrypt),
      _desKeySchedule(key.sublist(8, 16), encrypt),
      _desKeySchedule(key.sublist(0, 8), decrypt),
    ];
  }

  Uint8List _tripleDesCrypt(Uint8List data, List<List<List<int>>> key) {
    var result = data;
    for (int i = 0; i < 3; i++) {
      result = _desCrypt(result, key[i]);
    }
    return result;
  }

  Uint8List _desCrypt(Uint8List input, List<List<int>> keys) {
    final ip = _initialPermutation(input);
    int s0 = ip[0];
    int s1 = ip[1];

    for (int idx = 0; idx < 15; idx++) {
      final prevS1 = s1;
      s1 = (_desF(s1, keys[idx]) ^ s0) & 0xFFFFFFFF;
      s0 = prevS1;
    }
    s0 = (_desF(s1, keys[15]) ^ s0) & 0xFFFFFFFF;

    return _inversePermutation(s0, s1);
  }

  List<List<int>> _desKeySchedule(Uint8List key, int mode) {
    const keyPermC = [
      56,
      48,
      40,
      32,
      24,
      16,
      8,
      0,
      57,
      49,
      41,
      33,
      25,
      17,
      9,
      1,
      58,
      50,
      42,
      34,
      26,
      18,
      10,
      2,
      59,
      51,
      43,
      35,
    ];
    const keyPermD = [
      62,
      54,
      46,
      38,
      30,
      22,
      14,
      6,
      61,
      53,
      45,
      37,
      29,
      21,
      13,
      5,
      60,
      52,
      44,
      36,
      28,
      20,
      12,
      4,
      27,
      19,
      11,
      3,
    ];
    const keyCompression = [
      13,
      16,
      10,
      23,
      0,
      4,
      2,
      27,
      14,
      5,
      20,
      9,
      22,
      18,
      11,
      3,
      25,
      7,
      15,
      6,
      26,
      19,
      12,
      1,
      40,
      51,
      30,
      36,
      46,
      54,
      29,
      39,
      50,
      44,
      32,
      47,
      43,
      48,
      38,
      55,
      33,
      52,
      45,
      41,
      49,
      35,
      28,
      31,
    ];
    const keyRndShift = [1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1];
    const decrypt = 0;

    int c = 0, d = 0;
    for (int i = 0; i < 28; i++) {
      c |= _bitnum(key, keyPermC[i], 31 - i);
      d |= _bitnum(key, keyPermD[i], 31 - i);
    }
    c = c & 0xFFFFFFFF;
    d = d & 0xFFFFFFFF;

    final schedule = List.generate(16, (_) => List.filled(6, 0));
    for (int i = 0; i < 16; i++) {
      final shift = keyRndShift[i];
      c = (((c << shift) | (c >>> (28 - shift))) & 0xFFFFFFF0);
      d = (((d << shift) | (d >>> (28 - shift))) & 0xFFFFFFF0);

      final togen = mode == decrypt ? 15 - i : i;

      schedule[togen] = List.filled(6, 0);

      for (int j = 0; j < 24; j++) {
        schedule[togen][j ~/ 8] |= _bitnumIntr(
          c,
          keyCompression[j],
          7 - (j % 8),
        );
      }

      for (int j = 24; j < 48; j++) {
        schedule[togen][j ~/ 8] |= _bitnumIntr(
          d,
          keyCompression[j] - 27,
          7 - (j % 8),
        );
      }
    }
    return schedule;
  }

  int _bitnum(Uint8List a, int b, int c) {
    final byteIndex = (b ~/ 32) * 4 + 3 - ((b % 32) ~/ 8);
    final bitInByte = 7 - (b % 8);
    final bit = (a[byteIndex] >> bitInByte) & 1;
    return (bit << c) & 0xFFFFFFFF;
  }

  int _bitnumIntr(int a, int b, int c) {
    return (((a >>> (31 - b)) & 1) << c) & 0xFFFFFFFF;
  }

  int _bitnumIntl(int a, int b, int c) {
    return (((a << b) & 0x80000000) >>> c) & 0xFFFFFFFF;
  }

  List<int> _initialPermutation(Uint8List input) {
    int s0 = 0;
    s0 |= _bitnum(input, 57, 31);
    s0 |= _bitnum(input, 49, 30);
    s0 |= _bitnum(input, 41, 29);
    s0 |= _bitnum(input, 33, 28);
    s0 |= _bitnum(input, 25, 27);
    s0 |= _bitnum(input, 17, 26);
    s0 |= _bitnum(input, 9, 25);
    s0 |= _bitnum(input, 1, 24);
    s0 |= _bitnum(input, 59, 23);
    s0 |= _bitnum(input, 51, 22);
    s0 |= _bitnum(input, 43, 21);
    s0 |= _bitnum(input, 35, 20);
    s0 |= _bitnum(input, 27, 19);
    s0 |= _bitnum(input, 19, 18);
    s0 |= _bitnum(input, 11, 17);
    s0 |= _bitnum(input, 3, 16);
    s0 |= _bitnum(input, 61, 15);
    s0 |= _bitnum(input, 53, 14);
    s0 |= _bitnum(input, 45, 13);
    s0 |= _bitnum(input, 37, 12);
    s0 |= _bitnum(input, 29, 11);
    s0 |= _bitnum(input, 21, 10);
    s0 |= _bitnum(input, 13, 9);
    s0 |= _bitnum(input, 5, 8);
    s0 |= _bitnum(input, 63, 7);
    s0 |= _bitnum(input, 55, 6);
    s0 |= _bitnum(input, 47, 5);
    s0 |= _bitnum(input, 39, 4);
    s0 |= _bitnum(input, 31, 3);
    s0 |= _bitnum(input, 23, 2);
    s0 |= _bitnum(input, 15, 1);
    s0 |= _bitnum(input, 7, 0);
    s0 = s0 & 0xFFFFFFFF;

    int s1 = 0;
    s1 |= _bitnum(input, 56, 31);
    s1 |= _bitnum(input, 48, 30);
    s1 |= _bitnum(input, 40, 29);
    s1 |= _bitnum(input, 32, 28);
    s1 |= _bitnum(input, 24, 27);
    s1 |= _bitnum(input, 16, 26);
    s1 |= _bitnum(input, 8, 25);
    s1 |= _bitnum(input, 0, 24);
    s1 |= _bitnum(input, 58, 23);
    s1 |= _bitnum(input, 50, 22);
    s1 |= _bitnum(input, 42, 21);
    s1 |= _bitnum(input, 34, 20);
    s1 |= _bitnum(input, 26, 19);
    s1 |= _bitnum(input, 18, 18);
    s1 |= _bitnum(input, 10, 17);
    s1 |= _bitnum(input, 2, 16);
    s1 |= _bitnum(input, 60, 15);
    s1 |= _bitnum(input, 52, 14);
    s1 |= _bitnum(input, 44, 13);
    s1 |= _bitnum(input, 36, 12);
    s1 |= _bitnum(input, 28, 11);
    s1 |= _bitnum(input, 20, 10);
    s1 |= _bitnum(input, 12, 9);
    s1 |= _bitnum(input, 4, 8);
    s1 |= _bitnum(input, 62, 7);
    s1 |= _bitnum(input, 54, 6);
    s1 |= _bitnum(input, 46, 5);
    s1 |= _bitnum(input, 38, 4);
    s1 |= _bitnum(input, 30, 3);
    s1 |= _bitnum(input, 22, 2);
    s1 |= _bitnum(input, 14, 1);
    s1 |= _bitnum(input, 6, 0);
    s1 = s1 & 0xFFFFFFFF;

    return [s0, s1];
  }

  Uint8List _inversePermutation(int s0, int s1) {
    final data = Uint8List(8);
    data[3] =
        _bitnumIntr(s1, 7, 7) |
        _bitnumIntr(s0, 7, 6) |
        _bitnumIntr(s1, 15, 5) |
        _bitnumIntr(s0, 15, 4) |
        _bitnumIntr(s1, 23, 3) |
        _bitnumIntr(s0, 23, 2) |
        _bitnumIntr(s1, 31, 1) |
        _bitnumIntr(s0, 31, 0);
    data[2] =
        _bitnumIntr(s1, 6, 7) |
        _bitnumIntr(s0, 6, 6) |
        _bitnumIntr(s1, 14, 5) |
        _bitnumIntr(s0, 14, 4) |
        _bitnumIntr(s1, 22, 3) |
        _bitnumIntr(s0, 22, 2) |
        _bitnumIntr(s1, 30, 1) |
        _bitnumIntr(s0, 30, 0);
    data[1] =
        _bitnumIntr(s1, 5, 7) |
        _bitnumIntr(s0, 5, 6) |
        _bitnumIntr(s1, 13, 5) |
        _bitnumIntr(s0, 13, 4) |
        _bitnumIntr(s1, 21, 3) |
        _bitnumIntr(s0, 21, 2) |
        _bitnumIntr(s1, 29, 1) |
        _bitnumIntr(s0, 29, 0);
    data[0] =
        _bitnumIntr(s1, 4, 7) |
        _bitnumIntr(s0, 4, 6) |
        _bitnumIntr(s1, 12, 5) |
        _bitnumIntr(s0, 12, 4) |
        _bitnumIntr(s1, 20, 3) |
        _bitnumIntr(s0, 20, 2) |
        _bitnumIntr(s1, 28, 1) |
        _bitnumIntr(s0, 28, 0);
    data[7] =
        _bitnumIntr(s1, 3, 7) |
        _bitnumIntr(s0, 3, 6) |
        _bitnumIntr(s1, 11, 5) |
        _bitnumIntr(s0, 11, 4) |
        _bitnumIntr(s1, 19, 3) |
        _bitnumIntr(s0, 19, 2) |
        _bitnumIntr(s1, 27, 1) |
        _bitnumIntr(s0, 27, 0);
    data[6] =
        _bitnumIntr(s1, 2, 7) |
        _bitnumIntr(s0, 2, 6) |
        _bitnumIntr(s1, 10, 5) |
        _bitnumIntr(s0, 10, 4) |
        _bitnumIntr(s1, 18, 3) |
        _bitnumIntr(s0, 18, 2) |
        _bitnumIntr(s1, 26, 1) |
        _bitnumIntr(s0, 26, 0);
    data[5] =
        _bitnumIntr(s1, 1, 7) |
        _bitnumIntr(s0, 1, 6) |
        _bitnumIntr(s1, 9, 5) |
        _bitnumIntr(s0, 9, 4) |
        _bitnumIntr(s1, 17, 3) |
        _bitnumIntr(s0, 17, 2) |
        _bitnumIntr(s1, 25, 1) |
        _bitnumIntr(s0, 25, 0);
    data[4] =
        _bitnumIntr(s1, 0, 7) |
        _bitnumIntr(s0, 0, 6) |
        _bitnumIntr(s1, 8, 5) |
        _bitnumIntr(s0, 8, 4) |
        _bitnumIntr(s1, 16, 3) |
        _bitnumIntr(s0, 16, 2) |
        _bitnumIntr(s1, 24, 1) |
        _bitnumIntr(s0, 24, 0);
    return data;
  }

  int _desF(int state, List<int> key) {
    state = state & 0xFFFFFFFF;
    final t1 =
        _bitnumIntl(state, 31, 0) |
        (((state & 0xF0000000) >>> 1) & 0xFFFFFFFF) |
        _bitnumIntl(state, 4, 5) |
        _bitnumIntl(state, 3, 6) |
        (((state & 0x0F000000) >>> 3) & 0xFFFFFFFF) |
        _bitnumIntl(state, 8, 11) |
        _bitnumIntl(state, 7, 12) |
        (((state & 0x00F00000) >>> 5) & 0xFFFFFFFF) |
        _bitnumIntl(state, 12, 17) |
        _bitnumIntl(state, 11, 18) |
        (((state & 0x000F0000) >>> 7) & 0xFFFFFFFF) |
        _bitnumIntl(state, 16, 23);
    final t1Fixed = t1 & 0xFFFFFFFF;

    final t2 =
        _bitnumIntl(state, 15, 0) |
        (((state & 0x0000F000) << 15) & 0xFFFFFFFF) |
        _bitnumIntl(state, 20, 5) |
        _bitnumIntl(state, 19, 6) |
        (((state & 0x00000F00) << 13) & 0xFFFFFFFF) |
        _bitnumIntl(state, 24, 11) |
        _bitnumIntl(state, 23, 12) |
        (((state & 0x000000F0) << 11) & 0xFFFFFFFF) |
        _bitnumIntl(state, 28, 17) |
        _bitnumIntl(state, 27, 18) |
        (((state & 0x0000000F) << 9) & 0xFFFFFFFF) |
        _bitnumIntl(state, 0, 23);
    final t2Fixed = t2 & 0xFFFFFFFF;

    const sbox = [
      [
        14,
        4,
        13,
        1,
        2,
        15,
        11,
        8,
        3,
        10,
        6,
        12,
        5,
        9,
        0,
        7,
        0,
        15,
        7,
        4,
        14,
        2,
        13,
        1,
        10,
        6,
        12,
        11,
        9,
        5,
        3,
        8,
        4,
        1,
        14,
        8,
        13,
        6,
        2,
        11,
        15,
        12,
        9,
        7,
        3,
        10,
        5,
        0,
        15,
        12,
        8,
        2,
        4,
        9,
        1,
        7,
        5,
        11,
        3,
        14,
        10,
        0,
        6,
        13,
      ],
      [
        15,
        1,
        8,
        14,
        6,
        11,
        3,
        4,
        9,
        7,
        2,
        13,
        12,
        0,
        5,
        10,
        3,
        13,
        4,
        7,
        15,
        2,
        8,
        15,
        12,
        0,
        1,
        10,
        6,
        9,
        11,
        5,
        0,
        14,
        7,
        11,
        10,
        4,
        13,
        1,
        5,
        8,
        12,
        6,
        9,
        3,
        2,
        15,
        13,
        8,
        10,
        1,
        3,
        15,
        4,
        2,
        11,
        6,
        7,
        12,
        0,
        5,
        14,
        9,
      ],
      [
        10,
        0,
        9,
        14,
        6,
        3,
        15,
        5,
        1,
        13,
        12,
        7,
        11,
        4,
        2,
        8,
        13,
        7,
        0,
        9,
        3,
        4,
        6,
        10,
        2,
        8,
        5,
        14,
        12,
        11,
        15,
        1,
        13,
        6,
        4,
        9,
        8,
        15,
        3,
        0,
        11,
        1,
        2,
        12,
        5,
        10,
        14,
        7,
        1,
        10,
        13,
        0,
        6,
        9,
        8,
        7,
        4,
        15,
        14,
        3,
        11,
        5,
        2,
        12,
      ],
      [
        7,
        13,
        14,
        3,
        0,
        6,
        9,
        10,
        1,
        2,
        8,
        5,
        11,
        12,
        4,
        15,
        13,
        8,
        11,
        5,
        6,
        15,
        0,
        3,
        4,
        7,
        2,
        12,
        1,
        10,
        14,
        9,
        10,
        6,
        9,
        0,
        12,
        11,
        7,
        13,
        15,
        1,
        3,
        14,
        5,
        2,
        8,
        4,
        3,
        15,
        0,
        6,
        10,
        10,
        13,
        8,
        9,
        4,
        5,
        11,
        12,
        7,
        2,
        14,
      ],
      [
        2,
        12,
        4,
        1,
        7,
        10,
        11,
        6,
        8,
        5,
        3,
        15,
        13,
        0,
        14,
        9,
        14,
        11,
        2,
        12,
        4,
        7,
        13,
        1,
        5,
        0,
        15,
        10,
        3,
        9,
        8,
        6,
        4,
        2,
        1,
        11,
        10,
        13,
        7,
        8,
        15,
        9,
        12,
        5,
        6,
        3,
        0,
        14,
        11,
        8,
        12,
        7,
        1,
        14,
        2,
        13,
        6,
        15,
        0,
        9,
        10,
        4,
        5,
        3,
      ],
      [
        12,
        1,
        10,
        15,
        9,
        2,
        6,
        8,
        0,
        13,
        3,
        4,
        14,
        7,
        5,
        11,
        10,
        15,
        4,
        2,
        7,
        12,
        9,
        5,
        6,
        1,
        13,
        14,
        0,
        11,
        3,
        8,
        9,
        14,
        15,
        5,
        2,
        8,
        12,
        3,
        7,
        0,
        4,
        10,
        1,
        13,
        11,
        6,
        4,
        3,
        2,
        12,
        9,
        5,
        15,
        10,
        11,
        14,
        1,
        7,
        6,
        0,
        8,
        13,
      ],
      [
        4,
        11,
        2,
        14,
        15,
        0,
        8,
        13,
        3,
        12,
        9,
        7,
        5,
        10,
        6,
        1,
        13,
        0,
        11,
        7,
        4,
        9,
        1,
        10,
        14,
        3,
        5,
        12,
        2,
        15,
        8,
        6,
        1,
        4,
        11,
        13,
        12,
        3,
        7,
        14,
        10,
        15,
        6,
        8,
        0,
        5,
        9,
        2,
        6,
        11,
        13,
        8,
        1,
        4,
        10,
        7,
        9,
        5,
        0,
        15,
        14,
        2,
        3,
        12,
      ],
      [
        13,
        2,
        8,
        4,
        6,
        15,
        11,
        1,
        10,
        9,
        3,
        14,
        5,
        0,
        12,
        7,
        1,
        15,
        13,
        8,
        10,
        3,
        7,
        4,
        12,
        5,
        6,
        11,
        0,
        14,
        9,
        2,
        7,
        11,
        4,
        1,
        9,
        12,
        14,
        2,
        0,
        6,
        10,
        13,
        15,
        3,
        5,
        8,
        2,
        1,
        14,
        7,
        4,
        10,
        8,
        13,
        15,
        12,
        9,
        0,
        3,
        5,
        6,
        11,
      ],
    ];

    final lrgstate = [
      ((t1Fixed >>> 24) & 0xFF) ^ key[0],
      ((t1Fixed >>> 16) & 0xFF) ^ key[1],
      ((t1Fixed >>> 8) & 0xFF) ^ key[2],
      ((t2Fixed >>> 24) & 0xFF) ^ key[3],
      ((t2Fixed >>> 16) & 0xFF) ^ key[4],
      ((t2Fixed >>> 8) & 0xFF) ^ key[5],
    ];

    int sboxBit(int a) =>
        ((a & 32) | ((a & 31) >> 1) | ((a & 1) << 4)) & 0xFFFFFFFF;

    final newState =
        (sbox[0][sboxBit(lrgstate[0] >>> 2)] << 28) |
        (sbox[1][sboxBit(((lrgstate[0] & 0x03) << 4) | (lrgstate[1] >>> 4))] <<
            24) |
        (sbox[2][sboxBit(((lrgstate[1] & 0x0F) << 2) | (lrgstate[2] >>> 6))] <<
            20) |
        (sbox[3][sboxBit(lrgstate[2] & 0x3F)] << 16) |
        (sbox[4][sboxBit(lrgstate[3] >>> 2)] << 12) |
        (sbox[5][sboxBit(((lrgstate[3] & 0x03) << 4) | (lrgstate[4] >>> 4))] <<
            8) |
        (sbox[6][sboxBit(((lrgstate[4] & 0x0F) << 2) | (lrgstate[5] >>> 6))] <<
            4) |
        sbox[7][sboxBit(lrgstate[5] & 0x3F)];
    final newStateFixed = newState & 0xFFFFFFFF;

    int result = 0;
    result |= _bitnumIntl(newStateFixed, 15, 0);
    result |= _bitnumIntl(newStateFixed, 6, 1);
    result |= _bitnumIntl(newStateFixed, 19, 2);
    result |= _bitnumIntl(newStateFixed, 20, 3);
    result |= _bitnumIntl(newStateFixed, 28, 4);
    result |= _bitnumIntl(newStateFixed, 11, 5);
    result |= _bitnumIntl(newStateFixed, 27, 6);
    result |= _bitnumIntl(newStateFixed, 16, 7);
    result |= _bitnumIntl(newStateFixed, 0, 8);
    result |= _bitnumIntl(newStateFixed, 14, 9);
    result |= _bitnumIntl(newStateFixed, 22, 10);
    result |= _bitnumIntl(newStateFixed, 25, 11);
    result |= _bitnumIntl(newStateFixed, 4, 12);
    result |= _bitnumIntl(newStateFixed, 17, 13);
    result |= _bitnumIntl(newStateFixed, 30, 14);
    result |= _bitnumIntl(newStateFixed, 9, 15);
    result |= _bitnumIntl(newStateFixed, 1, 16);
    result |= _bitnumIntl(newStateFixed, 7, 17);
    result |= _bitnumIntl(newStateFixed, 23, 18);
    result |= _bitnumIntl(newStateFixed, 13, 19);
    result |= _bitnumIntl(newStateFixed, 31, 20);
    result |= _bitnumIntl(newStateFixed, 26, 21);
    result |= _bitnumIntl(newStateFixed, 2, 22);
    result |= _bitnumIntl(newStateFixed, 8, 23);
    result |= _bitnumIntl(newStateFixed, 18, 24);
    result |= _bitnumIntl(newStateFixed, 12, 25);
    result |= _bitnumIntl(newStateFixed, 29, 26);
    result |= _bitnumIntl(newStateFixed, 5, 27);
    result |= _bitnumIntl(newStateFixed, 21, 28);
    result |= _bitnumIntl(newStateFixed, 10, 29);
    result |= _bitnumIntl(newStateFixed, 3, 30);
    result |= _bitnumIntl(newStateFixed, 24, 31);
    return result & 0xFFFFFFFF;
  }

  String _removeQrcTag(String raw) {
    final match = RegExp(
      r'''LyricContent\s*=\s*(["'])([\s\S]*?)\1''',
      caseSensitive: false,
    ).firstMatch(raw);
    final content = match?.group(2) ?? raw;
    return _decodeXmlEntities(content).trim();
  }

  String _decodeXmlEntities(String text) {
    return text
        .replaceAll(r'\n', '\n')
        .replaceAll('&#10;', '\n')
        .replaceAll('&#13;', '\r')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
  }

  Map<String, String?> _parseQrcRaw(String raw) {
    String? lyric;
    String? crlyric;

    final lineTimeExp = RegExp(r'^\[(\d+),(\d+)\]');
    final wordTimeAllExp = RegExp(r'\((\d+),(\d+)(?:,\d+)?\)');

    final lrcLines = <String>[];
    final crlrcLines = <String>[];

    for (final rawLine in raw.split('\n')) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) continue;

      final lineMatch = lineTimeExp.firstMatch(trimmed);
      if (lineMatch == null) continue;

      final startMs = int.parse(lineMatch.group(1)!);
      final lineDuration = int.parse(lineMatch.group(2)!);
      final ms = startMs % 1000;
      final totalSec = startMs ~/ 1000;
      final m = (totalSec ~/ 60).toString().padLeft(2, '0');
      final s = (totalSec % 60).toString().padLeft(2, '0');
      final timeStr = '[$m:$s.${ms.toString().padLeft(3, '0')}]';

      var words = trimmed.replaceFirst(lineTimeExp, '');

      lrcLines.add('$timeStr${words.replaceAll(wordTimeAllExp, '')}');

      final times = wordTimeAllExp.allMatches(words).toList();
      if (times.isNotEmpty) {
        final processedTimes = <String>[];
        for (final time in times) {
          final rawStart = int.parse(time.group(1)!);
          final duration = int.parse(time.group(2)!);
          final wordStart = rawStart < startMs || rawStart <= lineDuration + 200
              ? startMs + rawStart
              : rawStart;
          processedTimes.add('($wordStart,$duration,0)');
        }
        final wordArr = words.split(wordTimeAllExp);
        final newWords = StringBuffer();
        if (wordArr.isNotEmpty) newWords.write(wordArr[0]);
        for (var i = 0; i < processedTimes.length; i++) {
          newWords.write(processedTimes[i]);
          final textIndex = i + 1;
          if (textIndex < wordArr.length) {
            newWords.write(wordArr[textIndex]);
          }
        }
        crlrcLines.add('[$startMs,$lineDuration]$newWords');
      }
    }

    lyric = lrcLines.join('\n');
    crlyric = crlrcLines.isNotEmpty ? crlrcLines.join('\n') : null;

    return {'lyric': lyric.isNotEmpty ? lyric : null, 'crlyric': crlyric};
  }

  String? _extractPlainText(String raw) {
    final lineTimeExp = RegExp(r'^\[(\d+),(\d+)\]');
    final wordTimeAllExp = RegExp(r'\(\d+,\d+,\d+\)');
    final lineTime2Exp = RegExp(r'^\[(\d{1,2}):(\d{2})\.(\d{2,3})\]');

    final lines = <String>[];
    for (final rawLine in raw.split('\n')) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) continue;

      var line = trimmed;
      final lineMatch = lineTimeExp.firstMatch(line);
      if (lineMatch != null) {
        final startMs = int.parse(lineMatch.group(1)!);
        final ms = startMs % 1000;
        final totalSec = startMs ~/ 1000;
        final m = (totalSec ~/ 60).toString().padLeft(2, '0');
        final s = (totalSec % 60).toString().padLeft(2, '0');
        line =
            '[$m:$s.${ms.toString().padLeft(3, '0')}]${line.replaceFirst(lineTimeExp, '')}';
      }

      line = line.replaceAll(wordTimeAllExp, '');
      final textOnly = line.replaceFirst(lineTime2Exp, '');
      if (textOnly.trim().isNotEmpty) {
        lines.add(line);
      }
    }
    return lines.isNotEmpty ? lines.join('\n') : null;
  }

  @override
  Future<String?> getCoverUrl(String songId) async {
    try {
      final cleanId = songId.replaceAll('tx_', '');
      return 'https://y.gtimg.cn/music/photo_new/T002R300x300M000$cleanId.jpg';
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<PlaylistTagGroup>> getPlaylistTags() async {
    try {
      final dataParam = jsonEncode({
        'tags': {
          'method': 'get_all_categories',
          'param': {'qq': ''},
          'module': 'playlist.PlaylistAllCategoriesServer',
        },
      });
      final url =
          'https://u.y.qq.com/cgi-bin/musicu.fcg?loginUin=0&hostUin=0'
          '&format=json&inCharset=utf-8&outCharset=utf-8&notice=0'
          '&platform=wk_v15.json&needNewCode=0'
          '&data=${Uri.encodeQueryComponent(dataParam)}';
      final response = await _apiService.get(url);
      dynamic body = response.data;
      if (body is String) body = jsonDecode(body);
      if (body == null || body['code'] != 0) return [];

      final vGroup = body['tags']?['data']?['v_group'] as List? ?? [];
      return vGroup.map((group) {
        final items = (group['v_item'] as List? ?? []).map((item) {
          return PlaylistTag(
            id: item['id'].toString(),
            name: item['name']?.toString() ?? '',
            source: 'tx',
          );
        }).toList();
        return PlaylistTagGroup(
          name: group['group_name']?.toString() ?? '',
          tags: items,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<PlaylistTag>> getHotPlaylistTags() async {
    try {
      const url = 'https://c.y.qq.com/node/pc/wk_v15/category_playlist.html';
      final html = await _apiService.getPlainText(url);
      if (html == null) return [];

      final tagRegExp = RegExp(
        r'class="c_bg_link js_tag_item" data-id="(\w+)">(.+?)</a>',
      );
      final matches = tagRegExp.allMatches(html);
      return matches.map((m) {
        return PlaylistTag(id: m.group(1)!, name: m.group(2)!, source: 'tx');
      }).toList();
    } catch (e) {
      return [];
    }
  }

  String _getListUrl(String sortId, String tagId, int page) {
    if (tagId.isNotEmpty) {
      final id = int.tryParse(tagId) ?? 10000000;
      final data = {
        'comm': {'cv': 1602, 'ct': 20},
        'playlist': {
          'method': 'get_category_content',
          'param': {
            'titleid': id,
            'caller': '0',
            'category_id': id,
            'size': 36,
            'page': page - 1,
            'use_page': 1,
          },
          'module': 'playlist.PlayListCategoryServer',
        },
      };
      return 'https://u.y.qq.com/cgi-bin/musicu.fcg?loginUin=0&hostUin=0&format=json&inCharset=utf-8&outCharset=utf-8&notice=0&platform=wk_v15.json&needNewCode=0&data=${Uri.encodeQueryComponent(jsonEncode(data))}';
    } else {
      final order = sortId == 'new' ? 2 : 5;
      final data = {
        'comm': {'cv': 1602, 'ct': 20},
        'playlist': {
          'method': 'get_playlist_by_tag',
          'param': {
            'id': 10000000,
            'sin': 36 * (page - 1),
            'size': 36,
            'order': order,
            'cur_page': page,
          },
          'module': 'playlist.PlayListPlazaServer',
        },
      };
      return 'https://u.y.qq.com/cgi-bin/musicu.fcg?loginUin=0&hostUin=0&format=json&inCharset=utf-8&outCharset=utf-8&notice=0&platform=wk_v15.json&needNewCode=0&data=${Uri.encodeQueryComponent(jsonEncode(data))}';
    }
  }

  int _parseSongCount(dynamic value) {
    if (value == null) return 0;
    if (value is List) return value.length;
    if (value is num) return value.toInt();
    final text = value.toString().trim();
    if (text.isEmpty) return 0;
    if (text.contains(',')) {
      return text.split(',').where((item) => item.trim().isNotEmpty).length;
    }
    return int.tryParse(text) ?? 0;
  }

  String? _readMapString(dynamic value, String key) {
    if (value is Map) return value[key]?.toString();
    return null;
  }

  String _formatPlayCount(dynamic count) {
    if (count == null) return '';
    final value = count is num
        ? count
        : num.tryParse(count.toString().replaceAll(RegExp(r'[^0-9.]'), ''));
    if (value == null) return count.toString();
    if (value > 100000000) return '${(value / 100000000).toStringAsFixed(1)}亿';
    if (value > 10000) return '${(value / 10000).toStringAsFixed(1)}万';
    return value.toInt().toString();
  }

  @override
  Future<List<Playlist>> getCategoryPlaylists({
    required String sortId,
    required String tagId,
    required int page,
    required int limit,
  }) async {
    try {
      final url = _getListUrl(sortId, tagId, page);
      final response = await _apiService.get(url);
      dynamic respData = response.data;
      if (respData is String) respData = jsonDecode(respData);

      if (respData == null || respData['code'] != 0) {
        return [];
      }

      final data = respData['playlist']['data'];

      if (tagId.isNotEmpty) {
        final content = data['content']['v_item'] as List? ?? [];
        return content.map((item) {
          final basic = item['basic'];
          return Playlist(
            id: 'tx_${basic['tid']?.toString() ?? ''}',
            title: basic['title']?.toString() ?? '',
            description: (basic['desc']?.toString() ?? '').replaceAll(
              '<br>',
              '\n',
            ),
            coverUrl:
                _readMapString(basic['cover'], 'medium_url') ??
                _readMapString(basic['cover'], 'default_url') ??
                '',
            songCount: 0,
            playCount: _formatPlayCount(basic['play_cnt']),
            author: _readMapString(basic['creator'], 'nick') ?? '',
            source: 'tx',
          );
        }).toList();
      } else {
        final playlist = data['v_playlist'] as List? ?? [];
        return playlist.map((item) {
          return Playlist(
            id: 'tx_${item['tid']?.toString() ?? ''}',
            title: item['title']?.toString() ?? '',
            description: (item['desc']?.toString() ?? '').replaceAll(
              '<br>',
              '\n',
            ),
            coverUrl: item['cover_url_medium']?.toString() ?? '',
            songCount: _parseSongCount(item['song_ids']),
            playCount: _formatPlayCount(item['access_num']),
            author: _readMapString(item['creator_info'], 'nick') ?? '',
            source: 'tx',
          );
        }).toList();
      }
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<Leaderboard>> getLeaderboards() async {
    try {
      // CeruMusic uses c.y.qq.com without sign — simpler and more reliable
      final response = await _apiService.get(
        'https://c.y.qq.com/v8/fcg-bin/fcg_myqq_toplist.fcg'
        '?g_tk=5381&loginUin=0&hostUin=0&format=json'
        '&inCharset=utf8&outCharset=utf-8&notice=0'
        '&platform=yqq&needNewCode=0',
      );
      final raw = response.data;
      final data = raw is String ? jsonDecode(raw) : raw;
      if (data == null || data['code'] != 0) {
        return _fallbackLeaderboards();
      }
      final topList = data['data']?['topList'] as List? ?? [];
      final result = topList
          .where((item) => item['id'] != 201) // skip MV榜
          .map((item) {
            return Leaderboard(
              id: 'tx_${item['id']}',
              name: (item['topTitle']?.toString() ?? '').replaceAll('巅峰榜·', ''),
              coverUrl: item['picUrl']?.toString() ?? '',
              playCount: _formatPlayCount(item['listenCount']),
              source: 'tx',
            );
          })
          .toList();
      return result.isNotEmpty ? result : _fallbackLeaderboards();
    } catch (e) {
      return _fallbackLeaderboards();
    }
  }

  List<Leaderboard> _fallbackLeaderboards() {
    return const [
      Leaderboard(id: 'tx_62', name: '飙升榜', source: 'tx'),
      Leaderboard(id: 'tx_26', name: '热歌榜', source: 'tx'),
      Leaderboard(id: 'tx_27', name: '新歌榜', source: 'tx'),
      Leaderboard(id: 'tx_4', name: '流行指数榜', source: 'tx'),
      Leaderboard(id: 'tx_57', name: '电音榜', source: 'tx'),
      Leaderboard(id: 'tx_58', name: '说唱榜', source: 'tx'),
      Leaderboard(id: 'tx_28', name: '网络歌曲榜', source: 'tx'),
      Leaderboard(id: 'tx_5', name: '内地榜', source: 'tx'),
      Leaderboard(id: 'tx_6', name: '港台榜', source: 'tx'),
      Leaderboard(id: 'tx_3', name: '欧美榜', source: 'tx'),
      Leaderboard(id: 'tx_16', name: '韩国榜', source: 'tx'),
      Leaderboard(id: 'tx_17', name: '日本榜', source: 'tx'),
    ];
  }

  @override
  Future<Playlist?> getLeaderboardDetail(String boardId, {int page = 1}) async {
    try {
      final cleanId = boardId.replaceAll('tx_', '');
      final period = await _getLeaderboardPeriod(cleanId);
      final data = {
        'toplist': {
          'module': 'musicToplist.ToplistInfoServer',
          'method': 'GetDetail',
          'param': {
            'topid': int.tryParse(cleanId) ?? 0,
            'num': 300,
            'period': period ?? '',
          },
        },
        'comm': {'uin': 0, 'format': 'json', 'ct': 20, 'cv': 1859},
      };

      final response = await _apiService.post(
        _searchBaseUrl,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)',
        },
        data: data,
      );

      final raw = response.data;
      final respData = raw is String ? jsonDecode(raw) : raw;
      if (respData == null || respData['code'] != 0) return null;

      final topListData = respData['toplist']?['data'];
      final list = topListData?['songInfoList'] as List? ?? [];
      final songs = list.map((item) {
        final singersRaw = item['singer'];
        String singerName = '';
        if (singersRaw is List) {
          singerName = singersRaw
              .map((s) => s is Map ? (s['name']?.toString() ?? '') : '')
              .where((s) => s.isNotEmpty)
              .join('、');
        } else if (singersRaw is String) {
          singerName = singersRaw;
        }
        return Song(
          id: 'tx_${item['mid']?.toString() ?? ''}',
          title: item['name']?.toString() ?? item['title']?.toString() ?? '',
          artist: singerName,
          album: item['album'] is Map
              ? (item['album']['name']?.toString() ?? '')
              : '',
          duration: _parseInt(item['interval']),
          coverUrl: item['album'] is Map && item['album']['mid'] != null
              ? 'https://y.gtimg.cn/music/photo_new/T002R300x300M000${item['album']['mid']}.jpg'
              : '',
          source: 'tx',
          lyricUrl: item['id']?.toString(),
        );
      }).toList();

      final topInfo = topListData?['data'] ?? topListData?['topInfo'];
      return Playlist(
        id: boardId,
        title:
            topInfo?['title']?.toString() ??
            topInfo?['topTitle']?.toString() ??
            '排行榜',
        description: topInfo?['updateTime']?.toString() ?? '',
        songCount: songs.length,
        songs: songs,
        coverUrl:
            topInfo?['headPicUrl']?.toString() ??
            topInfo?['frontPicUrl']?.toString() ??
            '',
        source: 'tx',
      );
    } catch (e) {
      return null;
    }
  }

  Future<String?> _getLeaderboardPeriod(String topId) async {
    try {
      final html = await _apiService.getPlainText(
        'https://c.y.qq.com/node/pc/wk_v15/top.html',
        headers: {
          'Referer': 'https://y.qq.com/',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36',
        },
      );
      if (html == null || html.isEmpty) return null;
      final itemExp = RegExp(
        r'<i class="play_cover__btn c_tx_link js_icon_play" data-listkey=".+?" data-listname=".+?" data-tid=".+?" data-date=".+?" .+?</i>',
        dotAll: true,
      );
      final periodExp = RegExp(
        r'data-listname="(.+?)" data-tid=".*?/(\d+)" data-date="(.+?)"',
        dotAll: true,
      );
      for (final match in itemExp.allMatches(html)) {
        final periodMatch = periodExp.firstMatch(match.group(0) ?? '');
        if (periodMatch != null && periodMatch.group(2) == topId) {
          return periodMatch.group(3);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<Song>> search(
    String query, {
    int page = 1,
    int limit = 20,
  }) async {
    if (query.isEmpty) return [];
    try {
      final requestBody = {
        'comm': {
          'ct': '11',
          'cv': '14090508',
          'v': '14090508',
          'tmeAppID': 'qqmusic',
          'phonetype': 'EBG-AN10',
          'devicelevel': '50',
          'os_ver': '12',
          'OpenUDID': '0',
          'OpenUDID2': '0',
          'QIMEI36': '0',
          'udid': '0',
          'chid': '0',
          'aid': '0',
          'oaid': '0',
          'taid': '0',
          'tid': '0',
          'wid': '0',
          'uid': '0',
          'sid': '0',
          'nettype': '1020',
          'v4ip': '',
        },
        'req': {
          'module': 'music.search.SearchCgiService',
          'method': 'DoSearchForQQMusicMobile',
          'param': {
            'search_type': 0,
            'searchid': _generateSearchId(),
            'query': query,
            'page_num': page,
            'num_per_page': limit,
            'highlight': 0,
            'nqc_flag': 0,
            'multi_zhida': 0,
            'cat': 2,
            'grp': 1,
            'sin': 0,
            'sem': 0,
          },
        },
      };

      final sign = _zzcSign(jsonEncode(requestBody));
      // QQ's signed mobile search endpoint is musics.fcg. Using musicu.fcg
      // often returns a misleading top-level success with req.code=2001.
      final url = '$_signedSearchBaseUrl?sign=$sign';
      final response = await _apiService.post(
        url,
        headers: {
          'User-Agent': 'QQMusic 14090508(android 12)',
          'Content-Type': 'application/json',
        },
        // Sign the exact JSON payload that is sent on the wire.
        data: jsonEncode(requestBody),
      );

      dynamic parsedData = response.data;

      // QQ Music API returns raw JSON string, need to parse it
      if (parsedData is String) {
        try {
          parsedData = jsonDecode(parsedData);
        } catch (e) {
          print('[TxMusicSource] JSON解析失败: $e');
          return [];
        }
      }

      if (parsedData == null || parsedData is! Map) {
        return _searchWithLegacyEndpoint(query, page: page, limit: limit);
      }

      if (parsedData['code'] != 0) {
        return _searchWithLegacyEndpoint(query, page: page, limit: limit);
      }

      if (parsedData['req']?['code'] != 0) {
        return _searchWithLegacyEndpoint(query, page: page, limit: limit);
      }

      final body = parsedData['req']?['data']?['body'];
      if (body == null || body is! Map) {
        return _searchWithLegacyEndpoint(query, page: page, limit: limit);
      }

      // QQ Music mobile search uses 'item_song' instead of 'song'
      dynamic songItem = body['item_song'] ?? body['song'];
      if (songItem == null) {
        return _searchWithLegacyEndpoint(query, page: page, limit: limit);
      }

      List<dynamic> songList;
      if (songItem is Map) {
        songList = songItem['list'] as List? ?? [];
      } else if (songItem is List) {
        songList = songItem;
      } else {
        return _searchWithLegacyEndpoint(query, page: page, limit: limit);
      }
      final songs = songList
          .map((item) {
            if (item is! Map) {
              return Song(
                id: '',
                title: '',
                artist: '',
                album: '',
                duration: 0,
                coverUrl: '',
                source: 'tx',
              );
            }
            final singersRaw = item['singer'];
            String singerName = '';
            if (singersRaw is List) {
              singerName = singersRaw
                  .map((s) => s is Map ? (s['name']?.toString() ?? '') : '')
                  .where((s) => s.isNotEmpty)
                  .join('、');
            } else if (singersRaw is String) {
              singerName = singersRaw;
            }
            return Song(
              id: 'tx_${item['mid']?.toString() ?? ''}',
              title:
                  (item['name']?.toString() ?? '') +
                  (item['title_extra']?.toString() ?? ''),
              artist: singerName,
              album: item['album'] is Map
                  ? (item['album']['name']?.toString() ?? '')
                  : '',
              duration: _parseInt(item['interval']),
              coverUrl: _buildCoverUrl(item),
              source: 'tx',
              lyricUrl: item['id']?.toString(),
            );
          })
          .where((song) => song.id != 'tx_')
          .toList();
      return songs.isNotEmpty
          ? songs
          : _searchWithLegacyEndpoint(query, page: page, limit: limit);
    } catch (e) {
      print('[TxMusicSource] 搜索异常: $e');
      return _searchWithLegacyEndpoint(query, page: page, limit: limit);
    }
  }

  /// QQ's legacy public search endpoint is a resilient fallback for cases
  /// where the signed mobile endpoint responds with an empty/error payload.
  Future<List<Song>> _searchWithLegacyEndpoint(
    String query, {
    required int page,
    required int limit,
  }) async {
    try {
      final url =
          'https://c.y.qq.com/soso/fcgi-bin/client_search_cp'
          '?p=$page'
          '&n=$limit'
          '&w=${Uri.encodeQueryComponent(query)}'
          '&format=json'
          '&new_json=1'
          '&cr=1'
          '&lossless=0'
          '&platform=yqq.json'
          '&needNewCode=0';
      final response = await _apiService.get(
        url,
        headers: {
          'Referer': 'https://y.qq.com/',
          'Origin': 'https://y.qq.com',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      );
      final parsed = _decodeQqJson(response.data);
      if (response.statusCode != 200 ||
          parsed is! Map ||
          _parseInt(parsed['code']) != 0) {
        return [];
      }

      final data = parsed['data'];
      final songData = data is Map ? data['song'] : null;
      final rawList = songData is Map ? songData['list'] : null;
      if (rawList is! List) return [];

      return rawList
          .whereType<Map>()
          .map((item) {
            final songMid =
                item['songmid']?.toString() ?? item['mid']?.toString() ?? '';
            final singersRaw = item['singer'];
            final singerName = singersRaw is List
                ? singersRaw
                      .whereType<Map>()
                      .map((s) => s['name']?.toString() ?? '')
                      .where((name) => name.isNotEmpty)
                      .join('/')
                : singersRaw?.toString() ?? '';
            final albumMid =
                item['albummid']?.toString() ??
                (item['album'] is Map
                    ? item['album']['mid']?.toString() ?? ''
                    : '');
            final singers = singersRaw is List ? singersRaw : const <dynamic>[];
            final singerMid = singers.isNotEmpty && singers.first is Map
                ? (singers.first as Map)['mid']?.toString() ?? ''
                : '';
            final title = item['songname']?.toString().trim().isNotEmpty == true
                ? item['songname'].toString()
                : item['title']?.toString() ?? item['name']?.toString() ?? '';
            final coverUrl = albumMid.isNotEmpty
                ? 'https://y.gtimg.cn/music/photo_new/T002R500x500M000$albumMid.jpg'
                : singerMid.isNotEmpty
                ? 'https://y.gtimg.cn/music/photo_new/T001R500x500M000$singerMid.jpg'
                : '';
            return Song(
              id: 'tx_$songMid',
              title: title,
              artist: singerName,
              album:
                  item['albumname']?.toString() ??
                  (item['album'] is Map
                      ? item['album']['name']?.toString() ?? ''
                      : ''),
              duration: _parseInt(item['interval']),
              coverUrl: coverUrl,
              source: 'tx',
              lyricUrl: item['songid']?.toString() ?? item['id']?.toString(),
            );
          })
          .where((song) => song.id != 'tx_')
          .toList();
    } catch (e) {
      print('[TxMusicSource] legacy search failed: $e');
      return [];
    }
  }

  String _buildCoverUrl(Map item) {
    // Try album mid first
    final albumMid = item['album']?['mid']?.toString();
    if (albumMid != null && albumMid.isNotEmpty) {
      return 'https://y.gtimg.cn/music/photo_new/T002R300x300M000$albumMid.jpg';
    }

    // Try singer mid as fallback
    final singers = item['singer'] as List?;
    if (singers != null && singers.isNotEmpty) {
      final singerMid = singers[0]['mid']?.toString();
      if (singerMid != null && singerMid.isNotEmpty) {
        return 'https://y.gtimg.cn/music/photo_new/T001R300x300M000$singerMid.jpg';
      }
    }

    return '';
  }

  @override
  Future<List<String>> getHotSearchTags() async {
    try {
      final data = {
        'comm': {
          'ct': '19',
          'cv': '1803',
          'guid': '0',
          'patch': '118',
          'psrf_access_token_expiresAt': 0,
          'psrf_qqaccess_token': '',
          'psrf_qqopenid': '',
          'psrf_qqunionid': '',
          'tmeAppID': 'qqmusic',
          'tmeLoginType': 0,
          'uin': '0',
          'wid': '0',
        },
        'hotkey': {
          'method': 'GetHotkeyForQQMusicPC',
          'module': 'tencent_musicsoso_hotkey.HotkeyService',
          'param': {'search_id': '', 'uin': 0},
        },
      };

      final response = await _apiService.post(
        _searchBaseUrl,
        headers: {
          'Referer': 'https://y.qq.com/portal/player.html',
          'User-Agent':
              'Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)',
        },
        data: data,
      );

      final respData = _decodeQqJson(response.data);
      final code = respData is Map ? respData['code'] : null;
      if (response.statusCode != 200 ||
          respData is! Map ||
          !(code == 0 || code?.toString() == '0')) {
        print(
          '[QQMusicSource] 热门搜索响应异常: status=${response.statusCode}, type=${response.data.runtimeType}, code=$code',
        );
        return [];
      }

      final hotkey = respData['hotkey'];
      final hotkeyData = hotkey is Map ? hotkey['data'] : null;
      final req = respData['req'];
      final reqData = req is Map ? req['data'] : null;
      final list = hotkeyData is Map
          ? hotkeyData['vec_hotkey']
          : reqData is Map
          ? reqData['hotkey']
          : null;
      final rawList = list is List ? list : const <dynamic>[];
      final tags = rawList
          .whereType<Map>()
          .map((h) => h['query']?.toString() ?? h['k']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .take(10)
          .toList();
      print('[QQMusicSource] 热门搜索获取成功: ${tags.length}');
      return tags;
    } catch (e) {
      print('[QQMusicSource] 热门搜索请求失败: $e');
      return [];
    }
  }

  @override
  Future<List<String>> getSearchSuggestions(String query) async {
    if (query.isEmpty) return [];
    try {
      final response = await _apiService.get(
        'https://c.y.qq.com/splcloud/fcgi-bin/smartbox_new.fcg?is_xml=0&format=json&key=${Uri.encodeQueryComponent(query)}&loginUin=0&hostUin=0&format=json&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq&needNewCode=0',
        headers: {
          'Referer': 'https://y.qq.com/portal/player.html',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36',
        },
      );
      final data = response.data;
      if (data == null || data['code'] != 0) return [];

      final suggestions = <String>[];
      final songData = data['data']?['song'];
      final songs = songData?['itemlist'] as List? ?? [];
      for (final item in songs) {
        final name = item['name']?.toString() ?? '';
        final singer = item['singer']?.toString() ?? '';
        if (name.isNotEmpty) {
          suggestions.add('$name - $singer');
        }
      }
      return suggestions;
    } catch (e) {
      return [];
    }
  }
}
