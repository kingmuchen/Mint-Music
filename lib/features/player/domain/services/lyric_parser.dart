import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/lyric_line.dart';
import 'ttml_parser.dart';

List<LyricLine> parseLrc(String lrcText, {String? tlyric, String? rlyric}) {
  if (lrcText.isEmpty) return [];

  final lines = <_RawLrcLine>[];
  final lineRegExp = RegExp(r'^\[(\d{1,2}):(\d{2})\.(\d{2,3})\](.*)$');
  final wordTagRegExp = RegExp(r'<\d{1,2}:\d{2}\.\d{2,3}>');
  final offsetRegExp = RegExp(r'^\[offset:(-?\d+)\]$');

  int globalOffset = 0;

  for (final rawLine in lrcText.split('\n')) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty) continue;

    final offsetMatch = offsetRegExp.firstMatch(trimmed);
    if (offsetMatch != null) {
      globalOffset = int.tryParse(offsetMatch.group(1) ?? '0') ?? 0;
      continue;
    }

    final match = lineRegExp.firstMatch(trimmed);
    if (match == null) continue;

    final minutes = int.parse(match.group(1)!);
    final seconds = int.parse(match.group(2)!);
    var msStr = match.group(3)!;
    if (msStr.length == 2) msStr = '${msStr}0';
    final ms = int.parse(msStr);
    var text = match.group(4)?.trim() ?? '';

    text = text.replaceAll(wordTagRegExp, '');
    // 去掉所有内嵌的 LRC 时间标签（形如 `[00:00.47]`），避免污染歌词文本
    // 这些标签可能出现在歌词文本的任意位置（行首、中间、行尾）
    text = text.replaceAll(RegExp(r'\[\d{1,2}:\d{2}(?:\.\d{2,3})?\]'), '');
    if (text.isEmpty) continue;

    final timestampMs = minutes * 60000 + seconds * 1000 + ms + globalOffset;
    lines.add(_RawLrcLine(timestampMs: timestampMs, text: text));
  }

  lines.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));

  final tlyricMap = _parseTranslationLrc(tlyric);
  final rlyricMap = _parseTranslationLrc(rlyric);

  final result = <LyricLine>[];
  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    final endTimeMs = i < lines.length - 1
        ? lines[i + 1].timestampMs - 1
        : line.timestampMs + 3000;

    final translation = _findTranslation(tlyricMap, line.timestampMs);
    final roman = _findTranslation(rlyricMap, line.timestampMs);

    result.add(
      LyricLine(
        startTimeMs: line.timestampMs,
        endTimeMs: endTimeMs,
        words: [
          LyricWord(
            word: line.text,
            startTimeMs: line.timestampMs,
            endTimeMs: endTimeMs,
          ),
        ],
        translatedLyric: translation,
        romanLyric: roman,
      ),
    );
  }

  return result;
}

class _RawLrcLine {
  final int timestampMs;
  final String text;
  const _RawLrcLine({required this.timestampMs, required this.text});
}

/// Remove timed word tags like `(37196,207)` or `（37196，207）`
/// from romanization text so only the readable text remains.
String _stripTimedWordTags(String text) {
  // ASCII parentheses: (ms,dur) or (ms,dur,extra)
  // Chinese full-width: （ms，dur） or （ms，dur，extra）
  return text
      .replaceAll(RegExp(r'[(（]\d+[,，]\d+(?:[,，]\d+)?[)）]'), '');
}

Map<int, String> _parseTranslationLrc(String? lrcText) {
  if (lrcText == null || lrcText.isEmpty) return {};

  final result = <int, String>{};
  final lineRegExp = RegExp(r'^\[(\d{1,2}):(\d{2})\.(\d{2,3})\](.*)$');

  for (final rawLine in lrcText.split('\n')) {
    final match = lineRegExp.firstMatch(rawLine.trim());
    if (match == null) continue;

    final minutes = int.parse(match.group(1)!);
    final seconds = int.parse(match.group(2)!);
    var msStr = match.group(3)!;
    if (msStr.length == 2) msStr = '${msStr}0';
    final ms = int.parse(msStr);
    final text = _stripTimedWordTags(match.group(4)?.trim() ?? '');
    if (text.isEmpty) continue;

    final timestampMs = minutes * 60000 + seconds * 1000 + ms;
    result[timestampMs] = text;
  }

  return result;
}

String? _findTranslation(Map<int, String> map, int timestampMs) {
  const tolerance = 300;
  for (final entry in map.entries) {
    if ((entry.key - timestampMs).abs() <= tolerance) {
      return entry.value;
    }
  }
  return map[timestampMs];
}

