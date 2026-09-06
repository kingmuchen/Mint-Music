import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/l10n/l10n.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_provider.dart';
import '../../features/player/domain/models/song.dart';
import '../../features/plugin/application/music_source_manager.dart';
import '../../features/plugin/application/plugin_providers.dart';
import 'song_action_sheet.dart';

class SongListItem extends ConsumerWidget {
  static const double itemExtent = 60;

  final Song song;
  final int? index;
  final bool showIndex;
  final bool showCover;
  final bool showQuality;
  final bool showSource;
  final bool showDuration;
  final bool showMenuButton;
  final VoidCallback? onTap;
  final VoidCallback? onPlayTap;
  final VoidCallback? onMenuTap;
  final bool isPlaying;
  final List<String>? supportedQualities;

  const SongListItem({
    super.key,
    required this.song,
    this.index,
    this.showIndex = true,
    this.showCover = true,
    this.showQuality = true,
    this.showSource = true,
    this.showDuration = true,
    this.showMenuButton = true,
    this.onTap,
    this.onPlayTap,
    this.onMenuTap,
    this.isPlaying = false,
    this.supportedQualities,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeColorsProvider);
    // All scrolling song lists already enable Sliver repaint boundaries.
    // Adding another boundary per row increases layer count and GPU
    // composition work without isolating any additional repaint.
    return _buildItem(colors, context, ref);
  }

  Widget _buildItem(ThemeColors colors, BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: onTap ?? () => _defaultOnTap(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            if (showIndex) _buildIndex(colors),
            if (showCover) ...[
              const SizedBox(width: AppSpacing.sm),
              _buildCover(colors, ref),
            ],
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: _buildSongInfo(colors, context)),
            if (showDuration) _buildDuration(colors),
            if (showMenuButton) _buildMenuButton(colors, context),
          ],
        ),
      ),
    );
  }

  Widget _buildIndex(ThemeColors colors) {
    return SizedBox(
      width: 28,
      child: isPlaying
          ? Icon(Icons.play_arrow, size: 18, color: colors.primary)
          : Text(
              index != null ? '${index! + 1}' : '',
              style: TextStyle(
                fontSize: 13,
                color: colors.textHint,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
    );
  }

  Widget _buildCover(ThemeColors colors, WidgetRef ref) {
    final coverUrl = song.coverUrl;
    final hasCoverUrl = coverUrl != null && coverUrl.isNotEmpty;
    if ((song.source == null || song.source == 'local') && !hasCoverUrl) {
      return _buildCoverPlaceholder(colors);
    }

    return _SongCover(
      song: song,
      initialUrl: coverUrl,
      colors: colors,
      sourceManager: ref.read(musicSourceManagerProvider),
    );
  }

  Widget _buildCoverPlaceholder(ThemeColors colors) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(Icons.music_note, size: 20, color: colors.primary),
    );
  }

  Widget _buildSongInfo(ThemeColors colors, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          song.title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isPlaying ? colors.primary : colors.textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            if (showQuality) _buildQualityTag(colors, context),
            if (showSource && song.source != null)
              _buildSourceTag(colors, context),
            Expanded(
              child: Text(
                song.artist,
                style: TextStyle(fontSize: 12, color: colors.textHint),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQualityTag(ThemeColors colors, BuildContext context) {
    final quality = _getHighestQuality();
    if (quality == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: _getQualityColor(quality).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        context.tr(quality),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: _getQualityColor(quality),
        ),
      ),
    );
  }

  Widget _buildSourceTag(ThemeColors colors, BuildContext context) {
    final sourceName = _getSourceName(song.source!);
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: _getSourceColor(song.source!).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        context.tr(sourceName),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: _getSourceColor(song.source!),
        ),
      ),
    );
  }

  Widget _buildDuration(ThemeColors colors) {
    if (song.duration <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Text(
        song.displayDuration,
        style: TextStyle(fontSize: 12, color: colors.textHint),
      ),
    );
  }

  Widget _buildMenuButton(ThemeColors colors, BuildContext context) {
    return IconButton(
      icon: Icon(Icons.more_vert, size: 20, color: colors.textHint),
      onPressed: onMenuTap ?? () => SongActionSheet.show(context, song: song),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }

  void _defaultOnTap(BuildContext context) {
    if (onPlayTap != null) {
      onPlayTap!();
    }
  }

  String? _getHighestQuality() {
    if (supportedQualities != null && supportedQualities!.isNotEmpty) {
      return supportedQualities!.last;
    }
    if (song.bitrate != null) {
      if (song.bitrate! >= 1900000) return 'Hi-Res';
      if (song.bitrate! >= 1000000) return '无损';
      if (song.bitrate! >= 320000) return '320k';
      if (song.bitrate! >= 192000) return '192k';
      if (song.bitrate! >= 128000) return '128k';
    }
    return null;
  }

  Color _getQualityColor(String quality) {
    switch (quality) {
      case 'Hi-Res':
      case '母带':
        return const Color(0xFFFFD700);
      case '无损':
      case 'SQ':
        return const Color(0xFFE5484D);
      case '320k':
      case 'HQ':
        return const Color(0xFF31C27C);
      case '192k':
        return const Color(0xFF2EADFB);
      case '128k':
        return const Color(0xFF888888);
      default:
        return const Color(0xFF888888);
    }
  }

  Color _getSourceColor(String source) {
    switch (source) {
      case 'wy':
        return const Color(0xFFE60026);
      case 'kg':
        return const Color(0xFF2EADFB);
      case 'kw':
        return const Color(0xFFFF8500);
      case 'tx':
        return const Color(0xFF31C27C);
      case 'mg':
        return const Color(0xFFFF7E00);
      case 'local':
        return const Color(0xFF666666);
      default:
        return const Color(0xFF888888);
    }
  }

  String _getSourceName(String source) {
    switch (source) {
      case 'wy':
        return '网易';
      case 'kg':
        return '酷狗';
      case 'kw':
        return '酷我';
      case 'tx':
        return 'QQ';
      case 'mg':
        return '咪咕';
      case 'local':
        return '本地';
      default:
        return source.toUpperCase();
    }
  }
}

