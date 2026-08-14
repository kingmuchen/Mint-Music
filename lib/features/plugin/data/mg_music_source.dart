import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../../../core/network/music_api_service.dart';
import '../../player/domain/models/song.dart';
import '../../player/domain/models/lyric_line.dart';
import '../../discover/domain/models/playlist.dart';
import '../../discover/domain/models/leaderboard.dart';
import '../domain/music_source_provider.dart';

class MiguMusicSource implements MusicSourceProvider {
  final MusicApiService _apiService = MusicApiService();

  @override
  String get name => 'MiguMusic';

  @override
  String get version => '1.0.0';

  static const _deviceId = '963B7AA0D21511ED807EE5846EC87D20';
  static const _signatureMd5 = '6cdc72a439cef99a3418d2a78aa28c73';
  static const _defaultHeaders = {
    'User-Agent':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1',
    'Referer': 'https://m.music.migu.cn/',
  };

  Map<String, String> _createSignature(String text) {
    final time = DateTime.now().millisecondsSinceEpoch.toString();
    final signStr =
        '$text$_signatureMd5${'yyapp2d16148780a1dcc7408e06336b98cfd50'}$_deviceId$time';
    final sign = md5.convert(utf8.encode(signStr)).toString();
    return {'sign': sign, 'deviceId': _deviceId, 'timestamp': time};
  }

  @override
  Future<Playlist?> getPlaylistDetail(String playlistId) async {
    try {
      final cleanId = playlistId.replaceAll('mg_', '');
      final response = await _apiService.get(
        'https://app.c.nf.migu.cn/MIGUM3.0/resource/playlist/song/v2.0?pageNo=1&pageSize=100&playlistId=$cleanId',
        headers: _defaultHeaders,
      );
      final data = response.data;
      if (data == null || data['code'] != '000000') return null;

      final list = data['data']?['songList'] as List? ?? [];
      final songs = list.map(_parseMiguSong).toList();

      Map? info;
      try {
        final infoResponse = await _apiService.get(
          'https://c.musicapp.migu.cn/MIGUM3.0/resource/playlist/v2.0?playlistId=$cleanId',
          headers: _defaultHeaders,
        );
        if (infoResponse.data?['code'] == '000000') {
          info = infoResponse.data?['data'];
        }
      } catch (_) {}

      return Playlist(
        id: playlistId,
        title:
            info?['title']?.toString() ??
            data['data']?['title']?.toString() ??
            '歌单',
        description: info?['summary']?.toString() ?? '',
        songCount: songs.length,
        songs: songs,
        coverUrl:
            info?['imgItem']?['img']?.toString() ??
            data['data']?['imgItem']?['img']?.toString() ??
            '',
        author: info?['ownerName']?.toString(),
        playCount: _formatPlayCount(info?['opNumItem']?['playNum']),
        source: 'mg',
      );
    } catch (e) {
      print('[MiguMusicSource] getPlaylistDetail error: $e');
      return null;
    }
  }

  Song _parseMiguSong(dynamic raw) {
    final item = raw is Map ? raw : <String, dynamic>{};
    final singerList = item['singerList'] as List?;
    final singerName =
        item['singerName']?.toString() ??
        item['singer']?.toString() ??
        (singerList == null
            ? ''
            : singerList
                  .map((s) => s is Map ? (s['name']?.toString() ?? '') : '')
                  .where((s) => s.isNotEmpty)
                  .join('、'));
    var coverUrl =
        item['img3']?.toString() ??
        item['img2']?.toString() ??
        item['img1']?.toString() ??
        item['img']?.toString() ??
        item['albumImg']?.toString() ??
        '';
    if (coverUrl.isNotEmpty && !coverUrl.startsWith('http')) {
      coverUrl = 'http://d.musicapp.migu.cn$coverUrl';
    }
    final id =
        item['copyrightId']?.toString() ??
        item['songId']?.toString() ??
        item['id']?.toString() ??
        item['resourceId']?.toString() ??
        '';
    return Song(
      id: 'mg_$id',
      title:
          item['songName']?.toString() ??
          item['name']?.toString() ??
          item['title']?.toString() ??
          '',
      artist: singerName,
      album: item['albumName']?.toString() ?? item['album']?.toString() ?? '',
      duration: _parseDuration(item['duration'] ?? item['length']),
      coverUrl: coverUrl,
      source: 'mg',
    );
  }

