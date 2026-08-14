import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/lyric_line.dart';
import '../services/ttml_parser.dart';
import '../../../../core/network/music_api_service.dart';

class TtmlDbService {
  final MusicApiService _apiService = MusicApiService();

  Future<List<LyricLine>?> fetchTtmlLyrics(String source, String songId) async {
    final dbSource = source == 'wy' ? 'ncm' : (source == 'tx' ? 'qq' : null);
    if (dbSource == null) return null;

    try {
      final url = 'https://amll-ttml-db.stevexmh.net/$dbSource/$songId';
      final text = await _apiService.getPlainText(url);

      if (text == null || text.isEmpty || text.length < 100) return null;

      debugPrint(
        '[TtmlDbService] Raw TTML start: ${text.substring(0, text.length > 300 ? 300 : text.length)}',
      );
      debugPrint('[TtmlDbService] TTML length: ${text.length}');

      final lines = parseTtml(text);
      if (lines.isEmpty) return null;

      if (lines.isNotEmpty) {
        debugPrint(
          '[TtmlDbService] First line words: ${lines[0].words.map((w) => w.word)}',
        );
        debugPrint(
          '[TtmlDbService] First line startTime: ${lines[0].startTimeMs}',
        );
      }

      return lines;
    } catch (e) {
      debugPrint('[TtmlDbService] error: $e');
      return null;
    }
  }
}

final ttmlDbServiceProvider = Provider<TtmlDbService>((ref) {
  return TtmlDbService();
});
