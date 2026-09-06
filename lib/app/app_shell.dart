import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/l10n/l10n.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_provider.dart';
import '../../core/utils/responsive_layout.dart';
import '../../features/player/presentation/mini_player.dart';
import '../../features/player/application/playback_controller.dart';
import '../../features/player/domain/services/cover_color_extractor.dart';
import '../../features/download/application/download_providers.dart';
import '../../features/settings/application/update_providers.dart';
import '../../features/settings/presentation/update_dialog.dart';

/// Navigation item configuration for sidebar/bottom nav.
class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String route;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.route,
  });
}

const _navItems = [
  _NavItem(icon: Icons.explore_outlined, activeIcon: Icons.explore, label: '发现', route: '/discover'),
  _NavItem(icon: Icons.library_music_outlined, activeIcon: Icons.library_music, label: '歌单', route: '/library'),
  _NavItem(icon: Icons.folder_outlined, activeIcon: Icons.folder, label: '本地', route: '/local'),
  _NavItem(icon: Icons.download_outlined, activeIcon: Icons.download, label: '下载', route: '/download'),
  _NavItem(icon: Icons.settings_outlined, activeIcon: Icons.settings, label: '设置', route: '/settings'),
];

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(playbackControllerProvider.notifier).onMessage =
          _showPlaybackMessage;
    });
    // 启动时自动检查更新（需开启「启动时检查更新」开关）
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final info = await runStartupUpdateCheck(ref);
      if (info != null && mounted) {
        await showUpdateDialog(context, info);
      }
    });
  }

  void _showPlaybackMessage(String message, {Color? backgroundColor}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor ?? Colors.grey[800],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<DownloadNotification?>(downloadNotificationProvider, (prev, next) {
      if (next != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.message),
            backgroundColor: next.backgroundColor ?? Colors.grey[800],
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
    final colors = ref.watch(themeColorsProvider);
    // 预热封面主色调：歌曲切换时就在后台 isolate 计算并缓存，
    // 用户再打开全屏播放页/歌词页时颜色已就绪，冷启动不出现
    // 「先默认色再换主题色」的跳变。
    ref.watch(currentCoverColorProvider);
    final isSettingsPage = widget.navigationShell.currentIndex == 4;
    final showSidebar = ResponsiveLayout.shouldShowSidebar(context);
    final isTablet = ResponsiveLayout.isTablet(context);

    if (showSidebar) {
      return _buildTabletLayout(colors, isSettingsPage);
    }
    return _buildPhoneLayout(colors, isSettingsPage);
  }

  /// Phone layout: bottom navigation bar (current behavior).
  Widget _buildPhoneLayout(ThemeColors colors, bool isSettingsPage) {
    return Scaffold(
      backgroundColor: colors.background,
      body: Stack(
        children: [
          RepaintBoundary(
            child: widget.navigationShell,
          ),
          if (!isSettingsPage)
            Positioned(
              left: 0,
              right: 0,
              bottom: 5,
              child: RepaintBoundary(
                child: const MiniPlayer(),
              ),
            ),
        ],
      ),
      bottomNavigationBar: RepaintBoundary(
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            boxShadow: [
              BoxShadow(
                color: colors.shadow,
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: BottomNavigationBar(
                currentIndex: widget.navigationShell.currentIndex,
                onTap: (index) => widget.navigationShell.goBranch(index),
                type: BottomNavigationBarType.fixed,
                backgroundColor: Colors.transparent,
                elevation: 0,
                selectedItemColor: colors.primary,
                unselectedItemColor: colors.textHint,
                selectedFontSize: 11,
                unselectedFontSize: 11,
                items: [
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.explore),
                    activeIcon: const Icon(Icons.explore),
                    label: context.tr('发现'),
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.library_music),
                    activeIcon: const Icon(Icons.library_music),
                    label: context.tr('歌单'),
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.folder),
                    activeIcon: const Icon(Icons.folder),
                    label: context.tr('本地'),
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.download),
                    activeIcon: const Icon(Icons.download),
                    label: context.tr('下载'),
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.settings),
                    activeIcon: const Icon(Icons.settings),
                    label: context.tr('设置'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Tablet layout: sidebar navigation + content area (inspired by Mio-Music HomeLayout).
  Widget _buildTabletLayout(ThemeColors colors, bool isSettingsPage) {
    final currentIndex = widget.navigationShell.currentIndex;
    final isLandscape = ResponsiveLayout.isLandscape(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: colors.background,
      body: Row(
        children: [
          // ── Sidebar ──────────────────────────────────────────────
          Container(
            width: isLandscape ? ResponsiveLayout.sidebarWidth : 72,
            decoration: BoxDecoration(
              color: isDark
                  ? colors.surface.withValues(alpha: 0.95)
                  : colors.surface.withValues(alpha: 0.98),
              border: Border(
                right: BorderSide(
                  color: colors.divider.withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // Logo / App title
                  if (isLandscape)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.asset(
                              'assets/images/MintMusicLogo.png',
                              width: 32,
                              height: 32,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            context.tr('薄荷音乐'),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 24),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.asset(
                          'assets/images/MintMusicLogo.png',
                          width: 36,
                          height: 36,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),

                  // Navigation items
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.symmetric(
                        horizontal: isLandscape ? 8 : 6,
                        vertical: 4,
                      ),
                      itemCount: _navItems.length,
                      itemBuilder: (context, index) {
                        final item = _navItems[index];
                        final isActive = index == currentIndex;
                        return _SidebarNavItem(
                          item: item,
                          isActive: isActive,
                          isExpanded: isLandscape,
                          colors: colors,
                          onTap: () => widget.navigationShell.goBranch(index),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Content area ─────────────────────────────────────────
          Expanded(
            child: Stack(
              children: [
                RepaintBoundary(
                  child: widget.navigationShell,
                ),
                if (!isSettingsPage)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 5,
                    child: RepaintBoundary(
                      child: const MiniPlayer(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sidebar navigation item widget.
class _SidebarNavItem extends StatelessWidget {
  final _NavItem item;
  final bool isActive;
  final bool isExpanded;
  final ThemeColors colors;
  final VoidCallback onTap;

  const _SidebarNavItem({
    required this.item,
    required this.isActive,
    required this.isExpanded,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      child: Material(
        color: isActive
            ? colors.primary.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isExpanded ? 16 : 0,
              vertical: 12,
            ),
            child: Row(
              mainAxisAlignment:
                  isExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Icon(
                  isActive ? item.activeIcon : item.icon,
                  size: 22,
                  color: isActive ? colors.primary : colors.textSecondary,
                ),
                if (isExpanded) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.tr(item.label),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                        color: isActive ? colors.primary : colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
