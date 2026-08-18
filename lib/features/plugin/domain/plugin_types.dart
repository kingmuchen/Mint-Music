class PluginSourceInfo {
  final String name;
  final List<String> qualities;

  const PluginSourceInfo({required this.name, required this.qualities});

  Map<String, dynamic> toJson() => {'name': name, 'qualities': qualities};

  factory PluginSourceInfo.fromJson(Map<String, dynamic> json) {
    return PluginSourceInfo(
      name: json['name'] as String,
      qualities: List<String>.from(json['qualities'] as List),
    );
  }
}

/// 插件测试用：插件宿主声明的一个音源。
///
/// [id] 为规范化后的音源标识（内置五源映射为 wy/kg/kw/tx/mg，
/// 其余音源沿用插件声明名），供搜索与链接解析使用。
class PluginSourceSpec {
  final String id;
  final String name;
  final List<String> qualities;

  const PluginSourceSpec({
    required this.id,
    required this.name,
    required this.qualities,
  });
}

class PluginMetadata {
  final String name;
  final String version;
  final String author;
  final String? description;

  const PluginMetadata({
    required this.name,
    required this.version,
    required this.author,
    this.description,
  });

  factory PluginMetadata.fromJson(Map<String, dynamic> json) {
    return PluginMetadata(
      name: json['name'] as String,
      version: json['version'] as String,
      author: json['author'] as String,
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'version': version,
    'author': author,
    'description': description,
  };
}

class MusicInfoForPlugin {
  final String? songmid;
  final dynamic songId;
  final String? hash;
  final String singer;
  final String name;
  final String albumName;
  final dynamic albumId;
  final dynamic albumMid;
  final dynamic strMediaMid;
  final dynamic copyrightId;
  final String source;
  final String interval;
  final String? img;
  final String? lrc;
  final String? lrcUrl;
  final String? mrcUrl;
  final String? trcUrl;
  final List<dynamic>? types;
  final Map<String, dynamic>? typeMap;
  final Map<String, dynamic>? typeUrl;

  const MusicInfoForPlugin({
    this.songmid,
    this.songId,
    this.hash,
    required this.singer,
    required this.name,
    required this.albumName,
    this.albumId,
    this.albumMid,
    this.strMediaMid,
    this.copyrightId,
    required this.source,
    this.interval = '',
    this.img,
    this.lrc,
    this.lrcUrl,
    this.mrcUrl,
    this.trcUrl,
    this.types,
    this.typeMap,
    this.typeUrl,
  });

  String get id => songmid ?? songId?.toString() ?? hash ?? '';

  Map<String, dynamic> toJson() => {
    'songmid': songmid,
    'songId': songId,
    'songid': songId,
    'hash': hash,
    'singer': singer,
    'name': name,
    'albumName': albumName,
    'albumId': albumId,
    'albumMid': albumMid,
    'strMediaMid': strMediaMid,
    'copyrightId': copyrightId,
    'source': source,
    'interval': interval,
    'img': img,
    'lrc': lrc,
    'lrcUrl': lrcUrl,
    'mrcUrl': mrcUrl,
    'trcUrl': trcUrl,
    'types': types,
    '_types': typeMap,
    'typeUrl': typeUrl ?? <String, dynamic>{},
    'id': id,
  };

  factory MusicInfoForPlugin.fromJson(Map<String, dynamic> json) {
    return MusicInfoForPlugin(
      songmid: json['songmid']?.toString(),
      songId: json['songId'] ?? json['songid'],
      hash: json['hash']?.toString(),
      singer: json['singer'] as String? ?? '',
      name: json['name'] as String? ?? '',
      albumName: json['albumName'] as String? ?? '',
      albumId: json['albumId'],
      albumMid: json['albumMid'],
      strMediaMid: json['strMediaMid'],
      copyrightId: json['copyrightId'],
      source: json['source'] as String? ?? '',
      interval: json['interval'] as String? ?? '',
      img: json['img'] as String?,
      lrc: json['lrc'] as String?,
      lrcUrl: json['lrcUrl'] as String?,
      mrcUrl: json['mrcUrl'] as String?,
      trcUrl: json['trcUrl'] as String?,
      types: json['types'] is List ? List<dynamic>.from(json['types']) : null,
      typeMap: json['_types'] is Map
          ? Map<String, dynamic>.from(json['_types'])
          : null,
      typeUrl: json['typeUrl'] is Map
          ? Map<String, dynamic>.from(json['typeUrl'])
          : null,
    );
  }
}

class SearchResultFromPlugin {
  final List<MusicInfoForPlugin> list;
  final int allPage;
  final int limit;
  final int total;
  final String source;

  const SearchResultFromPlugin({
    required this.list,
    this.allPage = 0,
    this.limit = 30,
    this.total = 0,
    required this.source,
  });

  factory SearchResultFromPlugin.fromJson(Map<String, dynamic> json) {
    return SearchResultFromPlugin(
      list:
          (json['list'] as List?)
              ?.map(
                (e) => MusicInfoForPlugin.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      allPage: json['allPage'] as int? ?? 0,
      limit: json['limit'] as int? ?? 30,
      total: json['total'] as int? ?? 0,
      source: json['source'] as String? ?? '',
    );
  }
}

class RequestResultFromPlugin {
  final dynamic body;
  final int statusCode;
  final Map<String, String> headers;

  const RequestResultFromPlugin({
    required this.body,
    required this.statusCode,
    required this.headers,
  });
}

/// Normalized playback information returned by an LX source.
///
/// LX scripts may return a URL directly or wrap it in several layers of
/// response data. Keeping the optional request headers here is important for
/// sources whose final media URL is protected by a referer or token header.
class PluginMusicUrlResult {
  final String url;
  final String quality;
  final Map<String, String> headers;

  const PluginMusicUrlResult({
    required this.url,
    this.quality = '',
    this.headers = const <String, String>{},
  });
}

enum PluginType { ceruMusic, lx }

class SourceInfo {
  final String id;
  final String name;

  const SourceInfo({required this.id, required this.name});

  static const List<SourceInfo> builtInSources = [
    SourceInfo(id: 'wy', name: '网易云音乐'),
    SourceInfo(id: 'kg', name: '酷狗音乐'),
    SourceInfo(id: 'kw', name: '酷我音乐'),
    SourceInfo(id: 'tx', name: 'QQ音乐'),
    SourceInfo(id: 'mg', name: '咪咕音乐'),
  ];

  static String getNameById(String id) {
    return builtInSources
        .firstWhere(
          (s) => s.id == id,
          orElse: () => const SourceInfo(id: '', name: '未知音源'),
        )
        .name;
  }
}