List<LyricLine> parseYrc(String yrcText) {
  if (yrcText.isEmpty) return [];

  yrcText = extractEmbeddedLyricContent(yrcText);
  final lines = <LyricLine>[];
  final lineRegExp = RegExp(r'^\[(\d+),(\d+)\](.*)$');
  final lrcLineRegExp = RegExp(r'^\[(\d{1,2}):(\d{2})\.(\d{2,3})\](.*)$');

  for (final rawLine in yrcText.split('\n')) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty) continue;

    final lineMatch = lineRegExp.firstMatch(trimmed);
    final lrcLineMatch = lineMatch == null
        ? lrcLineRegExp.firstMatch(trimmed)
        : null;
    if (lineMatch == null && lrcLineMatch == null) continue;

    final startTime = lineMatch != null
        ? int.parse(lineMatch.group(1)!)
        : _parseLrcTimestamp(
            lrcLineMatch!.group(1)!,
            lrcLineMatch.group(2)!,
            lrcLineMatch.group(3)!,
          );
    final duration = lineMatch != null ? int.parse(lineMatch.group(2)!) : 0;
    final content = lineMatch != null
        ? lineMatch.group(3)!
        : lrcLineMatch!.group(4)!;
    final endTime = duration > 0 ? startTime + duration : startTime;

    final words = _parseTimedWords(
      content: content,
      lineStartTime: startTime,
      lineEndTime: endTime,
      wordRegExp: RegExp(r'\((\d+),(\d+)(?:,\d+)?\)'),
      nextTagStart: '(',
      wordBeforeTag: !content.startsWith('('),
    );
    if (words.isEmpty && content.isNotEmpty) {
      words.add(
        LyricWord(word: content, startTimeMs: startTime, endTimeMs: endTime),
      );
    }
    if (words.isEmpty) continue;
    final resolvedEndTime = duration > 0
        ? endTime
        : words.fold<int>(
            startTime,
            (value, word) => max(value, word.endTimeMs),
          );

    lines.add(
      LyricLine(
        startTimeMs: startTime,
        endTimeMs: resolvedEndTime,
        words: words,
      ),
    );
  }

  lines.sort((a, b) => a.startTimeMs.compareTo(b.startTimeMs));
  return lines;
}

List<LyricLine> parseQrc(String qrcText) {
  if (qrcText.isEmpty) return [];

  qrcText = extractEmbeddedLyricContent(qrcText);
  final lines = <LyricLine>[];
  final lineRegExp = RegExp(r'^\[(\d+),(\d+)\](.*)$');

  for (final rawLine in qrcText.split('\n')) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty) continue;

    final lineMatch = lineRegExp.firstMatch(trimmed);
    if (lineMatch == null) continue;

    final startTime = int.parse(lineMatch.group(1)!);
    final duration = int.parse(lineMatch.group(2)!);
    final endTime = startTime + duration;
    final content = lineMatch.group(3)!;

    final words = _parseTimedWords(
      content: content,
      lineStartTime: startTime,
      lineEndTime: endTime,
      wordRegExp: RegExp(r'\((\d+),(\d+),(\d+)\)'),
      nextTagStart: '(',
      wordBeforeTag: !content.startsWith('('),
    );

    if (words.isEmpty && content.isNotEmpty) {
      words.add(
        LyricWord(word: content, startTimeMs: startTime, endTimeMs: endTime),
      );
    }

    if (words.isNotEmpty) {
      lines.add(
        LyricLine(startTimeMs: startTime, endTimeMs: endTime, words: words),
      );
    }
  }

  lines.sort((a, b) => a.startTimeMs.compareTo(b.startTimeMs));
  return lines;
}

List<LyricLine> parseKrc(String krcText) {
  if (krcText.isEmpty) return [];

  krcText = extractEmbeddedLyricContent(krcText);
  final lines = <LyricLine>[];
  final lineRegExp = RegExp(r'^\[(\d+),(\d+)\](.*)$');

  for (final rawLine in krcText.split('\n')) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty) continue;

    final lineMatch = lineRegExp.firstMatch(trimmed);
    if (lineMatch == null) continue;

    final startTime = int.parse(lineMatch.group(1)!);
    final duration = int.parse(lineMatch.group(2)!);
    final endTime = startTime + duration;
    final content = lineMatch.group(3)!;

    // Convert KRC <relStart,dur,0> to YRC-style (absStart,dur,0), matching CeruMusic kg.js
    final convertedContent = content.replaceAllMapped(
      RegExp(r'<(\d+),(\d+),0>'),
      (match) {
        final relStart = int.parse(match.group(1)!);
        final wordDur = int.parse(match.group(2)!);
        final absStart = startTime + relStart;
        return '($absStart,$wordDur,0)';
      },
    );

    final words = _parseTimedWords(
      content: convertedContent,
      lineStartTime: startTime,
      lineEndTime: endTime,
      wordRegExp: RegExp(r'\((\d+),(\d+)(?:,\d+)?\)'),
      nextTagStart: '(',
      wordBeforeTag: false,
    );

    if (words.isEmpty && content.isNotEmpty) {
      words.add(
        LyricWord(word: content, startTimeMs: startTime, endTimeMs: endTime),
      );
    }

    if (words.isNotEmpty) {
      lines.add(
        LyricLine(startTimeMs: startTime, endTimeMs: endTime, words: words),
      );
    }
  }

  lines.sort((a, b) => a.startTimeMs.compareTo(b.startTimeMs));
  return lines;
}

