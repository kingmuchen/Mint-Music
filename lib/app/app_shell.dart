import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_provider.dart';
import '../../features/player/presentation/mini_player.dart';
import '../../features/player/application/playback_controller.dart';
import '../../features/player/domain/services/cover_color_extractor.dart';
import '../../features/download/application/download_providers.dart';

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
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.explore),
                    activeIcon: Icon(Icons.explore),
                    label: '发现',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.library_music),
                    activeIcon: Icon(Icons.library_music),
                    label: '歌单',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.folder),
                    activeIcon: Icon(Icons.folder),
                    label: '本地',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.download),
                    activeIcon: Icon(Icons.download),
                    label: '下载',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.settings),
                    activeIcon: Icon(Icons.settings),
                    label: '设置',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}