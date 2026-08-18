import '../../player/domain/models/song.dart';
import '../../player/domain/models/lyric_line.dart';
import '../../discover/domain/models/playlist.dart';
import '../../discover/domain/models/leaderboard.dart';
import '../domain/music_source_provider.dart';

class BuiltInMusicSource implements MusicSourceProvider {
  @override
  String get name => 'BuiltIn';

  @override
  String get version => '1.0.0';

  final _allSongs = List.generate(50, (i) {
    final artists = ['周杰伦', '林俊杰', '陈奕迅', '邓紫棋', 'Taylor Swift', 'Ed Sheeran'];
    return Song(
      id: 'builtin_$i',
      title: '内置歌曲${i + 1}',
      artist: artists[i % artists.length],
      album: '内置专辑${(i % 5) + 1}',
      duration: 180 + (i * 13) % 200,
    );
  });

  @override
  Future<List<Song>> search(
    String query, {
    int page = 1,
    int limit = 20,
  }) async {
    if (query.isEmpty) return [];
    await Future.delayed(const Duration(milliseconds: 300));
    final results = _allSongs
        .where(
          (s) =>
              s.title.toLowerCase().contains(query.toLowerCase()) ||
              s.artist.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    final start = (page - 1) * limit;
    return results.skip(start).take(limit).toList();
  }

  @override
  Future<Playlist?> getPlaylistDetail(String playlistId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final playlists = await getHotPlaylists();
    return playlists.where((p) => p.id == playlistId).firstOrNull;
  }

  @override
  Future<List<Playlist>> getHotPlaylists() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return [
      Playlist(
        id: 'builtin_1',
        title: '今日热门推荐',
        description: '每日更新的热门歌曲推荐',
        songCount: 25,
        songs: _allSongs.take(25).toList(),
      ),
      Playlist(
        id: 'builtin_2',
        title: '华语经典',
        description: '那些年我们听过的歌',
        songCount: 40,
        songs: _allSongs.skip(25).take(25).toList(),
      ),
    ];
  }

  @override
  Future<List<Song>> getPlaylistSongs(String playlistId) async {
    final playlist = await getPlaylistDetail(playlistId);
    return playlist?.songs ?? [];
  }

  @override
  Future<String?> getSongUrl(String songId) async {
    return null;
  }

  @override
  Future<String?> getLyric(String songId) async {
    return null;
  }

  @override
  Future<LyricResult?> getLyricResult(String songId) async {
    return null;
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
    return [];
  }

  @override
  Future<Playlist?> getLeaderboardDetail(String boardId, {int page = 1}) async {
    return null;
  }

  @override
  Future<List<String>> getHotSearchTags() async {
    return const <String>[];
  }

  @override
  Future<List<Playlist>> searchPlaylists(
    String query, {
    int page = 1,
    int limit = 30,
  }) async {
    if (query.isEmpty) return [];
    final all = await getHotPlaylists();
    final q = query.toLowerCase();
    return all
        .where(
          (p) =>
              p.title.toLowerCase().contains(q) ||
              p.description.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Future<List<String>> getSearchSuggestions(String query) async {
    if (query.isEmpty) return [];
    return _allSongs
        .where(
          (s) =>
              s.title.toLowerCase().contains(query.toLowerCase()) ||
              s.artist.toLowerCase().contains(query.toLowerCase()),
        )
        .take(5)
        .map((s) => '${s.title} - ${s.artist}')
        .toList();
  }
}