List<LyricLine> parseMrc(String mrcText) {
  if (mrcText.isEmpty) return [];

  mrcText = extractEmbeddedLyricContent(mrcText);
  final lines = <LyricLine>[];
  final lineRegExp = RegExp(r'^\[(\d+),(\d+)\](.*)$');

  for (final rawLine in mrcText.split('\n')) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty) continue;

    final lineMatch = lineRegExp.firstMatch(trimmed);
    if (lineMatch == null) continue;

    final startTime = int.parse(lineMatch.group(1)!);
    final duration = int.parse(lineMatch.group(2)!);
    final endTime = startTime + duration;
    final content = lineMatch.group(3)!;

    final words = _parseTimedWords(
      content: content,
      lineStartTime: startTime,
      lineEndTime: endTime,
      wordRegExp: RegExp(r'\((\d+),(\d+)\)'),
      nextTagStart: '(',
    );

    if (words.isEmpty && content.isNotEmpty) {
      words.add(
        LyricWord(word: content, startTimeMs: startTime, endTimeMs: endTime),
      );
    }

    if (words.isNotEmpty) {
      lines.add(
        LyricLine(startTimeMs: startTime, endTimeMs: endTime, words: words),
      );
    }
  }

  lines.sort((a, b) => a.startTimeMs.compareTo(b.startTimeMs));
  return lines;
}

List<LyricLine> mergeTranslation(List<LyricLine> base, String? tlyric) {
  if (tlyric == null || tlyric.isEmpty || base.isEmpty) return base;

  final translated = parseLrc(tlyric);
  if (translated.isEmpty) return base;

  const matchWindow = 1500;

  int? usedJ;
  for (int i = 0; i < base.length; i++) {
    if (base[i].plainText.isEmpty) continue;
    if (base[i].translatedLyric != null) continue;

    final startJ = usedJ != null ? usedJ + 1 : 0;
    var bestJ = -1;
    var bestDiff = double.infinity;
    for (int j = startJ; j < translated.length; j++) {
      final diff = (translated[j].startTimeMs - base[i].startTimeMs)
          .abs()
          .toDouble();
      if (diff < bestDiff && diff <= matchWindow) {
        bestDiff = diff;
        bestJ = j;
      }
    }

    if (bestJ >= 0) {
      final text = translated[bestJ].plainText;
      if (text.isNotEmpty && text != '//') {
        base[i] = base[i].copyWith(translatedLyric: text);
        usedJ = bestJ;
      }
    }
  }

  return base;
}

List<LyricLine> stripTranslationFromWords(List<LyricLine> lines) {
  return lines.map((line) {
    final tran = line.translatedLyric;
    if (tran == null || tran.isEmpty || line.words.length <= 1) return line;

    final hasCjkTran = tran.codeUnits.any((cu) => cu >= 0x4E00 && cu <= 0x9FFF);
    if (!hasCjkTran) return line;

    final filtered = <LyricWord>[];
    for (final word in line.words) {
      final hasCjk = word.word.codeUnits.any(
        (cu) => cu >= 0x4E00 && cu <= 0x9FFF,
      );
      if (!hasCjk) {
        filtered.add(word);
      }
    }

    if (filtered.length == line.words.length || filtered.length < 2)
      return line;

    return line.copyWith(words: filtered);
  }).toList();
}