  int _parseDuration(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    final text = value?.toString() ?? '';
    if (text.contains(':')) {
      final parts = text.split(':').map((p) => int.tryParse(p) ?? 0).toList();
      return parts.fold(0, (total, part) => total * 60 + part);
    }
    return int.tryParse(text) ?? 0;
  }

  String _formatPlayCount(dynamic count) {
    if (count == null) return '';
    final value = count is num ? count : num.tryParse(count.toString());
    if (value == null) return count.toString();
    if (value >= 100000000) {
      return '${(value / 100000000).toStringAsFixed(1)}亿';
    }
    if (value >= 10000) return '${(value / 10000).toStringAsFixed(1)}万';
    return value.toInt().toString();
  }

  @override
  Future<List<Playlist>> getHotPlaylists() async {
    try {
      final url =
          'https://app.c.nf.migu.cn/pc/bmw/page-data/playlist-square-recommend/v1.0?templateVersion=2&pageNo=1';
      final response = await _apiService.get(
        url,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1',
          'Referer': 'https://m.music.migu.cn/',
        },
      );
      final data = response.data;
      if (data == null || data['code'] != '000000') return [];

      return _parsePlaylistSquareContents(
        data['data']?['contents'],
      ).take(30).toList();
    } catch (e) {
      return [];
    }
  }

  List<Playlist> _parsePlaylistSquareContents(dynamic raw) {
    final result = <Playlist>[];
    final seenIds = <String>{};

    void walk(dynamic node) {
      if (node == null) return;
      if (node is List) {
        for (final item in node) {
          walk(item);
        }
        return;
      }
      if (node is! Map) return;

      final resType = node['resType']?.toString();
      final logEvent = node['logEvent'];
      final logContentType = logEvent is Map
          ? logEvent['contentType']?.toString()
          : null;
      final rawId =
          node['resId']?.toString() ??
          (logEvent is Map ? logEvent['contentId']?.toString() : null) ??
          node['contentId']?.toString();

      if ((resType == '2021' || logContentType == '2021') &&
          rawId != null &&
          rawId.isNotEmpty &&
          !seenIds.contains(rawId)) {
        seenIds.add(rawId);
        result.add(
          Playlist(
            id: 'mg_$rawId',
            title:
                node['txt']?.toString() ??
                (logEvent is Map
                    ? logEvent['contentName']?.toString()
                    : null) ??
                '',
            description: node['txt2']?.toString() ?? '',
            songCount: 0,
            coverUrl: node['img']?.toString() ?? '',
            source: 'mg',
          ),
        );
      }

      walk(node['contents']);
      walk(node['content']);
      walk(node['itemList']);
    }

    walk(raw);
    return result;
  }

  @override
  Future<List<Song>> getPlaylistSongs(String playlistId) async {
    final playlist = await getPlaylistDetail(playlistId);
    return playlist?.songs ?? [];
  }

  @override
  Future<String?> getSongUrl(String songId) async {
    try {
      final cleanId = songId.replaceAll('mg_', '');
      final url =
          'https://c.musicapp.migu.cn/MIGUM2.0/v1.0/content/resourceinfo.do?resourceType=2';
      final response = await _apiService.post(
        url,
        form: {'resourceId': cleanId},
      );
      final data = response.data;
      if (data == null || data['code'] != '000000') return null;
      final resource = data['resource'] as List?;
      if (resource == null || resource.isEmpty) return null;
      final newRateFormats =
          resource.first['newRateFormats'] as List? ??
          resource.first['rateFormats'] as List? ??
          [];
      if (newRateFormats.isEmpty) return null;
      final formatUrl = newRateFormats.first['url']?.toString();
      if (formatUrl != null && formatUrl.isNotEmpty) return formatUrl;
      final androidUrl = newRateFormats.first['androidUrl']?.toString();
      if (androidUrl != null && androidUrl.isNotEmpty) return androidUrl;
      return null;
    } catch (e) {
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
      final cleanId = songId.replaceAll('mg_', '');
      print('[MgMusicSource] getLyricResult: songId=$songId, cleanId=$cleanId');

      final musicInfo = await _getMusicInfo(cleanId);
      print('[MgMusicSource] getLyricResult: musicInfo=$musicInfo');

      if (musicInfo != null) {
        final mrcUrl = musicInfo['mrcUrl'];
        if (mrcUrl != null && mrcUrl.isNotEmpty) {
          final mrcResult = await _getMrcLyric(mrcUrl);
          if (mrcResult != null) {
            final trcUrl = musicInfo['trcUrl']?.toString();
            String? tlyric;
            if (trcUrl != null && trcUrl.isNotEmpty) {
              tlyric = await _getTrcLyric(trcUrl);
            }
            return LyricResult(
              lrc: mrcResult['lyric'],
              crlyric: mrcResult['crlyric'],
              tlyric: tlyric ?? '',
              rlyric: '',
            );
          }
        }

        final lrcUrl = musicInfo['lrcUrl'];
        if (lrcUrl != null && lrcUrl.isNotEmpty) {
          final lrcText = await _getText(lrcUrl);
          if (lrcText != null) {
            final trcUrl = musicInfo['trcUrl']?.toString();
            String? tlyric;
            if (trcUrl != null && trcUrl.isNotEmpty) {
              tlyric = await _getTrcLyric(trcUrl);
            }
            return LyricResult(
              lrc: lrcText,
              tlyric: tlyric ?? '',
              rlyric: '',
              crlyric: '',
            );
          }
        }
      }

      return await _getLyricFromWeb(cleanId);
    } catch (e) {
      print('[MgMusicSource] getLyricResult error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _getMusicInfo(String copyrightId) async {
    try {
      final url =
          'https://c.musicapp.migu.cn/MIGUM2.0/v1.0/content/resourceinfo.do?copyrightId=$copyrightId&resourceType=2';
      final response = await _apiService.get(
        url,
        headers: {
          'Referer': 'https://app.c.nf.migu.cn/',
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 5.1.1; Nexus 6 Build/LYZ28E) AppleWebKit/537.36',
          'channel': '0146921',
        },
      );
      final data = response.data;
      if (data == null || data['code'] != '000000') return null;
      final resource = data['data']?[0];
      if (resource == null) return null;
      return {
        'mrcUrl':
            resource['mrcUrl']?.toString() ?? resource['lrcUrl']?.toString(),
        'lrcUrl': resource['lrcUrl']?.toString(),
        'trcUrl': resource['trcUrl']?.toString(),
      };
    } catch (e) {
      print('[MgMusicSource] _getMusicInfo error: $e');
      return null;
    }
  }

  Future<String?> _getText(String url) async {
    try {
      final text = await _apiService.getPlainText(
        url,
        headers: {
          'Referer': 'https://app.c.nf.migu.cn/',
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 5.1.1; Nexus 6 Build/LYZ28E) AppleWebKit/537.36',
          'channel': '0146921',
        },
      );
      return text;
    } catch (e) {
      print('[MgMusicSource] _getText error for $url: $e');
      return null;
    }
  }

  Future<Map<String, String>?> _getMrcLyric(String url) async {
    try {
      final text = await _getText(url);
      if (text == null || text.isEmpty) return null;

      final decrypted = _mrcDecrypt(text);
      if (decrypted == null || decrypted.isEmpty) return null;

      return _parseMrcLyric(decrypted);
    } catch (e) {
      return null;
    }
  }

  Future<String?> _getTrcLyric(String url) async {
    try {
      return await _getText(url);
    } catch (e) {
      return null;
    }
  }

  Future<LyricResult?> _getLyricFromWeb(String copyrightId) async {
    try {
      final url =
          'https://music.migu.cn/v3/api/music/audioPlayer/getLyric?copyrightId=$copyrightId';
      final response = await _apiService.get(
        url,
        headers: {
          'Referer': 'https://music.migu.cn/v3/music/player/audio?from=migu',
        },
      );
      final data = response.data;
      if (data == null || data['returnCode'] != '000000') return null;
      final lyric = data['lyric']?.toString();
      if (lyric == null || lyric.isEmpty) return null;
      return LyricResult(lrc: lyric, tlyric: '', rlyric: '', crlyric: '');
    } catch (e) {
      return null;
    }
  }

  String? _mrcDecrypt(String data) {
    try {
      if (data.isEmpty || data.length < 32) return data;

      const keyArr = [
        27303562373562475,
        18014862372307051,
        22799692160172081,
        34058940340699235,
        30962724186095721,
        27303523720101991,
        27303523720101998,
        31244139033526382,
        28992395054481524,
      ];

      final bigKeyArr = keyArr.map((e) => BigInt.from(e)).toList();
      final jArr = _toBigintArray(data);
      final decrypted = _teaDecrypt(jArr, bigKeyArr);
      return _longArrToString(decrypted);
    } catch (e) {
      return null;
    }
  }

  List<BigInt> _toBigintArray(String data) {
    final length = data.length ~/ 16;
    final jArr = <BigInt>[];
    for (int i = 0; i < length; i++) {
      final hexStr = data.substring(i * 16, i * 16 + 16);
      jArr.add(BigInt.parse(hexStr, radix: 16));
    }
    return jArr;
  }

  List<BigInt> _teaDecrypt(List<BigInt> data, List<BigInt> key) {
    final delta = BigInt.from(2654435769);
    final length = data.length;
    if (length < 1) return data;

    final lengthBigint = BigInt.from(length);
    var j2 = data[0];
    var j3 = _toLong(
      (BigInt.from(6) + BigInt.from(52) ~/ lengthBigint) * delta,
    );

    while (j3 != BigInt.zero) {
      final j5 = _toLong(BigInt.from(3) & _toLong(j3 >> 2));
      var j6 = lengthBigint;

      while (true) {
        j6 = j6 - BigInt.one;
        if (j6 > BigInt.zero) {
          final j7 = data[j6.toInt() - 1];
          final i = j6.toInt();
          j2 = _toLong(
            data[i] -
                (_toLong(
                      _toLong(j2 ^ j3) +
                          _toLong(
                            j7 ^
                                key[_toLong(
                                  _toLong(j6 & BigInt.from(3)) ^ j5,
                                ).toInt()],
                          ),
                    ) ^
                    _toLong(_toLong(j7 >> 5) + _toLong(j2 << 2)) +
                        _toLong(_toLong(j2 >> 3) + _toLong(j7 << 4))),
          );
          data[i] = j2;
        } else {
          break;
        }
      }

      final j8 = data[length - 1];
      j2 = _toLong(
        data[0] -
            _toLong(
              _toLong(
                    _toLong(
                          key[_toLong(
                                _toLong(j6 & BigInt.from(3)) ^ j5,
                              ).toInt()] ^
                              j8,
                        ) +
                        _toLong(j2 ^ j3),
                  ) ^
                  _toLong(_toLong(j8 >> 5) + _toLong(j2 << 2)) +
                      _toLong(_toLong(j2 >> 3) + _toLong(j8 << 4)),
            ),
      );
      data[0] = j2;
      j3 = _toLong(j3 - delta);
    }

    return data;
  }

  BigInt _toLong(BigInt num) {
    final max = BigInt.from(9223372036854775807);
    final min = BigInt.from(-9223372036854775808);
    final range = BigInt.parse('18446744073709551616');

    if (num > max) return _toLong(num - range);
    if (num < min) return _toLong(num + range);
    return num;
  }

  String _longArrToString(List<BigInt> data) {
    final bytes = <int>[];
    for (final j in data) {
      var l = j;
      for (int i = 0; i < 8; i++) {
        bytes.add((l & BigInt.from(0xff)).toInt());
        l = l >> 8;
      }
    }
    while (bytes.isNotEmpty && bytes.last == 0) {
      bytes.removeLast();
    }
    if (bytes.isEmpty) return '';
    try {
      return utf8.decode(bytes);
    } catch (e) {
      final codeUnits = <int>[];
      for (int i = 0; i < bytes.length - 1; i += 2) {
        final lo = bytes[i];
        final hi = i + 1 < bytes.length ? bytes[i + 1] : 0;
        codeUnits.add(lo | (hi << 8));
      }
      return String.fromCharCodes(codeUnits);
    }
  }

  Map<String, String>? _parseMrcLyric(String str) {
    str = str.replaceAll('\r', '');
    final lines = str.split('\n');
    final lxlrcLines = <String>[];
    final lrcLines = <String>[];

    final lineTimeExp = RegExp(r'^\s*\[(\d+),\d+\]');
    final wordTimeAllExp = RegExp(r'(\(\d+,\d+\))');
    final wordTimeExp = RegExp(r'\((\d+),(\d+)\)');

    for (final line in lines) {
      if (line.length < 6) continue;
      final result = lineTimeExp.firstMatch(line);
      if (result == null) continue;

      final startTime = int.parse(result.group(1)!);
      var time = startTime;
      final ms = time % 1000;
      time = time ~/ 1000;
      final m = (time ~/ 60).toString().padLeft(2, '0');
      time = time % 60;
      final s = time.toString().padLeft(2, '0');
      final timeStr = '$m:$s.$ms';

      final words = line.replaceFirst(lineTimeExp, '');
      lrcLines.add('[$timeStr]${words.replaceAll(wordTimeAllExp, '')}');

      final times = wordTimeAllExp.allMatches(words).toList();
      if (times.isEmpty) continue;

      final convertedTimes = times.map((time) {
        final r = wordTimeExp.firstMatch(time.group(0)!)!;
        return '<${int.parse(r.group(1)!) - startTime},${r.group(2)!}>';
      }).toList();

      final wordArr = words.split(wordTimeAllExp);
      final newWords = StringBuffer();
      for (int i = 0; i < convertedTimes.length && i < wordArr.length; i++) {
        newWords.write(convertedTimes[i]);
        newWords.write(wordArr[i]);
      }
      if (wordArr.length > convertedTimes.length) {
        newWords.write(wordArr.last);
      }
      lxlrcLines.add('[$timeStr]$newWords');
    }

    return {'lyric': lrcLines.join('\n'), 'crlyric': lxlrcLines.join('\n')};
  }

  @override
  Future<String?> getCoverUrl(String songId) async {
    return null;
  }

  @override
  Future<List<PlaylistTagGroup>> getPlaylistTags() async {
    return [];
  }

  @override
  Future<List<PlaylistTag>> getHotPlaylistTags() async {
    return [];
  }

  @override
  Future<List<Playlist>> getCategoryPlaylists({
    required String sortId,
    required String tagId,
    required int page,
    required int limit,
  }) async {
    return getHotPlaylists();
  }

  @override
  Future<List<Leaderboard>> getLeaderboards() async {
    return const [
      Leaderboard(id: 'mg_27553319', name: '新歌榜', source: 'mg'),
      Leaderboard(id: 'mg_27186466', name: '热歌榜', source: 'mg'),
      Leaderboard(id: 'mg_27553408', name: '原创榜', source: 'mg'),
      Leaderboard(id: 'mg_75959118', name: '音乐风向榜', source: 'mg'),
      Leaderboard(id: 'mg_76557036', name: '彩铃分贝榜', source: 'mg'),
      Leaderboard(id: 'mg_76557745', name: '会员挚爱榜', source: 'mg'),
      Leaderboard(id: 'mg_23189800', name: '港台榜', source: 'mg'),
      Leaderboard(id: 'mg_23189399', name: '内地榜', source: 'mg'),
      Leaderboard(id: 'mg_19190036', name: '欧美榜', source: 'mg'),
      Leaderboard(id: 'mg_83176390', name: '国风金曲榜', source: 'mg'),
    ];
  }

  @override
  Future<Playlist?> getLeaderboardDetail(String boardId, {int page = 1}) async {
    try {
      final cleanId = boardId.replaceAll('mg_', '');
      final response = await _apiService.get(
        'https://app.c.nf.migu.cn/MIGUM2.0/v1.0/content/querycontentbyId.do?columnId=$cleanId&needAll=0',
        headers: _defaultHeaders,
      );
      final data = response.data;
      if (data == null || data['code'] != '000000') return null;
      final columnInfo = data['columnInfo'];
      final contents = columnInfo?['contents'] as List? ?? [];
      final songs = contents
          .map((item) => item is Map ? item['objectInfo'] : null)
          .where((item) => item is Map)
          .map(_parseMiguSong)
          .toList();
      return Playlist(
        id: boardId,
        title: columnInfo?['columnTitle']?.toString() ?? '排行榜',
        description: '',
        songCount: songs.length,
        songs: songs,
        source: 'mg',
      );
    } catch (e) {
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
      final signData = _createSignature(query);
      final url =
          'https://jadeite.migu.cn/music_search/v3/search/searchAll?isCorrect=0&isCopyright=1&searchSwitch=%7B%22song%22%3A1%2C%22album%22%3A0%2C%22singer%22%3A0%2C%22tagSong%22%3A1%2C%22mvSong%22%3A0%2C%22bestShow%22%3A1%2C%22songlist%22%3A0%2C%22lyricSong%22%3A0%7D&pageSize=$limit&text=${Uri.encodeQueryComponent(query)}&pageNo=$page&sort=0&sid=USS';

      final response = await _apiService.get(
        url,
        headers: {
          'uiVersion': 'A_music_3.6.1',
          'deviceId': signData['deviceId']!,
          'timestamp': signData['timestamp']!,
          'sign': signData['sign']!,
          'channel': '0146921',
          'User-Agent':
              'Mozilla/5.0 (Linux; U; Android 11.0.0; zh-cn; MI 11 Build/OPR1.170623.032) AppleWebKit/534.30 (KHTML, like Gecko) Version/4.0 Mobile Safari/534.30',
        },
      );
      final data = response.data;
      if (data == null || data['code'] != '000000') return [];

      final songResultData = data['songResultData'] ?? {};
      final resultList = songResultData['resultList'] as List? ?? [];
      print('[MgMusicSource] 搜索结果数量: ${resultList.length}');

      final songs = <Song>[];
      final seenIds = <String>{};

      for (final item in resultList) {
        if (item is! List) continue;
        for (final data in item) {
          if (data is! Map) continue;

          final songId = data['songId']?.toString() ?? '';
          final copyrightId = data['copyrightId']?.toString() ?? '';
          if (songId.isEmpty || copyrightId.isEmpty) continue;
          if (seenIds.contains(copyrightId)) continue;
          seenIds.add(copyrightId);

          final singerList = data['singerList'] as List? ?? [];
          final singerName = singerList
              .map((s) => s['name']?.toString() ?? '')
              .join('、');

          String? img =
              data['img3']?.toString() ??
              data['img2']?.toString() ??
              data['img1']?.toString();
          if (img != null && img.isNotEmpty && !img.startsWith('http')) {
            img = 'http://d.musicapp.migu.cn$img';
          }

          print('[MgMusicSource] 搜索结果: songId=$songId, img=$img');

          songs.add(
            Song(
              id: 'mg_$copyrightId',
              title: data['name']?.toString() ?? '',
              artist: singerName,
              album: data['album']?.toString() ?? '',
              duration: int.tryParse(data['duration']?.toString() ?? '0') ?? 0,
              coverUrl: img,
              source: 'mg',
            ),
          );
        }
      }

      return songs;
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<String>> getHotSearchTags() async {
    try {
      final url = 'http://jadeite.migu.cn:7090/music_search/v3/search/hotword';
      final response = await _apiService.get(url);
      final data = response.data;
      if (data is! Map || data['code'] != '000000') return [];

      final hotwords = data['data']?['hotwords'] as List? ?? [];
      final list = hotwords.isNotEmpty
          ? hotwords.first['hotwordList'] as List? ?? []
          : const <dynamic>[];
      return list
          .map((h) => h['word']?.toString() ?? '')
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
      final url =
          'https://app.c.nf.migu.cn/MIGUM2.0/v1.0/content/search_suggest.do?keyword=${Uri.encodeQueryComponent(query)}';
      final response = await _apiService.get(url);
      final data = response.data;
      if (data == null || data['code'] != '000000') return [];

      final list = data['suggest']?['songList'] as List? ?? [];
      return list
          .map((h) => h['name']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (e) {
      return [];
    }
  }
}
