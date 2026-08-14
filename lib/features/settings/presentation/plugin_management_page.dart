import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/theme_provider.dart';
import '../application/plugin_providers.dart';
import '../domain/models/plugin_info.dart';

class PluginManagementPage extends ConsumerStatefulWidget {
  const PluginManagementPage({super.key});

  @override
  ConsumerState<PluginManagementPage> createState() =>
      _PluginManagementPageState();
}

class _PluginManagementPageState extends ConsumerState<PluginManagementPage> {
  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeColorsProvider);
    final pluginsAsync = ref.watch(pluginsProvider);

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
          '插件管理',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: colors.primary),
            onPressed: () => _showAddPluginSheet(colors),
          ),
        ],
      ),
      body: pluginsAsync.when(
        data: (plugins) => plugins.isEmpty
            ? _buildEmptyState(colors)
            : ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.lg),
                itemCount: plugins.length,
                itemBuilder: (context, index) =>
                    _buildPluginCard(colors, plugins[index]),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: colors.textHint),
              const SizedBox(height: AppSpacing.md),
              Text('加载失败', style: TextStyle(color: colors.textHint)),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: () => ref.invalidate(pluginsProvider),
                child: Text('重试', style: TextStyle(color: colors.primary)),
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
            '暂无插件',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '点击右上角 + 添加音源插件',
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
                '添加插件',
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

  Widget _buildPluginCard(ThemeColors colors, PluginInfo plugin) {
    final typeLabel = plugin.type == 'lx' ? '洛雪' : '澜音';
    final typeColor = plugin.type == 'lx'
        ? const Color(0xFF4FC3F7)
        : const Color(0xFFCE93D8);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: plugin.isEnabled
              ? colors.primary.withValues(alpha: 0.2)
              : colors.divider,
          width: plugin.isEnabled ? 1 : 0.5,
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
                    color: colors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(Icons.extension, color: colors.primary, size: 22),
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
                              typeLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: typeColor,
                              ),
                            ),
                          ),
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
                  '${plugin.installTime.year}/${plugin.installTime.month.toString().padLeft(2, '0')}/${plugin.installTime.day.toString().padLeft(2, '0')} 安装',
                  style: TextStyle(fontSize: 11, color: colors.textHint),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _showUninstallDialog(colors, plugin),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    child: Text(
                      '卸载',
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
          content: Text(error.toString().replaceFirst('Exception: ', '')),
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

  void _showUninstallDialog(ThemeColors colors, PluginInfo plugin) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: Text(
          '卸载插件',
          style: TextStyle(color: colors.textPrimary, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '确定要卸载以下插件吗？',
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
              '卸载后将删除插件文件，此操作不可撤销。',
              style: TextStyle(fontSize: 12, color: colors.textHint),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消', style: TextStyle(color: colors.textHint)),
          ),
          TextButton(
            onPressed: () {
              ref.read(pluginsProvider.notifier).uninstallPlugin(plugin.id);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '插件${plugin.name}卸载成功',
                    style: TextStyle(color: colors.textOnPrimary),
                  ),
                  backgroundColor: colors.primary,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: Text(
              '卸载',
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
              '添加插件',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '支持澜音(cr)和洛雪(lx)格式的JS插件',
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
                          '从文件导入',
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
                          '从URL下载',
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
                    '插件类型：',
                    style: TextStyle(fontSize: 13, color: colors.textSecondary),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  _buildTypeChip('澜音 (cr)', 'cr', colors),
                  const SizedBox(width: AppSpacing.sm),
                  _buildTypeChip('洛雪 (lx)', 'lx', colors),
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
                  '选择 ${_pluginType == 'lx' ? '洛雪' : '澜音'} 格式的 .js 插件文件',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _pluginType == 'cr'
                      ? '代码中需包含 cerumusic 关键字'
                      : '代码中需包含 lx 关键字',
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
              label: const Text('选择文件'),
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
              hintText: '输入插件JS文件的URL地址',
              hintStyle: TextStyle(fontSize: 13, color: colors.textHint),
              prefixIcon: Icon(Icons.link, color: colors.textHint, size: 20),
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
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '支持 HTTP/HTTPS 链接，将自动下载并校验插件格式',
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
              label: Text(_isLoading ? '下载中...' : '下载并安装'),
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
            content: Text('"${plugin.name} v${plugin.version}" 安装成功'),
            backgroundColor: widget.colors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: widget.colors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleUrlDownload() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请输入URL地址'),
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
            content: Text('"${plugin.name} v${plugin.version}" 安装成功'),
            backgroundColor: widget.colors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
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
