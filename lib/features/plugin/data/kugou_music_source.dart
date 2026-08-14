import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../../../core/network/music_api_service.dart';
import '../../player/domain/models/song.dart';
import '../../player/domain/models/lyric_line.dart';
import '../../discover/domain/models/playlist.dart';
import '../../discover/domain/models/leaderboard.dart';
import '../domain/music_source_provider.dart';

dynamic _decodeKugouJson(dynamic raw) {
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

class KugouMusicSource implements MusicSourceProvider {
  final MusicApiService _apiService = MusicApiService();

  @override
  String get name => 'KuGouMusic';

  @override
  String get version => '1.0.0';

  static const _searchBaseUrl = 'https://songsearch.kugou.com/song_search_v2';
  static const _songInfoBaseUrl = 'http://m.kugou.com/app/i/getSongInfo.php';
  static const _lyricBaseUrl = 'http://m.kugou.com/app/i/krc.php';
  static const _rankDetailBaseUrl =
      'http://mobilecdnbj.kugou.com/api/v3/rank/song';
  static const _plistDetailBaseUrl = 'http://m.kugou.com/plist/list';
  static const _hotSearchBaseUrl =
      'https://gateway.kugou.com/api/v3/search/hot_tab';
  static const _hotSearchFallbackUrl =
      'http://gateway.kugou.com/api/v3/search/hot_tab';

  // 酷狗码解析（t.kugou.com/command/）
  static const _commandBaseUrl = 'http://t.kugou.com/command/';
  static const _commandHeaders = {
    'KG-RC': '1',
    'KG-THash': 'network_super_call.cpp:3676261689:379',
    'User-Agent': '',
  };
  static const _commandCommonBody = {
    'appid': 1001,
    'clientver': 9020,
    'mid': '21511157a05844bd085308bc76ef3343',
    'clienttime': 640612895,
    'key': '36164c4015e704673c588ee202b9ecb8',
  };
  // 酷狗码对应的歌单（用户收藏）拉取
  static const _kucodeShareBaseUrl =
      'http://www2.kugou.kugou.com/apps/kucodeAndShare/app/';
  // gcid 歌单详情（手机分享链接 m.kugou.com/songlist/gcid_xxx）
  static const _gcidSongBaseUrl =
      'https://mobiles.kugou.com/api/v5/special/song_v2';
  static const _gcidInfoBaseUrl =
      'https://mobiles.kugou.com/api/v5/special/info_v2';
  static const _gcidHeaders = {
    'mid': '1586163242519',
    'Referer': 'https://m3ws.kugou.com/share/index.php',
    'User-Agent':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 11_0 like Mac OS X) AppleWebKit/604.1.38 (KHTML, like Gecko) Version/11.0 Mobile/15A372 Safari/604.1',
    'dfid': '-',
    'clienttime': '1586163242519',
  };

  String _decodeName(String name) {
    return name
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');
  }

  @override
  Future<List<Song>> search(
    String query, {
    int page = 1,
    int limit = 20,
  }) async {
    if (query.isEmpty) return [];

    try {
      final url =
          '$_searchBaseUrl?keyword=${Uri.encodeQueryComponent(query)}&page=$page&pagesize=$limit&userid=0&clientver=&platform=WebFilter&filter=2&iscorrection=1&privilege_filter=0&area_code=1';
      final response = await _apiService.get(url);
      dynamic data = response.data;

      // Kugou API returns raw JSON string, need to parse it
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (e) {
          return [];
        }
      }

      if (data is! Map) {
        return [];
      }

      if (data['status'] != 1 && data['errcode'] != 0) {
        return [];
      }

      dynamic dataNode = data['data'];
      if (dataNode is String) {
        try {
          dataNode = jsonDecode(dataNode);
        } catch (e) {
          return [];
        }
      }
      if (dataNode is! Map) {
        return [];
      }

      dynamic info =
          dataNode['lists'] ?? dataNode['abslist'] ?? dataNode['info'];
      if (info == null) {
        return [];
      }

      List<dynamic> songList;
      if (info is List) {
        songList = info;
      } else if (info is Map) {
        try {
          songList = info.values
              .where((e) => e is List)
              .expand((e) => (e as List))
              .toList();
          if (songList.isEmpty) {
            songList = info.values.where((e) => e is Map).toList();
          }
        } catch (e) {
          return [];
        }
      } else {
        return [];
      }

      return songList.asMap().entries.map((entry) {
        final item = entry.value;
        if (item is! Map) {
          return Song(
            id: '',
            title: '',
            artist: '',
            album: '',
            duration: 0,
            coverUrl: '',
            source: 'kg',
          );
        }
        final duration =
            int.tryParse(
              item['Duration']?.toString() ??
                  item['duration']?.toString() ??
                  '0',
            ) ??
            0;
        return Song(
          id: 'kg_${item['FileHash'] ?? item['hash'] ?? ''}',
          title: _decodeName(
            item['SongName']?.toString() ??
                item['songname']?.toString() ??
                item['filename']?.toString() ??
                '',
          ),
          artist: _decodeName(
            item['SingerName']?.toString() ??
                item['singername']?.toString() ??
                '',
          ),
          album: _decodeName(
            item['AlbumName']?.toString() ??
                item['album_name']?.toString() ??
                '',
          ),
          duration: duration,
          coverUrl: _buildCoverUrl(item),
          source: 'kg',
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<Playlist?> getPlaylistDetail(String playlistId) async {
    try {
      final cleanId = playlistId.replaceAll('kg_', '');

      // 纯数字：可能是酷狗码，优先尝试酷狗码解码；失败回退普通歌单ID
      if (RegExp(r'^\d+$').hasMatch(cleanId)) {
        try {
          final decoded = await _getPlaylistByKugouCode(cleanId);
          if (decoded != null && decoded.songs.isNotEmpty) return decoded;
          print('[KugouMusicSource] 酷狗码解析无结果，回退歌单ID: $cleanId');
        } catch (e) {
          print('[KugouMusicSource] 酷狗码解析失败，回退歌单ID: $e');
        }
      } else if (_isGcid(cleanId)) {
        // 手机版分享链接：m.kugou.com/songlist/gcid_xxx
        final gcidPlaylist = await _getPlaylistByGcid(cleanId);
        if (gcidPlaylist != null && gcidPlaylist.songs.isNotEmpty) {
          return gcidPlaylist;
        }
      }

      return await _getPlaylistDetailBySpecialId(playlistId, cleanId);
    } catch (e) {
      final cleanId = playlistId.replaceAll('kg_', '');
      return _getPlaylistDetailBySpecialId(playlistId, cleanId);
    }
  }

  /// 判断是否为 gcid（手机版歌单分享 ID，形如 3z9vj0yqz4bz00b）
  bool _isGcid(String id) {
    return id.length >= 8 &&
        RegExp(r'^[a-zA-Z0-9]+$').hasMatch(id) &&
        !RegExp(r'^\d+$').hasMatch(id);
  }

  /// kugou 部分接口返回的 JSON 是原始字符串（Content-Type 非 application/json），统一解析
  Map? _decodeJsonMap(dynamic data) {
    if (data is Map) return data;
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        return decoded is Map ? decoded : null;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// 通过酷狗码获取歌单（t.kugou.com/command/ 解码）
  Future<Playlist?> _getPlaylistByKugouCode(String code) async {
    final response = await _apiService.post(
      _commandBaseUrl,
      headers: _commandHeaders,
      data: {..._commandCommonBody, 'data': code},
    );
    final data = _decodeJsonMap(response.data);
    if (data == null) return null;

    final errCode = data['err_code'] ?? data['errcode'];
    if (errCode != null && errCode != 0) {
      print('[KugouMusicSource] 酷狗码解码失败 err_code=$errCode');
      return null;
    }

    final payload = data['data'];
    if (payload is! Map) return null;
    final info = payload['info'];
    if (info is! Map) return null;

    final name = info['name']?.toString() ?? '';
    final imgSize = info['img_size']?.toString();
    final img = (imgSize != null && imgSize.isNotEmpty)
        ? imgSize.replaceAll('{size}', '240')
        : info['img']?.toString();
    final author = info['username']?.toString();
    final type = info['type']?.toString();
    final id = info['id']?.toString();
    final userid = info['userid']?.toString();
    final gcid = info['global_collection_id']?.toString();

    // type 2 歌单且无 gcid → 直接按歌单ID拉取
    if (type == '2' && gcid == null && id != null) {
      final playlist = await _getPlaylistDetailBySpecialId('kg_$id', id);
      if (playlist != null && playlist.songs.isNotEmpty) return playlist;
    }

    // 有 global_collection_id → 按 gcid 拉取
    if (gcid != null) {
      final playlist = await _getPlaylistByGcid(
        gcid,
        name: name.isEmpty ? null : name,
        img: img,
        author: author,
      );
      if (playlist != null && playlist.songs.isNotEmpty) return playlist;
    }

    // 用户收藏歌单（酷狗码关联 userid）→ kucodeAndShare 拉取
    if (userid != null && id != null) {
      final playlist = await _getPlaylistByKucodeShare(
        id,
        userid,
        count: info['count']?.toString(),
        name: name.isEmpty ? null : name,
        img: img,
        author: author,
      );
      if (playlist != null && playlist.songs.isNotEmpty) return playlist;
    }

    // 解码接口直接返回的歌曲列表
    final rawList = payload['list'];
    if (rawList is List && rawList.isNotEmpty) {
      final songs = await _hydrateKugouSongs(rawList.whereType<Map>().toList());
      if (songs.isNotEmpty) {
        return _buildPlaylist(
          'kg_$code',
          name.isEmpty ? '酷狗歌单' : name,
          '',
          img,
          author,
          songs,
        );
      }
    }

    // 兜底：按歌单ID拉取
    if (id != null) {
      final playlist = await _getPlaylistDetailBySpecialId('kg_$id', id);
      if (playlist != null && playlist.songs.isNotEmpty) return playlist;
    }

    return null;
  }

  /// 通过 gcid 拉取歌单歌曲（mobiles.kugou.com song_v2，签名接口）
  /// 链接中的 gcid 是编码形式（如 3zo7prv6z9z0f0），先解码成 global_collection_id 再拉取
  Future<Playlist?> _getPlaylistByGcid(
    String gcid, {
    String? name,
    String? img,
    String? author,
  }) async {
    var realGcid = gcid;
    if (!gcid.startsWith('collection_')) {
      try {
        final decoded = await _decodeGcid(gcid);
        if (decoded != null && decoded.isNotEmpty) {
          realGcid = decoded;
          print('[KugouMusicSource] gcid 解码: $gcid -> $realGcid');
        }
      } catch (e) {
        print('[KugouMusicSource] gcid 解码失败（忽略）: $e');
      }
    }

    // 尝试获取歌单信息（名称/封面），失败不影响歌曲拉取
    String? resolvedName = name;
    String? resolvedImg = img;
    try {
      final infoParams =
          'appid=1058&specialid=0&global_specialid=$realGcid&format=jsonp&srcappid=2919&clientver=20000&clienttime=1586163242519&mid=1586163242519&uuid=1586163242519&dfid=-';
      final infoUrl =
          '$_gcidInfoBaseUrl?$infoParams&signature=${_kugouSignature(infoParams, web: true)}';
      final infoResponse = await _apiService.get(
        infoUrl,
        headers: _gcidHeaders,
      );
      final infoData = _decodeJsonMap(infoResponse.data);
      final inner = infoData?['data'];
      if (inner is Map) {
        resolvedName = inner['specialname']?.toString() ?? resolvedName;
        resolvedImg = inner['imgurl']?.toString() ?? resolvedImg;
      }
    } catch (e) {
      print('[KugouMusicSource] gcid 歌单信息获取失败（忽略）: $e');
    }

    final songs = <Song>[];
    var page = 1;
    const pageSize = 300;
    while (true) {
      final params =
          'appid=1058&global_specialid=$realGcid&specialid=0&plat=0&version=8000&page=$page&pagesize=$pageSize&srcappid=2919&clientver=20000&clienttime=1586163263991&mid=1586163263991&uuid=1586163263991&dfid=-';
      final url =
          '$_gcidSongBaseUrl?$params&signature=${_kugouSignature(params, web: true)}';
      final response = await _apiService.get(url, headers: _gcidHeaders);
      final data = _decodeJsonMap(response.data);
      if (data == null) break;
      final inner = data['data'];
      if (inner is! Map) break;
      final infoList = inner['info'] as List? ?? [];
      if (infoList.isEmpty) break;
      final hydrated = await _hydrateKugouSongs(
        infoList.whereType<Map>().toList(),
      );
      songs.addAll(hydrated);
      final total = int.tryParse(inner['total']?.toString() ?? '') ?? 0;
      if (total > 0 && songs.length >= total) break;
      if (infoList.length < pageSize) break;
      page++;
    }

    if (songs.isEmpty) return null;
    return _buildPlaylist(
      'kg_$realGcid',
      (resolvedName == null || resolvedName.isEmpty) ? '酷狗歌单' : resolvedName,
      '',
      resolvedImg,
      author,
      songs,
    );
  }

  /// 解码编码 gcid → global_collection_id（t.kugou.com/v1/songlist/batch_decode）
  Future<String?> _decodeGcid(String gcid) async {
    const params =
        'dfid=-&appid=1005&mid=0&clientver=20109&clienttime=640612895&uuid=-';
    final body = {
      'ret_info': 1,
      'data': [
        {'id': gcid, 'id_type': 2},
      ],
    };
    final bodyStr = jsonEncode(body);
    final url =
        'https://t.kugou.com/v1/songlist/batch_decode?$params&signature=${_kugouSignature(params, body: bodyStr)}';
    final response = await _apiService.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 10; HUAWEI HMA-AL00) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/83.0.4103.106 Mobile Safari/537.36',
        'Referer': 'https://m.kugou.com/',
      },
      data: body,
    );
    final data = _decodeJsonMap(response.data);
    if (data == null) return null;
    final payload = data['data'];
    if (payload is! Map) return null;
    final list = payload['list'] as List? ?? [];
    if (list.isEmpty) return null;
    final first = list.first;
    if (first is! Map) return null;
    return first['global_collection_id']?.toString();
  }

  /// 通过 kucodeAndShare 拉取酷狗码关联的用户收藏歌单
  Future<Playlist?> _getPlaylistByKucodeShare(
    String id,
    String userid, {
    String? count,
    String? name,
    String? img,
    String? author,
  }) async {
    final pagesize = int.tryParse(count ?? '') ?? 300;
    final response = await _apiService.post(
      _kucodeShareBaseUrl,
      headers: _commandHeaders,
      data: {
        ..._commandCommonBody,
        'data': {
          'id': id,
          'type': 3,
          'userid': userid,
          'collect_type': 0,
          'page': 1,
          'pagesize': pagesize,
        },
      },
    );
    final data = _decodeJsonMap(response.data);
    if (data == null) return null;
    final rawList = data['data'] is List
        ? data['data'] as List
        : (data['info'] is List ? data['info'] as List : null);
    if (rawList == null || rawList.isEmpty) return null;

    final songs = await _hydrateKugouSongs(rawList.whereType<Map>().toList());
    if (songs.isEmpty) return null;
    return _buildPlaylist(
      'kg_$id',
      (name == null || name.isEmpty) ? '酷狗歌单' : name,
      '',
      img,
      author,
      songs,
    );
  }

  Playlist _buildPlaylist(
    String id,
    String title,
    String description,
    String? coverUrl,
    String? author,
    List<Song> songs,
  ) {
    return Playlist(
      id: id,
      title: title,
      description: description,
      coverUrl: coverUrl != null ? _normalizeKugouImage(coverUrl, '400') : null,
      songCount: songs.length,
      songs: songs,
      author: author,
      source: 'kg',
    );
  }

  /// kugou 接口签名：MD5(key + 排序后的参数 + body + key)
  String _kugouSignature(String params, {String body = '', bool web = false}) {
    final key = web
        ? 'NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt'
        : 'OIlwieks28dk2k092lksi2UIkp';
    final sorted = (params.split('&')..sort()).join();
    return md5.convert(utf8.encode('$key$sorted$body$key')).toString();
  }

  /// 按歌单ID（specialid）拉取详情：m.kugou.com/plist/list + HTML 兜底
  Future<Playlist?> _getPlaylistDetailBySpecialId(
    String playlistId,
    String cleanId,
  ) async {
    try {
      final response = await _apiService.get(
        '$_plistDetailBaseUrl/$cleanId?json=true',
      );
      final data = response.data;
      if (data['status'] != 1) return null;
      final info = data['list']?['info'];
      if (info == null) return null;
      final songs = <Song>[];
      final members = info['members'] as List? ?? [];
      for (final item in members) {
        final duration = int.tryParse(item['duration']?.toString() ?? '0') ?? 0;
        songs.add(
          Song(
            id: 'kg_${item['hash']}',
            title:
                item['songname']?.toString() ??
                item['filename']?.toString() ??
                '',
            artist: item['singername']?.toString() ?? '',
            album: item['album_name']?.toString() ?? '',
            duration: duration,
            coverUrl: item['album_img']?.toString().replaceAll('{size}', '800'),
            source: 'kg',
          ),
        );
      }
      final playlist = Playlist(
        id: playlistId,
        title: info['specialname']?.toString() ?? '',
        description: info['intro']?.toString() ?? '',
        coverUrl: info['imgurl']?.toString().replaceAll('{size}', '400'),
        songCount: info['songcount'] ?? songs.length,
        songs: songs,
        source: 'kg',
      );
      if (songs.isNotEmpty) return playlist;
      return await _getPlaylistDetailFromHtml(playlistId, cleanId) ?? playlist;
    } catch (e) {
      return _getPlaylistDetailFromHtml(playlistId, cleanId);
    }
  }

  Future<Playlist?> _getPlaylistDetailFromHtml(
    String playlistId,
    String cleanId,
  ) async {
    try {
      final html = await _apiService.getPlainText(
        'http://www2.kugou.kugou.com/yueku/v9/special/single/$cleanId-5-9999.html',
      );
      if (html == null || html.isEmpty) return null;

      final listMatch = RegExp(
        r'global\.data = (\[.+?\]);',
        dotAll: true,
      ).firstMatch(html);
      if (listMatch == null) return null;

      final rawList = jsonDecode(listMatch.group(1)!) as List;
      final songs = await _hydrateKugouSongs(rawList.whereType<Map>().toList());

      final infoMatch = RegExp(
        r'global = \{[\s\S]+?name: "(.+?)"[\s\S]+?pic: "(.+?)"[\s\S]+?\};',
      ).firstMatch(html);
      final desc = _parseHtmlDescription(html);

      return Playlist(
        id: playlistId,
        title: infoMatch != null ? _decodeName(infoMatch.group(1)!) : '歌单',
        description: desc ?? '',
        coverUrl: infoMatch?.group(2),
        songCount: songs.length,
        songs: songs,
        source: 'kg',
      );
    } catch (e) {
      return null;
    }
  }

  String? _parseHtmlDescription(String html) {
    const prefix =
        '<div class="pc_specail_text pc_singer_tab_content" id="specailIntroduceWrap">';
    final start = html.indexOf(prefix);
    if (start < 0) return null;
    final after = html.substring(start + prefix.length);
    final end = after.indexOf('</div>');
    if (end < 0) return null;
    return _decodeName(after.substring(0, end).trim());
  }

  Song _parseKugouSong(Map item) {
    final audioInfo = item['audio_info'] is Map
        ? item['audio_info'] as Map
        : null;
    final albumInfo = item['album_info'] is Map
        ? item['album_info'] as Map
        : null;
    final hash =
        item['FileHash']?.toString() ??
        item['hash']?.toString() ??
        audioInfo?['hash']?.toString() ??
        item['audio_id']?.toString() ??
        '';
    return Song(
      id: 'kg_$hash',
      title: _decodeName(
        item['SongName']?.toString() ??
            item['songname']?.toString() ??
            item['songname_original']?.toString() ??
            item['filename']?.toString() ??
            item['FileName']?.toString() ??
            '',
      ),
      artist: _decodeName(
        item['SingerName']?.toString() ??
            item['singername']?.toString() ??
            item['AuthorName']?.toString() ??
            item['author_name']?.toString() ??
            '',
      ),
      album: _decodeName(
        item['AlbumName']?.toString() ??
            item['album_name']?.toString() ??
            albumInfo?['album_name']?.toString() ??
            '',
      ),
      duration: _parseDurationSeconds(item),
      coverUrl: _buildCoverUrl(item),
      source: 'kg',
    );
  }

  int _parseDurationSeconds(Map item) {
    final audioInfo = item['audio_info'] is Map
        ? item['audio_info'] as Map
        : null;
    final raw =
        item['Duration'] ??
        item['duration'] ??
        item['timeLength'] ??
        item['timelength'] ??
        audioInfo?['timelength'];
    final value = raw is num
        ? raw.toDouble()
        : double.tryParse(raw?.toString() ?? '') ?? 0;
    if (value <= 0) return 0;
    return value > 10000 ? (value / 1000).round() : value.round();
  }

  Future<List<Song>> _hydrateKugouSongs(List<Map> rawList) async {
    final hashes = rawList
        .map(
          (item) =>
              item['hash']?.toString() ?? item['FileHash']?.toString() ?? '',
        )
        .where((hash) => hash.isNotEmpty)
        .toList();
    if (hashes.isEmpty) return rawList.map(_parseKugouSong).toList();

    final hydrated = <Map>[];
    for (var i = 0; i < hashes.length; i += 100) {
      final chunk = hashes.skip(i).take(100).toList();
      try {
        final response = await _apiService.post(
          'http://gateway.kugou.com/v2/album_audio/audio',
          headers: {
            'KG-THash': '13a3164',
            'KG-RC': '1',
            'KG-Fake': '0',
            'KG-RF': '00869891',
            'User-Agent':
                'Android712-AndroidPhone-11451-376-0-FeeCacheUpdate-wifi',
            'x-router': 'kmr.service.kugou.com',
          },
          data: {
            'area_code': '1',
            'show_privilege': 1,
            'show_album_info': '1',
            'is_publish': '',
            'appid': 1005,
            'clientver': 11451,
            'mid': '1',
            'dfid': '-',
            'clienttime': DateTime.now().millisecondsSinceEpoch,
            'key': 'OIlwieks28dk2k092lksi2UIkp',
            'fields':
                'album_info,author_name,audio_info,ori_audio_name,base,songname',
            'data': chunk.map((hash) => {'hash': hash}).toList(),
          },
        );
        final data = response.data;
        final list = data is Map ? data['data'] as List? ?? [] : [];
        for (final row in list) {
          if (row is List && row.isNotEmpty && row.first is Map) {
            hydrated.add(row.first as Map);
          } else if (row is Map) {
            hydrated.add(row);
          }
        }
      } catch (_) {}
    }

    return (hydrated.isNotEmpty ? hydrated : rawList)
        .map(_parseKugouSong)
        .toList();
  }

  @override
  Future<List<Playlist>> getHotPlaylists({int tryNum = 0}) async {
    if (tryNum > 2) return [];
    try {
      final url =
          'http://www2.kugou.kugou.com/yueku/v9/special/getSpecial?is_ajax=1&cdn=cdn&t=5&c=&p=1';
      final response = await _apiService.get(url);
      dynamic data = response.data;

      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (e) {
          return [];
        }
      }

      if (data == null || data['status'] != 1) {
        return getHotPlaylists(tryNum: tryNum + 1);
      }
      final specialDb = data['special_db'] as List? ?? [];
      final playlists = specialDb.take(20).map((item) {
        return Playlist(
          id: 'kg_${item['specialid']}',
          title: _decodeName(item['specialname']?.toString() ?? ''),
          description: _decodeName(item['intro']?.toString() ?? ''),
          coverUrl: _normalizeKugouImage(
            (item['img'] ?? item['imgurl'])?.toString(),
            '400',
          ),
          songCount: item['songcount'] ?? item['song_count'] ?? 0,
          playCount: _formatPlayCount(
            item['total_play_count'] ?? item['playcount'] ?? item['play_count'],
          ),
          author:
              item['username']?.toString() ??
              item['nickname']?.toString() ??
              item['author']?.toString(),
          source: 'kg',
        );
      }).toList();

      if (playlists.isNotEmpty) {
        await _enrichSongCounts(playlists);
      }
      return playlists;
    } catch (e) {
      return [];
    }
  }

  Future<void> _enrichSongCounts(List<Playlist> playlists) async {
    final futures = <Future<Map<String, dynamic>?>>[];
    for (int i = 0; i < playlists.length; i++) {
      final id = playlists[i].id.replaceAll('kg_', '');
      final idx = i;
      futures.add(_fetchSongCount(id, idx));
    }

    final results = await Future.wait(futures);
    for (final r in results) {
      if (r != null) {
        final index = r['index'] as int;
        final count = r['songCount'] as int;
        if (index >= 0 && index < playlists.length) {
          playlists[index] = playlists[index].copyWith(songCount: count);
        }
      }
    }
  }

  Future<Map<String, dynamic>?> _fetchSongCount(
    String specialId,
    int index,
  ) async {
    try {
      final resp = await _apiService.get(
        'http://mobilecdn.kugou.com/api/v3/special/info?specialid=$specialId&version=9108',
      );
      dynamic d = resp.data;
      if (d is String) d = jsonDecode(d);
      if (d != null && d['errcode'] == 0) {
        final info = d['data'] as Map?;
        if (info != null && info['songcount'] != null) {
          return {'index': index, 'songCount': info['songcount'] as int};
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<List<Song>> getPlaylistSongs(String playlistId) async {
    final playlist = await getPlaylistDetail(playlistId);
    return playlist?.songs ?? [];
  }

  @override
  Future<String?> getSongUrl(String songId) async {
    try {
      final cleanId = songId.replaceAll('kg_', '');
      final url =
          '$_songInfoBaseUrl?cmd=playInfo&hash=$cleanId&from=mkugou&apiver=2&plat=0';
      print('[KugouMusicSource] getSongUrl: $url');
      final response = await _apiService.get(url);
      print(
        '[KugouMusicSource] getSongUrl: status=${response.statusCode}, data type=${response.data.runtimeType}',
      );
      final data = response.data;
      if (data is Map && data['status'] == 1) {
        final url = data['url']?.toString();
        print('[KugouMusicSource] getSongUrl: url=$url');
        return url;
      }
      print('[KugouMusicSource] getSongUrl: status not 1 or not Map');
      return null;
    } catch (e) {
      print('[KugouMusicSource] getSongUrl error: $e');
      return null;
    }
  }

  @override
  Future<String?> getLyric(String songId) async {
    final result = await getLyricResult(songId);
    return result?.lrc;
  }

  @override
  Future<LyricResult?> getLyricResult(String songId) async {
    try {
      final cleanId = songId.replaceAll('kg_', '');

      final songInfo = await _getSongInfo(cleanId);
      final songName = songInfo?['songName']?.toString() ?? '';
      final duration = songInfo?['duration'] is int
          ? (songInfo!['duration'] as int) * 1000
          : (int.tryParse(songInfo?['duration']?.toString() ?? '0') ?? 0) *
                1000;

      final searchHeaders = {
        'KG-RC': '1',
        'KG-THash': 'expand_search_manager.cpp:852736169:451',
        'User-Agent': 'KuGou2012-9020-ExpandSearchManager',
      };

      final searchResponse = await _apiService.get(
        'http://lyrics.kugou.com/search?ver=1&man=yes&client=pc&keyword=${Uri.encodeQueryComponent(songName)}&hash=$cleanId&timelength=$duration&lrctxt=1',
        headers: searchHeaders,
      );

      final searchData = searchResponse.data;
      if (searchData == null) {
        return null;
      }

      final candidates = searchData['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        final fallbackLrc = await _getFallbackLyric(cleanId, duration);
        if (fallbackLrc != null) return fallbackLrc;
        return null;
      }

      final candidate = candidates.first;
      final lyricId = candidate['id']?.toString();
      final accessKey = candidate['accesskey']?.toString();
      final krcType = candidate['krctype'];
      final contentType = candidate['contenttype'];
      final fmt = (krcType == 1 && contentType != 1) ? 'krc' : 'lrc';

      if (lyricId == null || accessKey == null) return null;

      final downloadResponse = await _apiService.get(
        'http://lyrics.kugou.com/download?ver=1&client=pc&id=$lyricId&accesskey=$accessKey&fmt=$fmt&charset=utf8',
        headers: searchHeaders,
      );

      final downloadData = downloadResponse.data;
      if (downloadData == null) return null;

      final content = downloadData['content']?.toString();
      if (content == null || content.isEmpty) return null;

      final responseFmt = downloadData['fmt']?.toString() ?? fmt;

      if (responseFmt == 'krc') {
        return _decodeKrc(content);
      } else {
        final decoded = utf8.decode(base64Decode(content));
        return LyricResult(lrc: decoded, tlyric: '', rlyric: '', crlyric: '');
      }
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _getSongInfo(String hash) async {
    try {
      final response = await _apiService.get(
        '$_songInfoBaseUrl?cmd=playInfo&hash=$hash&from=mkugou&apiver=2&plat=0',
      );
      final data = response.data;
      if (data is Map && data['status'] == 1) {
        return {
          'songName': data['songName'] ?? data['fileName'],
          'duration': data['timeDuration'] ?? data['duration'],
        };
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<LyricResult?> _getFallbackLyric(String hash, int duration) async {
    try {
      final response = await _apiService.get(
        '$_lyricBaseUrl?cmd=100&hash=$hash&timelength=$duration&apiver=2&plat=0',
        headers: {
          'KG-RC': '1',
          'KG-THash': 'expand_search_manager.cpp:852736169:451',
          'User-Agent': 'KuGou2012-9020-ExpandSearchManager',
        },
      );
      final data = response.data;
      if (data == null || data['status'] != 1) return null;
      final content = data['content']?.toString();
      if (content == null || content.isEmpty) return null;
      return LyricResult(lrc: content, tlyric: '', rlyric: '', crlyric: '');
    } catch (e) {
      return null;
    }
  }

  Future<LyricResult?> _decodeKrc(String base64Content) async {
    try {
      final rawBytes = base64Decode(base64Content);
      if (rawBytes.length < 4) return null;

      final buf = Uint8List.fromList(rawBytes.sublist(4));

      const encKey = [
        0x40,
        0x47,
        0x61,
        0x77,
        0x5e,
        0x32,
        0x74,
        0x47,
        0x51,
        0x36,
        0x31,
        0x2d,
        0xce,
        0xd2,
        0x6e,
        0x69,
      ];
      for (int i = 0; i < buf.length; i++) {
        buf[i] = buf[i] ^ encKey[i % 16];
      }

      final decompressed = zlib.decode(buf);
      final str = utf8.decode(decompressed);

      return _parseKrcText(str);
    } catch (e) {
      return null;
    }
  }

  LyricResult _parseKrcText(String str) {
    str = str.replaceAll('\r', '');

    // Step 1: Remove header
    final headExp = RegExp(r'^.*\[id:\$\w+\]\n');
    str = str.replaceFirst(headExp, '');

    // Step 2: Parse language info if exists
    final transMatch = RegExp(r'\[language:([\w=\\/+]+)\]').firstMatch(str);
    List<String>? rlyricLines;
    List<String>? tlyricLines;

    if (transMatch != null) {
      str = str.replaceFirst(RegExp(r'\[language:[\w=\\/+]+\]\n?'), '');
      try {
        final jsonStr = utf8.decode(base64Decode(transMatch.group(1)!));
        final json = jsonDecode(jsonStr) as Map;
        final content = json['content'] as List;
        for (final item in content) {
          final type = item['type'];
          final lyricContent = item['lyricContent'] as List;
          switch (type) {
            case 0:
              rlyricLines = lyricContent.map((line) {
                if (line is List) {
                  return line.map((w) => w?.toString() ?? '').join('');
                }
                return line?.toString() ?? '';
              }).toList();
              break;
            case 1:
              tlyricLines = lyricContent.map((line) {
                if (line is List) {
                  return line.map((w) => w?.toString() ?? '').join('');
                }
                return line?.toString() ?? '';
              }).toList();
              break;
          }
        }
      } catch (e) {
        // ignore parse error
      }
    }

    final wordTimeExp = RegExp(r'<(\d+),(\d+),(\d+)>');
    final lineTimeExp = RegExp(r'\[((\d+),\d+)\]');

    // Step 3: Process each line
    final lines = str.split('\n');
    final lrcLines = <String>[];
    final crlrcLines = <String>[];
    final rLyricWithTime = <String>[];
    final tLyricWithTime = <String>[];

    int lineIdx = 0;
    for (final line in lines) {
      if (line.trim().isEmpty) continue;

      final lineMatch = lineTimeExp.firstMatch(line);
      if (lineMatch == null) continue;

      // 从原始 KRC [start,duration] 中提取行持续时长，而非硬编码 5000ms
      final lineTimeParts = lineMatch.group(1)!.split(',');
      final lineStartTime = int.parse(lineTimeParts[0]);
      final lineDuration = int.parse(lineTimeParts[1]);

      // Convert line start time to [mm:ss.xxx] format
      final ms = lineStartTime % 1000;
      final totalSec = lineStartTime ~/ 1000;
      final m = (totalSec ~/ 60).toString().padLeft(2, '0');
      final s = (totalSec % 60).toString().padLeft(2, '0');
      final timeStr = '[$m:$s.${ms.toString().padLeft(3, '0')}]';

      // Process word timings - convert relative to absolute
      String crLine = line.replaceAllMapped(wordTimeExp, (wordMatch) {
        final start = int.parse(wordMatch.group(1)!);
        final duration = int.parse(wordMatch.group(2)!);
        final param = int.parse(wordMatch.group(3)!);
        final absoluteStart = lineStartTime + start;
        return '($absoluteStart,$duration,$param)';
      });

      // Create plain lyric line (without word timings)
      final plainLine = line.replaceAll(wordTimeExp, '');
      final lrcLine = plainLine.replaceFirst(lineTimeExp, timeStr);

      lrcLines.add(lrcLine);
      crlrcLines.add(
        crLine.replaceFirst(lineTimeExp, '[$lineStartTime,$lineDuration]'),
      );

      // Add time labels to translation and transliteration
      if (rlyricLines != null && lineIdx < rlyricLines.length) {
        rLyricWithTime.add('$timeStr${rlyricLines[lineIdx]}');
      }
      if (tlyricLines != null && lineIdx < tlyricLines.length) {
        tLyricWithTime.add('$timeStr${tlyricLines[lineIdx]}');
      }

      lineIdx++;
    }

    // Step 4: Final cleanups
    final lyric = lrcLines.join('\n');
    final crlyric = crlrcLines.join('\n');
    final rlyric = rLyricWithTime.join('\n');
    final tlyric = tLyricWithTime.join('\n');

    return LyricResult(
      lrc: lyric,
      tlyric: tlyric,
      rlyric: rlyric,
      crlyric: crlyric,
    );
  }

  @override
  Future<String?> getCoverUrl(String songId) async {
    try {
      final cleanId = songId.replaceAll('kg_', '');
      final response = await _apiService.get(
        '$_songInfoBaseUrl?cmd=playInfo&hash=$cleanId&from=mkugou&apiver=2&plat=0',
      );
      final data = response.data;
      if (data['status'] != 1) return null;
      return data['album_img']?.toString().replaceAll('{size}', '400');
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<String>> getHotSearchTags() async {
    try {
      var response = await _apiService.get(
        '$_hotSearchBaseUrl?signature=ee44edb9d7155821412d220bcaf509dd&appid=1005&clientver=10026&plat=0',
        headers: {
          'dfid': '1ssiv93oVqMp27cirf2CvoF1',
          'mid': '156798703528610303473757548878786007104',
          'clienttime': '1584257267',
          'x-router': 'msearch.kugou.com',
          'User-Agent':
              'Android9-AndroidPhone-10020-130-0-searchrecommendprotocol-wifi',
          'kg-rc': '1',
        },
      );
      // The gateway occasionally returns 502 on HTTPS while the same
      // endpoint is still available through its legacy HTTP entry point.
      if (response.statusCode != 200) {
        response = await _apiService.get(
          '$_hotSearchFallbackUrl?signature=ee44edb9d7155821412d220bcaf509dd&appid=1005&clientver=10026&plat=0',
          headers: {
            'dfid': '1ssiv93oVqMp27cirf2CvoF1',
            'mid': '156798703528610303473757548878786007104',
            'clienttime': '1584257267',
            'x-router': 'msearch.kugou.com',
            'User-Agent':
                'Android9-AndroidPhone-10020-130-0-searchrecommendprotocol-wifi',
            'kg-rc': '1',
          },
        );
      }
      final data = _decodeKugouJson(response.data);
      final errcode = data is Map ? data['errcode'] : null;
      if (response.statusCode != 200 ||
          data is! Map ||
          !(errcode == 0 || errcode?.toString() == '0')) {
        print(
          '[KugouMusicSource] 热门搜索响应异常: status=${response.statusCode}, type=${response.data.runtimeType}, errcode=$errcode',
        );
        return [];
      }

      final rawLists = <dynamic>[];
      final payload = data['data'];
      final info = payload is Map ? payload['info'] : null;
      final list = payload is Map ? payload['list'] : null;
      if (info is List) rawLists.addAll(info);
      if (list is List) rawLists.addAll(list);

      final result = <String>[];
      for (final item in rawLists) {
        if (item is! Map) continue;
        final directKeyword = item['keyword']?.toString() ?? '';
        if (directKeyword.isNotEmpty) result.add(directKeyword);
        final keywords = item['keywords'];
        if (keywords is List) {
          for (final keyword in keywords) {
            if (keyword is Map) {
              final value = keyword['keyword']?.toString() ?? '';
              if (value.isNotEmpty) result.add(value);
            }
          }
        }
      }
      final tags = result.toSet().take(10).toList();
      print('[KugouMusicSource] 热门搜索获取成功: ${tags.length}');
      return tags;
    } catch (e) {
      print('[KugouMusicSource] 热门搜索请求失败: $e');
      return [];
    }
  }

  @override
  Future<List<String>> getSearchSuggestions(String query) async {
    if (query.isEmpty) return [];
    try {
      final response = await _apiService.get(
        'https://searchtip.kugou.com/getSearchTip?MusicTipCount=10&keyword=${Uri.encodeQueryComponent(query)}',
        headers: {'Referer': 'https://www.kugou.com/'},
      );
      final data = response.data;
      if (data == null) return [];

      final results = <String>[];
      final rawData = data is List
          ? data
          : (data is Map ? data['data'] as List? ?? [] : []);
      if (rawData.isNotEmpty) {
        final songData = rawData[0];
        final records = songData['RecordDatas'] as List? ?? [];
        for (final item in records) {
          final hint = item['HintInfo']?.toString() ?? '';
          if (hint.isNotEmpty) results.add(hint);
        }
      }
      return results.take(10).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<PlaylistTagGroup>> getPlaylistTags() async {
    return [
      PlaylistTagGroup(
        name: '语种',
        tags: [
          const PlaylistTag(id: '', name: '全部', source: 'kg'),
          const PlaylistTag(id: '华语', name: '华语', source: 'kg'),
          const PlaylistTag(id: '欧美', name: '欧美', source: 'kg'),
        ],
      ),
      PlaylistTagGroup(
        name: '风格',
        tags: [
          const PlaylistTag(id: '流行', name: '流行', source: 'kg'),
          const PlaylistTag(id: '摇滚', name: '摇滚', source: 'kg'),
          const PlaylistTag(id: '民谣', name: '民谣', source: 'kg'),
        ],
      ),
    ];
  }

  @override
  Future<List<PlaylistTag>> getHotPlaylistTags() async {
    return [
      const PlaylistTag(id: '', name: '全部', source: 'kg'),
      const PlaylistTag(id: '华语', name: '华语', source: 'kg'),
      const PlaylistTag(id: '流行', name: '流行', source: 'kg'),
      const PlaylistTag(id: '电子', name: '电子', source: 'kg'),
    ];
  }

  @override
  Future<List<Playlist>> getCategoryPlaylists({
    required String sortId,
    required String tagId,
    required int page,
    required int limit,
  }) async {
    try {
      final actualSortId = sortId.isEmpty
          ? '5'
          : (_kugouSortIdMap[sortId] ?? sortId);
      final url = _getSongListUrl(actualSortId, tagId, page);
      final response = await _apiService.get(url);
      dynamic data = response.data;
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {
          return [];
        }
      }
      if (data['status'] != 1) return [];
      final infoList = data['special_db'] as List? ?? [];
      final playlists = infoList.map((pl) {
        return Playlist(
          id: 'kg_${pl['specialid']}',
          title: _decodeName(pl['specialname']?.toString() ?? ''),
          description: _decodeName(pl['intro']?.toString() ?? ''),
          coverUrl: _normalizeKugouImage(
            pl['img']?.toString() ?? pl['imgurl']?.toString(),
            '400',
          ),
          songCount: pl['songcount'] ?? pl['song_count'] ?? 0,
          playCount: _formatPlayCount(
            pl['total_play_count'] ?? pl['playcount'] ?? pl['play_count'],
          ),
          author: pl['username']?.toString(),
          source: 'kg',
        );
      }).toList();
      if (playlists.isNotEmpty) {
        await _enrichSongCounts(playlists);
      }
      return playlists;
    } catch (e) {
      return [];
    }
  }

  String _getSongListUrl(String sortId, String tagId, int page) {
    final effectiveSortId = _kugouSortIdMap[sortId] ?? sortId;
    if (tagId.isEmpty) {
      return 'http://www2.kugou.kugou.com/yueku/v9/special/getSpecial?is_ajax=1&cdn=cdn&t=$effectiveSortId&c=&p=$page';
    } else {
      return 'http://www2.kugou.kugou.com/yueku/v9/special/getSpecial?is_ajax=1&cdn=cdn&t=$effectiveSortId&c=$tagId&p=$page';
    }
  }

  static const _kugouSortIdMap = {'hot': '6', 'new': '7', 'recommend': '5'};

  @override
  Future<List<Leaderboard>> getLeaderboards() async {
    try {
      final response = await _apiService.get(
        'http://mobilecdnbj.kugou.com/api/v5/rank/list?version=9108&plat=0&showtype=2&parentid=0&apiver=6&area_code=1&withsong=1',
      );
      final raw = response.data;
      final data = raw is String ? jsonDecode(raw) : raw;
      if (data == null || (data['errcode'] != 0 && data['status'] != 1)) {
        return _fallbackLeaderboards();
      }
      final infoList = data['data']?['info'] as List? ?? [];
      final result = infoList
          .where((item) => item is Map && item['isvol']?.toString() == '1')
          .map((item) {
            final cover =
                item['banner_9']?.toString() ??
                item['table_plaque']?.toString() ??
                item['album_img_9']?.toString();
            return Leaderboard(
              id: 'kg_${item['rankid'] ?? item['id']}',
              name: item['rankname']?.toString() ?? '',
              coverUrl: _normalizeKugouImage(cover, '400'),
              playCount: _formatPlayCount(item['play_times']),
              updateFrequency: item['update_frequency_type']?.toString(),
              source: 'kg',
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
      Leaderboard(id: 'kg_8888', name: 'TOP500', source: 'kg'),
      Leaderboard(id: 'kg_6666', name: '飙升榜', source: 'kg'),
      Leaderboard(id: 'kg_59703', name: '蜂鸟流行音乐榜', source: 'kg'),
      Leaderboard(id: 'kg_52144', name: '抖音热歌榜', source: 'kg'),
      Leaderboard(id: 'kg_24971', name: 'DJ热歌榜', source: 'kg'),
      Leaderboard(id: 'kg_23784', name: '网络红歌榜', source: 'kg'),
      Leaderboard(id: 'kg_31308', name: '内地榜', source: 'kg'),
      Leaderboard(id: 'kg_31310', name: '欧美榜', source: 'kg'),
      Leaderboard(id: 'kg_33160', name: '电影榜', source: 'kg'),
    ];
  }

  @override
  Future<Playlist?> getLeaderboardDetail(String boardId, {int page = 1}) async {
    try {
      final cleanId = boardId.replaceAll('kg_', '');
      final response = await _apiService.get(
        '$_rankDetailBaseUrl?version=9108&ranktype=1&plat=0&pagesize=100&area_code=1&page=$page&rankid=$cleanId&with_res_tag=0&show_portrait_mv=1',
      );
      final raw = response.data;
      final data = raw is String ? jsonDecode(raw) : raw;
      if (data == null || (data['errcode'] != 0 && data['status'] != 1))
        return null;
      final bodyData = data['data'];
      final songList =
          bodyData?['info'] as List? ?? bodyData?['list'] as List? ?? [];
      final songs = songList.whereType<Map>().map(_parseKugouSong).toList();
      final firstSong = songList.isNotEmpty ? songList.first as Map? : null;
      final detailCover =
          bodyData?['imgurl']?.toString() ??
          bodyData?['banner_9']?.toString() ??
          firstSong?['album_sizable_cover']?.toString();
      return Playlist(
        id: boardId,
        title: bodyData?['rankname']?.toString() ?? '排行榜',
        description: bodyData?['intro']?.toString() ?? '',
        coverUrl: _normalizeKugouImage(detailCover, '400'),
        songCount: songs.length,
        songs: songs,
        playCount: _formatPlayCount(bodyData?['play_times']),
        source: 'kg',
      );
    } catch (e) {
      return null;
    }
  }

  String _buildCoverUrl(Map item) {
    final albumInfo = item['album_info'] is Map
        ? item['album_info'] as Map
        : null;
    for (final value in [
      item['sizable_cover'],
      item['album_sizable_cover'],
      albumInfo?['sizable_cover'],
      albumInfo?['album_img'],
      albumInfo?['img'],
      item['img'],
      item['pic'],
    ]) {
      final image = _normalizeKugouImage(value?.toString(), '800');
      if (image != null && image.isNotEmpty) return image;
    }

    // Try direct image fields first
    final directImg = item['Image']?.toString();
    if (directImg != null && directImg.isNotEmpty) {
      return _normalizeKugouImage(directImg, '800') ?? '';
    }

    final albumImg = item['album_img']?.toString();
    if (albumImg != null && albumImg.isNotEmpty) {
      return _normalizeKugouImage(albumImg, '800') ?? '';
    }

    // Construct from FileHash
    final hash = item['FileHash']?.toString() ?? item['hash']?.toString();
    if (hash != null && hash.isNotEmpty) {
      return 'https://imge.kugou.com/800/$hash.jpg';
    }

    return '';
  }

  String? _normalizeKugouImage(String? url, String size) {
    if (url == null || url.isEmpty) return url;
    var result = url.replaceAll('{size}', size);
    if (result.startsWith('//')) result = 'https:$result';
    return result.replaceAll('http://', 'https://');
  }

  String _formatPlayCount(dynamic count) {
    if (count == null) return '';
    if (count is String) {
      if (count.contains('亿') || count.contains('万')) return count;
      if (count.isEmpty) return '';
    }
    final n = count is int ? count : int.tryParse(count.toString()) ?? 0;
    if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    return n.toString();
  }

  void dispose() {
    _apiService.dispose();
  }
}
