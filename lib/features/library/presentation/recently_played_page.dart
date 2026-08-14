import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../shared/widgets/music_cover_image.dart';
import '../application/recently_played_providers.dart';
import '../../player/application/playback_controller.dart';
import '../../player/domain/models/song.dart';

class RecentlyPlayedPage extends ConsumerWidget {
  const RecentlyPlayedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeColorsProvider);
    final historyAsync = ref.watch(recentlyPlayedProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, colors, ref),
            Expanded(
              child: historyAsync.when(
                data: (history) => history.isEmpty
                    ? _buildEmptyState(colors)
                    : _buildHistoryList(context, ref, colors, history),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => Center(
                  child: Text('加载失败', style: TextStyle(color: colors.textHint)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeColors colors, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Icon(Icons.arrow_back, size: 24, color: colors.textPrimary),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            '最近播放',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => _confirmClear(context, colors, ref),
            child: Icon(Icons.delete_outline, size: 22, color: colors.textHint),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: 64, color: colors.textHint.withValues(alpha: 0.3)),
          const SizedBox(height: AppSpacing.md),
          Text(
            '暂无播放记录',
            style: TextStyle(fontSize: 16, color: colors.textHint),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '播放歌曲后将自动记录',
            style: TextStyle(fontSize: 13, color: colors.textHint.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList(
    BuildContext context,
    WidgetRef ref,
    ThemeColors colors,
    List history,
  ) {
    final songs = history.map((h) => h.song as Song).toList();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      itemCount: history.length,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemBuilder: (context, index) {
        final item = history[index];
        final song = item.song as Song;
        final timeStr = _formatTime(item.playedAt as DateTime);

        return Dismissible(
          key: Key('history_${song.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            color: colors.error,
            child: Icon(Icons.delete, color: colors.textOnPrimary),
          ),
          onDismissed: (_) {
            ref.read(recentlyPlayedProvider.notifier).removeFromHistory(song.id);
          },
          child: ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: song.coverUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: MusicCoverImage(
                        url: song.coverUrl,
                        fit: BoxFit.cover,
                        errorWidget:
                            Icon(Icons.music_note, size: 20, color: colors.primary),
                      ),
                    )
                  : Icon(Icons.music_note, size: 20, color: colors.primary),
            ),
            title: Text(
              song.title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${song.artist} - ${song.album}  ·  $timeStr',
              style: TextStyle(fontSize: 12, color: colors.textHint),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.playCount > 1)
                  Text(
                    '${item.playCount}次',
                    style: TextStyle(fontSize: 11, color: colors.textHint),
                  ),
                const SizedBox(width: AppSpacing.xs),
                Icon(Icons.more_vert, size: 18, color: colors.textHint),
              ],
            ),
            onTap: () async {
              final controller = ref.read(playbackControllerProvider.notifier);
              await controller.setQueue(songs, startIndex: index);
            },
          ),
        );
      },
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';

    return '${time.month}/${time.day}';
  }

  void _confirmClear(BuildContext context, ThemeColors colors, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('清除记录', style: TextStyle(color: colors.textPrimary)),
        content: Text(
          '确定要清除所有播放记录吗？',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消', style: TextStyle(color: colors.textHint)),
          ),
          TextButton(
            onPressed: () {
              ref.read(recentlyPlayedProvider.notifier).clearHistory();
              Navigator.pop(ctx);
            },
            child: Text('清除', style: TextStyle(color: colors.error)),
          ),
        ],
      ),
    );
  }
}