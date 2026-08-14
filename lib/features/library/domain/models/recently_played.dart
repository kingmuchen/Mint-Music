import '../../../player/domain/models/song.dart';

class RecentlyPlayedItem {
  final Song song;
  final DateTime playedAt;
  final int playCount;

  const RecentlyPlayedItem({
    required this.song,
    required this.playedAt,
    this.playCount = 1,
  });

  RecentlyPlayedItem copyWith({
    Song? song,
    DateTime? playedAt,
    int? playCount,
  }) {
    return RecentlyPlayedItem(
      song: song ?? this.song,
      playedAt: playedAt ?? this.playedAt,
      playCount: playCount ?? this.playCount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'song': song.toJson(),
      'playedAt': playedAt.toIso8601String(),
      'playCount': playCount,
    };
  }

  factory RecentlyPlayedItem.fromJson(Map<String, dynamic> json) {
    return RecentlyPlayedItem(
      song: Song.fromJson(json['song'] as Map<String, dynamic>),
      playedAt: DateTime.tryParse(json['playedAt'] ?? '') ?? DateTime.now(),
      playCount: json['playCount'] ?? 1,
    );
  }
}