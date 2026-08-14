import 'package:flutter_test/flutter_test.dart';
import 'package:mintmusic/features/player/domain/services/lyric_parser.dart';

void main() {
  group('parseLrc', () {
    test('removes inline timestamp tags from lyric text', () {
      final lines = parseLrc('[00:15.000]别一个人看喜剧[00:17.111]');

      expect(lines, hasLength(1));
      expect(lines.first.plainText, '别一个人看喜剧');
    });

    test('merges translation lyric into base lines via mergeTranslation', () {
      // 双语合并由 lyric_controller 调用 mergeTranslation 完成：
      // 基础歌词与翻译歌词（tlyric）分开解析，再按时间窗合并。
      final base = parseLrc(
        '[00:10.000]别一个人看喜剧\n[00:13.000]It echoes in the room',
      );
      final merged = mergeTranslation(
        base,
        '[00:10.000]Don\'t watch comedies alone\n[00:13.000]它在房间里回响',
      );

      expect(merged, hasLength(2));
      expect(merged.first.plainText, '别一个人看喜剧');
      expect(merged.first.translatedLyric, "Don't watch comedies alone");
      expect(merged.last.plainText, 'It echoes in the room');
      expect(merged.last.translatedLyric, '它在房间里回响');
    });

    test('parses Migu style lrcx word timings', () {
      final lines = parseLyricAuto('[00:12.005]<0,180>Stay<180,160>here');

      expect(lines, hasLength(1));
      expect(lines.first.isYrc, isTrue);
      expect(lines.first.words.first.word, 'Stay');
      expect(lines.first.words.first.startTimeMs, 12005);
      expect(lines.first.words.first.endTimeMs, 12185);
      expect(lines.first.words.last.word, 'here');
    });

    test('parses YRC style word timings used by wy kg and kw', () {
      final lines = parseLyricAuto(
        '[12005,340](12005,180,0)Stay(12185,160,0)here',
      );

      expect(lines, hasLength(1));
      expect(lines.first.isYrc, isTrue);
      expect(lines.first.startTimeMs, 12005);
      expect(lines.first.words.first.word, 'Stay');
      expect(lines.first.words.last.word, 'here');
    });
  });
}
