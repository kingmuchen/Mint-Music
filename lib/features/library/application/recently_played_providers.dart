import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/recently_played_repository.dart';
import '../domain/models/recently_played.dart';
import '../../player/domain/models/song.dart';

final recentlyPlayedRepositoryProvider = Provider<RecentlyPlayedRepository>((ref) {
  return RecentlyPlayedRepository();
});

final recentlyPlayedProvider = AsyncNotifierProvider<RecentlyPlayedNotifier, List<RecentlyPlayedItem>>(
  RecentlyPlayedNotifier.new,
);

class RecentlyPlayedNotifier extends AsyncNotifier<List<RecentlyPlayedItem>> {
  @override
  Future<List<RecentlyPlayedItem>> build() async {
    final repo = ref.read(recentlyPlayedRepositoryProvider);
    return repo.loadHistory();
  }

  Future<void> addToHistory(Song song) async {
    final repo = ref.read(recentlyPlayedRepositoryProvider);
    await repo.addToHistory(song);
    ref.invalidateSelf();
  }

  Future<void> clearHistory() async {
    final repo = ref.read(recentlyPlayedRepositoryProvider);
    await repo.clearHistory();
    ref.invalidateSelf();
  }

  Future<void> removeFromHistory(String songId) async {
    final repo = ref.read(recentlyPlayedRepositoryProvider);
    await repo.removeFromHistory(songId);
    ref.invalidateSelf();
  }
}