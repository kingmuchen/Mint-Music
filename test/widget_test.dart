import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mintmusic/core/theme/app_theme.dart';

// 说明：完整 App 的冒烟测试需要真实音频服务（AudioService / just_audio /
// audio_session 等平台通道），在纯 flutter_test 环境中无法运行
// （测试环境 MethodChannel 一律返回 null，会导致 AudioService 未初始化异常）。
// 因此这里只对主题层做基础冒烟测试；歌词解析等纯逻辑测试见
// lyric_parser_test.dart。
void main() {
  testWidgets('AppTheme 渲染浅色 / 深色 MaterialApp', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: const Scaffold(body: Text('薄荷音乐')),
      ),
    );
    expect(find.text('薄荷音乐'), findsOneWidget);
  });

  test('AppTheme 浅色 / 深色亮度正确', () {
    expect(AppTheme.light.brightness, Brightness.light);
    expect(AppTheme.dark.brightness, Brightness.dark);
  });
}
