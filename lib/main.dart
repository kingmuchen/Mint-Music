import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'core/services/audio_service_init.dart';
import 'features/settings/application/settings_providers.dart';
import 'shared/services/amll_toggle_service.dart';
import 'features/player/presentation/widgets/amll_lyric_player.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A large unbounded decoded-image cache causes memory pressure and GC jank
  // after browsing many playlists on lower-end devices. Cover widgets keep
  // their own small byte cache, so a bounded framework cache is sufficient.
  PaintingBinding.instance.imageCache.maximumSize = 120;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 48 << 20;

  HttpOverrides.global = _NeteaseImageHttpOverrides();

  print('>>> main: 开始初始化音频服务...');

  try {
    await initAudioService().timeout(const Duration(seconds: 10));
    print('>>> main: 音频服务初始化成功');
  } catch (e, stack) {
    print('>>> main: 音频服务初始化失败: $e');
    print('>>> main: 堆栈: $stack');
  }

  print('>>> main: 设置初始化...');

  final container = ProviderContainer();
  try {
    await container
        .read(settingsInitProvider.future)
        .timeout(const Duration(seconds: 5));
    print('>>> main: 设置初始化成功');
  } catch (e, stack) {
    print('>>> main: 设置初始化失败: $e');
    print('>>> main: 堆栈: $stack');
  }

  // 初始化 AMLL 开关
  await AmllToggleService().loadFromPrefs();
  print('>>> main: AMLL toggle loaded: ${AmllToggleService().enabled}');

  // Route preload is an idle-time optimization controlled by settings. It
  // only prepares the cached AMLL document; no WebView or audio resource is
  // created until the lyric route is actually shown.
  if (container.read(routePreloadEnabledProvider)) {
    unawaited(AmllLyricPlayerState.prewarm());
  }

  print('>>> main: 启动应用...');
  runApp(UncontrolledProviderScope(container: container, child: const App()));
}

class _NeteaseImageHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)..userAgent = null;
  }
}
