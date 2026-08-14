import 'dart:convert';

import '../models/lyric_line.dart';

class LyricBundle {
  final String? lrc;
  final String? crlyric;
  final String? tlyric;
  final String? rlyric;

  const LyricBundle({this.lrc, this.crlyric, this.tlyric, this.rlyric});

  bool get hasAny =>
      _hasText(lrc) ||
      _hasText(crlyric) ||
      _hasText(tlyric) ||
      _hasText(rlyric);

  bool get hasStructuredLyrics =>
      _hasText(crlyric) || _hasText(tlyric) || _hasText(rlyric);

  String? get primaryLyric => _pick(crlyric) ?? _pick(lrc);

  String? get standardLyric => _pick(lrc) ?? _pick(crlyric);

  static bool _hasText(String? value) =>
      value != null && value.trim().isNotEmpty;

  static String? _pick(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class LyricBundleCodec {
  static const marker = '[MintMusicLyricBundle:v1]';

  static String encode({
    String? lrc,
    String? crlyric,
    String? tlyric,
    String? rlyric,
  }) {
    final payload = <String, String>{
      if (_pick(lrc) != null) 'lrc': _pick(lrc)!,
      if (_pick(crlyric) != null) 'crlyric': _pick(crlyric)!,
      if (_pick(tlyric) != null) 'tlyric': _pick(tlyric)!,
      if (_pick(rlyric) != null) 'rlyric': _pick(rlyric)!,
    };
    return '$marker\n${jsonEncode(payload)}';
  }

  static String encodeResult(LyricResult result, {String? fallbackLrc}) {
    final bundle = LyricBundle(
      lrc: _pick(result.lrc) ?? _pick(fallbackLrc),
      crlyric: result.crlyric,
      tlyric: result.tlyric,
      rlyric: result.rlyric,
    );

    if (!bundle.hasStructuredLyrics) {
      return bundle.standardLyric ?? '';
    }

    return encode(
      lrc: bundle.lrc,
      crlyric: bundle.crlyric,
      tlyric: bundle.tlyric,
      rlyric: bundle.rlyric,
    );
  }

  static LyricBundle? tryDecode(String text) {
    final trimmed = text.trimLeft();
    if (!trimmed.startsWith(marker)) return null;

    final payloadText = trimmed.substring(marker.length).trim();
    if (payloadText.isEmpty) return null;

    try {
      final json = jsonDecode(payloadText);
      if (json is! Map) return null;
      return LyricBundle(
        lrc: _stringOrNull(json['lrc']),
        crlyric: _stringOrNull(json['crlyric']),
        tlyric: _stringOrNull(json['tlyric']),
        rlyric: _stringOrNull(json['rlyric']),
      );
    } catch (_) {
      return null;
    }
  }

  static String? _stringOrNull(dynamic value) {
    if (value is! String) return null;
    return _pick(value);
  }

  static String? _pick(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
