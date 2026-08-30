import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/utils/responsive_layout.dart';
import '../application/settings_providers.dart';
import '../application/plugin_providers.dart';
import '../application/update_providers.dart';
import '../data/settings_service.dart';
import '../data/update_service.dart';
import 'update_dialog.dart';
import '../../player/presentation/widgets/amll_lyric_player.dart';

const _settingsSheetAnimationStyle = AnimationStyle(
  duration: Duration(milliseconds: 220),
  reverseDuration: Duration(milliseconds: 180),
);

void _persistBool(
  BuildContext context,
  StateProvider<bool> provider,
  bool value,
  Future<void> Function(SettingsService svc) saveFn,
) {
  final container = ProviderScope.containerOf(context);
  container.read(provider.notifier).state = value;
  unawaited(_doPersist(container, saveFn));
}

void _persistString(
  BuildContext context,
  StateProvider<String> provider,
  String value,
  Future<void> Function(SettingsService svc) saveFn,
) {
  final container = ProviderScope.containerOf(context);
  container.read(provider.notifier).state = value;
  unawaited(_doPersist(container, saveFn));
}

void _persistDouble(
  BuildContext context,
  StateProvider<double> provider,
  double value,
  Future<void> Function(SettingsService svc) saveFn,
) {
  final container = ProviderScope.containerOf(context);
  container.read(provider.notifier).state = value;
  unawaited(_doPersist(container, saveFn));
}

void _persistInt(
  BuildContext context,
  StateProvider<int> provider,
  int value,
  Future<void> Function(SettingsService svc) saveFn,
) {
  final container = ProviderScope.containerOf(context);
  container.read(provider.notifier).state = value;
  unawaited(_doPersist(container, saveFn));
}

Future<void> _doPersist(
  ProviderContainer container,
  Future<void> Function(SettingsService svc) saveFn,
) async {
  try {
    final svc = await container.read(settingsServiceProvider.future);
    await saveFn(svc);
  } catch (_) {}
}

