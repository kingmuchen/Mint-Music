class LyricWord {
  final String word;
  final int startTimeMs;
  final int endTimeMs;
  final String? romanWord;

  const LyricWord({
    required this.word,
    required this.startTimeMs,
    required this.endTimeMs,
    this.romanWord,
  });

  int get durationMs => endTimeMs - startTimeMs;

  LyricWord copyWith({
    String? word,
    int? startTimeMs,
    int? endTimeMs,
    String? romanWord,
  }) {
    return LyricWord(
      word: word ?? this.word,
      startTimeMs: startTimeMs ?? this.startTimeMs,
      endTimeMs: endTimeMs ?? this.endTimeMs,
      romanWord: romanWord ?? this.romanWord,
    );
  }
}

class LyricLine {
  final int startTimeMs;
  final int endTimeMs;
  final List<LyricWord> words;
  final String? translatedLyric;
  final String? romanLyric;
  final String? adLibText;
  final bool isBG;
  final bool isDuet;

  const LyricLine({
    required this.startTimeMs,
    required this.endTimeMs,
    required this.words,
    this.translatedLyric,
    this.romanLyric,
    this.adLibText,
    this.isBG = false,
    this.isDuet = false,
  });

  bool get isYrc => words.length > 1;

  String get plainText => words.map((w) => w.word).join();

  Duration get startTime => Duration(milliseconds: startTimeMs);

  Duration get endTime => Duration(milliseconds: endTimeMs);

  LyricLine copyWith({
    int? startTimeMs,
    int? endTimeMs,
    List<LyricWord>? words,
    String? translatedLyric,
    String? romanLyric,
    String? adLibText,
    bool? isBG,
    bool? isDuet,
  }) {
    return LyricLine(
      startTimeMs: startTimeMs ?? this.startTimeMs,
      endTimeMs: endTimeMs ?? this.endTimeMs,
      words: words ?? this.words,
      translatedLyric: translatedLyric ?? this.translatedLyric,
      romanLyric: romanLyric ?? this.romanLyric,
      adLibText: adLibText ?? this.adLibText,
      isBG: isBG ?? this.isBG,
      isDuet: isDuet ?? this.isDuet,
    );
  }
}

class LyricResult {
  final String? lrc;
  final String? crlyric;
  final String? tlyric;
  final String? rlyric;

  const LyricResult({this.lrc, this.crlyric, this.tlyric, this.rlyric});
}
