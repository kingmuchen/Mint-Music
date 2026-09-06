import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/theme_provider.dart';
import '../application/plugin_providers.dart';
import '../data/plugin_repository.dart';
import '../domain/models/plugin_info.dart';
import 'plugin_test_dialog.dart';

class PluginManagementPage extends ConsumerStatefulWidget {
  const PluginManagementPage({super.key});

  /// 把插件加载/操作异常转成用户可读的提示，避免直接展示晦涩的
  /// "Stack Overflow" 原始错误文本（大型洛雪插件脚本递归过深时常见）。
  static String pluginErrorMessage(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '');
    if (text.contains('Stack Overflow') || text.contains('stack overflow')) {
      return tr('插件加载失败：插件脚本过大导致 JS 引擎栈溢出，请更换精简版插件');
    }
    return text;
  }

  @override
  ConsumerState<PluginManagementPage> createState() =>
      _PluginManagementPageState();
}

class _PluginManagementPageState extends ConsumerState<PluginManagementPage> {
  bool _isCheckingUpdates = false;
  StreamSubscription<Map<String, dynamic>>? _updateNoticeSubscription;

  @override
  void initState() {
    super.initState();
    // Subscribe to plugin-initiated update notices (from lx.send('updateAlert')).
    _subscribeToUpdateNotices();
    // Auto-check for updates when the page loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAllUpdates();
    });
  }

  @override
  void dispose() {
    _updateNoticeSubscription?.cancel();
    super.dispose();
  }

  void _subscribeToUpdateNotices() {
    final pluginService = ref.read(pluginServiceProvider);
    _updateNoticeSubscription = pluginService.updateNoticeStream.listen((notice) {
      if (!mounted) return;
      final pluginName = notice['pluginName'] as String? ?? tr('未知插件');
      final pluginVersion = notice['pluginVersion'] as String? ?? '';
      final pluginId = notice['pluginId'] as String? ?? '';
      final data = notice['data'];
      String log = '';
      String? updateUrl;
      if (data is Map) {
        log = data['log']?.toString() ?? '';
        updateUrl = data['updateUrl']?.toString();
      } else if (data is String) {
        log = data;
      }

      // Store the notice in the provider so the UI can show update badges.
      final existing = ref.read(pluginScriptUpdateNoticesProvider);
      if (!existing.any((n) => n['pluginId'] == pluginId)) {
        ref.read(pluginScriptUpdateNoticesProvider.notifier).state = [
          ...existing,
          notice,
        ];
      }

      _showPluginUpdateNoticeDialog(
        pluginName: pluginName,
        pluginVersion: pluginVersion,
        log: log,
        updateUrl: updateUrl,
      );
    });
  }

  void _showPluginUpdateNoticeDialog({
    required String pluginName,
    required String pluginVersion,
    required String log,
    String? updateUrl,
  }) {
    final colors = ref.read(themeColorsProvider);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: Row(
          children: [
            const Icon(Icons.system_update, color: Color(0xFF4CAF50), size: 24),
            const SizedBox(width: AppSpacing.sm),
            Text(
              ctx.tr('插件更新'),
              style: TextStyle(color: colors.textPrimary, fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  Icon(Icons.extension, color: colors.primary, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pluginName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          ctx.tr('当前版本 v$pluginVersion'),
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (log.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                log,
                style: TextStyle(color: colors.textSecondary, fontSize: 14),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.tr('关闭'), style: TextStyle(color: colors.textHint)),
          ),
          if (updateUrl != null && updateUrl.isNotEmpty)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _openUpdateUrl(updateUrl);
              },
              child: Text(
                ctx.tr('前往更新'),
                style: const TextStyle(
                  color: Color(0xFF4CAF50),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openUpdateUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url));
    } catch (e) {
      debugPrint('Failed to open update URL: $e');
    }
  }

  Future<void> _checkAllUpdates() async {
    if (_isCheckingUpdates) return;
    setState(() => _isCheckingUpdates = true);
    try {
      await ref.read(pluginsProvider.notifier).checkForUpdates();
    } catch (e) {
      // Silently handle update check errors
      debugPrint('Plugin update check failed: $e');
    } finally {
      if (mounted) setState(() => _isCheckingUpdates = false);
    }

    // Show any pending plugin-initiated update notices that arrived
    // during plugin initialization (before this page was opened).
    _showPendingPluginUpdateNotices();
  }

  void _showPendingPluginUpdateNotices() {
    // Retrieve buffered notices that arrived during plugin initialization
    // (before this page was opened). The buffer persists so repeated
    // opens of the page still show the update notification.
    final pluginService = ref.read(pluginServiceProvider);
    final pending = pluginService.getBufferedUpdateNotices();
    if (pending.isEmpty) return;
    debugPrint('[PluginManagementPage] Showing ${pending.length} buffered update notices');
    // Show dialogs sequentially with a small delay between each.
    for (final notice in pending) {
      final pluginName = notice['pluginName'] as String? ?? tr('未知插件');
      final pluginVersion = notice['pluginVersion'] as String? ?? '';
      final data = notice['data'];
      String log = '';
      String? updateUrl;
      if (data is Map) {
        log = data['log']?.toString() ?? '';
        updateUrl = data['updateUrl']?.toString();
      } else if (data is String) {
        log = data;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showPluginUpdateNoticeDialog(
            pluginName: pluginName,
            pluginVersion: pluginVersion,
            log: log,
            updateUrl: updateUrl,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeColorsProvider);
    final pluginsAsync = ref.watch(pluginsProvider);
    final updateResults = ref.watch(pluginUpdateResultsProvider);
    final scriptNotices = ref.watch(pluginScriptUpdateNoticesProvider);

    // Merge script-initiated update notices into the update results so
    // plugin cards show update badges for ALL plugin types (lx and cr).
    final mergedResults = List<PluginUpdateResult>.from(updateResults);
    for (final notice in scriptNotices) {
      final pluginId = notice['pluginId'] as String? ?? '';
      // Skip if already detected by the manual check.
      if (mergedResults.any((r) => r.plugin.id == pluginId && r.available)) continue;
      final pluginName = notice['pluginName'] as String? ?? '';
      final pluginVersion = notice['pluginVersion'] as String? ?? '';
      final data = notice['data'];
      String log = '';
      String? updateUrl;
      if (data is Map) {
        log = data['log']?.toString() ?? '';
        updateUrl = data['updateUrl']?.toString();
      } else if (data is String) {
        log = data;
      }
      // Find the matching PluginInfo from the loaded plugins list.
      final pluginInfo = pluginsAsync.valueOrNull
          ?.where((p) => p.id == pluginId)
          .firstOrNull;
      if (pluginInfo != null && log.isNotEmpty) {
        mergedResults.add(PluginUpdateResult(
          plugin: pluginInfo,
          available: true,
          remoteVersion: pluginVersion.isNotEmpty ? pluginVersion : 'latest',
          remoteCode: log,
        ));
      }
    }

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          context.tr('插件管理'),
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (_isCheckingUpdates)
            const Padding(
              padding: EdgeInsets.all(12.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: Icon(Icons.refresh, color: colors.primary),
              onPressed: _checkAllUpdates,
              tooltip: context.tr('检查更新'),
            ),
          IconButton(
            icon: Icon(Icons.add, color: colors.primary),
            onPressed: () => _showAddPluginSheet(colors),
          ),
        ],
      ),
      body: pluginsAsync.when(
        data: (plugins) => plugins.isEmpty
            ? _buildEmptyState(colors)
            :              ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.lg),
                itemCount: plugins.length,
                itemBuilder: (context, index) => _buildPluginCard(
                  colors,
                  plugins[index],
                  mergedResults,
                ),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: colors.textHint),
              const SizedBox(height: AppSpacing.md),
              Text(context.tr('加载失败'), style: TextStyle(color: colors.textHint)),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: () => ref.invalidate(pluginsProvider),
                child: Text(context.tr('重试'), style: TextStyle(color: colors.primary)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.extension,
              size: 40,
              color: colors.primary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            context.tr('暂无插件'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.tr('点击右上角 + 添加音源插件'),
            style: TextStyle(fontSize: 13, color: colors.textHint),
          ),
          const SizedBox(height: AppSpacing.lg),
          GestureDetector(
            onTap: () => _showAddPluginSheet(colors),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Text(
                context.tr('添加插件'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colors.textOnPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPluginCard(
    ThemeColors colors,
    PluginInfo plugin,
    List<PluginUpdateResult> updateResults,
  ) {
    final typeLabel = plugin.type == 'lx' ? '洛雪' : '澜音';
    final typeColor = plugin.type == 'lx'
        ? const Color(0xFF4FC3F7)
        : const Color(0xFFCE93D8);

    // Find update result for this plugin
    final updateResult = updateResults
        .where((r) => r.plugin.id == plugin.id && r.available)
        .firstOrNull;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: updateResult != null
              ? const Color(0xFF4CAF50).withValues(alpha: 0.5)
              : plugin.isEnabled
                  ? colors.primary.withValues(alpha: 0.2)
                  : colors.divider,
          width: updateResult != null ? 1.5 : (plugin.isEnabled ? 1 : 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
              0,
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: updateResult != null
                        ? const Color(0xFF4CAF50).withValues(alpha: 0.12)
                        : colors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(
                    updateResult != null
                        ? Icons.system_update
                        : Icons.extension,
                    color: updateResult != null
                        ? const Color(0xFF4CAF50)
                        : colors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              plugin.name,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: typeColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              context.tr(typeLabel),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: typeColor,
                              ),
                            ),
                          ),
                          if (updateResult != null) ...[
                            const SizedBox(width: AppSpacing.sm),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                context.tr('可更新 v${updateResult.remoteVersion}'),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF4CAF50),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${plugin.author} · v${plugin.version}',
                        style: TextStyle(fontSize: 12, color: colors.textHint),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: plugin.isEnabled,
                  onChanged: (value) {
                    _togglePlugin(plugin.id, value, colors);
                  },
                  activeTrackColor: colors.primary.withValues(alpha: 0.3),
                  activeThumbColor: colors.primary,
                ),
              ],
            ),
          ),
          if (plugin.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                0,
              ),
              child: Text(
                plugin.description,
                style: TextStyle(fontSize: 12, color: colors.textHint),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (plugin.supportedSources.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: plugin.supportedSources.map((source) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceVariant,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Text(
                      '${source.name} ${source.qualities.isNotEmpty ? "· ${source.qualities.join("/")}" : ""}',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textSecondary,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Divider(height: 1, color: colors.divider),
          SizedBox(
            height: 40,
            child: Row(
              children: [
                const SizedBox(width: AppSpacing.md),
                Icon(Icons.access_time, size: 14, color: colors.textHint),
                const SizedBox(width: 4),
                Text(
                  context.tr(
                    '${plugin.installTime.year}/${plugin.installTime.month.toString().padLeft(2, '0')}/${plugin.installTime.day.toString().padLeft(2, '0')} 安装',
                  ),
                  style: TextStyle(fontSize: 11, color: colors.textHint),
                ),
                const Spacer(),
                if (updateResult != null)
                  GestureDetector(
                    onTap: () => _showUpdateDialog(colors, updateResult),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                      child: Text(
                        context.tr('更新'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF4CAF50),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                // 插件测试仅对已启用插件显示：未启用的插件未加载运行时，
                // 测试服务无法解析其音源与音质，展示按钮只会误导用户。
                if (plugin.isEnabled)
                  GestureDetector(
                    onTap: () => _showPluginTestDialog(plugin),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                      child: Text(
                        context.tr('插件测试'),
                        style: TextStyle(fontSize: 12, color: colors.primary),
                      ),
                    ),
                  ),
                GestureDetector(
                  onTap: () => _showUninstallDialog(colors, plugin),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    child: Text(
                      context.tr('卸载'),
                      style: TextStyle(fontSize: 12, color: colors.error),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _togglePlugin(
    String pluginId,
    bool isEnabled,
    ThemeColors colors,
  ) async {
    try {
      await ref
          .read(pluginsProvider.notifier)
          .togglePlugin(pluginId, isEnabled);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(PluginManagementPage.pluginErrorMessage(error)),
          backgroundColor: colors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showAddPluginSheet(ThemeColors colors) {
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _AddPluginSheet(colors: colors, ref: ref),
    );
  }

  void _showPluginTestDialog(PluginInfo plugin) {
    showDialog(
      context: context,
      builder: (ctx) => PluginTestDialog(plugin: plugin),
    );
  }

  void _showUninstallDialog(ThemeColors colors, PluginInfo plugin) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: Text(
          ctx.tr('卸载插件'),
          style: TextStyle(color: colors.textPrimary, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ctx.tr('确定要卸载以下插件吗？'),
              style: TextStyle(color: colors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  Icon(Icons.extension, color: colors.primary, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plugin.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          'v${plugin.version} · ${plugin.author}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              ctx.tr('卸载后将删除插件文件，此操作不可撤销。'),
              style: TextStyle(fontSize: 12, color: colors.textHint),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.tr('取消'), style: TextStyle(color: colors.textHint)),
          ),
          TextButton(
            onPressed: () {
              ref.read(pluginsProvider.notifier).uninstallPlugin(plugin.id);
              // 转换文案需在 pop 之前捕获（ctx 在 pop 后失效）
              final msg = ctx.tr('插件${plugin.name}卸载成功');
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    msg,
                    style: TextStyle(color: colors.textOnPrimary),
                  ),
                  backgroundColor: colors.primary,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: Text(
              ctx.tr('卸载'),
              style: TextStyle(
                color: colors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showUpdateDialog(ThemeColors colors, PluginUpdateResult result) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: Row(
          children: [
            const Icon(Icons.system_update, color: Color(0xFF4CAF50), size: 24),
            const SizedBox(width: AppSpacing.sm),
            Text(
              ctx.tr('插件更新'),
              style: TextStyle(color: colors.textPrimary, fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  Icon(Icons.extension, color: colors.primary, size: 20),
                  const SizedBox(width: AppSpacing.sm),
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
                          result.remoteVersion != null && result.remoteVersion != 'latest'
                              ? 'v${result.plugin.version} → v${result.remoteVersion}'
                              : ctx.tr('v${result.plugin.version} → 可更新'),
                          style: TextStyle(
                            fontSize: 12,
                            color: const Color(0xFF4CAF50),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (result.remoteCode != null &&
                result.remoteCode!.isNotEmpty &&
                result.remoteCode != result.remoteVersion) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: colors.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Text(
                  result.remoteCode!,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textHint,
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Text(
              result.remoteVersion != null && result.remoteVersion != 'latest'
                  ? ctx.tr('发现新版本 v${result.remoteVersion}，是否更新？')
                  : ctx.tr('插件有新版本可用，是否更新？'),
              style: TextStyle(color: colors.textSecondary, fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.tr('取消'), style: TextStyle(color: colors.textHint)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _applyUpdate(result);
            },
            child: Text(
              ctx.tr('更新'),
              style: const TextStyle(
                color: Color(0xFF4CAF50),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _applyUpdate(PluginUpdateResult result) async {
    if (!mounted) return;
    final colors = ref.read(themeColorsProvider);

    // Show loading
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('正在更新 ${result.plugin.name}...')),
        backgroundColor: colors.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      // Uninstall old plugin
      await ref.read(pluginsProvider.notifier).uninstallPlugin(result.plugin.id);

      // Determine plugin type from the updateUrl or the existing plugin
      final type = result.plugin.type;

      // Download and install the new version from the updateUrl
      final pluginService = ref.read(pluginServiceProvider);
      final newPlugin = await pluginService.downloadAndAddPlugin(
        result.plugin.updateUrl!,
        type,
      );

      ref.invalidate(pluginInitializedProvider);
      ref.invalidate(pluginsProvider);

      // Clear buffered update notice for this plugin so it doesn't
      // show again after the page is reopened.
      ref.read(pluginServiceProvider).clearBufferedUpdateNotice(result.plugin.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr('"${newPlugin.name} v${newPlugin.version}" 更新成功'),
              style: TextStyle(color: colors.textOnPrimary),
            ),
            backgroundColor: const Color(0xFF4CAF50),
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Refresh update results
        _checkAllUpdates();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr('更新失败: ${PluginManagementPage.pluginErrorMessage(e)}'),
            ),
            backgroundColor: colors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

class _AddPluginSheet extends StatefulWidget {
  final ThemeColors colors;
  final WidgetRef ref;

  const _AddPluginSheet({required this.colors, required this.ref});

  @override
  State<_AddPluginSheet> createState() => _AddPluginSheetState();
}

class _AddPluginSheetState extends State<_AddPluginSheet> {
  int _selectedTab = 0;
  String _pluginType = 'cr';
  final _urlController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.md),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              context.tr('添加插件'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              context.tr('支持澜音(cr)和洛雪(lx)格式的JS插件'),
              style: TextStyle(fontSize: 12, color: colors.textHint),
            ),
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedTab = 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _selectedTab == 0
                              ? colors.primary.withValues(alpha: 0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          border: Border.all(
                            color: _selectedTab == 0
                                ? colors.primary
                                : colors.divider,
                          ),
                        ),
                        child: Text(
                          context.tr('从文件导入'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: _selectedTab == 0
                                ? colors.primary
                                : colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedTab = 1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _selectedTab == 1
                              ? colors.primary.withValues(alpha: 0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          border: Border.all(
                            color: _selectedTab == 1
                                ? colors.primary
                                : colors.divider,
                          ),
                        ),
                        child: Text(
                          context.tr('从URL下载'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: _selectedTab == 1
                                ? colors.primary
                                : colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                children: [
                  Text(
                    context.tr('插件类型：'),
                    style: TextStyle(fontSize: 13, color: colors.textSecondary),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  _buildTypeChip(context.tr('澜音 (cr)'), 'cr', colors),
                  const SizedBox(width: AppSpacing.sm),
                  _buildTypeChip(context.tr('洛雪 (lx)'), 'lx', colors),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_selectedTab == 0)
              _buildFileImportTab(colors)
            else
              _buildUrlDownloadTab(colors),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(String label, String type, ThemeColors colors) {
    final isSelected = _pluginType == type;
    return GestureDetector(
      onTap: () => setState(() => _pluginType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? colors.primary : colors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isSelected ? colors.textOnPrimary : colors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildFileImportTab(ThemeColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: colors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: colors.divider,
                style: BorderStyle.solid,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.upload_file,
                  size: 40,
                  color: colors.primary.withValues(alpha: 0.6),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  context.tr(
                    '选择 ${_pluginType == 'lx' ? '洛雪' : '澜音'} 格式的 .js 插件文件',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  context.tr(
                    _pluginType == 'cr'
                        ? '代码中需包含 cerumusic 关键字'
                        : '代码中需包含 lx 关键字',
                  ),
                  style: TextStyle(fontSize: 11, color: colors.textHint),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _handleFileImport,
              icon: const Icon(Icons.folder_open, size: 18),
              label: Text(context.tr('选择文件')),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.textOnPrimary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUrlDownloadTab(ThemeColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        children: [
          TextField(
            controller: _urlController,
            style: TextStyle(fontSize: 14, color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: context.tr('输入插件JS文件的URL地址'),
              hintStyle: TextStyle(fontSize: 13, color: colors.textHint),
              prefixIcon: Icon(Icons.link, color: colors.textHint, size: 20),
              suffixIcon: _urlController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, color: colors.textHint, size: 18),
                      onPressed: () {
                        _urlController.clear();
                        setState(() {});
                      },
                    )
                  : IconButton(
                      icon: Icon(
                        Icons.content_paste,
                        color: colors.primary,
                        size: 18,
                      ),
                      tooltip: context.tr('粘贴链接'),
                      onPressed: _pasteFromClipboard,
                    ),
              filled: true,
              fillColor: colors.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.full),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.full),
                borderSide: BorderSide(color: colors.primary),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            keyboardType: TextInputType.url,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.tr(
              '支持 HTTP/HTTPS 链接和 GitHub 仓库链接，将自动下载并校验插件格式',
            ),
            style: TextStyle(fontSize: 11, color: colors.textHint),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _handleUrlDownload,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.cloud_download, size: 18),
              label: Text(
                _isLoading ? context.tr('下载中...') : context.tr('下载并安装'),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.textOnPrimary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleFileImport() async {
    setState(() => _isLoading = true);
    try {
      final plugin = await widget.ref
          .read(pluginsProvider.notifier)
          .selectAndAddPlugin(_pluginType);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('"${plugin.name} v${plugin.version}" 安装成功')),
            backgroundColor: widget.colors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(PluginManagementPage.pluginErrorMessage(e)),
            backgroundColor: widget.colors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text != null && data!.text!.isNotEmpty) {
        _urlController.text = data.text!;
        setState(() {});
      }
    } catch (_) {
      // Ignore clipboard access errors
    }
  }

  Future<void> _handleUrlDownload() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('请输入URL地址')),
          backgroundColor: widget.colors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Basic URL format validation
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('请输入有效的HTTP/HTTPS链接')),
          backgroundColor: widget.colors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final plugin = await widget.ref
          .read(pluginsProvider.notifier)
          .downloadAndAddPlugin(url, _pluginType);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('"${plugin.name} v${plugin.version}" 安装成功')),
            backgroundColor: widget.colors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(PluginManagementPage.pluginErrorMessage(e)),
            backgroundColor: widget.colors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
