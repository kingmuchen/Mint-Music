import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/plugin_repository.dart';
import '../domain/models/plugin_info.dart';
import '../../plugin/application/plugin_providers.dart';

export '../../plugin/application/plugin_providers.dart'
    show musicSourceManagerProvider, pluginServiceProvider, pluginInitializedProvider;

final pluginRepositoryProvider = Provider<PluginRepository>((ref) {
  return PluginRepository();
});

final pluginsProvider =
    AsyncNotifierProvider<PluginsNotifier, List<PluginInfo>>(
      PluginsNotifier.new,
    );

/// Holds the results of the latest plugin update check.
final pluginUpdateResultsProvider =
    StateProvider<List<PluginUpdateResult>>((ref) => []);

class PluginsNotifier extends AsyncNotifier<List<PluginInfo>> {
  @override
  Future<List<PluginInfo>> build() async {
    final repo = ref.read(pluginRepositoryProvider);
    return repo.loadPlugins();
  }

  Future<PluginInfo> selectAndAddPlugin(String type) async {
    final pluginService = ref.read(pluginServiceProvider);
    final plugin = await pluginService.selectAndAddPlugin(type);
    ref.invalidate(pluginInitializedProvider);
    ref.invalidateSelf();
    return plugin;
  }

  Future<PluginInfo> downloadAndAddPlugin(String url, String type) async {
    final pluginService = ref.read(pluginServiceProvider);
    final plugin = await pluginService.downloadAndAddPlugin(url, type);
    ref.invalidate(pluginInitializedProvider);
    ref.invalidateSelf();
    return plugin;
  }

  Future<void> uninstallPlugin(String id) async {
    final pluginService = ref.read(pluginServiceProvider);
    await pluginService.uninstallPlugin(id);
    ref.invalidate(pluginInitializedProvider);
    ref.invalidateSelf();
  }

  Future<void> togglePlugin(String id, bool isEnabled) async {
    final previousPlugins = state.asData?.value;
    if (previousPlugins != null) {
      // Update the settings page before the plugin engine is initialized.
      // The actual runtime switch and persistence continue below.
      final optimisticPlugins = previousPlugins.map((plugin) {
        final nextIsEnabled = isEnabled
            ? plugin.id == id
            : plugin.id == id
            ? false
            : plugin.isEnabled;
        return plugin.copyWith(isEnabled: nextIsEnabled);
      }).toList();
      state = AsyncData(optimisticPlugins);
    }

    final pluginService = ref.read(pluginServiceProvider);
    try {
      await pluginService.togglePlugin(id, isEnabled);
      ref.invalidate(pluginInitializedProvider);
      final refreshedPlugins = await ref
          .read(pluginRepositoryProvider)
          .loadPlugins();
      state = AsyncData(refreshedPlugins);
    } catch (error, stackTrace) {
      if (previousPlugins != null) {
        state = AsyncData(previousPlugins);
      } else {
        state = AsyncError(error, stackTrace);
      }
      rethrow;
    }
  }

  /// Check all installed plugins for updates.
  Future<void> checkForUpdates() async {
    final repo = ref.read(pluginRepositoryProvider);
    final results = await repo.checkAllPluginUpdates();
    ref.read(pluginUpdateResultsProvider.notifier).state = results;
  }
}
