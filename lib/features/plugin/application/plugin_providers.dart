import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/music_source_provider.dart';
import '../domain/plugin_types.dart';
import '../data/plugin_service.dart';
import '../data/netease_music_source.dart';
import '../data/kugou_music_source.dart';
import 'music_source_manager.dart';
import 'plugin_test_service.dart';

final neteaseMusicSourceProvider = Provider<NeteaseMusicSource>((ref) {
  final source = NeteaseMusicSource();
  ref.onDispose(() => source.dispose());
  return source;
});

final kugouMusicSourceProvider = Provider<KugouMusicSource>((ref) {
  final source = KugouMusicSource();
  ref.onDispose(() => source.dispose());
  return source;
});

final musicSourceProvider = Provider<MusicSourceProvider>((ref) {
  return ref.watch(neteaseMusicSourceProvider);
});

final pluginServiceProvider = Provider<PluginService>((ref) {
  final service = PluginService();
  ref.onDispose(() => service.dispose());
  return service;
});

final pluginInitializedProvider = FutureProvider<void>((ref) async {
  final pluginService = ref.watch(pluginServiceProvider);
  print('[PluginProviders] 开始初始化插件系统...');
  await pluginService.initializePlugins();
  print('[PluginProviders] 插件系统初始化完成');
  print('[PluginProviders] 已加载插件数量: ${pluginService.enabledPlugins.length}');
  for (final plugin in pluginService.enabledPlugins) {
    print('[PluginProviders] - 插件: ${plugin.pluginInfo?.name ?? "未知"}');
    print('[PluginProviders]   源数量: ${plugin.sources.length}');
    for (final source in plugin.sources) {
      print('[PluginProviders]     - ${source.name}');
    }
    print('[PluginProviders]   源操作:');
    for (final entry in plugin.sourceActions.entries) {
      print('[PluginProviders]     - ${entry.key}: ${entry.value}');
    }
  }
});

final musicSourceManagerProvider = Provider<MusicSourceManager>((ref) {
  final pluginService = ref.watch(pluginServiceProvider);
  final manager = MusicSourceManager(pluginService);
  ref.onDispose(() => manager.dispose());
  return manager;
});

final pluginTestServiceProvider = Provider<PluginTestService>((ref) {
  return PluginTestService(
    manager: ref.watch(musicSourceManagerProvider),
    pluginService: ref.watch(pluginServiceProvider),
  );
});

final pluginSupportedSourcesProvider = Provider<List<SourceInfo>>((ref) {
  ref.watch(pluginInitializedProvider);

  final manager = ref.watch(musicSourceManagerProvider);
  final sources = manager.getPluginSupportedSources();
  print('[PluginProviders] 获取插件支持的源数量: ${sources.length}');
  for (final source in sources) {
    print('[PluginProviders]   - ${source.id}: ${source.name}');
  }
  return sources;
});

final searchSupportedSourcesProvider = Provider<List<SourceInfo>>((ref) {
  ref.watch(pluginInitializedProvider);

  final manager = ref.watch(musicSourceManagerProvider);
  final sources = manager.getSearchSupportedSources();
  print('[PluginProviders] 获取支持搜索的源数量: ${sources.length}');
  for (final source in sources) {
    print('[PluginProviders]   - ${source.id}: ${source.name}');
  }
  return sources;
});