class _SongCover extends StatefulWidget {
  final Song song;
  final String? initialUrl;
  final ThemeColors colors;
  final MusicSourceManager sourceManager;

  const _SongCover({
    required this.song,
    required this.initialUrl,
    required this.colors,
    required this.sourceManager,
  });

  @override
  State<_SongCover> createState() => _SongCoverState();
}

class _SongCoverState extends State<_SongCover> {
  String? _url;
  final Set<String> _failedUrls = <String>{};
  bool _fallbackStarted = false;

  @override
  void initState() {
    super.initState();
    _url = widget.initialUrl;
    if (_url == null || _url!.isEmpty) _loadFallback();
  }

  @override
  void didUpdateWidget(covariant _SongCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id ||
        oldWidget.initialUrl != widget.initialUrl) {
      _url = widget.initialUrl;
      _failedUrls.clear();
      _fallbackStarted = false;
      if (_url == null || _url!.isEmpty) _loadFallback();
    }
  }

  Future<void> _loadFallback() async {
    if (_fallbackStarted) return;
    _fallbackStarted = true;
    final fallback = await widget.sourceManager.getPic(
      widget.song,
      excludedUrls: _failedUrls,
    );
    if (!mounted || fallback == null || fallback.isEmpty) return;
    if (_failedUrls.contains(fallback)) return;
    if (fallback == _url) return;
    setState(() => _url = fallback);
  }

  void _handleImageError(String failedUrl) {
    if (_failedUrls.add(failedUrl)) {
      setState(() => _url = null);
      _loadFallback();
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    if (url == null || url.isEmpty || _failedUrls.contains(url)) {
      return _buildPlaceholder();
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: widget.colors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: CachedNetworkImage(
          imageUrl: url,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          memCacheWidth: 132,
          memCacheHeight: 132,
          maxWidthDiskCache: 132,
          maxHeightDiskCache: 132,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          filterQuality: FilterQuality.low,
          placeholder: (context, url) => _buildPlaceholder(),
          errorWidget: (context, url, error) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _handleImageError(url);
            });
            return _buildPlaceholder();
          },
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: widget.colors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(Icons.music_note, size: 20, color: widget.colors.primary),
    );
  }
}
