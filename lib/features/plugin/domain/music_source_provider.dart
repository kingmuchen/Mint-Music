import '../../player/domain/models/song.dart';
import '../../player/domain/models/lyric_line.dart';
import '../../discover/domain/models/playlist.dart';
import '../../discover/domain/models/leaderboard.dart';

abstract class MusicSourceProvider {
  String get name;
  String get version;

  Future<List<Song>> search(String query, {int page = 1, int limit = 20});
  Future<Playlist?> getPlaylistDetail(String playlistId);
  Future<List<Playlist>> getHotPlaylists();
  Future<List<Song>> getPlaylistSongs(String playlistId);
  Future<String?> getSongUrl(String songId);
  Future<String?> getLyric(String songId);
  Future<LyricResult?> getLyricResult(String songId);
  Future<String?> getCoverUrl(String songId);

  Future<List<PlaylistTagGroup>> getPlaylistTags();
  Future<List<PlaylistTag>> getHotPlaylistTags();
  Future<List<Playlist>> getCategoryPlaylists({
    required String sortId,
    required String tagId,
    required int page,
    required int limit,
  });
  Future<List<Leaderboard>> getLeaderboards();
  Future<Playlist?> getLeaderboardDetail(String boardId, {int page = 1});

  Future<List<String>> getHotSearchTags();
  Future<List<String>> getSearchSuggestions(String query);
}