List<LyricLine> extractAdLibWords(List<LyricLine> lines) {
  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.words.length < 2 || line.adLibText != null) continue;

    var adLibStart = -1;
    for (int j = line.words.length - 1; j >= 0; j--) {
      final w = line.words[j].word.trimRight();
      if (w.startsWith('(') ||
          w.startsWith('（') ||
          w.endsWith(')') ||
          w.endsWith('）')) {
        adLibStart = j;
      } else {
        if (adLibStart >= 0) break;
      }
    }
    if (adLibStart < 0) continue;

    final adLibWords = line.words.sublist(adLibStart);
    final mainWords = line.words.sublist(0, adLibStart);
    if (mainWords.length < 2) continue;

    final adLibJoined = adLibWords.map((w) => w.word).join(' ');
    final cleaned = adLibJoined
        .replaceAll(RegExp(r'^[（(]\s*'), '')
        .replaceAll(RegExp(r'\s*[）)]\s*$'), '');
    if (cleaned.isEmpty) continue;

    lines[i] = line.copyWith(words: mainWords, adLibText: cleaned);
  }
  return lines;
}

List<LyricLine> mergeRomanLyric(List<LyricLine> base, String? rlyric) {
  if (rlyric == null || rlyric.isEmpty || base.isEmpty) return base;

  final romanized = parseLrc(rlyric);
  if (romanized.isEmpty) return base;

  const tolerance = 300;
  const ratioTolerance = 0.4;

  int? anchorIndex;
  var bestDiff = double.infinity;
  for (int i = 0; i < romanized.length; i++) {
    final firstDuration = (base[0].endTimeMs - base[0].startTimeMs).abs();
    final firstTol = min(tolerance, firstDuration * ratioTolerance);
    final diff = (romanized[i].startTimeMs - base[0].startTimeMs)
        .abs()
        .toDouble();
    if (diff <= firstTol && diff < bestDiff) {
      bestDiff = diff;
      anchorIndex = i;
    }
  }

  if (anchorIndex != null) {
    var j = anchorIndex;
    for (int i = 0; i < base.length && j < romanized.length; i++, j++) {
      final romanText = _stripTimedWordTags(romanized[j].plainText);
      if (romanText.isEmpty || base[i].plainText.isEmpty) continue;
      if (base[i].romanLyric == null) {
        base[i] = base[i].copyWith(romanLyric: romanText);
      }
    }
  }

  return base;
}

List<LyricLine> sanitizeLyricLines(List<LyricLine> lines) {
  if (lines.isEmpty) return lines;

  final sanitized = <LyricLine>[];

  for (int i = 0; i < lines.length; i++) {
    var line = lines[i];

    if (line.startTimeMs < 0) {
      line = line.copyWith(startTimeMs: 0);
    }

    if (line.endTimeMs <= line.startTimeMs) {
      final defaultDuration = 3000;
      final nextStart = i < lines.length - 1
          ? lines[i + 1].startTimeMs
          : line.startTimeMs + defaultDuration;
      line = line.copyWith(
        endTimeMs: nextStart > line.startTimeMs
            ? nextStart - 1
            : line.startTimeMs + defaultDuration,
      );
    }

    final sanitizedWords = <LyricWord>[];
    for (final word in line.words) {
      var w = word;
      if (w.startTimeMs < line.startTimeMs) {
        w = w.copyWith(startTimeMs: line.startTimeMs);
      }
      if (w.endTimeMs > line.endTimeMs) {
        w = w.copyWith(endTimeMs: line.endTimeMs);
      }
      if (w.endTimeMs <= w.startTimeMs) {
        w = w.copyWith(
          endTimeMs:
              w.startTimeMs +
              max(
                100,
                (line.endTimeMs - line.startTimeMs) ~/ line.words.length,
              ),
        );
      }
      sanitizedWords.add(w);
    }

    final lastWordEnd = sanitizedWords.isNotEmpty
        ? sanitizedWords.last.endTimeMs
        : line.startTimeMs;
    if (line.endTimeMs < lastWordEnd) {
      line = line.copyWith(endTimeMs: lastWordEnd);
    }

    sanitized.add(line.copyWith(words: sanitizedWords));
  }

  sanitized.sort((a, b) => a.startTimeMs.compareTo(b.startTimeMs));
  return sanitized;
}

bool isYrcFormat(String text) {
  if (text.isEmpty) return false;
  final firstLines = text.split('\n').take(80);
  for (final line in firstLines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    if (RegExp(r'^\[\d+,\d+\].*\(\d+,\d+,\d+\)').hasMatch(trimmed) ||
        RegExp(r'^\[\d+,\d+\].*\(\d+,\d+\)').hasMatch(trimmed) ||
        (trimmed.startsWith('[') && trimmed.contains(']('))) {
      return true;
    }
  }
  return false;
}

bool isEnhancedLrcFormat(String text) {
  if (text.isEmpty) return false;
  final firstLines = text.split('\n').take(80);
  for (final line in firstLines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    if (RegExp(
      r'^\[\d{1,2}:\d{2}\.\d{2,3}\].*<\d{1,2}:\d{2}\.\d{2,3}>',
    ).hasMatch(trimmed)) {
      return true;
    }
  }
  return false;
}

