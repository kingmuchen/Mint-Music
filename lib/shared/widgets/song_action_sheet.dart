import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_provider.dart';
import '../../core/constants/app_routes.dart';
import '../../features/library/application/playlist_providers.dart';
import '../../features/library/domain/models/playlist.dart';
import '../../features/player/application/playback_controller.dart';
import '../../features/player/domain/models/song.dart';
import '../../features/download/application/download_providers.dart';
import '../../features/settings/application/settings_providers.dart';
import '../../features/settings/data/settings_service.dart';
import '../services/amll_toggle_service.dart';
import '../../features/plugin/application/plugin_providers.dart';
import 'share_preview_dialog.dart';
import 'music_cover_image.dart';
import 'sleep_timer_picker.dart';

const _sheetAnimationStyle = AnimationStyle(
  duration: Duration(milliseconds: 220),
  reverseDuration: Duration(milliseconds: 180),
);

String _estimateSize(String qualityId, int durationSec) {
  if (durationSec <= 0) return '';
  final kbps = <String, int>{
    '128k': 128,
    '192k': 192,
    '320k': 320,
    'flac': 1000,
    'flac24bit': 2000,
    'hires': 3000,
    'atmos': 500,
    'master': 3000,
  };
  final bitrate = kbps[qualityId] ?? 320;
  final sizeBytes = bitrate * 1000 ~/ 8 * durationSec;
  if (sizeBytes < 1024 * 1024)
    return '${(sizeBytes / 1024).toStringAsFixed(1)}KB';
  return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)}MB';
}

class SongActionSheet extends ConsumerStatefulWidget {
  final Song song;
  final List<Song>? playlistSongs;
  final bool showDownload;
  final bool showEditTag;
  final bool showAccurateMatch;
  final VoidCallback? onAccurateMatch;
  final bool showDelete;
  final VoidCallback? onDelete;
  final bool compactMode;

  const SongActionSheet({
    super.key,
    required this.song,
    this.playlistSongs,
    this.showDownload = true,
    this.showEditTag = false,
    this.showAccurateMatch = false,
    this.onAccurateMatch,
    this.showDelete = false,
    this.onDelete,
    this.compactMode = false,
  });

  static Future<void> show(
    BuildContext context, {
    required Song song,
    List<Song>? playlistSongs,
    bool showDownload = true,
    bool showEditTag = false,
    bool showAccurateMatch = false,
    VoidCallback? onAccurateMatch,
    bool showDelete = false,
    VoidCallback? onDelete,
  }) {
    return showModalBottomSheet(
      context: context,
      // 用根导航器弹出，避免被 AppShell 中悬浮的迷你播放器遮挡
      useRootNavigator: true,
      sheetAnimationStyle: _sheetAnimationStyle,
      backgroundColor: Colors.transparent,
      builder: (context) => SongActionSheet(
        song: song,
        playlistSongs: playlistSongs,
        showDownload: showDownload,
        showEditTag: showEditTag,
        showAccurateMatch: showAccurateMatch,
        onAccurateMatch: onAccurateMatch,
        showDelete: showDelete,
        onDelete: onDelete,
      ),
    );
  }

  /// Shows a compact player menu with only 4 options:
  /// 添加到歌单, 下载, 分享, 倍速
  static Future<void> showPlayerMenu(
    BuildContext context, {
    required Song song,
  }) {
    return showModalBottomSheet(
      context: context,
      // 用根导航器弹出，避免被迷你播放器遮挡
      useRootNavigator: true,
      sheetAnimationStyle: _sheetAnimationStyle,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          SongActionSheet(song: song, showDownload: true, compactMode: true),
    );
  }

  @override
  ConsumerState<SongActionSheet> createState() => _SongActionSheetState();
}

class _SongActionSheetState extends ConsumerState<SongActionSheet> {
  bool _isFavorited = false;

  @override
  void initState() {
    super.initState();
    _checkFavorited();
  }

