class Song {
  final String id;
  final String title;
  final String artist;
  final String album;
  final int duration;
  final String? coverUrl;
  final String? sourceUrl;
  final String? lyricUrl;
  final String? source;
  final String? filePath;
  final bool hasCover;
  final String? coverKey;
  final String? lrc;
  final int? bitrate;
  final int? sampleRate;
  final int? channels;
  final int? year;
  final int? mediaStoreId;
  final String? hash;
  final Map<String, dynamic>? lx;
  final Map<String, String>? sourceHeaders;
  final String? sourceQuality;

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    this.coverUrl,
    this.sourceUrl,
    this.lyricUrl,
    this.source,
    this.filePath,
    this.hasCover = false,
    this.coverKey,
    this.lrc,
    this.bitrate,
    this.sampleRate,
    this.channels,
    this.year,
    this.mediaStoreId,
    this.hash,
    this.lx,
    this.sourceHeaders,
    this.sourceQuality,
  });

  bool get isLocal => source == 'local';

  String get displayDuration {
    if (duration <= 0) return '';
    final m = duration ~/ 60;
    final s = duration % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Song copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    int? duration,
    String? coverUrl,
    String? sourceUrl,
    String? lyricUrl,
    String? source,
    String? filePath,
    bool? hasCover,
    String? coverKey,
    String? lrc,
    int? bitrate,
    int? sampleRate,
    int? channels,
    int? year,
    int? mediaStoreId,
    String? hash,
    Map<String, dynamic>? lx,
    Map<String, String>? sourceHeaders,
    String? sourceQuality,
    bool clearSourceUrl = false,
    bool clearSourceHeaders = false,
    bool clearSourceQuality = false,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      coverUrl: coverUrl ?? this.coverUrl,
      sourceUrl: clearSourceUrl ? null : sourceUrl ?? this.sourceUrl,
      lyricUrl: lyricUrl ?? this.lyricUrl,
      source: source ?? this.source,
      filePath: filePath ?? this.filePath,
      hasCover: hasCover ?? this.hasCover,
      coverKey: coverKey ?? this.coverKey,
      lrc: lrc ?? this.lrc,
      bitrate: bitrate ?? this.bitrate,
      sampleRate: sampleRate ?? this.sampleRate,
      channels: channels ?? this.channels,
      year: year ?? this.year,
      mediaStoreId: mediaStoreId ?? this.mediaStoreId,
      hash: hash ?? this.hash,
      lx: lx ?? this.lx,
      sourceHeaders: clearSourceHeaders
          ? null
          : sourceHeaders ?? this.sourceHeaders,
      sourceQuality: clearSourceQuality
          ? null
          : sourceQuality ?? this.sourceQuality,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Song && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  /// Returns a JSON-safe LX payload while preserving nested lists and maps.
  static dynamic _sanitizeLxValue(dynamic value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is List) {
      return value.map(_sanitizeLxValue).toList();
    }
    if (value is Map) {
      final result = <String, dynamic>{};
      value.forEach((key, nested) {
        if (key is String) {
          result[key] = _sanitizeLxValue(nested);
        }
      });
      return result;
    }
    return null;
  }

  static Map<String, dynamic>? _sanitizeLx(Map<String, dynamic>? lx) {
    if (lx == null) return null;
    final value = _sanitizeLxValue(lx);
    return value is Map<String, dynamic> ? value : null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'duration': duration,
      'coverUrl': coverUrl,
      'sourceUrl': sourceUrl,
      'lyricUrl': lyricUrl,
      'source': source,
      'filePath': filePath,
      'hasCover': hasCover,
      'coverKey': coverKey,
      'lrc': lrc,
      'bitrate': bitrate,
      'sampleRate': sampleRate,
      'channels': channels,
      'year': year,
      'mediaStoreId': mediaStoreId,
      'hash': hash,
      'lx': _sanitizeLx(lx),
      'sourceHeaders': sourceHeaders,
      'sourceQuality': sourceQuality,
    };
  }

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      artist: json['artist'] ?? '',
      album: json['album'] ?? '',
      duration: json['duration'] ?? 0,
      coverUrl: json['coverUrl'],
      sourceUrl: json['sourceUrl'],
      lyricUrl: json['lyricUrl'],
      source: json['source'],
      filePath: json['filePath'],
      hasCover: json['hasCover'] ?? false,
      coverKey: json['coverKey'],
      lrc: json['lrc'],
      bitrate: json['bitrate'],
      sampleRate: json['sampleRate'],
      channels: json['channels'],
      year: json['year'],
      mediaStoreId: json['mediaStoreId'],
      hash: json['hash'],
      lx: json['lx'] is Map ? Map<String, dynamic>.from(json['lx']) : null,
      sourceHeaders: json['sourceHeaders'] is Map
          ? Map<String, String>.from(
              (json['sourceHeaders'] as Map).map(
                (key, value) => MapEntry(key.toString(), value.toString()),
              ),
            )
          : null,
      sourceQuality: json['sourceQuality']?.toString(),
    );
  }
}
