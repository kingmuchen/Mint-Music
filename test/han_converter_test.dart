import 'package:flutter_test/flutter_test.dart';
import 'package:mintmusic/core/l10n/han_converter.dart';

void main() {
  group('HanConverter.s2t', () {
    test('单字与词组转换', () {
      expect(HanConverter.s2t('简体中文'), '簡體中文');
      expect(HanConverter.s2t('繁体中文'), '繁體中文');
      expect(HanConverter.s2t('头发'), '頭髮');
      expect(HanConverter.s2t('后面'), '後面');
      expect(HanConverter.s2t('干'), '幹'); // 独立字默认取常用义
      expect(HanConverter.s2t('干净'), '乾淨');
    });

    test('非中文字符原样通过', () {
      expect(HanConverter.s2t('Hello 123 !'), 'Hello 123 !');
      expect(HanConverter.s2t('あいう'), 'あいう');
    });

    test('繁体输入幂等（不破坏已繁体文本）', () {
      expect(HanConverter.s2t('繁體中文'), '繁體中文');
      expect(HanConverter.s2t('音樂'), '音樂');
    });

    test('空串', () {
      expect(HanConverter.s2t(''), '');
    });

    test('混排文本', () {
      expect(HanConverter.s2t('周杰伦的《晴天》 2003年'), '周杰倫的《晴天》 2003年');
    });
  });

  group('HanConverter.t2s', () {
    test('繁体转简体', () {
      expect(HanConverter.t2s('繁體中文'), '繁体中文');
      expect(HanConverter.t2s('頭髮'), '头发');
    });
  });

  group('HanConverter.containsChinese', () {
    test('检测汉字', () {
      expect(HanConverter.containsChinese('中文'), isTrue);
      expect(HanConverter.containsChinese('abc'), isFalse);
      expect(HanConverter.containsChinese('123'), isFalse);
    });
  });
}