enum SettingsCategory {
  appearance,
  playback,
  plugins,
  musicSource,
  storage,
  about,
}

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  SettingsCategory _activeCategory = SettingsCategory.appearance;

  /// 水平滚动控制器：用于点击标签时将选中项自动居中
  final ScrollController _tabScrollController = ScrollController();

  /// 每个标签按钮的 GlobalKey，用于测量位置
  final List<GlobalKey> _tabKeys =
      List.generate(SettingsCategory.values.length, (_) => GlobalKey());

  static const _categoryConfig = {
    SettingsCategory.appearance: (icon: Icons.palette, label: '外观设置'),
    SettingsCategory.playback: (icon: Icons.play_circle, label: '播放设置'),
    SettingsCategory.plugins: (icon: Icons.extension, label: '插件管理'),
    SettingsCategory.musicSource: (icon: Icons.music_note, label: '音乐源'),
    SettingsCategory.storage: (icon: Icons.storage, label: '存储管理'),
    SettingsCategory.about: (icon: Icons.info, label: '关于'),
  };

  @override
  void dispose() {
    _tabScrollController.dispose();
    super.dispose();
  }

  /// 点击标签后，将选中项平滑滚动到可视区域中央
  void _scrollToActiveTab() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_tabScrollController.hasClients) return;

      final index = SettingsCategory.values.indexOf(_activeCategory);
      if (index < 0 || index >= _tabKeys.length) return;

      final key = _tabKeys[index];
      final context = key.currentContext;
      if (context == null) return;

      // 获取标签按钮的位置信息
      final box = context.findRenderObject() as RenderBox?;
      if (box == null) return;

      final buttonCenter = box.localToGlobal(Offset(box.size.width / 2, 0)).dx;
      final viewportWidth =
          _tabScrollController.position.viewportDimension;
      final currentScroll = _tabScrollController.offset;

      // 计算需要滚动的距离，使按钮居中
      final targetOffset =
          currentScroll + buttonCenter - viewportWidth / 2;
      final clampedOffset = targetOffset.clamp(
        _tabScrollController.position.minScrollExtent,
        _tabScrollController.position.maxScrollExtent,
      );

      _tabScrollController.animateTo(
        clampedOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeColorsProvider);
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(colors),
            _buildCategoryTabs(colors),
            Expanded(child: _buildContent(colors)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeColors colors) {
    final isTablet = ResponsiveLayout.isTablet(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveLayout.horizontalPadding(context),
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Text(
            '设置',
            style: TextStyle(
              fontSize: isTablet ? 26 : 22,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs(ThemeColors colors) {
    return SizedBox(
      height: 48,
      child: Stack(
        children: [
          // 标签列表（可横向滚动）
          ListView(
            controller: _tabScrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            children: SettingsCategory.values.asMap().entries.map((entry) {
              final index = entry.key;
              final cat = entry.value;
              final config = _categoryConfig[cat]!;
              final isActive = _activeCategory == cat;
              return Padding(
                key: _tabKeys[index],
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: Material(
                  color: isActive ? colors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      setState(() {
                        _activeCategory = cat;
                      });
                      _scrollToActiveTab();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isActive ? colors.primary : colors.divider,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            config.icon,
                            size: 16,
                            color: isActive
                                ? Colors.white
                                : colors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            config.label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: isActive
                                  ? Colors.white
                                  : colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

        ],
      ),
    );
  }


  Widget _buildContent(ThemeColors colors) {
    // Only build the active category to avoid constructing all 6 categories
    // (and their heavy providers like plugins, directory scanning, etc.) on
    // first render, which causes a noticeable delay when navigating here.
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        ResponsiveLayout.horizontalPadding(context),
        AppSpacing.md,
        ResponsiveLayout.horizontalPadding(context),
        AppSpacing.xxxl,
      ),
      child: _buildContentForCategory(_activeCategory),
    );
  }

  Widget _buildContentForCategory(SettingsCategory cat) {
    switch (cat) {
      case SettingsCategory.appearance:
        return const _AppearanceContent();
      case SettingsCategory.playback:
        return const _PlaybackContent();
      case SettingsCategory.plugins:
        return const _PluginsContent();
      case SettingsCategory.musicSource:
        return const _MusicSourceContent();
      case SettingsCategory.storage:
        return const _StorageContent();
      case SettingsCategory.about:
        return const _AboutContent();
    }
  }

}

class _SettingGroup extends StatelessWidget {
  final String title;
  final String? subtitle;
  final ThemeColors colors;
  final List<Widget> children;
  const _SettingGroup({
    required this.title,
    this.subtitle,
    required this.colors,
    required this.children,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(fontSize: 12, color: colors.textHint),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          ...children,
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget trailing;
  final ThemeColors colors;
  final VoidCallback? onTap;
  const _SettingRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.trailing,
    required this.colors,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: colors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 14, color: colors.textPrimary),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: TextStyle(fontSize: 12, color: colors.textHint),
                    ),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _SettingDivider extends StatelessWidget {
  final ThemeColors colors;
  const _SettingDivider({required this.colors});
  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    indent: 32,
    color: colors.divider.withValues(alpha: 0.5),
  );
}

void _showBottomPicker(
  BuildContext context,
  ThemeColors colors,
  String title,
  List<String> options,
  String current,
  ValueChanged<String> onSelected,
) {
  showModalBottomSheet(
    context: context,
    sheetAnimationStyle: _settingsSheetAnimationStyle,
    backgroundColor: colors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      final maxHeight = MediaQuery.of(context).size.height * 0.6;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
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
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                ...options.map(
                  (o) => ListTile(
                    title: Text(
                      o,
                      style: TextStyle(
                        fontSize: 15,
                        color: o == current
                            ? colors.primary
                            : colors.textPrimary,
                        fontWeight: o == current
                            ? FontWeight.w500
                            : FontWeight.normal,
                      ),
                    ),
                    trailing: o == current
                        ? Icon(Icons.check, size: 20, color: colors.primary)
                        : null,
                    onTap: () {
                      onSelected(o);
                      Navigator.pop(context);
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Color _parseHexColor(String hex) {
  try {
    final code = hex.replaceFirst('#', '');
    return Color(int.parse('FF$code', radix: 16));
  } catch (_) {
    return const Color(0xFF73BCFC);
  }
}

// ==================== Appearance ====================

class _AppearanceContent extends ConsumerWidget {
  const _AppearanceContent();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeColorsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildThemeGroup(context, ref, colors),
        _buildBackgroundModeGroup(context, ref, colors),
        _buildPerformanceGroup(context, ref, colors),
      ],
    );
  }

  Widget _buildThemeGroup(
    BuildContext context,
    WidgetRef ref,
    ThemeColors colors,
  ) {
    final themeMode = ref.watch(themeModeProvider);
    final themeName = themeMode == ThemeMode.light ? '浅色主题' : '深色主题';
    final primaryHex = ref.watch(themePrimaryColorProvider);
    final presetColors = [
      ('#1DB954', 'Spotify 绿'),
      ('#6366F1', '靛蓝'),
      ('#3B82F6', '天蓝'),
      ('#EC4899', '粉红'),
      ('#F59E0B', '琥珀'),
      ('#EF4444', '红色'),
      ('#8B5CF6', '紫色'),
      ('#14B8A6', '青绿'),
      ('#F97316', '橙色'),
      ('#06B6D4', '蓝绿'),
    ];
    return _SettingGroup(
      title: '基础外观',
      subtitle: '主题和外观配置',
      colors: colors,
      children: [
        _SettingRow(
          icon: Icons.palette,
          title: '应用主题',
          subtitle: '选择应用的主题颜色',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                themeName,
                style: TextStyle(fontSize: 13, color: colors.textHint),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: colors.textHint),
            ],
          ),
          colors: colors,
          onTap: () => _showBottomPicker(
            context,
            colors,
            '选择主题',
            ['浅色主题', '深色主题'],
            themeName,
            (v) {
              final container = ProviderScope.containerOf(context);
              final mode = v == '浅色主题' ? ThemeMode.light : ThemeMode.dark;
              container.read(themeModeProvider.notifier).state = mode;
              unawaited(
                _doPersist(
                  container,
                  (s) => s.setThemeMode(
                    mode == ThemeMode.light ? 'light' : 'dark',
                  ),
                ),
              );
            },
          ),
        ),
        _SettingDivider(colors: colors),
        _SettingRow(
          icon: Icons.color_lens,
          title: '主题色',
          subtitle:
              '当前: ${presetColors.firstWhere((c) => c.$1 == primaryHex, orElse: () => (primaryHex, '自定义')).$2}',
          trailing: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _parseHexColor(primaryHex),
              border: Border.all(color: colors.divider, width: 1.5),
            ),
          ),
          colors: colors,
          onTap: () =>
              _showThemeColorPicker(context, colors, presetColors, primaryHex),
        ),
      ],
    );
  }

  void _showThemeColorPicker(
    BuildContext context,
    ThemeColors colors,
    List<(String, String)> presetColors,
    String currentHex,
  ) {
    showModalBottomSheet(
      context: context,
      sheetAnimationStyle: _settingsSheetAnimationStyle,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '选择主题色',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: presetColors.map((item) {
                  final isSelected = item.$1 == currentHex;
                  return GestureDetector(
                    onTap: () {
                      final container = ProviderScope.containerOf(context);
                      container.read(themePrimaryColorProvider.notifier).state =
                          item.$1;
                      unawaited(
                        _doPersist(
                          container,
                          (s) => s.setThemePrimaryColor(item.$1),
                        ),
                      );
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _parseHexColor(item.$1),
                        border: isSelected
                            ? Border.all(color: colors.textPrimary, width: 3)
                            : null,
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: _parseHexColor(
                                    item.$1,
                                  ).withValues(alpha: 0.4),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 24,
                            )
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackgroundModeGroup(
    BuildContext context,
    WidgetRef ref,
    ThemeColors colors,
  ) {
    final bgMode = ref.watch(fullScreenBackgroundModeProvider);
    final modeLabels = {
      FullScreenBackgroundMode.theme: '跟随主题',
      FullScreenBackgroundMode.cover: '封面模糊',
      FullScreenBackgroundMode.dark: '纯黑背景',
    };
    final currentLabel = modeLabels[bgMode] ?? '跟随主题';
    return _SettingGroup(
      title: '全屏播放背景',
      subtitle: '全屏播放页面的背景模式',
      colors: colors,
      children: [
        _SettingRow(
          icon: Icons.wallpaper,
          title: '背景模式',
          subtitle: '当前: $currentLabel',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                currentLabel,
                style: TextStyle(fontSize: 13, color: colors.textHint),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: colors.textHint),
            ],
          ),
          colors: colors,
          onTap: () => _showBottomPicker(
            context,
            colors,
            '背景模式',
            ['跟随主题', '封面模糊', '纯黑背景'],
            currentLabel,
            (v) {
              final map = {
                '跟随主题': FullScreenBackgroundMode.theme,
                '封面模糊': FullScreenBackgroundMode.cover,
                '纯黑背景': FullScreenBackgroundMode.dark,
              };
              final container = ProviderScope.containerOf(context);
              container.read(fullScreenBackgroundModeProvider.notifier).state =
                  map[v] ?? FullScreenBackgroundMode.theme;
              unawaited(
                _doPersist(
                  container,
                  (s) => s.setFullScreenBgMode(
                    v == '纯黑背景' ? 'dark' : (v == '跟随主题' ? 'theme' : 'cover'),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPerformanceGroup(
    BuildContext context,
    WidgetRef ref,
    ThemeColors colors,
  ) {
    final jumpLyric = ref.watch(appearanceJumpLyricProvider);
    final bgAnimation = ref.watch(appearanceBgAnimationProvider);
    final routePreload = ref.watch(routePreloadEnabledProvider);
    return _SettingGroup(
      title: '全屏播放-性能优化',
      subtitle: '控制全屏播放器的视觉效果和性能',
      colors: colors,
      children: [
        _SettingRow(
          icon: Icons.animation,
          title: '跳动歌词',
          subtitle: '使用弹簧引擎效果跳动歌词、占用更高的性能',
          trailing: Switch(
            value: jumpLyric,
            onChanged: (v) => _persistBool(
              context,
              appearanceJumpLyricProvider,
              v,
              (s) => s.setAppearanceJumpLyric(v),
            ),
            activeTrackColor: colors.primary.withValues(alpha: 0.3),
            activeThumbColor: colors.primary,
          ),
          colors: colors,
        ),
        _SettingDivider(colors: colors),
        _SettingRow(
          icon: Icons.motion_photos_on,
          title: '背景动画',
          subtitle: '启用布朗运动背景动画、占用更高的性能',
          trailing: Switch(
            value: bgAnimation,
            onChanged: (v) => _persistBool(
              context,
              appearanceBgAnimationProvider,
              v,
              (s) => s.setAppearanceBgAnimation(v),
            ),
            activeTrackColor: colors.primary.withValues(alpha: 0.3),
            activeThumbColor: colors.primary,
          ),
          colors: colors,
        ),
        _SettingDivider(colors: colors),
        _SettingRow(
          icon: Icons.route,
          title: '路由预加载',
          subtitle: '空闲时预加载页面组件，提升页面切换速度',
          trailing: Switch(
            value: routePreload,
            onChanged: (v) {
              _persistBool(
                context,
                routePreloadEnabledProvider,
                v,
                (s) => s.setRoutePreloadEnabled(v),
              );
              if (v) unawaited(AmllLyricPlayerState.prewarm());
            },
            activeTrackColor: colors.primary.withValues(alpha: 0.3),
            activeThumbColor: colors.primary,
          ),
          colors: colors,
        ),
      ],
    );
  }
}

// ==================== Playback ====================

class _PlaybackContent extends ConsumerWidget {
  const _PlaybackContent();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeColorsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPlaybackGroup(context, ref, colors),
        _buildEqualizerGroup(context, ref, colors),
        _buildAudioEffectGroup(context, ref, colors),
      ],
    );
  }

  Widget _buildPlaybackGroup(
    BuildContext context,
    WidgetRef ref,
    ThemeColors colors,
  ) {
    final autoQualityDowngrade = ref.watch(autoQualityDowngradeProvider);
    final autoPlay = ref.watch(autoPlayProvider);
    final rememberProgress = ref.watch(rememberProgressProvider);
    final notificationEnabled = ref.watch(notificationEnabledProvider);
    return _SettingGroup(
      title: '播放设置',
      subtitle: '播放行为和音频输出配置',
      colors: colors,
      children: [
        _SettingRow(
          icon: Icons.trending_down,
          title: '音质自动降级',
          subtitle: '当前音质失败时依次尝试更低音质，再自动换源',
          trailing: Switch(
            value: autoQualityDowngrade,
            onChanged: (v) => _persistBool(
              context,
              autoQualityDowngradeProvider,
              v,
              (s) => s.setAutoQualityDowngrade(v),
            ),
            activeTrackColor: colors.primary.withValues(alpha: 0.3),
            activeThumbColor: colors.primary,
          ),
          colors: colors,
        ),
        _SettingDivider(colors: colors),
        _SettingRow(
          icon: Icons.autorenew,
          title: '自动播放',
          subtitle: '启动时自动继续播放上次歌曲',
          trailing: Switch(
            value: autoPlay,
            onChanged: (v) {
              final container = ProviderScope.containerOf(context);
              container.read(autoPlayProvider.notifier).state = v;
              unawaited(_doPersist(container, (s) => s.setAutoPlay(v)));
            },
            activeTrackColor: colors.primary.withValues(alpha: 0.3),
            activeThumbColor: colors.primary,
          ),
          colors: colors,
        ),
        _SettingDivider(colors: colors),
        _SettingRow(
          icon: Icons.restore,
          title: '记住播放进度',
          subtitle: '退出后再次打开时继续上次进度',
          trailing: Switch(
            value: rememberProgress,
            onChanged: (v) {
              final container = ProviderScope.containerOf(context);
              container.read(rememberProgressProvider.notifier).state = v;
              unawaited(_doPersist(container, (s) => s.setRememberProgress(v)));
            },
            activeTrackColor: colors.primary.withValues(alpha: 0.3),
            activeThumbColor: colors.primary,
          ),
          colors: colors,
        ),
        _SettingDivider(colors: colors),
        _SettingRow(
          icon: Icons.notifications,
          title: '播放通知',
          subtitle: '显示播放状态通知',
          trailing: Switch(
            value: notificationEnabled,
            onChanged: (v) {
              final container = ProviderScope.containerOf(context);
              container.read(notificationEnabledProvider.notifier).state = v;
              unawaited(
                _doPersist(container, (s) => s.setNotificationEnabled(v)),
              );
            },
            activeTrackColor: colors.primary.withValues(alpha: 0.3),
            activeThumbColor: colors.primary,
          ),
          colors: colors,
        ),
      ],
    );
  }

  Widget _buildEqualizerGroup(
    BuildContext context,
    WidgetRef ref,
    ThemeColors colors,
  ) {
    final equalizerEnabled = ref.watch(equalizerEnabledProvider);
    final eqPreset = ref.watch(equalizerPresetProvider);
    final eqBands = ref.watch(equalizerBandsProvider);
    final customPresets = ref.watch(equalizerCustomPresetsProvider);
    final allPresetNames = <String>[
      ...kBuiltInPresets.map((p) => p.name),
      ...customPresets.map((p) => p['name'] as String),
    ];
    final isCustom = customPresets.any((p) => p['name'] == eqPreset);
    return _SettingGroup(
      title: '音频均衡器',
      subtitle: '调节音频频段增益 (Professional EQ)',
      colors: colors,
      children: [
        _SettingRow(
          icon: Icons.tune,
          title: '均衡器',
          subtitle: equalizerEnabled ? '开启' : '关闭',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(
                value: equalizerEnabled,
                onChanged: (v) {
                  final container = ProviderScope.containerOf(context);
                  container.read(equalizerEnabledProvider.notifier).state = v;
                  unawaited(
                    _doPersist(container, (s) => s.setEqualizerEnabled(v)),
                  );
                },
                activeTrackColor: colors.primary.withValues(alpha: 0.3),
                activeThumbColor: colors.primary,
              ),
              TextButton(
                onPressed: () => _resetEqualizer(context),
                child: Text(
                  '重置',
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ),
            ],
          ),
          colors: colors,
        ),
        _SettingDivider(colors: colors),
        _SettingRow(
          icon: Icons.graphic_eq,
          title: '均衡器预设',
          subtitle: '选择预设均衡器方案',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                eqPreset,
                style: TextStyle(fontSize: 13, color: colors.textHint),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: colors.textHint),
            ],
          ),
          colors: colors,
          onTap: () => _showBottomPicker(
            context,
            colors,
            '均衡器预设',
            allPresetNames,
            eqPreset,
            (v) => _applyEqPreset(context, v),
          ),
        ),
        _SettingDivider(colors: colors),
        ...List.generate(10, (i) {
          final freq = kEqFrequencies[i];
          final freqLabel = freq >= 1000 ? '${freq ~/ 1000}k' : '$freq';
          return Column(
            children: [
              _SettingRow(
                icon: Icons.equalizer,
                title: '$freqLabel Hz',
                subtitle: '${eqBands[i].toStringAsFixed(1)}dB',
                trailing: SizedBox(
                  width: 120,
                  child: Slider(
                    value: eqBands[i],
                    min: -12,
                    max: 12,
                    divisions: 240,
                    activeColor: colors.primary,
                    onChanged: equalizerEnabled
                        ? (v) {
                            final container = ProviderScope.containerOf(
                              context,
                            );
                            final nb = List<double>.from(eqBands);
                            nb[i] = v;
                            container
                                    .read(equalizerBandsProvider.notifier)
                                    .state =
                                nb;
                            unawaited(
                              _doPersist(
                                container,
                                (s) => s.setEqualizerBands(jsonEncode(nb)),
                              ),
                            );
                          }
                        : null,
                  ),
                ),
                colors: colors,
              ),
              if (i < 9) _SettingDivider(colors: colors),
            ],
          );
        }),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _showSavePresetDialog(context, colors),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.primary,
                  side: BorderSide(color: colors.primary),
                ),
                child: Text('保存预设'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _exportEqConfig(context, colors),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.textSecondary,
                  side: BorderSide(color: colors.divider),
                ),
                child: Text('导出配置'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _importEqConfig(context, colors),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.textSecondary,
                  side: BorderSide(color: colors.divider),
                ),
                child: Text('导入配置'),
              ),
            ),
          ],
        ),
        if (isCustom) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      _saveCurrentToPreset(context, eqPreset, eqBands),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.primary,
                    side: BorderSide(color: colors.primary),
                  ),
                  child: Text('保存到当前预设'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      _deletePreset(context, eqPreset, customPresets),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                  child: Text('删除预设'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  void _applyEqPreset(BuildContext context, String presetName) {
    final container = ProviderScope.containerOf(context);
    for (final p in kBuiltInPresets) {
      if (p.name == presetName) {
        container.read(equalizerBandsProvider.notifier).state =
            List<double>.from(p.gains);
        container.read(equalizerPresetProvider.notifier).state = presetName;
        unawaited(
          _doPersist(container, (s) async {
            await s.setEqualizerPreset(presetName);
            await s.setEqualizerBands(jsonEncode(p.gains));
          }),
        );
        return;
      }
    }
    final customPresets = container.read(equalizerCustomPresetsProvider);
    for (final p in customPresets) {
      if (p['name'] == presetName) {
        final gains = (p['gains'] as List)
            .map((value) => (value as num).toDouble())
            .toList();
        container.read(equalizerBandsProvider.notifier).state =
            List<double>.from(gains);
        container.read(equalizerPresetProvider.notifier).state = presetName;
        unawaited(
          _doPersist(container, (s) async {
            await s.setEqualizerPreset(presetName);
            await s.setEqualizerBands(jsonEncode(gains));
          }),
        );
        return;
      }
    }
  }

  void _resetEqualizer(BuildContext context) {
    final container = ProviderScope.containerOf(context);
    final presetName = container.read(equalizerPresetProvider);
    for (final p in kBuiltInPresets) {
      if (p.name == presetName) {
        container.read(equalizerBandsProvider.notifier).state =
            List<double>.from(p.gains);
        unawaited(
          _doPersist(
            container,
            (s) => s.setEqualizerBands(jsonEncode(p.gains)),
          ),
        );
        return;
      }
    }
    final customPresets = container.read(equalizerCustomPresetsProvider);
    for (final p in customPresets) {
      if (p['name'] == presetName && p['originalGains'] != null) {
        final original = (p['originalGains'] as List)
            .map((value) => (value as num).toDouble())
            .toList();
        container.read(equalizerBandsProvider.notifier).state =
            List<double>.from(original);
        unawaited(
          _doPersist(
            container,
            (s) => s.setEqualizerBands(jsonEncode(original)),
          ),
        );
        return;
      }
    }
    container.read(equalizerBandsProvider.notifier).state = List.filled(
      10,
      0.0,
    );
    unawaited(
      _doPersist(
        container,
        (s) => s.setEqualizerBands(jsonEncode(List.filled(10, 0.0))),
      ),
    );
  }

  void _showSavePresetDialog(BuildContext context, ThemeColors colors) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('保存为新预设', style: TextStyle(color: colors.textPrimary)),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: '输入预设名称',
            hintStyle: TextStyle(color: colors.textHint),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: colors.divider),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: colors.primary),
            ),
          ),
          style: TextStyle(color: colors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消', style: TextStyle(color: colors.textHint)),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              _saveNewPreset(context, name);
            },
            child: Text('保存', style: TextStyle(color: colors.primary)),
          ),
        ],
      ),
    );
  }

  void _saveNewPreset(BuildContext context, String name) {
    final container = ProviderScope.containerOf(context);
    if (kBuiltInPresets.any((p) => p.name == name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$name" 是内置预设名称'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final customPresets = List<Map<String, dynamic>>.from(
      container.read(equalizerCustomPresetsProvider),
    );
    if (customPresets.any((p) => p['name'] == name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('预设 "$name" 已存在'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final currentGains = List<double>.from(
      container.read(equalizerBandsProvider),
    );
    customPresets.add({
      'name': name,
      'gains': currentGains,
      'originalGains': List<double>.from(currentGains),
    });
    container.read(equalizerCustomPresetsProvider.notifier).state =
        customPresets;
    container.read(equalizerPresetProvider.notifier).state = name;
    unawaited(
      _doPersist(container, (s) async {
        await s.setEqualizerCustomPresets(jsonEncode(customPresets));
        await s.setEqualizerPreset(name);
      }),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('预设保存成功'), backgroundColor: Colors.green),
    );
  }

  void _saveCurrentToPreset(
    BuildContext context,
    String presetName,
    List<double> currentBands,
  ) {
    final container = ProviderScope.containerOf(context);
    final customPresets = List<Map<String, dynamic>>.from(
      container.read(equalizerCustomPresetsProvider),
    );
    for (int i = 0; i < customPresets.length; i++) {
      if (customPresets[i]['name'] == presetName) {
        customPresets[i]['gains'] = List<double>.from(currentBands);
        break;
      }
    }
    container.read(equalizerCustomPresetsProvider.notifier).state =
        customPresets;
    unawaited(
      _doPersist(
        container,
        (s) => s.setEqualizerCustomPresets(jsonEncode(customPresets)),
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已保存当前值到预设 "$presetName"'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _deletePreset(
    BuildContext context,
    String presetName,
    List<Map<String, dynamic>> customPresets,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除预设'),
        content: Text('确定要删除预设 "$presetName" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              final container = ProviderScope.containerOf(context);
              final updated = List<Map<String, dynamic>>.from(customPresets)
                ..removeWhere((p) => p['name'] == presetName);
              container.read(equalizerCustomPresetsProvider.notifier).state =
                  updated;
              container.read(equalizerPresetProvider.notifier).state =
                  'Flat(原声)';
              container.read(equalizerBandsProvider.notifier).state =
                  List.filled(10, 0.0);
              unawaited(
                _doPersist(container, (s) async {
                  await s.setEqualizerCustomPresets(jsonEncode(updated));
                  await s.setEqualizerPreset('Flat(原声)');
                  await s.setEqualizerBands(jsonEncode(List.filled(10, 0.0)));
                }),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('预设 "$presetName" 已删除'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _exportEqConfig(BuildContext context, ThemeColors colors) async {
    try {
      final container = ProviderScope.containerOf(context);
      final data = jsonEncode({
        'presets': kBuiltInPresets.map((p) => p.toJson()).toList(),
        'customPresets': container.read(equalizerCustomPresetsProvider),
        'currentPreset': container.read(equalizerPresetProvider),
        'gains': container.read(equalizerBandsProvider),
        'enabled': container.read(equalizerEnabledProvider),
      });
      final dir = await getApplicationDocumentsDirectory();
      await File('${dir.path}/mintmusic_eq_config.json').writeAsString(data);
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('均衡器配置已导出'), backgroundColor: colors.primary),
        );
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e'), backgroundColor: Colors.red),
        );
    }
  }

  Future<void> _importEqConfig(BuildContext context, ThemeColors colors) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.isEmpty) return;
      final data =
          jsonDecode(await File(result.files.single.path!).readAsString())
              as Map<String, dynamic>;
      if (!context.mounted) return;
      final container = ProviderScope.containerOf(context);
      if (data['customPresets'] != null) {
        final custom = (data['customPresets'] as List)
            .cast<Map<String, dynamic>>();
        container.read(equalizerCustomPresetsProvider.notifier).state = custom;
        unawaited(
          _doPersist(
            container,
            (s) => s.setEqualizerCustomPresets(jsonEncode(custom)),
          ),
        );
      }
      if (data['enabled'] != null) {
        container.read(equalizerEnabledProvider.notifier).state =
            data['enabled'] as bool;
        unawaited(
          _doPersist(
            container,
            (s) => s.setEqualizerEnabled(data['enabled'] as bool),
          ),
        );
      }
      if (data['gains'] != null) {
        final gains = (data['gains'] as List)
            .map((value) => (value as num).toDouble())
            .toList();
        container.read(equalizerBandsProvider.notifier).state = gains;
        unawaited(
          _doPersist(container, (s) => s.setEqualizerBands(jsonEncode(gains))),
        );
      }
      if (data['currentPreset'] != null) {
        container.read(equalizerPresetProvider.notifier).state =
            data['currentPreset'] as String;
        unawaited(
          _doPersist(
            container,
            (s) => s.setEqualizerPreset(data['currentPreset'] as String),
          ),
        );
      }
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('均衡器配置导入成功'), backgroundColor: colors.primary),
        );
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e'), backgroundColor: Colors.red),
        );
    }
  }

  Widget _buildAudioEffectGroup(
    BuildContext context,
    WidgetRef ref,
    ThemeColors colors,
  ) {
    final audioEffect = ref.watch(audioEffectEnabledProvider);
    final bassBoostEnabled = ref.watch(bassBoostEnabledProvider);
    final bassBoostGain = ref.watch(bassBoostGainProvider);
    final bassBoostPreset = ref.watch(bassBoostPresetProvider);
    final surroundEnabled = ref.watch(surroundEnabledProvider);
    final surroundMode = ref.watch(surroundModeProvider);
    final balanceEnabled = ref.watch(balanceEnabledProvider);
    final balanceValue = ref.watch(balanceValueProvider);
    final surroundLabels = {'small': '小房间', 'medium': '中厅堂', 'large': '大教堂'};
    final bassPresetLabels = {'light': '轻度', 'medium': '中度', 'heavy': '重度'};
    return _SettingGroup(
      title: '高级音效处理',
      subtitle: '低音增强、环绕音效、声道平衡',
      colors: colors,
      children: [
        _SettingRow(
          icon: Icons.graphic_eq,
          title: '音效增强',
          subtitle: '启用高级音效处理',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(
                value: audioEffect,
                onChanged: (v) => _persistBool(
                  context,
                  audioEffectEnabledProvider,
                  v,
                  (s) => s.setAudioEffectEnabled(v),
                ),
                activeTrackColor: colors.primary.withValues(alpha: 0.3),
                activeThumbColor: colors.primary,
              ),
              TextButton(
                onPressed: () => _resetAudioEffects(context),
                child: Text(
                  '重置全部',
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ),
            ],
          ),
          colors: colors,
        ),
        _SettingDivider(colors: colors),
        _SettingRow(
          icon: Icons.speaker,
          title: '低音增强 (Bass Boost)',
          subtitle: bassBoostEnabled
              ? '增益 ${bassBoostGain.toInt()}dB · ${bassPresetLabels[bassBoostPreset] ?? bassBoostPreset}'
              : '关闭',
          trailing: Switch(
            value: bassBoostEnabled,
            onChanged: (v) => _persistBool(
              context,
              bassBoostEnabledProvider,
              v,
              (s) => s.setBassBoostEnabled(v),
            ),
            activeTrackColor: colors.primary.withValues(alpha: 0.3),
            activeThumbColor: colors.primary,
          ),
          colors: colors,
        ),
        if (bassBoostEnabled) ...[
          _SettingDivider(colors: colors),
          _SettingRow(
            icon: Icons.speaker,
            title: '低频增益',
            subtitle: '${bassBoostGain.toInt()}dB',
            trailing: SizedBox(
              width: 120,
              child: Slider(
                value: bassBoostGain,
                min: -12,
                max: 12,
                divisions: 48,
                activeColor: colors.primary,
                onChanged: (v) => _persistDouble(
                  context,
                  bassBoostGainProvider,
                  v,
                  (s) => s.setBassBoostGain(v),
                ),
              ),
            ),
            colors: colors,
          ),
          _SettingDivider(colors: colors),
          _SettingRow(
            icon: Icons.tune,
            title: '低音预设',
            subtitle: '选择低音增强预设',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  bassPresetLabels[bassBoostPreset] ?? bassBoostPreset,
                  style: TextStyle(fontSize: 13, color: colors.textHint),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 18, color: colors.textHint),
              ],
            ),
            colors: colors,
            onTap: () => _showBottomPicker(
              context,
              colors,
              '低音预设',
              ['轻度', '中度', '重度'],
              bassPresetLabels[bassBoostPreset] ?? '中度',
              (v) {
                final map = {'轻度': 'light', '中度': 'medium', '重度': 'heavy'};
                final gainMap = {'light': 3.0, 'medium': 6.0, 'heavy': 9.0};
                _persistString(
                  context,
                  bassBoostPresetProvider,
                  map[v] ?? 'medium',
                  (s) => s.setBassBoostPreset(map[v] ?? 'medium'),
                );
                _persistDouble(
                  context,
                  bassBoostGainProvider,
                  gainMap[map[v]] ?? 6.0,
                  (s) => s.setBassBoostGain(gainMap[map[v]] ?? 6.0),
                );
              },
            ),
          ),
        ],
        _SettingDivider(colors: colors),
        _SettingRow(
          icon: Icons.surround_sound,
          title: '环绕音效 (Surround)',
          subtitle: surroundEnabled
              ? surroundLabels[surroundMode] ?? surroundMode
              : '关闭',
          trailing: Switch(
            value: surroundEnabled,
            onChanged: (v) => _persistBool(
              context,
              surroundEnabledProvider,
              v,
              (s) => s.setSurroundEnabled(v),
            ),
            activeTrackColor: colors.primary.withValues(alpha: 0.3),
            activeThumbColor: colors.primary,
          ),
          colors: colors,
        ),
        if (surroundEnabled) ...[
          _SettingDivider(colors: colors),
          _SettingRow(
            icon: Icons.surround_sound,
            title: '环境模拟',
            subtitle: '模拟 5.1/7.1 虚拟声场与环境混响',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  surroundLabels[surroundMode] ?? surroundMode,
                  style: TextStyle(fontSize: 13, color: colors.textHint),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 18, color: colors.textHint),
              ],
            ),
            colors: colors,
            onTap: () => _showBottomPicker(
              context,
              colors,
              '环绕模式',
              ['小房间', '中厅堂', '大教堂'],
              surroundLabels[surroundMode] ?? '小房间',
              (v) {
                final modeMap = {
                  '小房间': 'small',
                  '中厅堂': 'medium',
                  '大教堂': 'large',
                };
                _persistString(
                  context,
                  surroundModeProvider,
                  modeMap[v] ?? 'small',
                  (s) => s.setSurroundMode(modeMap[v] ?? 'small'),
                );
              },
            ),
          ),
        ],
        _SettingDivider(colors: colors),
        _SettingRow(
          icon: Icons.balance,
          title: '声道平衡 (Balance)',
          subtitle: balanceEnabled
              ? (balanceValue == 0
                    ? '居中'
                    : balanceValue < 0
                    ? '左 ${((-balanceValue) * 100).toInt()}%'
                    : '右 ${(balanceValue * 100).toInt()}%')
              : '关闭',
          trailing: Switch(
            value: balanceEnabled,
            onChanged: (v) => _persistBool(
              context,
              balanceEnabledProvider,
              v,
              (s) => s.setBalanceEnabled(v),
            ),
            activeTrackColor: colors.primary.withValues(alpha: 0.3),
            activeThumbColor: colors.primary,
          ),
          colors: colors,
        ),
        if (balanceEnabled) ...[
          _SettingDivider(colors: colors),
          _SettingRow(
            icon: Icons.balance,
            title: '平衡调节',
            subtitle: balanceValue == 0
                ? '居中'
                : balanceValue < 0
                ? '左 ${((-balanceValue) * 100).toInt()}%'
                : '右 ${(balanceValue * 100).toInt()}%',
            trailing: SizedBox(
              width: 120,
              child: Slider(
                value: balanceValue,
                min: -1,
                max: 1,
                divisions: 40,
                activeColor: colors.primary,
                onChanged: (v) => _persistDouble(
                  context,
                  balanceValueProvider,
                  v,
                  (s) => s.setBalanceValue(v),
                ),
              ),
            ),
            colors: colors,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.volume_up,
                  size: 20,
                  color: colors.textSecondary.withValues(
                    alpha: 1 - balanceValue.clamp(0, 1),
                  ),
                ),
                const SizedBox(width: 24),
                Text(
                  '😐',
                  style: TextStyle(fontSize: 20, color: colors.textPrimary),
                ),
                const SizedBox(width: 24),
                Icon(
                  Icons.volume_up,
                  size: 20,
                  color: colors.textSecondary.withValues(
                    alpha: 1 + balanceValue.clamp(-1, 0),
                  ),
                ),
              ],
            ),
          ),
          Center(
            child: TextButton(
              onPressed: () => _persistDouble(
                context,
                balanceValueProvider,
                0.0,
                (s) => s.setBalanceValue(0.0),
              ),
              child: Text(
                '居中校准',
                style: TextStyle(fontSize: 12, color: colors.primary),
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _resetAudioEffects(BuildContext context) {
    final container = ProviderScope.containerOf(context);
    container.read(bassBoostEnabledProvider.notifier).state = false;
    container.read(bassBoostGainProvider.notifier).state = 6.0;
    container.read(bassBoostPresetProvider.notifier).state = 'medium';
    container.read(surroundEnabledProvider.notifier).state = false;
    container.read(surroundModeProvider.notifier).state = 'small';
    container.read(balanceEnabledProvider.notifier).state = false;
    container.read(balanceValueProvider.notifier).state = 0.0;
    unawaited(
      _doPersist(container, (s) async {
        await s.setBassBoostEnabled(false);
        await s.setBassBoostGain(6.0);
        await s.setBassBoostPreset('medium');
        await s.setSurroundEnabled(false);
        await s.setSurroundMode('small');
        await s.setBalanceEnabled(false);
        await s.setBalanceValue(0.0);
      }),
    );
  }
}

// ==================== Plugins ====================

class _PluginsContent extends ConsumerWidget {
  const _PluginsContent();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeColorsProvider);
    final pluginsAsync = ref.watch(pluginsProvider);
    return _SettingGroup(
      title: '插件管理',
      subtitle: '管理和配置应用插件，扩展音乐播放器功能',
      colors: colors,
      children: [
        _SettingRow(
          icon: Icons.extension,
          title: '管理插件',
          subtitle: '查看和管理已安装的插件',
          trailing: Icon(Icons.chevron_right, size: 18, color: colors.textHint),
          colors: colors,
          onTap: () => context.push('/plugin-management'),
        ),
        _SettingDivider(colors: colors),
        pluginsAsync.when(
          data: (plugins) {
            if (plugins.isEmpty)
              return _SettingRow(
                icon: Icons.add_circle_outline,
                title: '添加插件',
                subtitle: '暂无已安装的插件',
                trailing: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: colors.textHint,
                ),
                colors: colors,
                onTap: () => context.push('/plugin-management'),
              );
            return Column(
              children: plugins
                  .take(3)
                  .map(
                    (plugin) => Column(
                      children: [
                        _SettingRow(
                          icon: Icons.extension,
                          title: plugin.name,
                          subtitle:
                              'v${plugin.version} · ${plugin.isEnabled ? "已启用" : "已禁用"}',
                          trailing: Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: colors.textHint,
                          ),
                          colors: colors,
                          onTap: () => context.push('/plugin-management'),
                        ),
                        if (plugin != plugins.last)
                          _SettingDivider(colors: colors),
                      ],
                    ),
                  )
                  .toList(),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (error, stack) => _SettingRow(
            icon: Icons.error_outline,
            title: '加载失败',
            subtitle: '点击重试',
            trailing: Icon(Icons.refresh, size: 18, color: colors.textHint),
            colors: colors,
            onTap: () =>
                ProviderScope.containerOf(context).invalidate(pluginsProvider),
          ),
        ),
      ],
    );
  }
}