  void _checkFavorited() {
    final playlistsAsync = ref.read(playlistsProvider);
    setState(() {
      _isFavorited = playlistsAsync.when(
        data: (playlists) {
          final favorites = playlists
              .where((p) => p.id == '__favorites__')
              .firstOrNull;
          if (favorites == null) return false;
          return favorites.songs.any((s) => s.id == widget.song.id);
        },
        loading: () => false,
        error: (_, __) => false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = ref.watch(themeColorsProvider);
    final playlistsAsync = ref.watch(playlistsProvider);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    // Compact mode (player menu) uses always-dark colors matching the play queue window.
    // Full mode (song context menu) uses the theme-provided colors.
    final colors = widget.compactMode
        ? ThemeColors.darkWithPrimary(AppColors.primary)
        : themeColors;

    return Container(
      decoration: BoxDecoration(
        // Compact mode (player menu) uses always-dark surface matching the play queue.
        // Full mode (song context menu) uses the themed surface (white in light theme).
        color: widget.compactMode ? AppColors.surface : colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomPadding + 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: AppSpacing.md),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _buildSongInfo(colors),
                const SizedBox(height: AppSpacing.sm),
                Divider(
                  height: 1,
                  color: widget.compactMode
                      ? AppColors.divider
                      : colors.divider,
                ),
                // --- Compact mode (player menu: 4 options matching play queue style) ---
                if (widget.compactMode) ...[
                  _buildActionItem(
                    colors: colors,
                    icon: Icons.add_to_photos,
                    label: '添加到歌单',
                    onTap: () => _showAddToPlaylist(colors, playlistsAsync),
                    skipPop: true,
                  ),
                  _buildActionItem(
                    colors: colors,
                    icon: Icons.download_outlined,
                    label: '下载',
                    onTap: _download,
                    skipPop: true,
                  ),
                  _buildShareItem(colors),
                  _buildSpeedItem(colors),
                  const SleepTimerMenuTile(),
                  _buildLyricSettingsItem(colors),
                ],
                // --- Full mode (song context menu) ---
                if (!widget.compactMode) ...[
                  _buildActionItem(
                    colors: colors,
                    icon: Icons.play_circle_outline,
                    label: '播放',
                    onTap: _play,
                  ),
                  _buildActionItem(
                    colors: colors,
                    icon: Icons.playlist_add,
                    label: '加入播放列表',
                    onTap: _appendToQueue,
                  ),
                  if (widget.showDownload)
                    _buildActionItem(
                      colors: colors,
                      icon: Icons.download_outlined,
                      label: '下载',
                      onTap: _download,
                      skipPop: true,
                    ),
                  _buildActionItem(
                    colors: colors,
                    icon: Icons.add_to_photos,
                    label: '添加到歌单',
                    onTap: () => _showAddToPlaylist(colors, playlistsAsync),
                    skipPop: true,
                  ),
                  _buildShareItem(colors),
                  _buildFavoriteItem(colors),
                  if (widget.showDelete && widget.onDelete != null)
                    _buildActionItem(
                      colors: colors,
                      icon: Icons.delete_outline,
                      label: '删除',
                      onTap: widget.onDelete!,
                      iconColor: colors.error,
                      labelColor: colors.error,
                    ),
                  if (widget.showAccurateMatch)
                    _buildActionItem(
                      colors: colors,
                      icon: Icons.search,
                      label: '精准匹配',
                      onTap: widget.onAccurateMatch ?? () {},
                    ),
                  if (widget.showEditTag)
                    _buildActionItem(
                      colors: colors,
                      icon: Icons.edit,
                      label: '编辑标签',
                      onTap: () => context.push(
                        '${AppRoutes.tagEditor}?songId=${widget.song.id}',
                      ),
                    ),
                ],
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSongInfo(ThemeColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          _buildCover(colors),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.song.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${widget.song.artist}${widget.song.album.isNotEmpty ? ' · ${widget.song.album}' : ''}',
                  style: TextStyle(fontSize: 12, color: colors.textHint),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCover(ThemeColors colors) {
    // 优先使用 coverUrl（精准匹配后的在线封面），再回退到设备本地封面
    if (widget.song.coverUrl != null && widget.song.coverUrl!.isNotEmpty) {
      return MusicCoverImage(
        url: widget.song.coverUrl,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        borderRadius: BorderRadius.circular(AppRadius.md),
        errorWidget: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colors.surfaceVariant,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(Icons.music_note, size: 22, color: colors.primary),
        ),
      );
    }
    if (widget.song.isLocal && widget.song.mediaStoreId != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: QueryArtworkWidget(
          key: ValueKey(widget.song.mediaStoreId),
          id: widget.song.mediaStoreId!,
          type: ArtworkType.AUDIO,
          keepOldArtwork: true,
          artworkBorder: BorderRadius.zero,
          artworkFit: BoxFit.cover,
          size: 88,
          quality: 100,
          nullArtworkWidget: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(Icons.music_note, size: 22, color: colors.primary),
          ),
        ),
      );
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Icon(Icons.music_note, size: 22, color: colors.primary),
    );
  }

  Widget _buildActionItem({
    required ThemeColors colors,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool skipPop = false,
    Color? iconColor,
    Color? labelColor,
  }) {
    return InkWell(
      onTap: () {
        if (!skipPop) Navigator.pop(context);
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: iconColor ?? colors.textSecondary),
            const SizedBox(width: AppSpacing.md),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                color: labelColor ?? colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShareItem(ThemeColors colors) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        SharePreviewDialog.show(context, song: widget.song);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(Icons.share, size: 22, color: colors.textSecondary),
            const SizedBox(width: AppSpacing.md),
            Text(
              '分享',
              style: TextStyle(fontSize: 15, color: colors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoriteItem(ThemeColors colors) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        _toggleFavorite();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(
              _isFavorited ? Icons.favorite : Icons.favorite_border,
              size: 22,
              color: _isFavorited ? Colors.red : colors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              _isFavorited ? '已收藏' : '收藏',
              style: TextStyle(
                fontSize: 15,
                color: _isFavorited ? Colors.red : colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeedItem(ThemeColors colors) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        _showSpeedPicker();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(Icons.speed, size: 22, color: colors.textSecondary),
            const SizedBox(width: AppSpacing.md),
            Text(
              '倍速',
              style: TextStyle(fontSize: 15, color: colors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  void _showSpeedPicker() {
    final currentSpeed = ref.read(playbackSpeedProvider);
    const speeds = ['0.5x', '0.75x', '1.0x', '1.25x', '1.5x', '2.0x'];
    showModalBottomSheet(
      context: context,
      sheetAnimationStyle: _sheetAnimationStyle,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '播放速度',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              ...speeds.map((label) {
                final speed = double.parse(label.replaceAll('x', ''));
                final isSelected = currentSpeed == speed;
                return ListTile(
                  leading: Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                  title: Text(
                    label,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                  onTap: () {
                    ref.read(playbackSpeedProvider.notifier).state = speed;
                    unawaited(_doPersistSpeed(speed));
                    ref.read(audioHandlerProvider).setSpeed(speed);
                    Navigator.pop(ctx);
                  },
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _doPersistSpeed(double speed) async {
    try {
      final svc = await ref.read(settingsServiceProvider.future);
      await svc.setPlaybackSpeed(speed);
    } catch (_) {}
  }

  Widget _buildLyricSettingsItem(ThemeColors colors) {
    return InkWell(
      onTap: () {
        // 注意：不要在这里 Navigator.pop(context)！
        // 如果先关闭 SongActionSheet，_SongActionSheetState（ConsumerState）会被 dispose，
        // 后续 _persist* 方法中任何基于 widget ref / context 的操作都会失效，
        // SharedPreferences 写入会静默失败。
        // 改为在当前 ActionSheet 之上再叠加一层歌词设置 BottomSheet。
        _showLyricSettings();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(Icons.lyrics, size: 22, color: colors.textSecondary),
            const SizedBox(width: AppSpacing.md),
            Text(
              '歌词设置',
              style: TextStyle(fontSize: 15, color: colors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  void _showLyricSettings() {
    showModalBottomSheet(
      context: context,
      sheetAnimationStyle: _sheetAnimationStyle,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        // 使用 ProviderScope 读取/写入设置
        final container = ProviderScope.containerOf(ctx);
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '歌词设置',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                // 字体设置行
                _lyricSettingRow(
                  ctx,
                  container,
                  icon: Icons.font_download,
                  title: '字体设置',
                  subtitle: '字体、大小、字重',
                  onTap: () => _showFontPicker(ctx, container),
                ),
                const Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: AppColors.divider,
                ),
                // 显示翻译
                _lyricSettingSwitch(
                  ctx,
                  container,
                  icon: Icons.translate,
                  title: '显示翻译',
                  provider: lyricShowTranslationProvider,
                  getter: (c) => c.read(lyricShowTranslationProvider),
                  setter: (c, v) =>
                      c.read(lyricShowTranslationProvider.notifier).state = v,
                ),
                const Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: AppColors.divider,
                ),
                // 显示罗马音
                _lyricSettingSwitch(
                  ctx,
                  container,
                  icon: Icons.abc,
                  title: '显示罗马音',
                  provider: lyricShowRomanProvider,
                  getter: (c) => c.read(lyricShowRomanProvider),
                  setter: (c, v) =>
                      c.read(lyricShowRomanProvider.notifier).state = v,
                ),
                const Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: AppColors.divider,
                ),
                // 模糊效果
                _lyricSettingSwitch(
                  ctx,
                  container,
                  icon: Icons.blur_on,
                  title: '模糊效果',
                  provider: lyricEnableBlurProvider,
                  getter: (c) => c.read(lyricEnableBlurProvider),
                  setter: (c, v) =>
                      c.read(lyricEnableBlurProvider.notifier).state = v,
                ),
                const Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: AppColors.divider,
                ),
                // 缩放效果
                _lyricSettingSwitch(
                  ctx,
                  container,
                  icon: Icons.zoom_out_map,
                  title: '缩放效果',
                  provider: lyricEnableScaleProvider,
                  getter: (c) => c.read(lyricEnableScaleProvider),
                  setter: (c, v) =>
                      c.read(lyricEnableScaleProvider.notifier).state = v,
                ),
                const Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: AppColors.divider,
                ),
                // 歌词居中：普通逐字与 AMLL 分别持久化，默认普通居中、AMLL 左对齐
                ListenableBuilder(
                  listenable: AmllToggleService(),
                  builder: (context, _) {
                    final amll = AmllToggleService().enabled;
                    final provider = amll
                        ? amllCenterAlignProvider
                        : lyricCenterAlignProvider;
                    return _lyricSettingSwitch(
                      ctx,
                      container,
                      icon: Icons.format_align_center,
                      title: '歌词居中',
                      provider: provider,
                      getter: (c) => c.read(provider),
                      setter: (c, v) => c.read(provider.notifier).state = v,
                    );
                  },
                ),
                const Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: AppColors.divider,
                ),
                // Apple Music 风格歌词
                _buildAmllToggle(ctx, container),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _lyricSettingRow(
    BuildContext ctx,
    ProviderContainer container, {
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppColors.textSecondary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textHint,
                      ),
                    ),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.textHint,
              ),
          ],
        ),
      ),
    );
  }

  Widget _lyricSettingSwitch(
    BuildContext ctx,
    ProviderContainer container, {
    required IconData icon,
    required String title,
    required StateProvider<bool> provider,
    required bool Function(ProviderContainer) getter,
    required void Function(ProviderContainer, bool) setter,
  }) {
    final value = getter(container);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: (v) {
              setter(container, v);
              _persistSetting(container, provider, v);
              (ctx as Element).markNeedsBuild();
            },
            activeTrackColor: AppColors.primary.withValues(alpha: 0.3),
            activeThumbColor: AppColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildAmllToggle(BuildContext ctx, ProviderContainer container) {
    return ListenableBuilder(
      listenable: AmllToggleService(),
      builder: (context, _) {
        final amll = AmllToggleService().enabled;
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.music_video,
                size: 22,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: Text(
                  'Apple Music 风格歌词',
                  style: TextStyle(fontSize: 15, color: AppColors.textPrimary),
                ),
              ),
              Switch(
                value: amll,
                onChanged: (v) => AmllToggleService().setAndPersist(v),
                activeTrackColor: AppColors.primary.withValues(alpha: 0.3),
                activeThumbColor: AppColors.primary,
              ),
            ],
          ),
        );
      },
    );
  }

  void _persistSetting(
    ProviderContainer container,
    StateProvider<bool> provider,
    bool value,
  ) {
    container.read(provider.notifier).state = value;
    unawaited(_doPersistSetting(container, provider, value));
  }

  Future<void> _doPersistSetting(
    ProviderContainer container,
    StateProvider<bool> provider,
    bool value,
  ) async {
    try {
      final svc = await container.read(settingsServiceProvider.future);
      // Map provider names to settings service methods
      if (provider == lyricShowTranslationProvider)
        await svc.setLyricShowTranslation(value);
      else if (provider == lyricShowRomanProvider)
        await svc.setLyricShowRoman(value);
      else if (provider == lyricEnableBlurProvider)
        await svc.setLyricEnableBlur(value);
      else if (provider == lyricEnableScaleProvider)
        await svc.setLyricEnableScale(value);
      else if (provider == lyricCenterAlignProvider)
        await svc.setLyricCenterAlign(value);
      else if (provider == amllCenterAlignProvider)
        await svc.setAmllCenterAlign(value);
      debugPrint(
        '[Settings] saved bool ${provider.name ?? provider.runtimeType} = $value',
      );
    } catch (e) {
      debugPrint('[Settings] persistBool error: $e');
    }
  }

  void _showFontPicker(BuildContext ctx, ProviderContainer container) {
    const fontNameMap = {
      '': '系统默认',
      'lyricfont': '阿里巴巴圆润体',
      'PingFangSC-Semibold': '苹方-简 中粗体',
    };

    showModalBottomSheet(
      context: ctx,
      sheetAnimationStyle: _sheetAnimationStyle,
      backgroundColor: Colors.transparent,
      builder: (ctx2) {
        final c2 = ProviderScope.containerOf(ctx2);
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              // 所有 provider 都必须在 StatefulBuilder.builder 内部读取，
              // 这样 setSheetState 触发重建时才能拿到最新的值
              final storedFamily = ProviderScope.containerOf(
                context,
              ).read(lyricFontFamilyProvider);
              final familyDisplay = fontNameMap[storedFamily] ?? '系统默认';
              final storedRate = ProviderScope.containerOf(
                context,
              ).read(lyricFontRateProvider);
              final rateDisplay = '${(storedRate * 100).toInt()}%';
              final storedWeight = ProviderScope.containerOf(
                context,
              ).read(lyricFontWeightProvider);
              return SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '字体设置',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 字体选择
                    _fontSettingRow(ctx2, c2, '选择字体', familyDisplay, () {
                      _showFontFamilyPicker(ctx2, c2).then((_) {
                        setSheetState(() {});
                      });
                    }),
                    const Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: AppColors.divider,
                    ),
                    // 字体大小
                    _fontSettingRow(ctx2, c2, '字体大小', rateDisplay, () {
                      _showFontRatePicker(ctx2, c2).then((_) {
                        setSheetState(() {});
                      });
                    }),
                    const Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: AppColors.divider,
                    ),
                    // 字重
                    _fontSettingRow(ctx2, c2, '字重', '$storedWeight', () {
                      _showFontWeightPicker(ctx2, c2).then((_) {
                        setSheetState(() {});
                      });
                    }),
                    const SizedBox(height: 16),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _fontSettingRow(
    BuildContext ctx,
    ProviderContainer c,
    String title,
    String value,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 13, color: AppColors.textHint),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.textHint,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showFontFamilyPicker(
    BuildContext ctx,
    ProviderContainer container,
  ) {
    final fonts = ['系统默认', '阿里巴巴圆润体', '苹方-简 中粗体'];
    final current = container.read(lyricFontFamilyProvider);
    final map = {
      '': '系统默认',
      'lyricfont': '阿里巴巴圆润体',
      'PingFangSC-Semibold': '苹方-简 中粗体',
    };
    final revMap = {
      '系统默认': '',
      '阿里巴巴圆润体': 'lyricfont',
      '苹方-简 中粗体': 'PingFangSC-Semibold',
    };
    final currentLabel = map[current] ?? '系统默认';

    return showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (ctx2) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '选择字体',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              ...fonts.map(
                (f) => ListTile(
                  title: Text(
                    f,
                    style: TextStyle(
                      color: f == currentLabel
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                  trailing: f == currentLabel
                      ? const Icon(
                          Icons.check,
                          size: 18,
                          color: AppColors.primary,
                        )
                      : null,
                  onTap: () async {
                    final val = revMap[f]!;
                    container.read(lyricFontFamilyProvider.notifier).state =
                        val;
                    await _persistStringSetting(
                      container,
                      lyricFontFamilyProvider,
                      val,
                      (s) => s.setLyricFontFamily(val),
                    );
                    if (ctx2.mounted) Navigator.pop(ctx2);
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showFontRatePicker(
    BuildContext ctx,
    ProviderContainer container,
  ) {
    return showModalBottomSheet(
      context: ctx,
      sheetAnimationStyle: _sheetAnimationStyle,
      backgroundColor: Colors.transparent,
      builder: (ctx2) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: StatefulBuilder(
            builder: (context, setState) {
              final c2 = ProviderScope.containerOf(context);
              final rate = c2.read(lyricFontRateProvider);
              return SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '字体大小',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Text(
                            '${(rate * 100).toInt()}%',
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              value: rate,
                              min: 0.5,
                              max: 2.0,
                              divisions: 15,
                              activeColor: AppColors.primary,
                              onChanged: (v) async {
                                c2.read(lyricFontRateProvider.notifier).state =
                                    v;
                                await _persistDoubleSetting(
                                  container,
                                  lyricFontRateProvider,
                                  v,
                                  (s) => s.setLyricFontRate(v),
                                );
                                setState(() {});
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _showFontWeightPicker(
    BuildContext ctx,
    ProviderContainer container,
  ) {
    final weights = ['400 正常', '500 中等', '600 半粗', '700 粗', '800 特粗', '900 黑'];

    return showModalBottomSheet(
      context: ctx,
      sheetAnimationStyle: _sheetAnimationStyle,
      backgroundColor: Colors.transparent,
      builder: (ctx2) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: StatefulBuilder(
            builder: (context, setState) {
              final c2 = ProviderScope.containerOf(context);
              final current = c2.read(lyricFontWeightProvider);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '字重',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...weights.map((w) {
                    final v = int.parse(w.split(' ')[0]);
                    return ListTile(
                      title: Text(
                        w,
                        style: TextStyle(
                          color: v == current
                              ? AppColors.primary
                              : AppColors.textPrimary,
                        ),
                      ),
                      trailing: v == current
                          ? const Icon(
                              Icons.check,
                              size: 18,
                              color: AppColors.primary,
                            )
                          : null,
                      onTap: () async {
                        container.read(lyricFontWeightProvider.notifier).state =
                            v;
                        await _persistIntSetting(
                          container,
                          lyricFontWeightProvider,
                          v,
                          (s) => s.setLyricFontWeight(v),
                        );
                        if (ctx2.mounted) {
                          setState(() {});
                          Navigator.pop(ctx2);
                        }
                      },
                    );
                  }),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _persistStringSetting(
    ProviderContainer c,
    StateProvider<String> p,
    String v,
    Future<void> Function(SettingsService svc) saveFn,
  ) async {
    c.read(p.notifier).state = v;
    try {
      final svc = await c.read(settingsServiceProvider.future);
      await saveFn(svc);
      debugPrint('[Settings] saved String ${p.name ?? p.runtimeType} = "$v"');
    } catch (e) {
      debugPrint('[Settings] persistString error: $e');
    }
  }

  Future<void> _persistDoubleSetting(
    ProviderContainer c,
    StateProvider<double> p,
    double v,
    Future<void> Function(SettingsService svc) saveFn,
  ) async {
    c.read(p.notifier).state = v;
    try {
      final svc = await c.read(settingsServiceProvider.future);
      await saveFn(svc);
      debugPrint('[Settings] saved Double ${p.name ?? p.runtimeType} = $v');
    } catch (e) {
      debugPrint('[Settings] persistDouble error: $e');
    }
  }

  Future<void> _persistIntSetting(
    ProviderContainer c,
    StateProvider<int> p,
    int v,
    Future<void> Function(SettingsService svc) saveFn,
  ) async {
    c.read(p.notifier).state = v;
    try {
      final svc = await c.read(settingsServiceProvider.future);
      await saveFn(svc);
      debugPrint('[Settings] saved Int ${p.name ?? p.runtimeType} = $v');
    } catch (e) {
      debugPrint('[Settings] persistInt error: $e');
    }
  }

  Future<void> _play() async {
    final controller = ref.read(playbackControllerProvider.notifier);
    if (widget.playlistSongs != null && widget.playlistSongs!.isNotEmpty) {
      final index = widget.playlistSongs!.indexWhere(
        (s) => s.id == widget.song.id,
      );
      await controller.setQueue(
        widget.playlistSongs!,
        startIndex: index >= 0 ? index : 0,
      );
    } else {
      await controller.setQueue([widget.song]);
    }
  }

  void _appendToQueue() {
    ref.read(playbackControllerProvider.notifier).appendToQueue([widget.song]);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已加入播放列表'), duration: Duration(seconds: 2)),
    );
  }

  void _toggleFavorite() {
    if (_isFavorited) {
      ref
          .read(playlistsProvider.notifier)
          .removeSongFromPlaylist('__favorites__', widget.song.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已取消收藏'), duration: Duration(seconds: 1)),
      );
    } else {
      ref
          .read(playlistsProvider.notifier)
          .addSongToPlaylist('__favorites__', widget.song);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已收藏'), duration: Duration(seconds: 1)),
      );
    }
    _checkFavorited();
  }

  void _download() {
    _showQualityDialog();
  }

  void _showQualityDialog() {
    final sourceId = widget.song.source ?? 'wy';
    final manager = ProviderScope.containerOf(
      context,
    ).read(musicSourceManagerProvider);
    final qualities = manager.getSupportedQualitiesForSourceId(sourceId);

    showModalBottomSheet(
      context: context,
      sheetAnimationStyle: _sheetAnimationStyle,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).padding.bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '选择下载音质',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                ...qualities.map((q) => _buildQualityItem(ctx, q)),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQualityItem(BuildContext ctx, String q) {
    return InkWell(
      onTap: () {
        Navigator.pop(ctx);
        _startDownload(q);
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    getQualityDisplayName(q),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${kQualityDescription[q] ?? ''}  ${_estimateSize(q, widget.song.duration)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.download_outlined,
              color: Colors.white.withValues(alpha: 0.4),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _startDownload(String quality) async {
    Navigator.pop(context);
    try {
      final repo = ref.read(downloadRepositoryProvider);
      await repo.addTask(song: widget.song, quality: quality);
      // onTaskStarted 回调会显示 "开始下载 xxx" 通知
    } catch (e) {
      final err = e.toString();
      if (err.contains('UNSUPPORTED_QUALITY')) {
        final q = err.split(':').last;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('音质 $q 不受当前音源支持，请选择其他音质'),
              duration: const Duration(seconds: 3),
              backgroundColor: Colors.orange,
              action: SnackBarAction(
                label: '重新选择',
                textColor: Colors.white,
                onPressed: _showQualityDialog,
              ),
            ),
          );
        }
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('下载失败: $e'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showAddToPlaylist(
    ThemeColors colors,
    AsyncValue<List<Playlist>> playlistsAsync,
  ) {
    // Save song reference BEFORE any pops (widget becomes invalid after pop).
    final targetSong = widget.song;
    playlistsAsync.when(
      data: (List<Playlist> playlists) {
        // Exclude __favorites__ from the picker (it has its own "收藏" toggle)
        final playlistList = playlists
            .where((p) => p.id != '__favorites__')
            .toList();
        // Save root navigator context BEFORE popping (after pop the widget context becomes invalid).
        final navContext = Navigator.of(context, rootNavigator: true).context;
        // Pop SongActionSheet first
        if (mounted) Navigator.pop(context);
        // navContext remains valid because it's from the root navigator.
        final bottomPadding = MediaQuery.of(navContext).padding.bottom;
        showModalBottomSheet(
          context: navContext,
          sheetAnimationStyle: _sheetAnimationStyle,
          backgroundColor: Colors.transparent,
          builder: (ctx) => Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(bottom: bottomPadding + 16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.divider,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        '添加到歌单',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (playlistList.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Text(
                            '暂无歌单',
                            style: TextStyle(color: AppColors.textHint),
                          ),
                        )
                      else
                        ...playlistList.map<Widget>(
                          (Playlist playlist) => ListTile(
                            leading: Icon(
                              Icons.queue_music,
                              color: AppColors.textSecondary,
                            ),
                            title: Text(
                              playlist.name,
                              style: TextStyle(color: AppColors.textPrimary),
                            ),
                            trailing: Text(
                              '${playlist.songCount}首',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textHint,
                              ),
                            ),
                            onTap: () async {
                              Navigator.pop(ctx);
                              // Save messenger and container BEFORE any async gap.
                              // navContext is the root navigator context which remains valid
                              // across the entire app lifecycle.
                              // ignore: use_build_context_synchronously
                              final messenger = ScaffoldMessenger.of(
                                navContext,
                              );
                              // ignore: use_build_context_synchronously
                              final container = ProviderScope.containerOf(
                                navContext,
                              );
                              final notifier = container.read(
                                playlistsProvider.notifier,
                              );
                              try {
                                final added = await notifier.addSongToPlaylist(
                                  playlist.id,
                                  targetSong,
                                );
                                if (added) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text('已添加到"${playlist.name}"'),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                } else {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '歌曲已在歌单"${playlist.name}"中',
                                      ),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              } catch (e) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: const Text('添加到歌单失败'),
                                    duration: const Duration(seconds: 2),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
      loading: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('加载歌单中...'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      },
      error: (_, __) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('加载歌单失败'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      },
    );
  }
}
