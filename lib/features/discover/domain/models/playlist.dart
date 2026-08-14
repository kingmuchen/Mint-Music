import '../../../player/domain/models/song.dart';

class Playlist {
  final String id;
  final String title;
  final String description;
  final String? coverUrl;
  final int songCount;
  final List<Song> songs;
  final String? playCount;
  final String? author;
  final String source;

  const Playlist({
    required this.id,
    required this.title,
    required this.description,
    this.coverUrl,
    required this.songCount,
    this.songs = const [],
    this.playCount,
    this.author,
    this.source = 'wy',
  });

  Playlist copyWith({
    int? songCount,
    String? playCount,
  }) {
    return Playlist(
      id: id,
      title: title,
      description: description,
      coverUrl: coverUrl,
      songCount: songCount ?? this.songCount,
      songs: songs,
      playCount: playCount ?? this.playCount,
      author: author,
      source: source,
    );
  }
}