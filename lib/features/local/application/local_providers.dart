import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../data/local_music_repository.dart';
import '../../player/domain/models/song.dart';

final localMusicRepositoryProvider = Provider<LocalMusicRepository>((ref) {
  return LocalMusicRepository();
});

final onAudioQueryProvider = Provider<OnAudioQuery>((ref) {
  return OnAudioQuery();
});

final localPermissionProvider = StateProvider<AsyncValue<bool>>((ref) {
  return const AsyncValue.data(false);
});

final localSongsProvider = FutureProvider<List<Song>>((ref) async {
  final repo = ref.watch(localMusicRepositoryProvider);
  await repo.init();
  return repo.getLocalSongs();
});

final localSearchQueryProvider = StateProvider<String>((ref) => '');

final filteredLocalSongsProvider = Provider<List<Song>>((ref) {
  final query = ref.watch(localSearchQueryProvider);
  final songsAsync = ref.watch(localMusicNotifierProvider);
  return songsAsync.when(
    data: (songs) {
      if (query.isEmpty) return songs;
      final q = query.toLowerCase();
      return songs.where((s) =>
          s.title.toLowerCase().contains(q) ||
          s.artist.toLowerCase().contains(q) ||
          s.album.toLowerCase().contains(q)).toList();
    },
    loading: () => [],
    error: (_, _) => [],
  );
});

final scannedDirectoriesProvider = Provider<List<String>>((ref) {
  final repo = ref.watch(localMusicRepositoryProvider);
  return repo.getScannedDirectories();
});

final scanProgressProvider = StateProvider<ScanProgress>((ref) {
  return const ScanProgress();
});

final batchMatchProgressProvider = StateProvider<BatchMatchProgress>((ref) {
  return const BatchMatchProgress();
});

class LocalMusicNotifier extends StateNotifier<AsyncValue<List<Song>>> {
  final Ref _ref;

  LocalMusicNotifier(this._ref) : super(const AsyncValue.loading()) {
    _init();
  }

  Future<void> _init() async {
    try {
      final repo = _ref.read(localMusicRepositoryProvider);
      await repo.init();

      final hasPermission = await repo.checkPermission();
      if (hasPermission) {
        final songs = repo.getLocalSongs();
        if (songs.isEmpty) {
          await repo.scanAll(
            onProgress: (progress) {
              _ref.read(scanProgressProvider.notifier).state = progress;
            },
          );
        }
      }

      state = AsyncValue.data(repo.getLocalSongs());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<bool> requestPermissionAndScan() async {
    try {
      final repo = _ref.read(localMusicRepositoryProvider);
      final alreadyGranted = await repo.checkPermission();
      if (!alreadyGranted) {
        final granted = await repo.requestPermission();
        _ref.read(localPermissionProvider.notifier).state = AsyncValue.data(granted);
        if (!granted) return false;
      }
      await scanAll();
      return true;
    } catch (e, st) {
      _ref.read(localPermissionProvider.notifier).state = AsyncValue.error(e, st);
      return false;
    }
  }

  Future<void> addDirectory(String dirPath) async {
    try {
      final repo = _ref.read(localMusicRepositoryProvider);
      await repo.addDirectory(dirPath);
      state = AsyncValue.data(repo.getLocalSongs());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> removeDirectory(String dirPath) async {
    try {
      final repo = _ref.read(localMusicRepositoryProvider);
      await repo.removeDirectory(dirPath);
      state = AsyncValue.data(repo.getLocalSongs());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> setDirectories(List<String> dirs) async {
    try {
      final repo = _ref.read(localMusicRepositoryProvider);
      await repo.setDirectories(dirs);
      state = AsyncValue.data(repo.getLocalSongs());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> scanAll() async {
    try {
      final repo = _ref.read(localMusicRepositoryProvider);
      await repo.scanAll(
        onProgress: (progress) {
          _ref.read(scanProgressProvider.notifier).state = progress;
        },
      );
      state = AsyncValue.data(repo.getLocalSongs());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> clearIndex() async {
    try {
      final repo = _ref.read(localMusicRepositoryProvider);
      await repo.clearIndex();
      state = AsyncValue.data(repo.getLocalSongs());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> upsertSong(Song song, {bool forceOverwrite = false}) async {
    try {
      final repo = _ref.read(localMusicRepositoryProvider);
      await repo.upsertSong(song, forceOverwrite: forceOverwrite);
      state = AsyncValue.data(repo.getLocalSongs());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 删除本地歌曲。返回是否成功移除。
  Future<bool> deleteSong(Song song) async {
    try {
      final repo = _ref.read(localMusicRepositoryProvider);
      final ok = await repo.deleteSong(song.id);
      if (ok) {
        state = AsyncValue.data(repo.getLocalSongs());
      }
      return ok;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  void refresh() {
    _init();
  }
}

final localMusicNotifierProvider =
    StateNotifierProvider<LocalMusicNotifier, AsyncValue<List<Song>>>((ref) {
  return LocalMusicNotifier(ref);
});
