import 'package:xml/xml.dart';
import '../models/lyric_line.dart';

List<LyricLine> parseTtml(String ttmlText) {
  if (ttmlText.isEmpty) return [];

  try {
    final document = XmlDocument.parse(ttmlText);
    final body = document.findAllElements('body').firstOrNull;
    if (body == null) return [];

    final lines = <LyricLine>[];
    final divs = body.findAllElements('div');

    for (final div in divs) {
      final paragraphs = div.findElements('p');
      for (final p in paragraphs) {
        final line = _parseTtmlParagraph(p);
        if (line != null) lines.add(line);
      }
    }

    lines.sort((a, b) => a.startTimeMs.compareTo(b.startTimeMs));
    return lines;
  } catch (e) {
    return [];
  }
}

class _SpanInfo {
  final String text;
  final int startTimeMs;
  final int endTimeMs;
  const _SpanInfo({
    required this.text,
    required this.startTimeMs,
    required this.endTimeMs,
  });
}

LyricLine? _parseTtmlParagraph(XmlElement p) {
  final beginAttr = p.getAttribute('begin');
  final endAttr = p.getAttribute('end');
  if (beginAttr == null) return null;

  final startTimeMs = _parseTtmlTime(beginAttr);
  final endTimeMs = endAttr != null
      ? _parseTtmlTime(endAttr)
      : startTimeMs + 3000;
  if (startTimeMs < 0) return null;

  final fullText = p.innerText.trim();
  if (fullText.isEmpty) return null;

  // Normalize: collapse all whitespace runs to single spaces
  final normalized = fullText.replaceAll(RegExp(r'\s+'), ' ');

  final children = p.children;
  final hasSpans = children.any((c) => c is XmlElement);

  final words = <LyricWord>[];

  if (!hasSpans) {
    // No span children — treat full text as a single word
    words.add(
      LyricWord(
        word: normalized,
        startTimeMs: startTimeMs,
        endTimeMs: endTimeMs,
      ),
    );
  } else {
    // Collect span data from XmlElement children only (skip XmlText)
    final spans = <_SpanInfo>[];
    for (final child in children) {
      if (child is XmlElement) {
        final text = child.innerText.trim();
        if (text.isEmpty) continue;
        final spanBegin = child.getAttribute('begin');
        final spanEnd = child.getAttribute('end');
        spans.add(
          _SpanInfo(
            text: text,
            startTimeMs: spanBegin != null
                ? _parseTtmlTime(spanBegin)
                : startTimeMs,
            endTimeMs: spanEnd != null ? _parseTtmlTime(spanEnd) : endTimeMs,
          ),
        );
      }
    }

    if (spans.isEmpty) return null;

    // Align span-concatenated text with fullText to find word boundaries.
    // Wherever fullText has a space, that's a word boundary.
    // Mark the preceding span to get a trailing space.
    final spanConcat = spans.map((s) => s.text).join();
    final boundaryAfter = List.filled(spans.length, false);

    int scPos = 0;
    for (
      int ftPos = 0;
      ftPos < normalized.length && scPos < spanConcat.length;
      ftPos++
    ) {
      if (normalized[ftPos] == ' ') {
        if (scPos > 0) {
          final spanIdx = _spanAtCharPos(scPos - 1, spans);
          if (spanIdx >= 0 && spanIdx < boundaryAfter.length) {
            boundaryAfter[spanIdx] = true;
          }
        }
      } else if (normalized[ftPos] == spanConcat[scPos]) {
        scPos++;
      }
    }

    // Build LyricWord list — add trailing space at word boundaries
    for (int i = 0; i < spans.length; i++) {
      final span = spans[i];
      final w = boundaryAfter[i] ? '${span.text} ' : span.text;
      words.add(
        LyricWord(
          word: w,
          startTimeMs: span.startTimeMs,
          endTimeMs: span.endTimeMs,
        ),
      );
    }
  }

  if (words.isEmpty) return null;

  return LyricLine(
    startTimeMs: startTimeMs,
    endTimeMs: endTimeMs,
    words: words,
  );
}

/// Find which span contains the character at [charPos] in the concatenated span text.
int _spanAtCharPos(int charPos, List<_SpanInfo> spans) {
  int pos = 0;
  for (int i = 0; i < spans.length; i++) {
    pos += spans[i].text.length;
    if (charPos < pos) return i;
  }
  return spans.length - 1;
}

int _parseTtmlTime(String timeStr) {
  if (timeStr.contains(':')) {
    final parts = timeStr.split(':');
    if (parts.length == 3) {
      final hours = int.tryParse(parts[0]) ?? 0;
      final minutes = int.tryParse(parts[1]) ?? 0;
      final seconds = _parseSeconds(parts[2]);
      return (hours * 3600 + minutes * 60) * 1000 + seconds;
    } else if (parts.length == 2) {
      final minutes = int.tryParse(parts[0]) ?? 0;
      final seconds = _parseSeconds(parts[1]);
      return (minutes * 60) * 1000 + seconds;
    }
  }

  final ms = int.tryParse(timeStr);
  if (ms != null) return ms;

  if (timeStr.endsWith('ms')) {
    return int.tryParse(timeStr.replaceAll('ms', '')) ?? -1;
  }
  if (timeStr.endsWith('s')) {
    final s = double.tryParse(timeStr.replaceAll('s', '')) ?? 0;
    return (s * 1000).round();
  }

  final fallback = double.tryParse(timeStr);
  if (fallback != null) return (fallback * 1000).round();

  return -1;
}

int _parseSeconds(String s) {
  if (s.contains('.')) {
    final parts = s.split('.');
    final wholeSeconds = int.tryParse(parts[0]) ?? 0;
    var fraction = parts.length > 1 ? parts[1] : '0';
    while (fraction.length < 3) {
      fraction += '0';
    }
    if (fraction.length > 3) {
      fraction = fraction.substring(0, 3);
    }
    final ms = int.tryParse(fraction) ?? 0;
    return wholeSeconds * 1000 + ms;
  }
  return (int.tryParse(s) ?? 0) * 1000;
}