bool isKrcFormat(String text) {
  if (text.isEmpty) return false;
  final firstLines = text.split('\n').take(80);
  for (final line in firstLines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    if (RegExp(r'^\[\d+,\d+\].*<\d+,\d+,\d+>').hasMatch(trimmed)) {
      return true;
    }
  }
  return false;
}

bool isLrcxFormat(String text) {
  if (text.isEmpty) return false;
  final firstLines = text.split('\n').take(80);
  for (final line in firstLines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    // 标准 LRCx：`[毫秒,时长]<相对起始,时长>字`
    if (RegExp(r'^\[\d+,\d+\].*<\d+,\d+>').hasMatch(trimmed)) {
      return true;
    }
    // 咪咕（Migu）风格：LRC 行时间戳 + 相对字时间标签 `[mm:ss.mmm]<相对起始,时长>字`
    if (RegExp(r'^\[\d{1,2}:\d{2}\.\d{2,3}\].*<\d+,\d+>').hasMatch(trimmed)) {
      return true;
    }
  }
  return false;
}

bool isMrcFormat(String text) {
  if (text.isEmpty) return false;
  final firstLines = text.split('\n').take(80);
  for (final line in firstLines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    if (RegExp(r'^\[\d+,\d+\].*\(\d+,\d+\)[^(]').hasMatch(trimmed)) {
      return true;
    }
  }
  return false;
}

bool isTtmlFormat(String text) {
  if (text.isEmpty) return false;
  final trimmed = text.trimLeft();
  return trimmed.startsWith('<tt') ||
      (trimmed.contains('<tt') &&
          trimmed.contains('<body') &&
          trimmed.contains('<p'));
}

List<LyricLine> parseEnhancedLrc(String lrcText) {
  if (lrcText.isEmpty) return [];

  final rawLines = <_EnhancedRawLine>[];
  final lineRegExp = RegExp(r'^\[(\d{1,2}):(\d{2})\.(\d{2,3})\](.*)$');

  for (final rawLine in lrcText.split('\n')) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty) continue;

    final match = lineRegExp.firstMatch(trimmed);
    if (match == null) continue;

    final timestamp = _parseLrcTimestamp(
      match.group(1)!,
      match.group(2)!,
      match.group(3)!,
    );
    final content = match.group(4)?.trim() ?? '';
    if (content.isEmpty) continue;

    rawLines.add(_EnhancedRawLine(timestampMs: timestamp, content: content));
  }

  rawLines.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));

  final result = <LyricLine>[];
  for (var i = 0; i < rawLines.length; i++) {
    final raw = rawLines[i];
    final nextStart = i < rawLines.length - 1
        ? rawLines[i + 1].timestampMs
        : raw.timestampMs + 5000;
    final lineEnd = max(raw.timestampMs + 500, nextStart - 1);
    final words = _parseEnhancedLrcWords(raw.content, raw.timestampMs, lineEnd);
    if (words.isEmpty) continue;

    result.add(
      LyricLine(
        startTimeMs: raw.timestampMs,
        endTimeMs: max(lineEnd, words.last.endTimeMs),
        words: words,
      ),
    );
  }

  return result;
}

List<LyricWord> _parseEnhancedLrcWords(
  String content,
  int lineStartTime,
  int lineEndTime,
) {
  final tagExp = RegExp(r'<(\d{1,2}):(\d{2})\.(\d{2,3})>');
  final matches = tagExp.allMatches(content).toList();
  if (matches.isEmpty) return [];

  final words = <LyricWord>[];
  for (var i = 0; i < matches.length; i++) {
    final match = matches[i];
    final nextMatch = i < matches.length - 1 ? matches[i + 1] : null;
    final wordText = content
        .substring(match.end, nextMatch?.start ?? content.length)
        .replaceAll(tagExp, '');
    if (wordText.isEmpty) continue;

    final startTime = _parseLrcTimestamp(
      match.group(1)!,
      match.group(2)!,
      match.group(3)!,
    );
    final endTime = nextMatch != null
        ? _parseLrcTimestamp(
            nextMatch.group(1)!,
            nextMatch.group(2)!,
            nextMatch.group(3)!,
          )
        : lineEndTime;

    words.add(
      LyricWord(
        word: wordText,
        startTimeMs: max(lineStartTime, startTime),
        endTimeMs: max(startTime + 80, endTime),
      ),
    );
  }

  return words;
}

