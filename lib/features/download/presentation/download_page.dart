import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_provider.dart';
import '../application/download_providers.dart';
import '../domain/models/download_task.dart';

class DownloadPage extends ConsumerStatefulWidget {
  const DownloadPage({super.key});

  @override
  ConsumerState<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends ConsumerState<DownloadPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeColorsProvider);
    final stats = ref.watch(downloadStatsProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(colors, stats),
            _buildTabBar(colors, stats),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildDownloadingTab(colors),
                  _buildCompletedTab(colors),
                  _buildFailedTab(colors),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeColors colors, dynamic stats) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.tr('下载管理'),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
          ),
          // 全部暂停
          if (stats.downloading > 0)
            _buildActionButton(
              colors,
              icon: Icons.pause_circle,
              label: context.tr('全部暂停'),
              onTap: () => ref.read(downloadRepositoryProvider).pauseAllTasks(),
            ),
          const SizedBox(width: AppSpacing.sm),
          // 全部开始
          if (stats.downloading == 0 && stats.failed == 0)
            _buildActionButton(
              colors,
              icon: Icons.play_circle,
              label: context.tr('全部开始'),
              onTap: () => ref.read(downloadRepositoryProvider).resumeAllTasks(),
            ),
        ],
      ),
    );
  }

  Widget _buildActionButton(ThemeColors colors, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: colors.primary),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: colors.primary)),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar(ThemeColors colors, dynamic stats) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: colors.primary,
          borderRadius: BorderRadius.circular(12),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: colors.textSecondary,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 13),
        dividerColor: Colors.transparent,
        tabs: [
          Tab(text: context.tr('进行中 (${stats.downloading})')),
          Tab(text: context.tr('已完成 (${stats.completed})')),
          Tab(text: context.tr('失败 (${stats.failed})')),
        ],
      ),
    );
  }

  // ==================== 进行中 Tab ====================

  Widget _buildDownloadingTab(ThemeColors colors) {
    final tasksAsync = ref.watch(downloadTasksProvider);
    return tasksAsync.when(
      data: (tasks) {
        final activeTasks = tasks.where((t) =>
            t.status == DownloadStatus.downloading ||
            t.status == DownloadStatus.queued ||
            t.status == DownloadStatus.paused).toList();
        // 排序：下载中 > 等待中 > 暂停
        activeTasks.sort((a, b) {
          final aOrder = _statusOrder(a.status);
          final bOrder = _statusOrder(b.status);
          if (aOrder != bOrder) return aOrder.compareTo(bOrder);
          return a.priority.compareTo(b.priority);
        });

        if (activeTasks.isEmpty) {
          return _buildEmptyState(colors, Icons.download, context.tr('暂无进行中的下载'));
        }
        return _buildTaskList(colors, activeTasks, showProgress: true);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _buildEmptyState(colors, Icons.error, context.tr('加载失败')),
    );
  }

  // ==================== 已完成 Tab ====================

  Widget _buildCompletedTab(ThemeColors colors) {
    final tasksAsync = ref.watch(downloadTasksProvider);
    return tasksAsync.when(
      data: (tasks) {
        final completedTasks = tasks
            .where((t) => t.status == DownloadStatus.completed)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        if (completedTasks.isEmpty) {
          return _buildEmptyState(colors, Icons.check_circle, context.tr('暂无已完成的下载'));
        }
        return _buildTaskList(colors, completedTasks);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _buildEmptyState(colors, Icons.error, context.tr('加载失败')),
    );
  }

  // ==================== 失败 Tab ====================

  Widget _buildFailedTab(ThemeColors colors) {
    final tasksAsync = ref.watch(downloadTasksProvider);
    return tasksAsync.when(
      data: (tasks) {
        final failedTasks = tasks
            .where((t) =>
                t.status == DownloadStatus.error ||
                t.status == DownloadStatus.cancelled)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        if (failedTasks.isEmpty) {
          return _buildEmptyState(colors, Icons.cancel, context.tr('暂无失败的任务'));
        }
        return _buildTaskList(colors, failedTasks, showRetry: true);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _buildEmptyState(colors, Icons.error, context.tr('加载失败')),
    );
  }

  // ==================== 共用组件 ====================

  Widget _buildEmptyState(ThemeColors colors, IconData icon, String text) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: colors.textHint),
          const SizedBox(height: AppSpacing.md),
          Text(text, style: TextStyle(fontSize: 14, color: colors.textHint)),
        ],
      ),
    );
  }

  Widget _buildTaskList(ThemeColors colors, List<DownloadTask> tasks, {
    bool showProgress = false,
    bool showRetry = false,
  }) {
    return ListView.builder(
      padding: const EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.md,
        bottom: AppSpacing.xxxl,
      ),
      itemCount: tasks.length,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return _buildTaskItem(colors, task,
            showProgress: showProgress, showRetry: showRetry);
      },
    );
  }

  Widget _buildTaskItem(ThemeColors colors, DownloadTask task, {
    bool showProgress = false,
    bool showRetry = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.music_note, size: 20, color: colors.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${task.song.title} - ${task.song.artist}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (task.error != null)
                        Text(
                          task.error!,
                          style: TextStyle(fontSize: 11, color: colors.error),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                _buildStatusWidget(task, colors, showRetry: showRetry),
              ],
            ),
            if (showProgress && task.status == DownloadStatus.downloading) ...[
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: task.progress,
                  backgroundColor: colors.disabled,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                  minHeight: 4,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(task.progress * 100).toStringAsFixed(0)}%  ${_formatSpeed(task.speed)}',
                    style: TextStyle(fontSize: 11, color: colors.textHint),
                  ),
                  Text(
                    '${_formatSize(task.downloadedSize)}/${_formatSize(task.totalSize)}  ${_formatRemaining(context, task.remainingTime)}',
                    style: TextStyle(fontSize: 11, color: colors.textHint),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusWidget(DownloadTask task, ThemeColors colors, {bool showRetry = false}) {
    switch (task.status) {
      case DownloadStatus.completed:
        return Icon(Icons.check_circle, size: 20, color: colors.primary);
      case DownloadStatus.downloading:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => ref.read(downloadRepositoryProvider).pauseTask(task.id),
              child: Icon(Icons.pause_circle, size: 22, color: colors.textSecondary),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => ref.read(downloadRepositoryProvider).cancelTask(task.id),
              child: Icon(Icons.close, size: 18, color: colors.textHint),
            ),
          ],
        );
      case DownloadStatus.queued:
        return GestureDetector(
          onTap: () => ref.read(downloadRepositoryProvider).cancelTask(task.id),
          child: Icon(Icons.close, size: 18, color: colors.textHint),
        );
      case DownloadStatus.paused:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => ref.read(downloadRepositoryProvider).resumeTask(task.id),
              child: Icon(Icons.play_circle, size: 22, color: colors.primary),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => ref.read(downloadRepositoryProvider).deleteTask(task.id),
              child: Icon(Icons.delete, size: 18, color: colors.textHint),
            ),
          ],
        );
      case DownloadStatus.error:
        if (showRetry) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => ref.read(downloadRepositoryProvider).retryTask(task.id),
                child: Icon(Icons.refresh, size: 20, color: colors.primary),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => ref.read(downloadRepositoryProvider).deleteTask(task.id),
                child: Icon(Icons.delete, size: 18, color: colors.textHint),
              ),
            ],
          );
        }
        return Icon(Icons.error, size: 20, color: colors.error);
      case DownloadStatus.cancelled:
        return GestureDetector(
          onTap: () => ref.read(downloadRepositoryProvider).deleteTask(task.id),
          child: Icon(Icons.delete, size: 18, color: colors.textHint),
        );
    }
  }

  int _statusOrder(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.downloading:
        return 0;
      case DownloadStatus.queued:
        return 1;
      case DownloadStatus.paused:
        return 2;
      default:
        return 3;
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '';
    if (bytesPerSec < 1024) return '${bytesPerSec.toStringAsFixed(0)} B/s';
    if (bytesPerSec < 1024 * 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  String _formatRemaining(BuildContext context, int? seconds) {
    if (seconds == null || seconds <= 0) return '';
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    if (mins > 0) return context.tr('剩余 ${mins}分${secs}秒');
    return context.tr('剩余 ${secs}秒');
  }
}
