import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models/song.dart';
import '../domain/models/lyric_line.dart';
import '../domain/models/playback_state.dart';
import '../domain/services/lyric_parser.dart';
import '../domain/services/embedded_lyrics_extractor.dart';
import '../domain/services/ttml_db_service.dart';
import '../../plugin/application/music_source_manager.dart';
import '../../plugin/application/plugin_providers.dart';
import 'playback_controller.dart';

class LyricState {
  final List<LyricLine> lines;
  final bool isLoading;
  final String? error;
  final String? currentSongId;
  final String? currentSongSource;
  final bool hasYrc;

  const LyricState({
    this.lines = const [],
    this.isLoading = false,
    this.error,
    this.currentSongId,
    this.currentSongSource,
    this.hasYrc = false,
  });

  LyricState copyWith({
    List<LyricLine>? lines,
    bool? isLoading,
    String? error,
    String? currentSongId,
    String? currentSongSource,
    bool? hasYrc,
  }) {
    return LyricState(
      lines: lines ?? this.lines,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      currentSongId: currentSongId ?? this.currentSongId,
      currentSongSource: currentSongSource ?? this.currentSongSource,
      hasYrc: hasYrc ?? this.hasYrc,
    );
  }
}

class LyricController extends StateNotifier<LyricState> {
  final MusicSourceManager _musicSourceManager;
  final TtmlDbService _ttmlDbService;
  int _requestId = 0;
  static const Duration _lyricFetchTimeout = Duration(seconds: 10);

  LyricController(this._musicSourceManager, this._ttmlDbService)
    : super(const LyricState());

