import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:gbk_codec/gbk_codec.dart';
import '../../../core/network/music_api_service.dart';
import '../../player/domain/models/song.dart';
import '../../player/domain/models/lyric_line.dart';
import '../../discover/domain/models/playlist.dart';
import '../../discover/domain/models/leaderboard.dart';
import '../domain/music_source_provider.dart';

dynamic _decodeKuwoJson(dynamic raw) {
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

/// 酷我 `nmobi.kuwo.cn/mobi.s` 接口返回的音频元数据。
class _NmobiResult {
  final String url;
  final int duration;
  final int bitrate;
  final int type;
  final String format;

  const _NmobiResult({
    required this.url,
    this.duration = 0,
    this.bitrate = 0,
    this.type = 0,
    this.format = '',
  });
}

class KuwoMusicSource implements MusicSourceProvider {
  final MusicApiService _apiService = MusicApiService();
  static const _fullCoverDirectorySize = 1500;

  @override
  String get name => 'KuwoMusic';

  @override
  String get version => '1.0.0';

  static const _songDetailBaseUrl =
      'http://m.kuwo.cn/newh5/singles/songinfoandlrc';
  static const _picBaseUrl = 'http://kuwo.cn/api/v1/www/music/playInfo';

  String? _normalizeCoverUrl(Object? value, {bool artist = false}) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    if (raw.startsWith('//')) return 'http:$raw';
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw.replaceFirst(
        RegExp(r'^https://', caseSensitive: false),
        'http://',
      );
    }

    final path = raw.replaceFirst(RegExp(r'^/+'), '');
    final directory = artist ? 'starheads' : 'albumcover';
    return 'http://img1.kuwo.cn/star/$directory/$path';
  }

  /// Kuwo serves the same artwork under several resolution directories
  /// (`120`, `500`, `700`, `1500`, ...). Search responses deliberately use the 120px
  /// thumbnail for quick list rendering, while the player should use the
  /// largest public artwork variant.
  String? _toHighResolutionCoverUrl(Object? value) {
    final normalized = _normalizeCoverUrl(value);
    if (normalized == null) return null;
    return normalized.replaceFirstMapped(
      RegExp(r'/(albumcover|starheads)/\d+/'),
      (match) => '/${match.group(1)}/$_fullCoverDirectorySize/',
    );
  }

  String? _cleanSongId(String songId) {
    final raw = songId
        .replaceFirst(RegExp(r'^kw_', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^music_', caseSensitive: false), '');
    return RegExp(r'\d+').firstMatch(raw)?.group(0);
  }

  @override
  Future<Playlist?> getPlaylistDetail(
    String playlistId, {
    int retryNum = 0,
  }) async {
    if (retryNum > 2) return null;
    try {
      String actualId = playlistId;
      if (actualId.startsWith('kw_')) {
        actualId = actualId.substring(3);
      }

      int? digestType;
      if (actualId.startsWith('digest-')) {
        final parts = actualId.split('__');
        if (parts.length == 2) {
          digestType = int.tryParse(parts[0].replaceFirst('digest-', ''));
          actualId = parts[1];
        }
      }

      if (digestType == 5) {
        return _getPlaylistDetailDigest5(actualId);
      }

      // digest-13 = album playlist; fall through to digest8 as best effort
      final result = await _getPlaylistDetailDigest8(actualId);
      if (result != null && result.songs.isNotEmpty) return result;
      if (result == null && retryNum < 2) {
        return getPlaylistDetail(playlistId, retryNum: retryNum + 1);
      }
      return result;
    } catch (e) {
      if (retryNum < 2) {
        return getPlaylistDetail(playlistId, retryNum: retryNum + 1);
      }
      return null;
    }
  }

  Future<Playlist?> _getPlaylistDetailDigest8(
    String id, {
    int tryNum = 0,
  }) async {
    if (tryNum > 2) return null;
    try {
      final url =
          'http://nplserver.kuwo.cn/pl.svc?op=getlistinfo&pid=$id&pn=0&rn=1000&encode=utf8&keyset=pl2012&identity=kuwo&pcmp4=1&plat=web&from=web&vipver=MUSIC_9.0.5.0_W1&newver=1';
      final response = await _apiService.get(url);
      dynamic data = response.data;
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {
          return _getPlaylistDetailDigest8(id, tryNum: tryNum + 1);
        }
      }
      if (data == null)
        return _getPlaylistDetailDigest8(id, tryNum: tryNum + 1);
      if (data['result'] != null && data['result'] != 'ok') {
        return _getPlaylistDetailDigest8(id, tryNum: tryNum + 1);
      }

      final list = data['musiclist'] as List? ?? [];
      final songs = list.map((item) {
        final rid = item['id']?.toString() ?? item['mid']?.toString() ?? '';
        final durationStr = item['duration']?.toString() ?? '0';
        return Song(
          id: 'kw_$rid',
          title: _decodeName(item['name']?.toString() ?? ''),
          artist: _decodeName(
            item['artist']?.toString() ?? item['singer']?.toString() ?? '',
          ),
          album: _decodeName(item['album']?.toString() ?? ''),
          duration: int.tryParse(durationStr) ?? 0,
          coverUrl:
              item['albumpic']?.toString() ??
              item['musicPic']?.toString() ??
              '',
          source: 'kw',
        );
      }).toList();

      return Playlist(
        id: 'kw_digest-8__$id',
        title: _decodeName(
          data['title']?.toString() ?? data['name']?.toString() ?? '未知歌单',
        ),
        description: data['info']?.toString() ?? '',
        songCount: songs.length,
        songs: songs,
        coverUrl: data['pic']?.toString() ?? '',
        author: data['uname']?.toString(),
        playCount: _formatPlayCount(data['playnum']),
        source: 'kw',
      );
    } catch (e) {
      return _getPlaylistDetailDigest8(id, tryNum: tryNum + 1);
    }
  }

  Future<Playlist?> _getPlaylistDetailDigest5(
    String id, {
    int tryNum = 0,
  }) async {
    if (tryNum > 2) return null;
    try {
      final infoUrl =
          'http://qukudata.kuwo.cn/q.k?op=query&cont=ninfo&node=$id&pn=0&rn=1&fmt=json&src=mbox&level=2';
      final infoResponse = await _apiService.get(infoUrl);
      dynamic infoData = infoResponse.data;
      if (infoData is String) {
        try {
          infoData = jsonDecode(infoData);
        } catch (_) {
          return null;
        }
      }
      if (infoData == null) return null;

      final child = infoData['child'] as List? ?? [];
      if (child.isEmpty) return null;
      final sourceId = child[0]['sourceid']?.toString();
      if (sourceId == null) return null;

      final url =
          'http://nplserver.kuwo.cn/pl.svc?op=getlistinfo&pid=$sourceId&pn=0&rn=1000&encode=utf-8&keyset=pl2012&identity=kuwo&pcmp4=1&plat=web&from=web&vipver=MUSIC_9.0.5.0_W1&newver=1';
      final response = await _apiService.get(url);
      dynamic data = response.data;
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {
          return _getPlaylistDetailDigest5(id, tryNum: tryNum + 1);
        }
      }
      if (data == null)
        return _getPlaylistDetailDigest5(id, tryNum: tryNum + 1);
      if (data['result'] != null && data['result'] != 'ok') {
        return _getPlaylistDetailDigest5(id, tryNum: tryNum + 1);
      }

      final list = data['musiclist'] as List? ?? [];
      final songs = list.map((item) {
        final rid = item['id']?.toString() ?? item['mid']?.toString() ?? '';
        final durationStr = item['duration']?.toString() ?? '0';
        return Song(
          id: 'kw_$rid',
          title: _decodeName(item['name']?.toString() ?? ''),
          artist: _decodeName(
            item['artist']?.toString() ?? item['singer']?.toString() ?? '',
          ),
          album: _decodeName(item['album']?.toString() ?? ''),
          duration: int.tryParse(durationStr) ?? 0,
          coverUrl:
              item['albumpic']?.toString() ??
              item['musicPic']?.toString() ??
              '',
          source: 'kw',
        );
      }).toList();

      return Playlist(
        id: 'kw_digest-5__$id',
        title: _decodeName(
          data['title']?.toString() ?? data['name']?.toString() ?? '未知歌单',
        ),
        description: data['info']?.toString() ?? '',
        songCount: songs.length,
        songs: songs,
        coverUrl: data['pic']?.toString() ?? '',
        author: data['uname']?.toString(),
        playCount: _formatPlayCount(data['playnum']),
        source: 'kw',
      );
    } catch (e) {
      return _getPlaylistDetailDigest5(id, tryNum: tryNum + 1);
    }
  }

  @override
  Future<List<Playlist>> getHotPlaylists() async {
    try {
      final url =
          'http://wapi.kuwo.cn/api/pc/classify/playlist/getRcmPlayList?loginUid=0&loginSid=0&appUid=76039576&pn=1&rn=20&order=hot';
      final response = await _apiService.get(url);
      dynamic data = response.data;
      if (data is String) data = jsonDecode(data);
      if (data == null || data['code'] != 200) return [];

      final list = data['data']?['data'] as List? ?? [];
      return list.map((item) {
        return Playlist(
          id: 'kw_digest-${item['digest']}__${item['id']}',
          title: _decodeName(item['name']?.toString() ?? ''),
          description: item['desc']?.toString() ?? '',
          songCount: _parseInt(item['total']),
          coverUrl: item['img']?.toString() ?? '',
          playCount: _formatPlayCount(item['listencnt']),
          author: item['uname']?.toString(),
          source: 'kw',
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

  /// 将应用内音质标识映射为酷我 `br` 参数。
  ///
  /// 酷我 `nmobi.kuwo.cn/mobi.s` 车机端接口的 `br` 取值：
  /// 128kmp3 / 192kmp3 / 320kmp3 / flac / flac24bit / hires。
  static String _qualityToBr(String quality) {
    switch (quality.toLowerCase()) {
      case '320k':
        return '320kmp3';
      case '192k':
        return '192kmp3';
      case 'flac':
        return 'flac';
      case 'flac24bit':
      case '24bit':
        return 'flac24bit';
      case 'hires':
      case 'lossless':
        return 'hires';
      case '128k':
      default:
        return '128kmp3';
    }
  }

  /// 音质感知的播放地址获取。优先于 [getSongUrl]，供 MusicSourceManager 在
  /// 解析 kw 源 URL 时直接传入用户请求的音质，避免只回退到 128k。
  ///
  /// [expectedDurationSeconds] 为歌曲预期时长（秒）。当传入大于 0 的值时，
  /// 会把接口返回的 `duration` 与之比较，明显不符的地址会被丢弃，避免把
  /// 酷我提示音当成正式歌曲返回。
  ///
  /// 实现走 `nmobi.kuwo.cn/mobi.s` 车机端接口。对返回结果会二次校验，丢弃
  /// 酷我提示音（短时长、低码率、type=1）、加密格式（.mflac/.mgg）等
  /// 不可播放的 URL。
  Future<String?> getSongUrlWithQuality(
    String songId, {
    String quality = '320k',
    int expectedDurationSeconds = 0,
  }) async {
    try {
      final cleanId = songId.replaceAll('kw_', '');
      final br = _qualityToBr(quality);

      // 优先按请求音质获取；若返回加密/提示音等无效地址，则降级到 320k/128k。
      final brChain = <String>[];
      void addBr(String value) {
        if (!brChain.contains(value)) brChain.add(value);
      }

      addBr(br);
      if (br != '320kmp3') addBr('320kmp3');
      if (br != '128kmp3') addBr('128kmp3');

      for (final candidateBr in brChain) {
        // 同一音质多次更换随机 user/loginUid 重试，避免某组账号被限制或
        // 固定返回提示音。
        for (var attempt = 0; attempt < _nmobiRetryCount; attempt++) {
          final result = await _getNmobiUrl(cleanId, candidateBr);
          if (result != null &&
              _isValidKwAudioResult(
                result,
                expectedDurationSeconds: expectedDurationSeconds,
              )) {
            print(
              '[KwMusicSource] getSongUrlWithQuality($quality/$br) success: '
              'duration=${result.duration} bitrate=${result.bitrate} url=${result.url}',
            );
            return result.url;
          }
          print(
            '[KwMusicSource] getSongUrlWithQuality($quality/$br) $candidateBr '
            'attempt=${attempt + 1} invalid: ${result?.url} '
            '(duration=${result?.duration}, bitrate=${result?.bitrate}, type=${result?.type})',
          );
        }
      }
      return null;
    } catch (e) {
      print('[KwMusicSource] getSongUrlWithQuality error: $e');
      return null;
    }
  }

  /// 调用酷我 `nmobi.kuwo.cn/mobi.s` 车机端接口获取播放地址。
  ///
  /// 参数 `source` 使用玉宁熙等 LX 插件常用的车机包名，可有效绕过 VIP 限制。
  Future<_NmobiResult?> _getNmobiUrl(String cleanId, String br) async {
    final user = (100000000 + _random.nextInt(900000000)).toString();
    // Dart Random.nextInt 要求 max <= 2^32，避免 RangeError。
    // loginUid 取 [1_000_000_000, 4_294_967_295] 即可覆盖常见账号范围。
    final loginUid = (1000000000 + _random.nextInt(4294967296 - 1000000000))
        .toString();
    final url =
        'https://nmobi.kuwo.cn/mobi.s?f=web&source=kwplayercar_ar_6.0.0.9_B_jiakong_vh.apk&type=convert_url_with_sign&rid=$cleanId&br=$br&user=$user&loginUid=$loginUid';
    print('[KwMusicSource] _getNmobiUrl try: $url');
    final response = await _apiService.get(
      url,
      headers: {
        'Referer': 'http://www.kuwo.cn/',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Mobile Safari/537.36',
      },
    );
    print(
      '[KwMusicSource] _getNmobiUrl status=${response.statusCode}, data type=${response.data.runtimeType}',
    );

    final data = response.data;
    Map<String, dynamic>? nested;
    if (data is Map) {
      nested = data['data'] is Map
          ? Map<String, dynamic>.from(data['data'] as Map)
          : null;
    } else if (data is String) {
      final trimmed = data.trim();
      if (trimmed.startsWith('{')) {
        try {
          final decoded = jsonDecode(trimmed) as Map<String, dynamic>;
          nested = decoded['data'] is Map
              ? Map<String, dynamic>.from(decoded['data'] as Map)
              : null;
        } catch (_) {}
      }
    }

    if (nested == null) return null;
    final raw = nested['url']?.toString();
    if (raw == null || !raw.trim().startsWith('http')) return null;

    return _NmobiResult(
      url: raw.trim(),
      duration: (nested['duration'] as num?)?.toInt() ?? 0,
      bitrate: (nested['bitrate'] as num?)?.toInt() ?? 0,
      type: (nested['type'] as num?)?.toInt() ?? 0,
      format: nested['format']?.toString() ?? '',
    );
  }

  static final Random _random = Random();
  static const int _nmobiRetryCount = 3;

  /// 校验酷我 nmobi 接口返回的结果是否可直接播放。
  ///
  /// 过滤条件：
  /// - 非 http 地址
  /// - 提示音（URL 含 promo、短时长 <=15s、低码率 <10、type == 1）
  /// - 加密封装（.mflac / .mgg）
  /// - 当 [expectedDurationSeconds] > 0 时，接口返回时长与预期时长偏差过大
  bool _isValidKwAudioResult(
    _NmobiResult result, {
    int expectedDurationSeconds = 0,
  }) {
    final lower = result.url.toLowerCase();
    if (!lower.startsWith('http')) return false;
    if (lower.contains('kw_promo')) return false;
    if (lower.contains('kuwo_promo')) return false;
    if (lower.contains('/promo/')) return false;
    if (lower.contains('permission_prompt')) return false;
    if (lower.contains('trial')) return false;
    // .mflac / .mgg 是酷我加密格式，普通播放器无法解码，视为无效。
    final pathWithoutQuery = lower.split('?').first;
    if (pathWithoutQuery.endsWith('.mflac')) return false;
    if (pathWithoutQuery.endsWith('.mgg')) return false;
    // 提示音特征：极短时长、极低码率、type == 1
    if (result.duration > 0 && result.duration <= 15) return false;
    if (result.bitrate > 0 && result.bitrate < 10) return false;
    if (result.type == 1) return false;
    if (expectedDurationSeconds > 0 && result.duration > 0) {
      final tolerance = max(8, (expectedDurationSeconds * 0.15).round());
      if ((result.duration - expectedDurationSeconds).abs() > tolerance) {
        return false;
      }
    }
    return true;
  }

  @override
  Future<String?> getSongUrl(String songId) async {
    return getSongUrlWithQuality(songId, quality: '128k');
  }

  @override
  Future<String?> getLyric(String songId) async {
    final result = await getLyricResult(songId);
    return result?.lrc;
  }

  @override
  Future<LyricResult?> getLyricResult(String songId) async {
    try {
      final cleanId = songId.replaceAll('kw_', '');

      final lrcxResult = await _getLyricFromNewlyric(cleanId, true);
      if (lrcxResult != null) return lrcxResult;

      final lrcResult = await _getLyricFromNewlyric(cleanId, false);
      if (lrcResult != null) return lrcResult;

      return await _getLyricFromSongInfo(cleanId);
    } catch (e) {
      return null;
    }
  }

  Future<LyricResult?> _getLyricFromNewlyric(
    String musicId,
    bool isGetLyricx,
  ) async {
    try {
      final params = _buildParams(musicId, isGetLyricx);
      final url = 'http://newlyric.kuwo.cn/newlyric.lrc?$params';
      final response = await _apiService.getBytes(url);
      if (response == null || response.isEmpty) return null;

      final decoded = _decodeLyric(response, isGetLyricx);
      if (decoded == null || decoded.isEmpty) return null;

      return _parseKwLyric(decoded);
    } catch (e) {
      return null;
    }
  }

  String _buildParams(String id, bool isGetLyricx) {
    var params =
        'user=12345,web,web,web&requester=localhost&req=1&rid=MUSIC_$id';
    if (isGetLyricx) params += '&lrcx=1';

    final bufStr = utf8.encode(params);
    final key = utf8.encode('yeelion');
    final output = Uint8List(bufStr.length);

    int i = 0;
    while (i < bufStr.length) {
      int j = 0;
      while (j < key.length && i < bufStr.length) {
        output[i] = key[j] ^ bufStr[i];
        i++;
        j++;
      }
    }

    return base64Encode(output);
  }

  String? _decodeLyric(Uint8List raw, bool isGetLyricx) {
    try {
      // 检查头部 tp=content
      if (raw.length < 10) return null;
      final headerCheck = utf8.decode(raw.sublist(0, 10), allowMalformed: true);
      if (headerCheck != 'tp=content') {
        // 尝试查找 tp=content 在数据中的位置
        final rawStr = utf8.decode(raw, allowMalformed: true);
        if (!rawStr.contains('tp=content')) return null;
      }

      // 查找 '\r\n\r\n' 位置
      final headerEndIndex = _findDoubleCRLF(raw);
      if (headerEndIndex < 0) return null;

      // 获取压缩数据
      final compressedData = raw.sublist(headerEndIndex + 4);

      // 与 CeruMusic 一致：先尝试 raw inflate（无 zlib 头）
      List<int> decompressed;
      try {
        decompressed = ZLibDecoder(raw: true).convert(compressedData);
      } catch (e) {
        try {
          // 回退：标准 zlib decode
          decompressed = zlib.decode(compressedData);
        } catch (e2) {
          return null;
        }
      }

      // 非 lrcx 情况，直接 GB18030 解码
      if (!isGetLyricx) {
        return _decodeGb18030(decompressed);
      }

      // lrcx 情况的处理：解压后的数据是 base64 字符串
      try {
        // 将解压后的数据作为 base64 字符串解码
        final base64Str = utf8
            .decode(decompressed, allowMalformed: true)
            .trim();
        final lrcBytes = base64Decode(base64Str);

        // XOR 解密，使用 'yeelion' 密钥（与 CeruMusic 完全一致）
        final keyStr = 'yeelion';
        for (int i = 0; i < lrcBytes.length; i++) {
          lrcBytes[i] = lrcBytes[i] ^ keyStr.codeUnitAt(i % keyStr.length);
        }
        final output = Uint8List.fromList(lrcBytes);

        // GB18030 解码
        return _decodeGb18030(output);
      } catch (e) {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  int _findDoubleCRLF(Uint8List data) {
    // 查找 '\r\n\r\n' 的位置
    const crlf = [0x0d, 0x0a, 0x0d, 0x0a];
    for (int i = 0; i < data.length - 3; i++) {
      if (data[i] == crlf[0] &&
          data[i + 1] == crlf[1] &&
          data[i + 2] == crlf[2] &&
          data[i + 3] == crlf[3]) {
        return i;
      }
    }
    return -1;
  }

  String? _decodeGb18030(List<int> bytes) {
    try {
      return gbk_bytes.decode(bytes);
    } catch (e) {
      try {
        return utf8.decode(bytes, allowMalformed: true);
      } catch (e2) {
        try {
          return String.fromCharCodes(bytes);
        } catch (e3) {
          return null;
        }
      }
    }
  }

  LyricResult? _parseKwLyric(String lrcText) {
    try {
      final lines = lrcText.split(RegExp(r'\r\n|\r|\n'));
      final tags = <String>[];
      final lrcArr = <Map<String, String>>[];

      final timeExp = RegExp(r'^\[([\d:.]*)\]{1}');
      final tagLineExp = RegExp(
        r'\[(ver|ti|ar|al|offset|by|kuwo):\s*(\S+(?:\s+\S+)*)\s*\]',
      );

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        final timeMatch = timeExp.firstMatch(trimmed);
        if (timeMatch != null) {
          final text = trimmed.replaceFirst(timeExp, '').trim();
          var time = timeMatch.group(1)!;
          if (RegExp(r'\.\d\d$').hasMatch(time)) time += '0';
          lrcArr.add({'time': time, 'text': text});
        } else if (tagLineExp.hasMatch(trimmed)) {
          tags.add(trimmed);
        }
      }

      final sorted = _sortLrcArr(lrcArr);

      final lyric = _transformLrc(tags, sorted['lrc']!);
      final tlyric = sorted['lrcT']!.isNotEmpty
          ? _transformLrc(tags, sorted['lrcT']!)
          : '';

      final wordTimeAllExp = RegExp(r'<(-?\d+),(-?\d+)(?:,-?\d+)?>');

      String crlyric = '';
      try {
        crlyric = _parseLrcTools(lyric);
      } catch (e) {
        crlyric = '';
      }

      final cleanLyric = lyric.replaceAll(wordTimeAllExp, '');
      final cleanTlyric = tlyric.replaceAll(wordTimeAllExp, '');

      final existTimeExp = RegExp(r'\[\d{1,2}:.*\d{1,4}\]');
      if (!existTimeExp.hasMatch(cleanLyric)) return null;

      return LyricResult(
        lrc: cleanLyric,
        tlyric: cleanTlyric,
        rlyric: '',
        crlyric: crlyric,
      );
    } catch (e) {
      return null;
    }
  }

  Map<String, List<Map<String, String>>> _sortLrcArr(
    List<Map<String, String>> arr,
  ) {
    final lrcSet = <String>{};
    final lrc = <Map<String, String>>[];
    final lrcT = <Map<String, String>>[];
    final lyricxTagExp = RegExp(r'^<-?\d+,-?\d+>');

    bool isLyricx = false;

    for (final item in arr) {
      if (lrcSet.contains(item['time'])) {
        if (lrc.length < 2) continue;
        final tItem = Map<String, String>.from(lrc.removeLast());
        tItem['time'] = lrc.isNotEmpty ? lrc.last['time']! : tItem['time']!;
        lrcT.add(tItem);
        lrc.add(item);
      } else {
        lrc.add(item);
        lrcSet.add(item['time']!);
      }
      if (!isLyricx && lyricxTagExp.hasMatch(item['text'] ?? '')) {
        isLyricx = true;
      }
    }

    if (!isLyricx &&
        lrcT.length > lrc.length * 0.3 &&
        lrc.length - lrcT.length > 6) {
      throw Exception('not lyricx, too many translations');
    }

    return {'lrc': lrc, 'lrcT': lrcT};
  }

  String _transformLrc(List<String> tags, List<Map<String, String>> lrclist) {
    final tagStr = tags.join('\n');
    final lrcStr = lrclist.map((l) => '[${l['time']}]${l['text']}').join('\n');
    if (tagStr.isNotEmpty) return '$tagStr\n$lrcStr';
    return lrcStr;
  }

  String _parseLrcTools(String lrc) {
    final wordLineExp = RegExp(
      r'^(\[\d{1,2}:.*\d{1,4}\])\s*(\S+(?:\s+\S+)*)?\s*',
    );
    final tagLineExp = RegExp(
      r'\[(ver|ti|ar|al|offset|by|kuwo):\s*(\S+(?:\s+\S+)*)\s*\]',
    );
    final wordTimeAllExp = RegExp(r'<(-?\d+),(-?\d+)(?:,-?\d+)?>');

    int offset = 1;
    int offset2 = 1;
    final parsedLines = <String>[];
    final parsedTags = <String>[];

    final lines = lrc.split(RegExp(r'\r\n|\r|\n'));

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final tagMatch = tagLineExp.firstMatch(trimmed);
      if (tagMatch != null) {
        if (tagMatch.group(1) == 'kuwo') {
          var content = tagMatch.group(2)!;
          if (content.contains('][')) {
            content = content.substring(0, content.indexOf(']['));
          }
          final valueOf = int.tryParse(content, radix: 8) ?? 0;
          offset = valueOf ~/ 10;
          offset2 = valueOf % 10;
          if (offset == 0 || offset2 == 0) return '';
        } else {
          parsedTags.add(trimmed);
        }
        continue;
      }

      final wordMatch = wordLineExp.firstMatch(trimmed);
      if (wordMatch == null) continue;

      final time = wordMatch.group(1)!;
      var words = wordMatch.group(2) ?? '';
      final wordTimes = wordTimeAllExp.allMatches(words).toList();
      if (wordTimes.isEmpty) continue;

      final timeMatch = RegExp(r'\[(\d+):(\d+)\.(\d+)\]').firstMatch(time);
      if (timeMatch == null) continue;

      final minutes = int.parse(timeMatch.group(1)!);
      final seconds = int.parse(timeMatch.group(2)!);
      final milliseconds = int.parse(timeMatch.group(3)!);
      final lineStartTime = minutes * 60000 + seconds * 1000 + milliseconds;

      Map<String, dynamic>? prevWordInfo;

      for (final timeStr in wordTimes) {
        final str1 = int.parse(timeStr.group(1)!);
        final str2 = int.parse(timeStr.group(2)!);
        final startTime = ((str1 + str2).abs() / (offset * 2)).round();
        final duration = ((str1 - str2).abs() / (offset2 * 2)).round();
        final absoluteStartTime = lineStartTime + startTime;
        final endTime = absoluteStartTime + duration;

        if (prevWordInfo != null &&
            absoluteStartTime < prevWordInfo['endTime']) {
          prevWordInfo['endTime'] = absoluteStartTime;
          if (prevWordInfo['absoluteStartTime'] > prevWordInfo['endTime']) {
            prevWordInfo['absoluteStartTime'] = prevWordInfo['endTime'];
          }
          final prevAbsStart = prevWordInfo['absoluteStartTime'];
          final prevDuration = prevWordInfo['endTime'] - prevAbsStart;
          final prevNewTimeStr = '($prevAbsStart,$prevDuration,0)';
          words = words.replaceFirst(
            prevWordInfo['timeStr'] as String,
            prevNewTimeStr,
          );
        }

        final newTimeStr = '($absoluteStartTime,$duration,0)';
        words = words.replaceFirst(timeStr.group(0)!, newTimeStr);

        prevWordInfo = {
          'startTime': startTime,
          'absoluteStartTime': absoluteStartTime,
          'endTime': endTime,
          'duration': duration,
          'timeStr': newTimeStr,
        };
      }

      final lastWordEnd = prevWordInfo?['endTime'] ?? lineStartTime + 5000;
      final lineDuration = lastWordEnd - lineStartTime + 500;
      parsedLines.add('[$lineStartTime,$lineDuration]$words');
    }

    var result = parsedLines.join('\n');
    if (parsedTags.isNotEmpty) result = '${parsedTags.join('\n')}\n$result';
    return result;
  }

  Future<LyricResult?> _getLyricFromSongInfo(String musicId) async {
    try {
      final url = '$_songDetailBaseUrl?musicId=$musicId';
      final response = await _apiService.get(url);
      final data = response.data;
      if (data == null) return null;

      final lrclist = data['data']?['lrclist'] as List?;
      if (lrclist == null || lrclist.isEmpty) return null;

      final lrcLines = <String>[];
      for (final item in lrclist) {
        final time = item['time'];
        final lineLyric = item['lineLyric']?.toString() ?? '';
        if (time != null) {
          final totalMs = (double.tryParse(time.toString()) ?? 0) * 1000;
          final totalMsInt = totalMs.round();
          final ms = totalMsInt % 1000;
          final totalSec = totalMsInt ~/ 1000;
          final m = (totalSec ~/ 60).toString().padLeft(2, '0');
          final s = (totalSec % 60).toString().padLeft(2, '0');
          lrcLines.add('[$m:$s.${ms.toString().padLeft(3, '0')}]$lineLyric');
        }
      }

      if (lrcLines.isEmpty) return null;
      return LyricResult(
        lrc: lrcLines.join('\n'),
        tlyric: '',
        rlyric: '',
        crlyric: '',
      );
    } catch (e) {
      return null;
    }
  }

  @override
  Future<String?> getCoverUrl(String songId) async {
    final cleanId = _cleanSongId(songId);
    if (cleanId == null || cleanId.isEmpty) return null;

    try {
      // Request the largest public artwork variant. Kuwo currently maps this
      // request to its largest public source image (rather than the 500px
      // image used by the old implementation), which keeps full-player
      // artwork sharp.
      // This resolver is intentionally only used lazily during playback, not
      // for every item in a search result.
      final url =
          'http://artistpicserver.kuwo.cn/pic.web?corp=kuwo&type=rid_pic'
          '&pictype=$_fullCoverDirectorySize&size=$_fullCoverDirectorySize&rid=$cleanId';
      final body = await _apiService.getPlainText(url);
      final cover = _toHighResolutionCoverUrl(body);
      if (cover != null) return cover;
    } catch (e) {
      // Fall through to the official endpoint if the lightweight resolver is
      // temporarily unavailable.
    }

    try {
      final response = await _apiService.get(
        '$_picBaseUrl?mid=$cleanId&type=music&httpsStatus=1',
        headers: {'Referer': 'https://www.kuwo.cn/'},
      );
      final data = response.data;
      final nested = data is Map ? data['data'] : null;
      final picture = nested is Map ? nested['pic'] : null;
      return _toHighResolutionCoverUrl(picture);
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
      final url =
          'http://search.kuwo.cn/r.s?client=kt&all=${Uri.encodeQueryComponent(query)}&pn=${page - 1}&rn=$limit&uid=794762570&ver=kwplayer_ar_9.2.2.1&vipver=1&show_copyright_off=1&newver=1&ft=music&cluster=0&strategy=2012&encoding=utf8&rformat=json&vermerge=1&mobi=1&issubtitle=1';
      final response = await _apiService.get(
        url,
        headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'},
      );
      dynamic data = response.data;

      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (e) {
          return [];
        }
      }

      if (data == null || data is! Map) {
        return [];
      }

      if (data['SHOW'] == '0') {
        return [];
      }

      final absList = data['abslist'] as List? ?? [];

      final songs = <Song>[];
      for (final item in absList) {
        if (item is! Map) {
          songs.add(
            Song(
              id: '',
              title: '',
              artist: '',
              album: '',
              duration: 0,
              coverUrl: '',
              source: 'kw',
            ),
          );
          continue;
        }
        final songId =
            item['MUSICRID']?.toString().replaceAll('MUSIC_', '') ?? '';
        final durationStr = item['DURATION']?.toString() ?? '0';
        final usableCover =
            _normalizeCoverUrl(item['web_albumpic_short']) ??
            _normalizeCoverUrl(item['ALBUMPIC']) ??
            _normalizeCoverUrl(item['albumpic']) ??
            _normalizeCoverUrl(item['MUSICPIC']) ??
            _normalizeCoverUrl(item['musicPic']) ??
            _normalizeCoverUrl(item['web_artistpic_short'], artist: true);

        songs.add(
          Song(
            id: 'kw_$songId',
            title: _decodeName(item['SONGNAME']?.toString() ?? ''),
            artist: _decodeName(item['ARTIST']?.toString() ?? ''),
            album: _decodeName(item['ALBUM']?.toString() ?? ''),
            duration: int.tryParse(durationStr) ?? 0,
            // Resolve covers lazily in the image layer. Resolving one cover
            // through artistpicserver for every result serialized the search
            // page behind dozens of extra requests.
            coverUrl: usableCover,
            source: 'kw',
          ),
        );
      }
      return songs;
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<PlaylistTagGroup>> getPlaylistTags() async {
    try {
      const url =
          'http://wapi.kuwo.cn/api/pc/classify/playlist/getTagList'
          '?cmd=rcm_keyword_playlist&user=0&prod=kwplayer_pc_9.0.5.0'
          '&vipver=9.0.5.0&source=kwplayer_pc_9.0.5.0'
          '&loginUin=0&loginSid=0&appUid=76039576';
      final response = await _apiService.get(url);
      dynamic body = response.data;
      if (body is String) body = jsonDecode(body);
      if (body == null || body['code'] != 200) return [];

      final data = body['data'] as List? ?? [];
      return data.map((group) {
        final items = (group['data'] as List? ?? []).map((item) {
          final tagId = '${item['id']}-${item['digest']}';
          return PlaylistTag(
            id: tagId,
            name: item['name']?.toString() ?? '',
            source: 'kw',
          );
        }).toList();
        return PlaylistTagGroup(
          name: group['name']?.toString() ?? '',
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
      const url =
          'http://wapi.kuwo.cn/api/pc/classify/playlist/getRcmTagList'
          '?loginUin=0&loginSid=0&appUid=76039576';
      final response = await _apiService.get(url);
      dynamic body = response.data;
      if (body is String) body = jsonDecode(body);
      if (body == null || body['code'] != 200) return [];

      final data = body['data'] as List? ?? [];
      if (data.isEmpty) return [];
      final items = data[0]['data'] as List? ?? [];
      return items.map((item) {
        return PlaylistTag(
          id: '${item['id']}-${item['digest']}',
          name: item['name']?.toString() ?? '',
          source: 'kw',
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  String _getSongListUrl(String sortId, String tagId, int page, int limit) {
    final actualSortId = sortId.isEmpty ? 'hot' : sortId;

    if (tagId.isEmpty) {
      return 'http://wapi.kuwo.cn/api/pc/classify/playlist/getRcmPlayList?loginUid=0&loginSid=0&appUid=76039576&&pn=${page - 1}&rn=$limit&order=$actualSortId';
    } else {
      final tagParts = tagId.split('-');
      final id = tagParts[0];
      return 'http://wapi.kuwo.cn/api/pc/classify/playlist/getTagPlayList?loginUid=0&loginSid=0&appUid=76039576&pn=${page - 1}&id=$id&rn=$limit';
    }
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

  int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  @override
  Future<List<Playlist>> getCategoryPlaylists({
    required String sortId,
    required String tagId,
    required int page,
    required int limit,
  }) async {
    try {
      final url = _getSongListUrl(sortId, tagId, page, limit);
      final response = await _apiService.get(url);
      dynamic data = response.data;
      if (data is String) data = jsonDecode(data);

      if (data == null || data['code'] != 200) return [];

      final infoList = data['data']?['data'] as List? ?? [];
      return infoList.map((item) {
        return Playlist(
          id: 'kw_digest-${item['digest']}__${item['id']}',
          title: _decodeName(item['name']?.toString() ?? ''),
          description: _decodeName(item['desc']?.toString() ?? ''),
          coverUrl: item['img']?.toString(),
          songCount: _parseInt(item['total']),
          playCount: _formatPlayCount(item['listencnt']),
          author: item['uname']?.toString(),
          source: 'kw',
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<Leaderboard>> getLeaderboards() async {
    try {
      // CeruMusic uses qukudata.kuwo.cn for leaderboard list
      final url =
          'http://qukudata.kuwo.cn/q.k?op=query&cont=tree&node=2&pn=0&rn=1000&fmt=json&level=3';
      final response = await _apiService.get(url);
      final raw = response.data;
      final data = raw is String ? jsonDecode(raw) : raw;
      if (data == null) return _fallbackLeaderboards();

      final rawList = data['child'] as List? ?? [];
      if (rawList.isEmpty) return _fallbackLeaderboards();

      rawList.sort((a, b) {
        final aListen = _parseInt(a['listen']);
        final bListen = _parseInt(b['listen']);
        return bListen.compareTo(aListen);
      });

      final result = rawList.map((item) {
        return Leaderboard(
          id: 'kw_${item['sourceid']?.toString() ?? ''}',
          name: _decodeName(item['name']?.toString() ?? ''),
          coverUrl: item['pic']?.toString() ?? '',
          playCount: _formatPlayCount(item['listen']),
          updateFrequency: item['info']?.toString(),
          source: 'kw',
        );
      }).toList();
      return result.isNotEmpty ? result : _fallbackLeaderboards();
    } catch (e) {
      return _fallbackLeaderboards();
    }
  }

  List<Leaderboard> _fallbackLeaderboards() {
    return const [
      Leaderboard(id: 'kw_93', name: '飙升榜', source: 'kw'),
      Leaderboard(id: 'kw_16', name: '热歌榜', source: 'kw'),
      Leaderboard(id: 'kw_17', name: '新歌榜', source: 'kw'),
      Leaderboard(id: 'kw_158', name: '流行趋势榜', source: 'kw'),
      Leaderboard(id: 'kw_145', name: '抖音歌曲榜', source: 'kw'),
      Leaderboard(id: 'kw_187', name: '快手歌曲榜', source: 'kw'),
      Leaderboard(id: 'kw_141', name: '网络神曲榜', source: 'kw'),
      Leaderboard(id: 'kw_184', name: '综艺热歌榜', source: 'kw'),
      Leaderboard(id: 'kw_242', name: '华语榜', source: 'kw'),
      Leaderboard(id: 'kw_243', name: '欧美榜', source: 'kw'),
      Leaderboard(id: 'kw_244', name: '日韩榜', source: 'kw'),
    ];
  }

  @override
  Future<Playlist?> getLeaderboardDetail(String boardId, {int page = 1}) async {
    try {
      final cleanId = boardId.replaceAll('kw_', '');
      final wbdResult = await _getLeaderboardDetailFromWbd(cleanId, page);
      if (wbdResult != null && wbdResult.songs.isNotEmpty) return wbdResult;

      final url =
          'http://kbangserver.kuwo.cn/ksong.s?from=pc&fmt=json&pn=${page - 1}&rn=100&type=bang&data=content&id=$cleanId&show_copyright_off=0&pcmp4=1&isbang=1';
      final response = await _apiService.get(url);
      final raw = response.data;
      final data = raw is String ? jsonDecode(raw) : raw;
      if (data == null) return _getPlaylistDetailDigest8(cleanId);

      final list =
          data['musiclist'] as List? ??
          data['bang']?['musiclist'] as List? ??
          [];
      final songs = list.map((item) {
        final rid = item['id']?.toString() ?? item['mid']?.toString() ?? '';
        return Song(
          id: 'kw_$rid',
          title: _decodeName(item['name']?.toString() ?? ''),
          artist: _decodeName(
            item['artist']?.toString() ?? item['singer']?.toString() ?? '',
          ),
          album: _decodeName(item['album']?.toString() ?? ''),
          duration: int.tryParse(item['duration']?.toString() ?? '0') ?? 0,
          coverUrl:
              item['pic']?.toString() ?? item['albumpic']?.toString() ?? '',
          source: 'kw',
        );
      }).toList();
      if (songs.isEmpty) return _getPlaylistDetailDigest8(cleanId);
      await _enrichKuwoCovers(songs);

      return Playlist(
        id: boardId,
        title: _decodeName(
          data['name']?.toString() ??
              data['bang']?['title']?.toString() ??
              '排行榜',
        ),
        description: '',
        songCount: songs.length,
        songs: songs,
        source: 'kw',
      );
    } catch (e) {
      return null;
    }
  }

  Future<Playlist?> _getLeaderboardDetailFromWbd(
    String cleanId,
    int page,
  ) async {
    try {
      final requestBody = {
        'uid': '',
        'devId': '',
        'sFrom': 'kuwo_sdk',
        'user_type': 'AP',
        'carSource': 'kwplayercar_ar_6.0.1.0_apk_keluze.apk',
        'id': int.tryParse(cleanId) ?? cleanId,
        'pn': page - 1,
        'rn': 100,
      };
      final url =
          'https://wbd.kuwo.cn/api/bd/bang/bang_info?${_buildWbdParam(requestBody)}';
      final response = await _apiService.get(url);
      final decoded = _decodeWbdData(response.data?.toString() ?? '');
      if (decoded == null || decoded['code'] != 200) return null;

      final data = decoded['data'] as Map?;
      final musicList = data?['musiclist'] as List? ?? [];
      final songs = musicList.whereType<Map>().map(_parseKuwoRankSong).toList();
      return Playlist(
        id: 'kw_$cleanId',
        title: _decodeName(
          data?['name']?.toString() ?? data?['title']?.toString() ?? '排行榜',
        ),
        description: data?['info']?.toString() ?? '',
        songCount: _parseInt(data?['total'] ?? songs.length),
        songs: songs,
        coverUrl: data?['pic']?.toString() ?? '',
        source: 'kw',
      );
    } catch (_) {
      return null;
    }
  }

  Song _parseKuwoRankSong(Map item) {
    final rid = item['id']?.toString() ?? item['rid']?.toString() ?? '';
    return Song(
      id: 'kw_$rid',
      title: _decodeName(item['name']?.toString() ?? ''),
      artist: _decodeName(item['artist']?.toString() ?? ''),
      album: _decodeName(item['album']?.toString() ?? ''),
      duration: _parseInt(item['duration']),
      coverUrl: item['pic']?.toString() ?? '',
      source: 'kw',
    );
  }

  static final _wbdKey = encrypt.Key(
    Uint8List.fromList([
      112,
      87,
      39,
      61,
      199,
      250,
      41,
      191,
      57,
      68,
      45,
      114,
      221,
      94,
      140,
      228,
    ]),
  );

  String _buildWbdParam(Map<String, dynamic> jsonData) {
    final encrypter = encrypt.Encrypter(
      encrypt.AES(_wbdKey, mode: encrypt.AESMode.ecb, padding: 'PKCS7'),
    );
    final encodedData = encrypter.encrypt(jsonEncode(jsonData)).base64;
    final time = DateTime.now().millisecondsSinceEpoch;
    final sign = md5
        .convert(utf8.encode('y67sprxhhpws$encodedData$time'))
        .toString()
        .toUpperCase();
    return 'data=${Uri.encodeQueryComponent(encodedData)}&time=$time&appId=y67sprxhhpws&sign=$sign';
  }

  Map<String, dynamic>? _decodeWbdData(String encoded) {
    try {
      final encrypter = encrypt.Encrypter(
        encrypt.AES(_wbdKey, mode: encrypt.AESMode.ecb, padding: 'PKCS7'),
      );
      final normalized = Uri.decodeComponent(encoded);
      final jsonText = encrypter.decrypt64(normalized);
      final decoded = jsonDecode(jsonText);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String _decodeName(String name) {
    return name
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }

  @override
  Future<List<String>> getHotSearchTags() async {
    try {
      final url =
          'https://hotword.kuwo.cn/hotword.s?prod=kwplayer_ar_9.3.0.1&corp=kuwo&newver=2&vipver=9.3.0.1&source=kwplayer_ar_9.3.0.1_40.apk&p2p=1&notrace=0&uid=0&plat=kwplayer_ar&rformat=json&encoding=utf8&tabid=1';
      final response = await _apiService.get(
        url,
        headers: {
          'User-Agent': 'Dalvik/2.1.0 (Linux; U; Android 9;)',
          'Referer': 'https://kuwo.cn/',
        },
      );
      final data = _decodeKuwoJson(response.data);
      if (response.statusCode != 200 ||
          data is! Map ||
          data['status']?.toString().toLowerCase() != 'ok') {
        print(
          '[KuwoMusicSource] 热门搜索响应异常: status=${response.statusCode}, type=${response.data.runtimeType}',
        );
        return [];
      }

      final rawList = data['tagvalue'];
      final list = rawList is List ? rawList : const <dynamic>[];
      final tags = list
          .whereType<Map>()
          .map((h) => h['key']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .take(10)
          .toList();
      print('[KuwoMusicSource] 热门搜索获取成功: ${tags.length}');
      return tags;
    } catch (e) {
      print('[KuwoMusicSource] 热门搜索请求失败: $e');
      return [];
    }
  }

  @override
  Future<List<String>> getSearchSuggestions(String query) async {
    if (query.isEmpty) return [];
    try {
      final url =
          'https://tips.kuwo.cn/t.s?corp=kuwo&newver=3&p2p=1&notrace=0&c=mbox&w=${Uri.encodeQueryComponent(query)}&encoding=utf8&rformat=json';
      final response = await _apiService.get(
        url,
        headers: {'Referer': 'http://www.kuwo.cn/'},
      );
      final data = response.data;
      if (data == null) return [];

      final items = data['WORDITEMS'] as List? ?? [];
      return items
          .map((h) => h['RELWORD']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> _enrichKuwoCovers(List<Song> songs) async {
    final noCover = <int>[];
    for (var i = 0; i < songs.length; i++) {
      final url = songs[i].coverUrl;
      if (url == null || url.isEmpty) noCover.add(i);
    }
    if (noCover.isEmpty) return;
    const batchSize = 10;
    for (var start = 0; start < noCover.length; start += batchSize) {
      final batch = noCover.skip(start).take(batchSize);
      await Future.wait(
        batch.map((i) async {
          try {
            final rid = songs[i].id.replaceAll('kw_', '');
            final url = await _apiService.getPlainText(
              'http://artistpicserver.kuwo.cn/pic.web'
              '?corp=kuwo&type=rid_pic&pictype=500&size=500&rid=$rid',
            );
            if (url != null && url.isNotEmpty && url.startsWith('http')) {
              songs[i] = songs[i].copyWith(coverUrl: url);
            }
          } catch (_) {}
        }),
      );
    }
  }
}
