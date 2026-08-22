import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_provider.dart';
import '../core/router/app_router.dart';
import '../features/plugin/application/plugin_providers.dart';
import '../features/settings/application/plugin_providers.dart';
import '../features/settings/data/plugin_repository.dart';

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  bool _hasCheckedUpdates = false;

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    // Listen for plugin initialization completion to trigger update check
    ref.listen(pluginInitializedProvider, (previous, next) {
      next.whenData((_) {
        if (!_hasCheckedUpdates) {
          _hasCheckedUpdates = true;
          _checkPluginsForUpdates();
        }
      });
    });

    // Also check if plugins were already initialized (e.g. on hot reload)
    final pluginState = ref.watch(pluginInitializedProvider);
    if (pluginState.hasValue && !_hasCheckedUpdates) {
      _hasCheckedUpdates = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkPluginsForUpdates();
      });
    }

    return MaterialApp.router(
      title: '薄荷音乐',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: appRouter,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: MediaQuery.of(context).textScaler,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }

  Future<void> _checkPluginsForUpdates() async {
    if (!mounted) return;
    try {
      final repo = PluginRepository();
      final results = await repo.checkAllPluginUpdates();
      final available = results.where((r) => r.available).toList();

      if (available.isNotEmpty && mounted) {
        _showUpdateNotificationDialog(available);
      }
    } catch (e) {
      debugPrint('App startup plugin update check failed: $e');
    }
  }

  void _showUpdateNotificationDialog(List<PluginUpdateResult> updates) {
    if (!mounted) return;
    final colors = ref.read(themeColorsProvider);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            const Icon(Icons.system_update, color: Color(0xFF4CAF50), size: 24),
            const SizedBox(width: 8),
            Text(
              '插件更新',
              style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '发现 ${updates.length} 个插件可更新：',
                style: TextStyle(color: colors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 12),
              ...updates.map((result) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.extension, color: colors.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            result.plugin.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: colors.textPrimary,
                            ),
                          ),
                          Text(
                            'v${result.plugin.version} → v${result.remoteVersion}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF4CAF50),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
              const SizedBox(height: 4),
              Text(
                '前往 插件管理 页面可进行更新操作。',
                style: TextStyle(fontSize: 12, color: colors.textHint),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('稍后', style: TextStyle(color: colors.textHint)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Navigate to plugin management page
              GoRouter.of(context).push('/plugin-management');
            },
            child: const Text(
              '去更新',
              style: TextStyle(
                color: Color(0xFF4CAF50),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