List<LyricLine> parseLrcx(String lrcxText) {
  if (lrcxText.isEmpty) return [];

  lrcxText = extractEmbeddedLyricContent(lrcxText);
  final lines = <LyricLine>[];
  final lineTimeExp = RegExp(r'^\[(\d+),(\d+)\]');
  final lineTime2Exp = RegExp(r'^\[(\d{1,2}):(\d{2})\.(\d{2,3})\]');
  final wordTimeExp = RegExp(r'<(\d+),(\d+)>');

  for (final rawLine in lrcxText.split('\n')) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty) continue;

    int? startTime;
    int? duration;
    String content;

    final lineMatch = lineTimeExp.firstMatch(trimmed);
    if (lineMatch != null) {
      startTime = int.parse(lineMatch.group(1)!);
      duration = int.parse(lineMatch.group(2)!);
      content = trimmed.replaceFirst(lineTimeExp, '');
    } else {
      final lineMatch2 = lineTime2Exp.firstMatch(trimmed);
      if (lineMatch2 == null) continue;
      final m = int.parse(lineMatch2.group(1)!);
      final s = int.parse(lineMatch2.group(2)!);
      var msStr = lineMatch2.group(3)!;
      if (msStr.length == 2) msStr = '${msStr}0';
      startTime = m * 60000 + s * 1000 + int.parse(msStr);
      content = trimmed.replaceFirst(lineTime2Exp, '');
      duration = 5000;
    }

    final endTime = startTime + duration;
    final words = <LyricWord>[];
    var remaining = content;
    var lastEnd = startTime;

    while (remaining.isNotEmpty) {
      final match = wordTimeExp.firstMatch(remaining);
      if (match == null) break;

      final textBefore = remaining.substring(0, match.start);
      final rawWordStart = int.parse(match.group(1)!);
      final wordDuration = int.parse(match.group(2)!);
      final wordStart = _resolveTimedWordStart(
        lineStartTime: startTime,
        lineEndTime: endTime,
        rawStartTime: rawWordStart,
        duration: wordDuration,
      );
      final wordEnd = wordStart + wordDuration;

      remaining = remaining.substring(match.end);

      if (textBefore.isNotEmpty) {
        words.add(
          LyricWord(
            word: textBefore,
            startTimeMs: lastEnd,
            endTimeMs: wordStart,
          ),
        );
      }

      String wordText = '';
      if (remaining.isNotEmpty && !remaining.startsWith('<')) {
        final nextTag = remaining.indexOf('<');
        if (nextTag < 0) {
          wordText = remaining;
          remaining = '';
        } else {
          wordText = remaining.substring(0, nextTag);
          remaining = remaining.substring(nextTag);
        }
      }

      if (wordText.isNotEmpty) {
        words.add(
          LyricWord(word: wordText, startTimeMs: wordStart, endTimeMs: wordEnd),
        );
      }

      lastEnd = wordEnd;
    }

    if (words.isEmpty && content.isNotEmpty) {
      final cleanContent = content.replaceAll(wordTimeExp, '');
      if (cleanContent.isNotEmpty) {
        words.add(
          LyricWord(
            word: cleanContent,
            startTimeMs: startTime,
            endTimeMs: endTime,
          ),
        );
      }
    }

    if (words.isNotEmpty) {
      lines.add(
        LyricLine(startTimeMs: startTime, endTimeMs: endTime, words: words),
      );
    }
  }

  lines.sort((a, b) => a.startTimeMs.compareTo(b.startTimeMs));
  return lines;
}

/// 检测是否为 NetEase JSON-lines YRC 格式。
/// 每行: {"t":ms,"c":[{"tx":"字","t":"m:ss.ms"},...]}
bool isNeteaseJsonYrcFormat(String text) {
  if (text.isEmpty) return false;
  final firstLines = text.split('\n').take(20);
  var jsonLineCount = 0;
  for (final line in firstLines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    if (trimmed.startsWith('{"t":') || trimmed.startsWith('{"t" :')) {
      jsonLineCount++;
      if (jsonLineCount >= 2) return true;
    }
  }
  return false;
}

