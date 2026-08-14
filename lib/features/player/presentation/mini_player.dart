import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../shared/widgets/music_cover_image.dart';
import '../application/playback_controller.dart';
import '../domain/models/song.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeColorsProvider);
    ref.watch(currentSongIdentityProvider);
    final song = ref.read(playbackControllerProvider).currentSong;
    final isPlaying = ref.watch(
      playbackControllerProvider.select((s) => s.isPlaying),
    );
    // 与全屏播放页保持一致：加载中也显示转圈，避免「迷你=暂停、全屏=转圈」的状态不一致。
    final isLoading = ref.watch(
      playbackControllerProvider.select((s) => s.isLoading),
    );
    final controller = ref.read(playbackControllerProvider.notifier);
    if (song == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => context.push('/player/full'),
      child: Container(
        height: 56,
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: colors.shadow,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const SizedBox(width: AppSpacing.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: colors.surfaceVariant),
                child: _buildCover(colors, song),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    song.artist,
                    style: TextStyle(fontSize: 11, color: colors.textHint),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.skip_previous,
                size: 20,
                color: colors.textSecondary,
              ),
              onPressed: () => controller.previous(),
            ),
            IconButton(
              icon: isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.textPrimary,
                      ),
                    )
                  : Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                      size: 24,
                      color: colors.textPrimary,
                    ),
              // 遵循 CeruMusic/Sollin-Music：加载期间禁用按钮，
              // 避免用户在 URL 获取 / 换源过程中连点导致状态错乱。
              onPressed: isLoading ? null : () => controller.togglePlayPause(),
            ),
            IconButton(
              icon: Icon(
                Icons.skip_next,
                size: 20,
                color: colors.textSecondary,
              ),
              onPressed: () => controller.next(),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(ThemeColors colors, Song song) {
    if (song.mediaStoreId != null) {
      return QueryArtworkWidget(
        // 用 song.id 做 key：唯一标识歌曲，播放/暂停等状态变更时
        // key 不变，Flutter 复用 widget，避免封面图片重新加载闪烁。
        key: ValueKey('mp_cover_${song.id}'),
        id: song.mediaStoreId!,
        type: ArtworkType.AUDIO,
        keepOldArtwork: true,
        artworkFit: BoxFit.cover,
        nullArtworkWidget: Icon(
          Icons.music_note,
          size: 20,
          color: colors.primary,
        ),
      );
    }
    if (song.coverUrl != null && song.coverUrl!.isNotEmpty) {
      return MusicCoverImage(
        key: ValueKey('mp_cover_img_${song.id}'),
        url: song.coverUrl,
        fit: BoxFit.cover,
        errorWidget: Icon(Icons.music_note, size: 20, color: colors.primary),
      );
    }
    return Icon(Icons.music_note, size: 20, color: colors.primary);
  }
}
