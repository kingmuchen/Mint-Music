import '../../../player/domain/models/song.dart';

class Playlist {
  final String id;
  final String name;
  final String description;
  final String coverImgUrl;
  final String source;
  final DateTime createTime;
  final DateTime updateTime;
  final List<Song> songs;
  final Map<String, dynamic> meta;

  const Playlist({
    required this.id,
    required this.name,
    this.description = '',
    this.coverImgUrl = '',
    this.source = 'local',
    required this.createTime,
    required this.updateTime,
    this.songs = const [],
    this.meta = const {},
  });

  int get songCount => songs.length;

  Playlist copyWith({
    String? id,
    String? name,
    String? description,
    String? coverImgUrl,
    String? source,
    DateTime? createTime,
    DateTime? updateTime,
    List<Song>? songs,
    Map<String, dynamic>? meta,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      coverImgUrl: coverImgUrl ?? this.coverImgUrl,
      source: source ?? this.source,
      createTime: createTime ?? this.createTime,
      updateTime: updateTime ?? this.updateTime,
      songs: songs ?? this.songs,
      meta: meta ?? this.meta,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'coverImgUrl': coverImgUrl,
      'source': source,
      'createTime': createTime.toIso8601String(),
      'updateTime': updateTime.toIso8601String(),
      'songs': songs.map((s) => s.toJson()).toList(),
      'meta': meta,
    };
  }

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      coverImgUrl: json['coverImgUrl'] ?? '',
      source: json['source'] ?? 'local',
      createTime: DateTime.tryParse(json['createTime'] ?? '') ?? DateTime.now(),
      updateTime: DateTime.tryParse(json['updateTime'] ?? '') ?? DateTime.now(),
      songs: (json['songs'] as List<dynamic>?)
              ?.map((s) => Song.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      meta: json['meta'] as Map<String, dynamic>? ?? {},
    );
  }
}