// ==================== Music Source ====================

class _MusicSourceContent extends ConsumerWidget {
  const _MusicSourceContent();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeColorsProvider);
    final musicSource = ref.watch(musicSourceProvider);
    final sourceQuality = ref.watch(sourceQualityProvider);
    final globalQuality = ref.watch(globalQualityProvider);
    // 与全屏播放页保持一致：音质列表动态取插件声明的音质，插件未声明时回退内置默认
    final musicSourceManager = ref.watch(musicSourceManagerProvider);
    final allSources = ['网易云', 'QQ音乐', '酷狗', '酷我', '咪咕'];
    final currentQuality = sourceQuality[musicSource] ?? '320k';
    final supportedQualities = musicSourceManager.getSupportedQualitiesForSourceId(
      kSourceNameToId[musicSource] ?? 'wy',
    );
    final qualityDisplayNames = supportedQualities
        .map((q) => getQualityDisplayName(q))
        .toList();
    final currentQualityDisplay = getQualityDisplayName(currentQuality);
    final globalQualityDisplay = getQualityDisplayName(globalQuality);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingGroup(
          title: '音乐源选择',
          subtitle: '选择音乐来源和音质配置',
          colors: colors,
          children: [
            _SettingRow(
              icon: Icons.source,
              title: '默认音源',
              subtitle: '选择默认音乐来源',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    musicSource,
                    style: TextStyle(fontSize: 13, color: colors.textHint),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 18, color: colors.textHint),
                ],
              ),
              colors: colors,
              onTap: () => _showBottomPicker(
                context,
                colors,
                '选择音源',
                allSources,
                musicSource,
                (v) {
                  final container = ProviderScope.containerOf(context);
                  container.read(musicSourceProvider.notifier).state = v;
                  unawaited(_doPersist(container, (s) => s.setMusicSource(v)));
                },
              ),
            ),
            _SettingDivider(colors: colors),
            _SettingRow(
              icon: Icons.high_quality,
              title: '音质选择',
              subtitle: '$musicSource: $currentQualityDisplay',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    currentQualityDisplay,
                    style: TextStyle(fontSize: 13, color: colors.textHint),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 18, color: colors.textHint),
                ],
              ),
              colors: colors,
              onTap: () => _showBottomPicker(
                context,
                colors,
                '$musicSource 音质',
                qualityDisplayNames,
                currentQualityDisplay,
                (v) {
                  final idx = qualityDisplayNames.indexOf(v);
                  if (idx < 0) return;
                  final qualityId = supportedQualities[idx];
                  final container = ProviderScope.containerOf(context);
                  final updated = Map<String, String>.from(sourceQuality);
                  updated[musicSource] = qualityId;
                  container.read(sourceQualityProvider.notifier).state =
                      updated;
                  unawaited(
                    _doPersist(container, (s) => s.setSourceQuality(updated)),
                  );
                },
              ),
            ),
          ],
        ),
        _SettingGroup(
          title: '全局音质',
          subtitle: '一键设置所有音源的音质等级',
          colors: colors,
          children: [
            _SettingRow(
              icon: Icons.tune,
              title: '全局音质',
              subtitle: '应用到所有音源的默认音质',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    globalQualityDisplay,
                    style: TextStyle(fontSize: 13, color: colors.textHint),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 18, color: colors.textHint),
                ],
              ),
              colors: colors,
              onTap: () {
                final allQualityIds = <String>{};
                for (final src in allSources) {
                  allQualityIds.addAll(
                    musicSourceManager.getSupportedQualitiesForSourceId(
                      kSourceNameToId[src] ?? 'wy',
                    ),
                  );
                }
                final sortedIds = allQualityIds.toList();
                final sortedNames = sortedIds
                    .map((q) => getQualityDisplayName(q))
                    .toList();
                _showBottomPicker(
                  context,
                  colors,
                  '全局音质',
                  sortedNames,
                  globalQualityDisplay,
                  (v) {
                    final idx = sortedNames.indexOf(v);
                    if (idx < 0) return;
                    final qualityId = sortedIds[idx];
                    final container = ProviderScope.containerOf(context);
                    container.read(globalQualityProvider.notifier).state =
                        qualityId;
                    unawaited(
                      _doPersist(
                        container,
                        (s) => s.setGlobalQuality(qualityId),
                      ),
                    );
                  },
                );
              },
            ),
            _SettingDivider(colors: colors),
            _SettingRow(
              icon: Icons.done_all,
              title: '应用到所有音源',
              subtitle: '将全局音质 "$globalQualityDisplay" 应用到所有音源',
              trailing: OutlinedButton(
                onPressed: () {
                  final container = ProviderScope.containerOf(context);
                  final updated = <String, String>{};
                  for (final src in allSources) {
                    final supported = musicSourceManager
                        .getSupportedQualitiesForSourceId(
                          kSourceNameToId[src] ?? 'wy',
                        );
                    if (supported.contains(globalQuality)) {
                      updated[src] = globalQuality;
                    } else {
                      updated[src] = supported.isNotEmpty
                          ? supported.last
                          : '320k';
                    }
                  }
                  container.read(sourceQualityProvider.notifier).state =
                      updated;
                  unawaited(
                    _doPersist(container, (s) => s.setSourceQuality(updated)),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已将所有音源音质设置为 $globalQualityDisplay'),
                      backgroundColor: colors.primary,
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.primary,
                  side: BorderSide(color: colors.primary),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                ),
                child: Text('应用'),
              ),
              colors: colors,
            ),
          ],
        ),
        _SettingGroup(
          title: '配置状态',
          subtitle: '当前音乐源和音质配置',
          colors: colors,
          children: [
            _SettingRow(
              icon: Icons.music_note,
              title: '音乐源',
              subtitle: musicSource,
              trailing: Text(
                musicSource,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              colors: colors,
            ),
            _SettingDivider(colors: colors),
            _SettingRow(
              icon: Icons.graphic_eq,
              title: '音质',
              subtitle: currentQualityDisplay,
              trailing: Text(
                currentQualityDisplay,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              colors: colors,
            ),
            _SettingDivider(colors: colors),
            ...allSources.map(
              (src) => Column(
                children: [
                  _SettingRow(
                    icon: Icons.album,
                    title: src,
                    subtitle:
                        '音质: ${getQualityDisplayName(sourceQuality[src] ?? "320k")}',
                    trailing: Text(
                      getQualityDisplayName(sourceQuality[src] ?? '320k'),
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                    colors: colors,
                  ),
                  if (src != allSources.last) _SettingDivider(colors: colors),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ==================== Storage ====================

class _StorageContent extends ConsumerWidget {
  const _StorageContent();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeColorsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDirectoryGroup(context, ref, colors),
        _buildCacheGroup(context, ref, colors),
        _buildFilenameGroup(context, ref, colors),
        _buildTagWriteGroup(context, ref, colors),
      ],
    );
  }

  Widget _buildDirectoryGroup(
    BuildContext context,
    WidgetRef ref,
    ThemeColors colors,
  ) {
    final downloadDir = ref.watch(downloadDirProvider);
    final cacheDir = ref.watch(cacheDirProvider);
    final wifiOnly = ref.watch(wifiOnlyDownloadProvider);
    final downloadDirSize = ref.watch(downloadDirSizeProvider);
    final cacheDirSize = ref.watch(cacheDirSizeProvider);
    return _SettingGroup(
      title: '存储目录配置',
      subtitle: '缓存和下载目录设置',
      colors: colors,
      children: [
        Text(
          '缓存目录',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '用于存储歌曲缓存文件，提高播放速度',
          style: TextStyle(fontSize: 12, color: colors.textHint),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.divider.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  cacheDir.isEmpty ? '未设置' : cacheDir,
                  style: TextStyle(fontSize: 13, color: colors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: colors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: cacheDirSize.when(
                  data: (s) => Text(
                    s,
                    style: TextStyle(fontSize: 11, color: colors.primary),
                  ),
                  loading: () => Text(
                    '...',
                    style: TextStyle(fontSize: 11, color: colors.textHint),
                  ),
                  error: (e, st) => Text(
                    '0 B',
                    style: TextStyle(fontSize: 11, color: colors.textHint),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  try {
                    final result = await FilePicker.platform.getDirectoryPath();
                    if (result != null && context.mounted) {
                      final container = ProviderScope.containerOf(context);
                      container.read(cacheDirProvider.notifier).state = result;
                      unawaited(
                        _doPersist(container, (s) => s.setCacheDir(result)),
                      );
                    }
                  } catch (_) {}
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.primary,
                  side: BorderSide(color: colors.primary),
                ),
                child: Text('选择目录'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _openDirectory(cacheDir),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.textSecondary,
                  side: BorderSide(color: colors.divider),
                ),
                child: Text('打开目录'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          '下载目录',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '用于存储下载的音乐文件',
          style: TextStyle(fontSize: 12, color: colors.textHint),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.divider.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  downloadDir,
                  style: TextStyle(fontSize: 13, color: colors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.3),
                  ),
                ),
                child: downloadDirSize.when(
                  data: (s) => Text(
                    s,
                    style: TextStyle(fontSize: 11, color: Colors.green),
                  ),
                  loading: () => Text(
                    '...',
                    style: TextStyle(fontSize: 11, color: colors.textHint),
                  ),
                  error: (e, st) => Text(
                    '0 B',
                    style: TextStyle(fontSize: 11, color: colors.textHint),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  try {
                    final result = await FilePicker.platform.getDirectoryPath();
                    if (result != null && context.mounted) {
                      final container = ProviderScope.containerOf(context);
                      container.read(downloadDirProvider.notifier).state =
                          result;
                      unawaited(
                        _doPersist(container, (s) => s.setDownloadDir(result)),
                      );
                    }
                  } catch (_) {}
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.primary,
                  side: BorderSide(color: colors.primary),
                ),
                child: Text('选择目录'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _openDirectory(downloadDir),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.textSecondary,
                  side: BorderSide(color: colors.divider),
                ),
                child: Text('打开目录'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _resetDirectories(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.textSecondary,
                  side: BorderSide(color: colors.divider),
                ),
                child: Text('重置为默认'),
              ),
            ),
          ],
        ),
        _SettingDivider(colors: colors),
        _SettingRow(
          icon: Icons.wifi,
          title: '仅WiFi下载',
          subtitle: '仅在WiFi网络下下载',
          trailing: Switch(
            value: wifiOnly,
            onChanged: (v) {
              final container = ProviderScope.containerOf(context);
              container.read(wifiOnlyDownloadProvider.notifier).state = v;
              unawaited(_doPersist(container, (s) => s.setWifiOnlyDownload(v)));
            },
            activeTrackColor: colors.primary.withValues(alpha: 0.3),
            activeThumbColor: colors.primary,
          ),
          colors: colors,
        ),
      ],
    );
  }

  void _openDirectory(String path) {
    if (path.isEmpty) return;
    try {
      Process.run('explorer', [path]);
    } catch (_) {}
  }

  void _resetDirectories(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors_surface(context).surface,
        title: Text('重置目录设置', style: TextStyle(color: text_primary(context))),
        content: Text(
          '确定要重置为默认目录吗？这将清除当前的自定义目录设置。',
          style: TextStyle(color: text_secondary(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消', style: TextStyle(color: text_hint(context))),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final container = ProviderScope.containerOf(context);
              final svc = await container.read(settingsServiceProvider.future);
              final defaultDownload = '/storage/emulated/0/Music/MintMusic';
              final tempDir = await getTemporaryDirectory();
              container.read(downloadDirProvider.notifier).state =
                  defaultDownload;
              container.read(cacheDirProvider.notifier).state = tempDir.path;
              unawaited(
                _doPersist(container, (s) async {
                  await s.setDownloadDir(defaultDownload);
                  await s.setCacheDir(tempDir.path);
                }),
              );
              if (context.mounted)
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('已重置为默认目录'),
                    backgroundColor: Theme.of(context).primaryColor,
                  ),
                );
            },
            child: Text(
              '确定重置',
              style: TextStyle(color: Theme.of(context).primaryColor),
            ),
          ),
        ],
      ),
    );
  }

  ThemeColors colors_surface(BuildContext context) => ref_watch_colors(context);
  Color text_primary(BuildContext context) =>
      ref_watch_colors(context).textPrimary;
  Color text_secondary(BuildContext context) =>
      ref_watch_colors(context).textSecondary;
  Color text_hint(BuildContext context) => ref_watch_colors(context).textHint;
  ThemeColors ref_watch_colors(BuildContext context) =>
      ProviderScope.containerOf(context).read(themeColorsProvider);

  Widget _buildCacheGroup(
    BuildContext context,
    WidgetRef ref,
    ThemeColors colors,
  ) {
    final cacheSize = ref.watch(cacheSizeProvider);
    final autoCache = ref.watch(autoCacheMusicProvider);
    return _SettingGroup(
      title: '本地歌曲缓存配置',
      subtitle: '缓存管理和存储设置',
      colors: colors,
      children: [
        Row(
          children: [
            Text(
              '已有歌曲缓存大小：',
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
            Text(
              cacheSize,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => _showClearCacheDialog(context, colors),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.surface,
              foregroundColor: colors.textPrimary,
              side: BorderSide(color: colors.divider),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text('清除本地缓存'),
          ),
        ),
        _SettingDivider(colors: colors),
        _SettingRow(
          icon: Icons.cached,
          title: '自动缓存音乐',
          subtitle: '播放时自动读取/写入缓存，加速后续播放',
          trailing: Switch(
            value: autoCache,
            onChanged: (v) => _persistBool(
              context,
              autoCacheMusicProvider,
              v,
              (s) => s.setAutoCacheMusic(v),
            ),
            activeTrackColor: colors.primary.withValues(alpha: 0.3),
            activeThumbColor: colors.primary,
          ),
          colors: colors,
        ),
      ],
    );
  }

  void _showClearCacheDialog(BuildContext context, ThemeColors colors) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('清除缓存', style: TextStyle(color: colors.textPrimary)),
        content: Text(
          '确定要清除所有缓存吗？这将删除临时文件和播放历史。',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消', style: TextStyle(color: colors.textHint)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _clearCache(context);
            },
            child: Text('确定', style: TextStyle(color: colors.primary)),
          ),
        ],
      ),
    );
  }

  void _clearCache(BuildContext context) async {
    try {
      final container = ProviderScope.containerOf(context);
      final svc = await container.read(settingsServiceProvider.future);
      await svc.clearCache();
      container.read(cacheSizeProvider.notifier).state = '0 MB';
    } catch (_) {}
  }

  Widget _buildFilenameGroup(
    BuildContext context,
    WidgetRef ref,
    ThemeColors colors,
  ) {
    final filenameTemplate = ref.watch(filenameTemplateProvider);
    final preview = filenameTemplate
        .replaceAll('%t', '半岛铁盒')
        .replaceAll('%s', '周杰伦')
        .replaceAll('%a', '八度空间')
        .replaceAll('%u', 'tx')
        .replaceAll('%q', 'master')
        .replaceAll('%d', '2026-01-01');
    return _SettingGroup(
      title: '下载文件名格式设置',
      subtitle: '选择下载歌曲时要保存的文件名格式',
      colors: colors,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _buildTemplateTag(colors, '%t', '歌曲名称'),
            _buildTemplateTag(colors, '%s', '歌手'),
            _buildTemplateTag(colors, '%a', '专辑'),
            _buildTemplateTag(colors, '%u', '平台'),
            _buildTemplateTag(colors, '%q', '音质'),
            _buildTemplateTag(colors, '%d', '日期'),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: TextEditingController(text: filenameTemplate),
          onChanged: (v) {
            final container = ProviderScope.containerOf(context);
            container.read(filenameTemplateProvider.notifier).state = v.isEmpty
                ? '%t - %s'
                : v;
            unawaited(
              _doPersist(
                container,
                (s) => s.setFilenameTemplate(v.isEmpty ? '%t - %s' : v),
              ),
            );
          },
          style: TextStyle(fontSize: 14, color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: '文件名格式',
            hintStyle: TextStyle(color: colors.textHint),
            filled: true,
            fillColor: colors.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.primary),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.divider.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Text(
                '预览：',
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
              ),
              Expanded(
                child: Text(
                  preview,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTemplateTag(ThemeColors colors, String tag, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tag,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildTagWriteGroup(
    BuildContext context,
    WidgetRef ref,
    ThemeColors colors,
  ) {
    final basicInfo = ref.watch(tagWriteBasicInfoProvider);
    final cover = ref.watch(tagWriteCoverProvider);
    final lyrics = ref.watch(tagWriteLyricsProvider);
    final downloadLyrics = ref.watch(tagWriteDownloadLyricsProvider);
    final lyricFormat = ref.watch(tagWriteLyricFormatProvider);
    final enabledList = <String>[
      if (basicInfo) '基础信息',
      if (cover) '封面',
      if (lyrics) '歌词',
      if (downloadLyrics) '单独下载歌词',
    ];
    final statusText = enabledList.isNotEmpty
        ? enabledList.join('、')
        : '未选择任何选项';
    return _SettingGroup(
      title: '下载标签写入设置',
      subtitle: '选择下载歌曲时要写入的标签信息',
      colors: colors,
      children: [
        _buildTagCheckbox(
          context,
          ref,
          colors,
          Icons.info_outline,
          '基础信息',
          '包括歌曲标题、艺术家、专辑名称等基本信息',
          tagWriteBasicInfoProvider,
          (s, v) => s.setTagWriteBasicInfo(v),
        ),
        _SettingDivider(colors: colors),
        _buildTagCheckbox(
          context,
          ref,
          colors,
          Icons.image,
          '封面',
          '将专辑封面嵌入到音频文件中',
          tagWriteCoverProvider,
          (s, v) => s.setTagWriteCover(v),
        ),
        _SettingDivider(colors: colors),
        _buildTagCheckbox(
          context,
          ref,
          colors,
          Icons.lyrics,
          '歌词信息',
          '将歌词信息写入音频文件的元信息中',
          tagWriteLyricsProvider,
          (s, v) => s.setTagWriteLyrics(v),
        ),
        _SettingDivider(colors: colors),
        _buildTagCheckbox(
          context,
          ref,
          colors,
          Icons.download,
          '单独下载歌词文件',
          '在下载歌曲的同时，在相同目录下保存一个独立的LRC歌词文件',
          tagWriteDownloadLyricsProvider,
          (s, v) => s.setTagWriteDownloadLyrics(v),
        ),
        _SettingDivider(colors: colors),
        _SettingRow(
          icon: Icons.format_align_left,
          title: '歌词格式',
          subtitle: '选择写入或下载的歌词格式',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildLyricFormatChip(
                context,
                colors,
                '标准LRC',
                'lrc',
                lyricFormat,
              ),
              const SizedBox(width: 8),
              _buildLyricFormatChip(
                context,
                colors,
                '逐字歌词',
                'word-by-word',
                lyricFormat,
              ),
            ],
          ),
          colors: colors,
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.divider.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Text(
                '当前配置：',
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
              ),
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTagCheckbox(
    BuildContext context,
    WidgetRef ref,
    ThemeColors colors,
    IconData icon,
    String title,
    String desc,
    StateProvider<bool> provider,
    Future<void> Function(SettingsService, bool) saveFn,
  ) {
    final value = ref.watch(provider);
    return _SettingRow(
      icon: icon,
      title: title,
      subtitle: desc,
      trailing: Checkbox(
        value: value,
        onChanged: (v) {
          final newVal = v ?? false;
          final container = ProviderScope.containerOf(context);
          container.read(provider.notifier).state = newVal;
          unawaited(_doPersist(container, (s) => saveFn(s, newVal)));
        },
        activeColor: colors.primary,
      ),
      colors: colors,
    );
  }

  Widget _buildLyricFormatChip(
    BuildContext context,
    ThemeColors colors,
    String label,
    String value,
    String currentValue,
  ) {
    final isActive = currentValue == value;
    return GestureDetector(
      onTap: () => _persistString(
        context,
        tagWriteLyricFormatProvider,
        value,
        (s) => s.setTagWriteLyricFormat(value),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? colors.primary : colors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isActive ? colors.primary : colors.divider),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isActive ? Colors.white : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ==================== About ====================

class _AboutContent extends ConsumerStatefulWidget {
  const _AboutContent();

  @override
  ConsumerState<_AboutContent> createState() => _AboutContentState();
}

class _AboutContentState extends ConsumerState<_AboutContent> {
  bool _checkingUpdate = false;

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeColorsProvider);
    final versionAsync = ref.watch(appVersionProvider);
    final autoUpdate = ref.watch(autoUpdateProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAppHeader(context, ref, colors, versionAsync),
        _buildVersionGroup(context, ref, colors, versionAsync, autoUpdate),
        _buildTechStackGroup(colors),
        _buildLegalGroup(colors),
        _buildContactGroup(context, colors),
      ],
    );
  }

  /// 手动检查更新：拉取 GitHub 最新 release，有新版弹窗提示，否则提示已最新。
  Future<void> _checkForUpdate(BuildContext context) async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    final service = ref.read(updateServiceProvider);
    final info = await service.fetchLatestRelease();
    if (!context.mounted) return;
    setState(() => _checkingUpdate = false);
    final colors = ref.read(themeColorsProvider);

    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('检查更新失败，请稍后重试'),
          backgroundColor: colors.error,
        ),
      );
      return;
    }
    if (!UpdateService.isNewerVersion(info.version, AppConstants.appVersion)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('已是最新版本'),
          backgroundColor: colors.primary,
        ),
      );
      return;
    }
    await showUpdateDialog(context, info);
  }

  Widget _buildAppHeader(
    BuildContext context,
    WidgetRef ref,
    ThemeColors colors,
    AsyncValue<String> versionAsync,
  ) {
    return _SettingGroup(
      title: '应用信息',
      colors: colors,
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                'assets/images/MintMusicLogo.png',
                width: 64,
                height: 64,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Mint Music',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: colors.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: versionAsync.when(
                          data: (v) => Text(
                            'v$v',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colors.primary,
                            ),
                          ),
                          loading: () => Text(
                            '...',
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textHint,
                            ),
                          ),
                          error: (e, st) => Text(
                            'v1.0.0',
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textHint,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '薄荷音乐',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Mint Music 是一个跨平台的音乐播放器应用，支持基于合规插件获取公开音乐信息与播放功能。',
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVersionGroup(
    BuildContext context,
    WidgetRef ref,
    ThemeColors colors,
    AsyncValue<String> versionAsync,
    bool autoUpdate,
  ) {
    return _SettingGroup(
      title: '版本信息',
      subtitle: '应用版本和更新设置',
      colors: colors,
      children: [
        _SettingRow(
          icon: Icons.info_outline,
          title: '应用版本',
          subtitle: '当前安装的版本',
          trailing: versionAsync.when(
            data: (v) => Text(
              'v$v',
              style: TextStyle(fontSize: 13, color: colors.textHint),
            ),
            loading: () => const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            error: (e, st) => Text(
              'v1.0.0',
              style: TextStyle(fontSize: 13, color: colors.textHint),
            ),
          ),
          colors: colors,
        ),
        _SettingDivider(colors: colors),
        _SettingRow(
          icon: Icons.update,
          title: '启动时检查更新',
          subtitle: '应用启动时自动检查新版本',
          trailing: Switch(
            value: autoUpdate,
            onChanged: (v) => _persistBool(
              context,
              autoUpdateProvider,
              v,
              (s) => s.setAutoUpdate(v),
            ),
            activeTrackColor: colors.primary.withValues(alpha: 0.3),
            activeThumbColor: colors.primary,
          ),
          colors: colors,
        ),
        _SettingDivider(colors: colors),
        _SettingRow(
          icon: Icons.refresh,
          title: '检查更新',
          subtitle: '手动检查是否有新版本',
          trailing: _checkingUpdate
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.chevron_right, size: 18, color: colors.textHint),
          colors: colors,
          onTap: _checkingUpdate ? null : () => _checkForUpdate(context),
        ),
      ],
    );
  }

  Widget _buildTechStackGroup(ThemeColors colors) {
    final techItems = [
      ('Flutter', '跨平台UI框架'),
      ('Dart', '高效编程语言'),
      ('Riverpod', '状态管理工具'),
      ('Just Audio', '音频播放引擎'),
      ('Isar', '本地数据库'),
      ('Go Router', '路由导航框架'),
    ];
    return _SettingGroup(
      title: '技术栈',
      subtitle: 'Mint Music 使用的核心技术',
      colors: colors,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: techItems.map((item) {
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colors.divider.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.$1,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    item.$2,
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildLegalGroup(ThemeColors colors) {
    return _SettingGroup(
      title: '法律声明',
      subtitle: '使用条款与免责声明',
      colors: colors,
      children: [
        _buildLegalItem(
          colors,
          '数据与内容责任',
          '本项目不直接获取、存储、传输任何音乐数据或版权内容，仅提供插件运行框架。用户通过插件获取的所有数据，其合法性由插件提供者及用户自行负责。',
        ),
        const SizedBox(height: 12),
        _buildLegalItem(
          colors,
          '版权合规要求',
          '用户承诺仅通过合规插件获取音乐相关信息，且获取、使用版权内容的行为符合相关法律法规，不侵犯任何第三方合法权益。',
        ),
        const SizedBox(height: 12),
        _buildLegalItem(
          colors,
          '使用限制',
          '本项目仅允许用于非商业、纯技术学习目的，禁止用于任何商业运营、盈利活动，禁止修改后用于侵犯第三方权益的场景。',
        ),
      ],
    );
  }

  Widget _buildLegalItem(ThemeColors colors, String title, String content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.divider.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            content,
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('无法打开链接: $url'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildContactGroup(BuildContext context, ThemeColors colors) {
    return _SettingGroup(
      title: '联系方式',
      subtitle: '如有技术问题或合作意向，请通过以下方式联系',
      colors: colors,
      children: [
        _SettingRow(
          icon: Icons.forum,
          title: '问题反馈',
          subtitle: '提交 Bug 或功能建议',
          trailing: Icon(Icons.open_in_new, size: 18, color: colors.textHint),
          colors: colors,
          onTap: () => _openUrl(
            context,
            'https://github.com/kingmuchen/Mint-Music/issues',
          ),
        ),
        _SettingDivider(colors: colors),
        _SettingRow(
          icon: Icons.language,
          title: '官方网站',
          subtitle: '访问项目主页',
          trailing: Icon(Icons.open_in_new, size: 18, color: colors.textHint),
          colors: colors,
          onTap: () => _openUrl(context, 'https://kingmc.mintmusic.ccwu.cc'),
        ),
        _SettingDivider(colors: colors),
        _SettingRow(
          icon: Icons.code,
          title: '开源仓库',
          subtitle: '查看源代码',
          trailing: Icon(Icons.open_in_new, size: 18, color: colors.textHint),
          colors: colors,
          onTap: () => _openUrl(context, 'https://github.com/kingmuchen/Mint-Music'),
        ),
      ],
    );
  }
}