  Future<void> loadLyrics(Song? song) async {
    if (song == null) {
      debugPrint('[LyricController] song is null, clearing lyrics');
      state = const LyricState();
      return;
    }

    debugPrint(
      '[LyricController] loadLyrics called for song: ${song.title}, id: ${song.id}, source: ${song.source}',
    );

    if (state.currentSongId == song.id &&
        state.currentSongSource == song.source &&
        state.lines.isNotEmpty) {
      debugPrint('[LyricController] Same song and lyrics already loaded');
      return;
    }

    final requestId = ++_requestId;
    state = LyricState(
      // Preserve the last rendered lyrics while the next song is loading.
      // This keeps AMLL's platform view mounted and avoids a full-screen
      // black/transparent flash between previous/next tracks.
      lines: state.lines,
      isLoading: true,
      currentSongId: song.id,
      currentSongSource: song.source,
      hasYrc: state.hasYrc,
    );

    try {
      String? lrc = song.lrc;
      String? crlyric;
      String? tlyric;
      String? rlyric;

      // Step 1: Try TTML DB for wy/tx sources
      List<LyricLine>? ttmlLines;
      if (song.source == 'wy' || song.source == 'tx') {
        final cleanId = song.id.replaceAll('wy_', '').replaceAll('tx_', '');
        try {
          ttmlLines = await _ttmlDbService
              .fetchTtmlLyrics(song.source!, cleanId)
              .timeout(_lyricFetchTimeout);
        } catch (_) {
          ttmlLines = null;
        }
        if (requestId != _requestId) return;
      }

      // Step 2: Fetch online lyrics for tlyric/rlyric when TTML used, or as fallback.
      // tx/wy 即使已有普通 LRC，也要继续请求一次，避免错过 QRC/YRC 逐字歌词。
      if (song.source != null && song.source != 'local') {
        final sourceSupportsWordLyric =
            song.source == 'tx' || song.source == 'wy';
        final needOnlineLyric =
            (lrc == null || lrc.isEmpty) ||
            (ttmlLines != null) ||
            sourceSupportsWordLyric;
        if (needOnlineLyric) {
          LyricResult? result;
          try {
            result = await _musicSourceManager
                .getLyricResult(song)
                .timeout(_lyricFetchTimeout);
          } catch (_) {
            result = null;
          }
          if (requestId != _requestId) return;
          if (result != null) {
            if (result.crlyric?.trim().isNotEmpty ?? false) {
              crlyric = result.crlyric;
            }
            if ((lrc == null || lrc.isEmpty) &&
                (result.lrc?.trim().isNotEmpty ?? false)) {
              lrc = result.lrc;
            }
            tlyric = result.tlyric;
            rlyric = result.rlyric;
          }
        }
      } else if (song.isLocal && (lrc == null || lrc.isEmpty)) {
        try {
          lrc = await EmbeddedLyricsExtractor.extract(
            song.filePath!,
          ).timeout(_lyricFetchTimeout);
        } catch (_) {
          lrc = null;
        }
      }

      // Step 3: TTML path — use TTML lines as base, merge tlyric/rlyric
      if (ttmlLines != null && ttmlLines.isNotEmpty) {
        final ttmlHasYrc = ttmlLines.any((line) => line.isYrc);
        final onlineHasYrc =
            crlyric != null &&
            crlyric.isNotEmpty &&
            parseLyricAuto(crlyric).any((line) => line.isYrc);

        if (!onlineHasYrc || ttmlHasYrc) {
          debugPrint(
            '[LyricController] DEBUG TTML BEFORE tlyric: tlyric=${tlyric != null ? "${tlyric.length}chars" : "null"}',
          );
          ttmlLines = sanitizeLyricLines(ttmlLines);

          if (tlyric != null && tlyric.isNotEmpty) {
            ttmlLines = mergeTranslation(ttmlLines, tlyric);
            ttmlLines = stripTranslationFromWords(ttmlLines);
          }
          ttmlLines = extractAdLibWords(ttmlLines);
          if (rlyric != null && rlyric.isNotEmpty) {
            ttmlLines = mergeRomanLyric(ttmlLines, rlyric);
          }

          final hasYrc = ttmlLines.any((line) => line.isYrc);

          state = LyricState(
            lines: ttmlLines,
            currentSongId: song.id,
            hasYrc: hasYrc,
          );
          return;
        }

        debugPrint(
          '[LyricController] Prefer online word lyric over non-word TTML',
        );
      }

      if (requestId != _requestId) return;

      if ((lrc == null || lrc.isEmpty) &&
          (crlyric == null || crlyric.isEmpty)) {
        state = LyricState(error: '暂无歌词', currentSongId: song.id);
        return;
      }

      List<LyricLine> parsedLines;

      final lyricCandidates = <String>[
        if (crlyric != null && crlyric.isNotEmpty) crlyric,
        if (lrc != null && lrc.isNotEmpty) lrc,
      ];

      if (lyricCandidates.isNotEmpty) {
        parsedLines = [];
        for (final candidate in lyricCandidates) {
          final parsed = parseLyricAuto(candidate);
          debugPrint(
            '[LyricController] candidate(${candidate.length}chars) => ${parsed.length} lines, hasYrc=${parsed.any((l) => l.isYrc)}',
          );
          if (parsed.isEmpty) continue;

          final candidateHasYrc = parsed.any((line) => line.isYrc);
          if (candidateHasYrc || parsedLines.isEmpty) {
            parsedLines = parsed;
          }
          if (candidateHasYrc) break;
        }
        debugPrint(
          '[LyricController] final parsedLines=${parsedLines.length} hasYrc=${parsedLines.any((l) => l.isYrc)}',
        );

        if (tlyric != null && tlyric.isNotEmpty) {
          parsedLines = mergeTranslation(parsedLines, tlyric);
          parsedLines = stripTranslationFromWords(parsedLines);
        }
        parsedLines = extractAdLibWords(parsedLines);
        if (rlyric != null && rlyric.isNotEmpty) {
          parsedLines = mergeRomanLyric(parsedLines, rlyric);
        }
      } else {
        parsedLines = [];
      }

      if (requestId != _requestId) return;

      if (parsedLines.isEmpty) {
        state = LyricState(error: '歌词解析失败', currentSongId: song.id);
        return;
      }

      parsedLines = sanitizeLyricLines(parsedLines);

      final hasYrc = parsedLines.any((line) => line.isYrc);

      state = LyricState(
        lines: parsedLines,
        currentSongId: song.id,
        hasYrc: hasYrc,
      );
    } catch (e, stack) {
      debugPrint('[LyricController] Error loading lyrics: $e');
      debugPrint('[LyricController] Stack: $stack');
      if (requestId != _requestId) return;
      state = LyricState(error: '加载歌词失败: $e', currentSongId: song.id);
    }
  }

  void clear() {
    state = const LyricState();
  }
}

final lyricControllerProvider = StateNotifierProvider<LyricController, LyricState>((
  ref,
) {
  final musicSourceManager = ref.watch(musicSourceManagerProvider);
  final ttmlDbService = ref.watch(ttmlDbServiceProvider);
  final controller = LyricController(musicSourceManager, ttmlDbService);

  ref.listen<PlaybackState>(playbackControllerProvider, (previous, next) {
    if (next.currentSong?.id != previous?.currentSong?.id) {
      debugPrint(
        '[LyricController] Song changed from ${previous?.currentSong?.title} to ${next.currentSong?.title}',
      );
      Future.microtask(() => controller.loadLyrics(next.currentSong));
    }
  });

  return controller;
});
