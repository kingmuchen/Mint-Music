import '../../../player/domain/models/song.dart';

class RecognizeResult {
  final String songmid;
  final String name;
  final String singer;
  final String albumName;
  final String albumId;
  final String source;
  final String interval;
  final String img;
  final double startTime;
  final String? lrc;
  final List<Map<String, String>> types;

  const RecognizeResult({
    required this.songmid,
    required this.name,
    required this.singer,
    required this.albumName,
    required this.albumId,
    required this.source,
    required this.interval,
    required this.img,
    this.lrc,
    this.startTime = 0,
    this.types = const [],
  });

  Song toSong() => Song(
    id: songmid,
    title: name,
    artist: singer,
    album: albumName,
    duration: _parseDuration(interval),
    coverUrl: img,
    lrc: lrc,
    source: source,
  );

  static int _parseDuration(String interval) {
    final parts = interval.split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]) ?? 0;
      final s = int.tryParse(parts[1]) ?? 0;
      return m * 60 + s;
    }
    return 0;
  }

  factory RecognizeResult.fromJson(Map<String, dynamic> json) {
    return RecognizeResult(
      songmid: json['songmid']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      singer: json['singer']?.toString() ?? '',
      albumName: json['albumName']?.toString() ?? '',
      albumId: json['albumId']?.toString() ?? '',
      source: json['source']?.toString() ?? 'wy',
      interval: json['interval']?.toString() ?? '--/--',
      img: json['img']?.toString() ?? '',
      startTime: (json['startTime'] as num?)?.toDouble() ?? 0,
      lrc: json['lrc']?.toString(),
      types: json['types'] is List
          ? (json['types'] as List).map((e) => Map<String, String>.from(e as Map)).toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() => {
        'songmid': songmid,
        'name': name,
        'singer': singer,
        'albumName': albumName,
        'albumId': albumId,
        'source': source,
        'interval': interval,
        'img': img,
        'startTime': startTime,
        'lrc': lrc,
        'types': types,
      };
}

class RecognizeAudioQuality {
  final String type;
  final String size;

  const RecognizeAudioQuality({required this.type, required this.size});

  factory RecognizeAudioQuality.fromJson(Map<String, dynamic> json) {
    return RecognizeAudioQuality(
      type: json['type']?.toString() ?? '',
      size: json['size']?.toString() ?? '',
    );
  }
}
