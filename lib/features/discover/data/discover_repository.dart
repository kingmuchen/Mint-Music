import '../domain/models/playlist.dart';
import '../domain/models/leaderboard.dart';
import '../../player/domain/models/song.dart';
import '../../plugin/application/music_source_manager.dart';

class DiscoverRepository {
  final MusicSourceManager _manager;

  DiscoverRepository(this._manager);

  Future<List<Playlist>> getHotPlaylists({String sourceId = 'wy'}) async {
    return _manager.getHotPlaylists(sourceId: sourceId);
  }

  Future<List<PlaylistTagGroup>> getPlaylistTags({String sourceId = 'wy'}) async {
    return _manager.getPlaylistTags(sourceId: sourceId);
  }

  Future<List<PlaylistTag>> getHotPlaylistTags({String sourceId = 'wy'}) async {
    return _manager.getHotPlaylistTags(sourceId: sourceId);
  }

  Future<List<Playlist>> getCategoryPlaylists({
    required String sortId,
    required String tagId,
    required int page,
    required int limit,
    String sourceId = 'wy',
  }) async {
    return _manager.getCategoryPlaylists(
      sortId: sortId,
      tagId: tagId,
      page: page,
      limit: limit,
      sourceId: sourceId,
    );
  }

  Future<List<Leaderboard>> getLeaderboards({String sourceId = 'wy'}) async {
    return _manager.getLeaderboards(sourceId: sourceId);
  }

  Future<Playlist?> getLeaderboardDetail(String boardId, {int page = 1, String sourceId = 'wy'}) async {
    return _manager.getLeaderboardDetail(boardId, page: page, sourceId: sourceId);
  }

  Future<List<Song>> search(String query) async {
    if (query.isEmpty) return [];
    return _manager.search(query);
  }

  Future<List<String>> getHotSearchTags() async {
    return _manager.getHotSearchTags();
  }

  Future<List<String>> getSearchSuggestions(String query) async {
    return _manager.getSearchSuggestions(query);
  }

  Future<Playlist?> getPlaylistDetail(String playlistId) async {
    return _manager.getPlaylistDetail(playlistId);
  }
}