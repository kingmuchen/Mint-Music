import 'han_data.dart';

/// 繁简中文转换器。
///
/// 基于 OpenCC 字典数据(opencc-js, MIT)的纯 Dart 实现:
/// - [s2t]: 简体中文 -> 繁体中文
/// - [t2s]: 繁体中文 -> 简体中文
///
/// 采用"词组最长匹配优先 + 单字兜底"的经典 OpenCC 转换策略:
/// 扫描时先从当前位置尝试最长的词组映射,未命中再回退到单字映射。
class HanConverter {
  HanConverter._();

  /// 简体 -> 繁体。
  static String s2t(String input) =>
      _convert(input, kSTPhrases, kSTCharacters, kSTMaxPhraseLen);

  /// 繁体 -> 简体。
  static String t2s(String input) =>
      _convert(input, kTSPhrases, kTSCharacters, kTSMaxPhraseLen);

  static String _convert(
    String input,
    Map<String, String> phrases,
    Map<String, String> chars,
    int maxPhraseLen,
  ) {
    if (input.isEmpty) return input;

    final buffer = StringBuffer();
    var i = 0;
    final length = input.length;

    while (i < length) {
      // 词组最长匹配:从 maxPhraseLen 递减尝试
      final remaining = length - i;
      final maxLen = remaining < maxPhraseLen ? remaining : maxPhraseLen;
      var matched = false;
      for (var len = maxLen; len >= 2; len--) {
        final key = input.substring(i, i + len);
        final value = phrases[key];
        if (value != null) {
          buffer.write(value);
          i += len;
          matched = true;
          break;
        }
      }
      if (matched) continue;

      // 单字映射兜底
      final ch = input[i];
      buffer.write(chars[ch] ?? ch);
      i++;
    }

    return buffer.toString();
  }

  /// 判断字符串是否包含 CJK 汉字(供调用方决定是否需要转换)。
  static bool containsChinese(String text) {
    for (final rune in text.runes) {
      // CJK Unified Ideographs 4E00-9FFF(含扩展判断可选)
      if (rune >= 0x4e00 && rune <= 0x9fff) return true;
    }
    return false;
  }
}