/// 将 NetEase JSON-lines YRC 转换为标准 [startMs,duration](absMs,dur,0)字 格式。
/// 非 JSON 行（标准 YRC / LRC 格式）原样透传，不会丢失。
String _convertNeteaseJsonYrc(String yrcText) {
  final rawLines = yrcText.split('\n');
  final rawNonJson = <String>[];
  final allLineStarts = <int>[];
  final allLineChars = <List<_JsonChar>>[];

  for (final rawLine in rawLines) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty) continue;
    if (!trimmed.startsWith('{')) {
      rawNonJson.add(trimmed);
      continue;
    }
    try {
      final json = jsonDecode(trimmed) as Map?;
      if (json == null) continue;
      final lineStart = json['t'];
      if (lineStart is! int) continue;
      final chars = json['c'] as List?;
      if (chars == null || chars.isEmpty) continue;

      final charList = <_JsonChar>[];
      for (final char in chars) {
        if (char is! Map) continue;
        final tx = char['tx']?.toString() ?? '';
        if (tx.isEmpty) continue;
        final tStr = char['t']?.toString();
        int relStart;
        if (tStr != null && tStr.isNotEmpty) {
          final parts = tStr.split(':');
          if (parts.length == 2) {
            final minutes = int.tryParse(parts[0]) ?? 0;
            final secParts = parts[1].split('.');
            final seconds = int.tryParse(secParts[0]) ?? 0;
            final ms = secParts.length > 1
                ? int.tryParse(secParts[1].padRight(3, '0').substring(0, 3)) ??
                      0
                : 0;
            relStart = minutes * 60000 + seconds * 1000 + ms;
          } else {
            relStart = charList.isEmpty ? 0 : charList.last.relStart + 200;
          }
        } else {
          relStart = charList.isEmpty ? 0 : charList.last.relStart + 200;
        }
        charList.add(_JsonChar(tx, relStart));
      }
      if (charList.isNotEmpty) {
        final hasTiming = chars.any(
          (c) =>
              c is Map && c['t'] != null && c['t'].toString().trim().isNotEmpty,
        );
        if (allLineStarts.length < 3) {
          debugPrint(
            '[YRC Convert] JSON line: lineStart=$lineStart chars=${chars.length} hasTiming=$hasTiming first3="${chars.take(3).map((c) => c is Map ? '${c["tx"]}@${c["t"]}' : '?').join(", ")}"',
          );
        }
        if (!hasTiming) {
          final txAll = chars
              .map((c) => c is Map ? (c['tx']?.toString() ?? '') : '')
              .join();
          allLineStarts.add(lineStart);
          allLineChars.add([_JsonChar(txAll, 0)]);
        } else {
          allLineStarts.add(lineStart);
          allLineChars.add(charList);
        }
      }
    } catch (_) {}
  }

  final resultLines = <String>[];
  int jsonIdx = 0;

  // Emit non-JSON lines and converted JSON lines in original order
  for (final rawLine in rawLines) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty) continue;
    if (trimmed.startsWith('{')) {
      // This was a JSON line; emit its converted form if available
      if (jsonIdx < allLineStarts.length) {
        final lineStart = allLineStarts[jsonIdx];
        final chars = allLineChars[jsonIdx];
        jsonIdx++;

        final nextLineStart = jsonIdx < allLineStarts.length
            ? allLineStarts[jsonIdx]
            : lineStart + 5000;

        final yrcWords = <String>[];
        var maxWordEnd = lineStart;
        for (int j = 0; j < chars.length; j++) {
          final ch = chars[j];
          final absStart = lineStart + ch.relStart;
          final wordEnd = j < chars.length - 1
              ? lineStart + chars[j + 1].relStart
              : nextLineStart;
          final dur = wordEnd - absStart;
          yrcWords.add('($absStart,${dur > 0 ? dur : 100},0)${ch.tx}');
          if (wordEnd > maxWordEnd) maxWordEnd = wordEnd;
        }

        final lineDuration = maxWordEnd - lineStart;
        resultLines.add(
          '[$lineStart,$lineDuration]${yrcWords.join('').trimRight()}',
        );
      }
    } else {
      resultLines.add(trimmed);
    }
  }

  return resultLines.join('\n');
}

class _JsonChar {
  final String tx;
  final int relStart;
  const _JsonChar(this.tx, this.relStart);
}

List<LyricLine> parseLyricAuto(String text) {
  if (text.isEmpty) return [];

  text = extractEmbeddedLyricContent(text);

  List<LyricLine> result;
  String format;

  if (isTtmlFormat(text)) {
    format = 'ttml';
    result = parseTtml(text);
  } else if (isNeteaseJsonYrcFormat(text)) {
    text = _convertNeteaseJsonYrc(text);
    format = 'netease-json-yrc';
    result = parseYrc(text);
  } else if (isYrcFormat(text)) {
    format = 'yrc';
    result = parseYrc(text);
  } else if (isKrcFormat(text)) {
    format = 'krc';
    result = parseKrc(text);
  } else if (isLrcxFormat(text)) {
    format = 'lrcx';
    result = parseLrcx(text);
  } else if (isMrcFormat(text)) {
    format = 'mrc';
    result = parseMrc(text);
  } else if (isEnhancedLrcFormat(text)) {
    format = 'elrc';
    result = parseEnhancedLrc(text);
  } else {
    format = 'lrc';
    result = parseLrc(text);
  }

  debugPrint(
    '[LyricParser] detected=$format textLen=${text.length} resultLines=${result.length}',
  );
  final nonEmptyLines = text
      .split('\n')
      .where((l) => l.trim().isNotEmpty)
      .toList();
  if (nonEmptyLines.isNotEmpty) {
    debugPrint(
      '[LyricParser] firstLine="${nonEmptyLines.first.trim().substring(0, (nonEmptyLines.first.trim().length).clamp(0, 80))}"',
    );
  }
  return result;
}

