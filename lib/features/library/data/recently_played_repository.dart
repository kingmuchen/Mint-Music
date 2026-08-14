import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models/recently_played.dart';
import '../../player/domain/models/song.dart';

class RecentlyPlayedRepository {
  static const _key = 'recently_played';
  static const int _maxItems = 100;

  Future<List<RecentlyPlayedItem>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    if (data == null) return [];
    final list = jsonDecode(data) as List<dynamic>;
    return list
        .map((e) => RecentlyPlayedItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveHistory(List<RecentlyPlayedItem> history) async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(history.map((h) => h.toJson()).toList());
    await prefs.setString(_key, data);
  }

  Future<void> addToHistory(Song song) async {
    final history = await loadHistory();
    final existingIndex = history.indexWhere((h) => h.song.id == song.id);

    if (existingIndex != -1) {
      final existing = history[existingIndex];
      history[existingIndex] = existing.copyWith(
        playedAt: DateTime.now(),
        playCount: existing.playCount + 1,
      );
    } else {
      history.insert(
        0,
        RecentlyPlayedItem(song: song, playedAt: DateTime.now()),
      );
    }

    if (history.length > _maxItems) {
      history.removeRange(_maxItems, history.length);
    }

    await saveHistory(history);
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  Future<void> removeFromHistory(String songId) async {
    final history = await loadHistory();
    history.removeWhere((h) => h.song.id == songId);
    await saveHistory(history);
  }
}