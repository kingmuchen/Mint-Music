import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models/playlist.dart';
import '../../player/domain/models/song.dart';

class PlaylistRepository {
  static const _key = 'playlists';
  static const _favoritesId = '__favorites__';

  Future<List<Playlist>> loadPlaylists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_key);
      List<Playlist> playlists = [];
      if (data != null && data.isNotEmpty) {
        final list = jsonDecode(data) as List<dynamic>;
        playlists = list
            .map((e) => Playlist.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      if (!playlists.any((p) => p.id == _favoritesId)) {
        final now = DateTime.now();
        final favorites = Playlist(
          id: _favoritesId,
          name: '我的收藏',
          description: '收藏的歌曲',
          createTime: now,
          updateTime: now,
        );
        playlists.insert(0, favorites);
        await savePlaylists(playlists);
      }
      return playlists;
    } catch (e) {
      // ignore: avoid_print
      print('PlaylistRepository.loadPlaylists error: $e');
      rethrow;
    }
  }

  Future<void> savePlaylists(List<Playlist> playlists) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = jsonEncode(playlists.map((p) => p.toJson()).toList());
      await prefs.setString(_key, data);
    } catch (e) {
      // log and rethrow so the notifier can surface the error
      // ignore: avoid_print
      print('PlaylistRepository.savePlaylists error: $e');
      rethrow;
    }
  }

  Future<void> savePlaylist(Playlist playlist) async {
    final playlists = await loadPlaylists();
    final existingIndex = playlists.indexWhere((p) => p.id == playlist.id);
    if (existingIndex != -1) {
      playlists[existingIndex] = playlist.copyWith(updateTime: DateTime.now());
    } else {
      playlists.add(playlist);
    }
    await savePlaylists(playlists);
  }

  Future<Playlist> createPlaylist(String name, {String description = ''}) async {
    final playlists = await loadPlaylists();
    final now = DateTime.now();
    final playlist = Playlist(
      id: now.millisecondsSinceEpoch.toString(),
      name: name,
      description: description,
      createTime: now,
      updateTime: now,
    );
    playlists.add(playlist);
    await savePlaylists(playlists);
    return playlist;
  }

  Future<Playlist> createPlaylistWithSongs(
    String name,
    List<Map<String, dynamic>> songsData,
    {String description = ''}
  ) async {
    final playlists = await loadPlaylists();
    final now = DateTime.now();
    
    final songs = songsData.map((data) {
      return Song(
        id: data['id']?.toString() ?? '',
        title: data['title']?.toString() ?? '未知歌曲',
        artist: data['artist']?.toString() ?? '未知歌手',
        album: data['album']?.toString() ?? '未知专辑',
        duration: (data['duration'] is int) ? data['duration'] as int : 0,
        coverUrl: data['coverUrl']?.toString(),
        sourceUrl: data['sourceUrl']?.toString(),
        source: data['source']?.toString(),
        lrc: data['lrc']?.toString(),
      );
    }).toList();

    final playlist = Playlist(
      id: now.millisecondsSinceEpoch.toString(),
      name: name,
      description: description,
      createTime: now,
      updateTime: now,
      songs: songs,
      coverImgUrl: songs.isNotEmpty ? (songs.first.coverUrl ?? '') : '',
    );
    playlists.add(playlist);
    await savePlaylists(playlists);
    return playlist;
  }

  Future<void> updatePlaylist(Playlist playlist) async {
    final playlists = await loadPlaylists();
    final index = playlists.indexWhere((p) => p.id == playlist.id);
    if (index != -1) {
      playlists[index] = playlist.copyWith(updateTime: DateTime.now());
      await savePlaylists(playlists);
    }
  }

  Future<void> deletePlaylist(String id) async {
    if (id == _favoritesId) return;
    final playlists = await loadPlaylists();
    playlists.removeWhere((p) => p.id == id);
    await savePlaylists(playlists);
  }

  /// Returns true if the song was actually added (not a duplicate).
  Future<bool> addSongToPlaylist(String playlistId, Song song) async {
    try {
      final playlists = await loadPlaylists();
      final index = playlists.indexWhere((p) => p.id == playlistId);
      if (index != -1) {
        final playlist = playlists[index];
        if (!playlist.songs.any((s) => s.id == song.id)) {
          final updatedSongs = [song, ...playlist.songs];
          playlists[index] = playlist.copyWith(
            songs: updatedSongs,
            updateTime: DateTime.now(),
            coverImgUrl: playlist.coverImgUrl.isEmpty
                ? (song.coverUrl ?? '')
                : playlist.coverImgUrl,
          );
          await savePlaylists(playlists);
          return true;
        }
      }
      return false;
    } catch (e) {
      // ignore: avoid_print
      print('PlaylistRepository.addSongToPlaylist error: $e');
      rethrow;
    }
  }

  Future<void> removeSongFromPlaylist(String playlistId, String songId) async {
    final playlists = await loadPlaylists();
    final index = playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      final playlist = playlists[index];
      final updatedSongs = playlist.songs.where((s) => s.id != songId).toList();
      playlists[index] = playlist.copyWith(
        songs: updatedSongs,
        updateTime: DateTime.now(),
      );
      await savePlaylists(playlists);
    }
  }

  Future<String> exportPlaylist(Playlist playlist) async {
    return jsonEncode(playlist.toJson());
  }

  Future<Playlist> importPlaylist(String jsonString) async {
    final data = jsonDecode(jsonString) as Map<String, dynamic>;
    final playlist = Playlist.fromJson(data);
    final playlists = await loadPlaylists();
    final existingIndex = playlists.indexWhere((p) => p.id == playlist.id);
    if (existingIndex != -1) {
      playlists[existingIndex] = playlist.copyWith(updateTime: DateTime.now());
    } else {
      playlists.add(playlist.copyWith(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      ));
    }
    await savePlaylists(playlists);
    return playlist;
  }
}