class _EnhancedRawLine {
  final int timestampMs;
  final String content;

  const _EnhancedRawLine({required this.timestampMs, required this.content});
}

int _parseLrcTimestamp(String minutes, String seconds, String milliseconds) {
  var msStr = milliseconds;
  if (msStr.length == 2) msStr = '${msStr}0';
  if (msStr.length > 3) msStr = msStr.substring(0, 3);
  return int.parse(minutes) * 60000 +
      int.parse(seconds) * 1000 +
      int.parse(msStr);
}

List<LyricWord> _parseTimedWords({
  required String content,
  required int lineStartTime,
  required int lineEndTime,
  required RegExp wordRegExp,
  required String nextTagStart,
  bool wordBeforeTag = true,
}) {
  final words = <LyricWord>[];
  var remaining = content;

  while (remaining.isNotEmpty) {
    final match = wordRegExp.firstMatch(remaining);
    if (match == null) break;

    final rawWordStart = int.parse(match.group(1)!);
    final wordDuration = int.parse(match.group(2)!);
    final wordStart = _resolveTimedWordStart(
      lineStartTime: lineStartTime,
      lineEndTime: lineEndTime,
      rawStartTime: rawWordStart,
      duration: wordDuration,
    );
    final wordEnd = wordStart + wordDuration;

    if (wordBeforeTag) {
      // YRC/QRC convention: text(offset,dur) — text before tag is the word
      final textBefore = remaining.substring(0, match.start);
      remaining = remaining.substring(match.end);

      if (textBefore.isNotEmpty) {
        words.add(
          LyricWord(
            word: textBefore,
            startTimeMs: wordStart,
            endTimeMs: wordEnd,
          ),
        );
      }
    } else {
      // KRC convention: (offset,dur)text — text after tag is the word
      remaining = remaining.substring(match.end);

      String wordText = '';
      if (remaining.isNotEmpty && !remaining.startsWith(nextTagStart)) {
        final nextTag = remaining.indexOf(nextTagStart);
        if (nextTag < 0) {
          wordText = remaining;
          remaining = '';
        } else {
          wordText = remaining.substring(0, nextTag);
          remaining = remaining.substring(nextTag);
        }
      }

      if (wordText.isNotEmpty) {
        words.add(
          LyricWord(word: wordText, startTimeMs: wordStart, endTimeMs: wordEnd),
        );
      }
    }
  }

  return words;
}

int _resolveTimedWordStart({
  required int lineStartTime,
  required int lineEndTime,
  required int rawStartTime,
  required int duration,
}) {
  // CeruMusic 的所有 crlyric 来源（wy/kg/kw/mg）在产出时都已转换为绝对时间戳。
  // AMLL 的 parseYrc/parseQrc 始终按绝对时间戳处理。
  // 只有 LRCx 的原始字时间戳是行内相对值，且始终 < lineStartTime。
  // 因此仅靠 rawStartTime < lineStartTime 即可正确区分，去掉按 lineDuration 猜测的逻辑。
  if (rawStartTime < lineStartTime) {
    return lineStartTime + rawStartTime;
  }

  return rawStartTime;
}

String extractEmbeddedLyricContent(String text) {
  if (!text.contains('LyricContent=')) return text.trim();

  final match = RegExp(
    r'''LyricContent\s*=\s*(["'])([\s\S]*?)\1''',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return text.trim();

  return _decodeXmlEntities(match.group(2) ?? '').trim();
}

String _decodeXmlEntities(String text) {
  return text
      .replaceAll(r'\n', '\n')
      .replaceAll('&#10;', '\n')
      .replaceAll('&#13;', '\r')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&')
      .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
        final codePoint = int.tryParse(match.group(1)!, radix: 16);
        return codePoint == null
            ? match.group(0)!
            : String.fromCharCode(codePoint);
      })
      .replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
        final codePoint = int.tryParse(match.group(1)!);
        return codePoint == null
            ? match.group(0)!
            : String.fromCharCode(codePoint);
      });
}
