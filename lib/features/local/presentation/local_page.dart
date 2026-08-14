import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/constants/app_routes.dart';
import '../../../shared/widgets/song_action_sheet.dart';
import '../application/local_providers.dart';
import '../data/local_music_repository.dart';
import '../../player/application/playback_controller.dart';
import '../../player/domain/models/song.dart';
import '../../library/application/playlist_providers.dart';
import '../../plugin/application/plugin_providers.dart';

class LocalPage extends ConsumerStatefulWidget {
  const LocalPage({super.key});

  @override
  ConsumerState<LocalPage> createState() => _LocalPageState();
}

class _LocalPageState extends ConsumerState<LocalPage> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  bool _showLocateBtn = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPermissionAndScan();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkPermissionAndScan() async {
    final repo = ref.read(localMusicRepositoryProvider);
    final hasPermission = await repo.checkPermission();
    if (!hasPermission) {
      if (mounted) _showPermissionDialog();
      return;
    }

    final songs = repo.getLocalSongs();
    if (songs.isEmpty) {
      await ref.read(localMusicNotifierProvider.notifier).scanAll();
    }
  }

  void _showPermissionDialog() {
    final colors = ref.read(themeColorsProvider);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('需要存储权限', style: TextStyle(color: colors.textPrimary)),
        content: Text(
          '为了扫描本地音乐，薄荷音乐需要访问您设备上的音频文件。请授予权限后继续。',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: colors.textHint)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final granted = await ref.read(localMusicNotifierProvider.notifier).requestPermissionAndScan();
              if (!granted && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('权限被拒绝，无法扫描本地音乐'), duration: Duration(seconds: 3)),
                );
              }
            },
            child: Text('授权', style: TextStyle(color: colors.primary)),
          ),
        ],
      ),
    );
  }

  void _onScroll() {
    final playbackState = ref.read(playbackControllerProvider);
    final currentSong = playbackState.currentSong;
    if (currentSong == null || currentSong.source != 'local') {
      if (_showLocateBtn) setState(() => _showLocateBtn = false);
      return;
    }
    setState(() => _showLocateBtn = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_scrollController.position.isScrollingNotifier.value) {
        setState(() => _showLocateBtn = false);
      }
    });
  }

  void _locateCurrentSong() {
    final playbackState = ref.read(playbackControllerProvider);
    final currentSong = playbackState.currentSong;
    if (currentSong == null) return;

    final songs = ref.read(filteredLocalSongsProvider);
    final index = songs.indexWhere((s) => s.id == currentSong.id);
    if (index == -1) return;

    final itemHeight = 72.0;
    _scrollController.animateTo(
      index * itemHeight,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
    setState(() => _showLocateBtn = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeColorsProvider);
    final songs = ref.watch(filteredLocalSongsProvider);
    final songsAsync = ref.watch(localMusicNotifierProvider);
    final scanProgress = ref.watch(scanProgressProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(colors),
            _buildControls(colors, songs, scanProgress),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: songsAsync.when(
                data: (_) => _buildSongList(colors, songs),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => _buildErrorState(colors, e.toString()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 24,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              '本地音乐库',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _showDirModal(colors),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_open, size: 16, color: colors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    '选择目录',
                    style: TextStyle(fontSize: 12, color: colors.textSecondary, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(ThemeColors colors, List<Song> songs, ScanProgress scanProgress) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => _playAll(songs),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_arrow, size: 18, color: colors.textOnPrimary),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        '播放全部',
                        style: TextStyle(fontSize: 13, color: colors.textOnPrimary, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              GestureDetector(
                onTap: () => _scanLibrary(),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(
                    Icons.refresh,
                    size: 20,
                    color: scanProgress.running ? colors.primary : colors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              GestureDetector(
                onTap: () => _showMoreActions(colors, songs),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(Icons.more_horiz, size: 20, color: colors.textSecondary),
                ),
              ),
              if (scanProgress.running) ...[
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary),
                ),
                const SizedBox(width: 4),
                Text(
                  '${scanProgress.processed}/${scanProgress.total}',
                  style: TextStyle(fontSize: 11, color: colors.textHint),
                ),
              ],
              const Spacer(),
              Text(
                '${songs.length} 首',
                style: TextStyle(fontSize: 12, color: colors.textHint),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildSearchBar(colors),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ThemeColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 18, color: colors.textHint),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                ref.read(localSearchQueryProvider.notifier).state = value;
              },
              decoration: InputDecoration(
                hintText: '搜索本地歌曲/歌手/专辑',
                border: InputBorder.none,
                hintStyle: TextStyle(color: colors.textHint, fontSize: 14),
              ),
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchController.clear();
                ref.read(localSearchQueryProvider.notifier).state = '';
              },
              child: Icon(Icons.close, size: 18, color: colors.textHint),
            ),
        ],
      ),
    );
  }

  Widget _buildSongList(ThemeColors colors, List<Song> songs) {
    if (songs.isEmpty) {
      return _buildEmptyState(colors);
    }

    return Stack(
      children: [
        ListView.separated(
          controller: _scrollController,
          padding: const EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            // 底部多留出空间，避免最后一项被悬浮的迷你播放器遮挡
            bottom: AppSpacing.xxxl + AppSpacing.huge,
          ),
          itemCount: songs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 2),
          itemBuilder: (context, index) {
            return _LocalSongItem(
              key: ValueKey(songs[index].id),
              song: songs[index],
              onPlay: _playSong,
              onContextMenu: _showSongContextMenu,
            );
          },
        ),
      ],
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
            child: Icon(Icons.library_music, size: 40, color: colors.primary.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            '暂无本地音乐',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '点击下方按钮扫描设备音乐',
            style: TextStyle(fontSize: 13, color: colors.textHint),
          ),
          const SizedBox(height: AppSpacing.lg),
          GestureDetector(
            onTap: () async {
              final granted = await ref.read(localMusicNotifierProvider.notifier).requestPermissionAndScan();
              if (!granted && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('权限被拒绝，无法扫描本地音乐'), duration: Duration(seconds: 3)),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Text(
                '扫描本地音乐',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textOnPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(ThemeColors colors, String error) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: colors.textHint),
          const SizedBox(height: AppSpacing.md),
          Text('加载失败', style: TextStyle(color: colors.textHint)),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: () => ref.read(localMusicNotifierProvider.notifier).refresh(),
            child: Text('重试', style: TextStyle(color: colors.primary)),
          ),
        ],
      ),
    );
  }

  void _playSong(Song song) {
    final songs = ref.read(filteredLocalSongsProvider);
    final index = songs.indexWhere((s) => s.id == song.id);
    final controller = ref.read(playbackControllerProvider.notifier);
    controller.setQueue(songs, startIndex: index >= 0 ? index : 0);
  }

  void _playAll(List<Song> songs) {
    if (songs.isEmpty) return;
    final controller = ref.read(playbackControllerProvider.notifier);
    controller.setQueue(songs);
  }

  void _addAllToPlaylist(List<Song> songs) {
    if (songs.isEmpty) return;
    final controller = ref.read(playbackControllerProvider.notifier);
    controller.appendToQueue(songs);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已将 ${songs.length} 首加入播放列表'), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _scanLibrary() async {
    await ref.read(localMusicNotifierProvider.notifier).requestPermissionAndScan();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('扫描完成'), duration: Duration(seconds: 2)),
      );
    }
  }

  void _showSongContextMenu(ThemeColors colors, Song song) {
    final songs = ref.read(filteredLocalSongsProvider);
    showModalBottomSheet(
      context: context,
      // 用根导航器弹出，避免弹窗被 AppShell 中悬浮的迷你播放器遮挡
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SongActionSheet(
        song: song,
        playlistSongs: songs,
        showDownload: false,
        showEditTag: true,
        showAccurateMatch: true,
        onAccurateMatch: () => _showAccurateMatch(colors, song),
        showDelete: true,
        onDelete: () => _confirmDeleteSong(song),
      ),
    );
  }

  Future<void> _confirmDeleteSong(Song song) async {
    final colors = ref.read(themeColorsProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('删除歌曲', style: TextStyle(color: colors.textPrimary)),
        content: Text(
          '确定要删除「${song.title}」吗？\n此操作将从本地音乐库移除该歌曲。',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消', style: TextStyle(color: colors.textHint)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('删除', style: TextStyle(color: colors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await ref
        .read(localMusicNotifierProvider.notifier)
        .deleteSong(song);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '已删除「${song.title}」' : '删除失败'),
        duration: const Duration(seconds: 2),
        backgroundColor: ok ? null : Colors.red,
      ),
    );
  }

  Widget _contextMenuItem(ThemeColors colors, IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        child: Row(
          children: [
            Icon(icon, size: 22, color: colors.textSecondary),
            const SizedBox(width: AppSpacing.md),
            Text(
              label,
              style: TextStyle(fontSize: 15, color: colors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  void _showMoreActions(ThemeColors colors, List<Song> songs) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomPadding + 72),
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
                      '更多操作',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colors.textPrimary),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _contextMenuItem(colors, Icons.playlist_add, '添加全部到播放列表', () {
                      Navigator.pop(context);
                      _addAllToPlaylist(songs);
                    }),
                    _contextMenuItem(colors, Icons.delete_outline, '清空所有', () {
                      Navigator.pop(context);
                      _confirmClearIndex(colors);
                    }),
                    _contextMenuItem(colors, Icons.auto_fix_high, '批量匹配标签', () {
                      Navigator.pop(context);
                      _startBatchMatch(colors, songs);
                    }),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _confirmClearIndex(ThemeColors colors) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('确认清空', style: TextStyle(color: colors.textPrimary)),
        content: Text('将清空所有本地音乐索引，此操作不可恢复。', style: TextStyle(color: colors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: colors.textHint)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(localMusicNotifierProvider.notifier).clearIndex();
            },
            child: Text('确认', style: TextStyle(color: colors.primary)),
          ),
        ],
      ),
    );
  }

  void _startBatchMatch(ThemeColors colors, List<Song> songs) {
    final needMatch = songs.where((s) =>
        !s.hasCover ||
        s.artist == '未知艺术家' ||
        s.title == '未知曲目' ||
        s.album == '未知专辑').toList();

    if (needMatch.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有需要匹配的歌曲'), duration: Duration(seconds: 2)),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('开始匹配 ${needMatch.length} 首歌曲...'), duration: const Duration(seconds: 2)),
    );

    _doBatchMatch(colors, needMatch, 0, 0);
  }

  Future<void> _doBatchMatch(ThemeColors colors, List<Song> songs, int index, int matched) async {
    if (index >= songs.length) {
      ref.read(batchMatchProgressProvider.notifier).state = BatchMatchProgress(
        processed: songs.length,
        total: songs.length,
        matched: matched,
        running: false,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('批量匹配完成，成功匹配 $matched 首'), duration: const Duration(seconds: 3)),
        );
      }
      return;
    }

    ref.read(batchMatchProgressProvider.notifier).state = BatchMatchProgress(
      processed: index,
      total: songs.length,
      matched: matched,
      running: true,
    );

    final song = songs[index];
    try {
      final searchResults = await _searchOnlineForMatch(song.title);
      if (searchResults.isNotEmpty) {
        final best = searchResults.first;
        final updated = song.copyWith(
          title: best.title,
          artist: best.artist,
          album: best.album,
          coverUrl: best.coverUrl,
          hasCover: best.coverUrl != null,
        );
        await ref.read(localMusicNotifierProvider.notifier).upsertSong(updated);
        _doBatchMatch(colors, songs, index + 1, matched + 1);
        return;
      }
    } catch (_) {}
    _doBatchMatch(colors, songs, index + 1, matched);
  }

  Future<List<Song>> _searchOnlineForMatch(String keyword) async {
    try {
      final source = ref.read(musicSourceProvider);
      return await source.search(keyword, limit: 5);
    } catch (_) {
      return [];
    }
  }

  void _showAccurateMatch(ThemeColors colors, Song song) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomPadding + 72),
              child: DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.3,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
              return Column(
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
                    '精准匹配',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colors.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: Text(
                      '${song.title} - ${song.artist}',
                      style: TextStyle(fontSize: 13, color: colors.textHint),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Expanded(
                    child: FutureBuilder<List<Song>>(
                      future: _searchOnlineForMatch(song.title),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final results = snapshot.data ?? [];
                        if (results.isEmpty) {
                          return Center(
                            child: Text('未找到匹配结果', style: TextStyle(color: colors.textHint)),
                          );
                        }
                        return ListView.builder(
                          controller: scrollController,
                          itemCount: results.length,
                          addAutomaticKeepAlives: false,
                          addRepaintBoundaries: true,
                          itemBuilder: (context, index) {
                            final candidate = results[index];
                            return _buildMatchCandidate(colors, song, candidate);
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMatchCandidate(ThemeColors colors, Song original, Song candidate) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: colors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                image: candidate.coverUrl != null
                    ? DecorationImage(image: NetworkImage(candidate.coverUrl!), fit: BoxFit.cover)
                    : null,
              ),
              child: candidate.coverUrl == null
                  ? Icon(Icons.music_note, size: 20, color: colors.textHint)
                  : null,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    candidate.title,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${candidate.artist} · ${candidate.album}',
                    style: TextStyle(fontSize: 12, color: colors.textHint),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () async {
                final updated = original.copyWith(
                  title: candidate.title,
                  artist: candidate.artist,
                  album: candidate.album,
                  coverUrl: candidate.coverUrl,
                  hasCover: candidate.coverUrl != null,
                );
                await ref.read(localMusicNotifierProvider.notifier).upsertSong(updated);
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已应用匹配结果'), duration: Duration(seconds: 2)),
                  );
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  '使用',
                  style: TextStyle(fontSize: 12, color: colors.textOnPrimary, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddToPlaylistSheet(ThemeColors colors, Song song, AsyncValue playlistsAsync) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    playlistsAsync.when(
      data: (playlists) {
        showModalBottomSheet(
          context: context,
          useRootNavigator: true,
          backgroundColor: Colors.transparent,
          builder: (context) {
            return Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.only(bottom: bottomPadding + 72),
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
                          '添加到歌单',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colors.textPrimary),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        if (playlists.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(AppSpacing.xl),
                            child: Text('暂无歌单', style: TextStyle(color: colors.textHint)),
                          )
                        else
                          ...playlists.map<Widget>((playlist) => ListTile(
                                leading: Icon(Icons.queue_music, color: colors.textSecondary),
                                title: Text(playlist.name, style: TextStyle(color: colors.textPrimary)),
                                trailing: Text(
                                  '${playlist.songCount}首',
                                  style: TextStyle(fontSize: 12, color: colors.textHint),
                                ),
                                onTap: () {
                                  Navigator.pop(context);
                                  ref.read(playlistsProvider.notifier).addSongToPlaylist(playlist.id, song);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('已添加到"${playlist.name}"'),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                },
                              )),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
      loading: () => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('加载歌单中...'), duration: Duration(seconds: 1)),
      ),
      error: (_, __) => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('加载歌单失败'), duration: Duration(seconds: 2)),
      ),
    );
  }

  void _showDirModal(ThemeColors colors) {
    final dirs = List<String>.from(ref.read(scannedDirectoriesProvider));
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom + bottomPadding + 72,
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
                      '扫描目录设置',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colors.textPrimary),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      dirs.isEmpty
                          ? '未设置目录时将扫描设备全部音乐'
                          : '设置目录后仅扫描指定目录下的音乐',
                      style: TextStyle(fontSize: 12, color: colors.textHint),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (dirs.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          children: [
                            Icon(Icons.all_inclusive, size: 32, color: colors.primary.withValues(alpha: 0.5)),
                            const SizedBox(height: AppSpacing.sm),
                            Text('当前：扫描全部音乐', style: TextStyle(color: colors.textSecondary, fontSize: 13)),
                          ],
                        ),
                      )
                    else
                      ...dirs.map((d) => Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.xs,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.sm,
                              ),
                              decoration: BoxDecoration(
                                color: colors.surfaceVariant,
                                borderRadius: BorderRadius.circular(AppRadius.md),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.folder, size: 18, color: colors.textSecondary),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      d,
                                      style: TextStyle(fontSize: 13, color: colors.textPrimary),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      dirs.remove(d);
                                      setModalState(() {});
                                    },
                                    child: Icon(Icons.close, size: 16, color: colors.textHint),
                                  ),
                                ],
                              ),
                            ),
                          )),
                    const SizedBox(height: AppSpacing.lg),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                dirs.clear();
                                setModalState(() {});
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: colors.surfaceVariant,
                                  borderRadius: BorderRadius.circular(AppRadius.full),
                                  border: Border.all(color: colors.divider),
                                ),
                                child: Text(
                                  '扫描全部',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: colors.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: GestureDetector(
                              onTap: () async {
                                final result = await _pickDirectory();
                                if (result != null && !dirs.contains(result)) {
                                  dirs.add(result);
                                  setModalState(() {});
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: colors.surfaceVariant,
                                  borderRadius: BorderRadius.circular(AppRadius.full),
                                  border: Border.all(color: colors.divider),
                                ),
                                child: Text(
                                  '添加文件夹',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: colors.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      child: GestureDetector(
                        onTap: () async {
                          await ref.read(localMusicNotifierProvider.notifier).setDirectories(dirs);
                          await ref.read(localMusicNotifierProvider.notifier).scanAll();
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('目录已保存并重新扫描'), duration: Duration(seconds: 2)),
                            );
                          }
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: colors.primary,
                            borderRadius: BorderRadius.circular(AppRadius.full),
                          ),
                          child: Text(
                            '确认并重新扫描',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: colors.textOnPrimary,
                            ),
                          ),
                        ),
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
      },
    );
  }

  Future<String?> _pickDirectory() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath();
      return result;
    } catch (_) {
      return null;
    }
  }
}

class _LocalSongItem extends ConsumerWidget {
  const _LocalSongItem({
    super.key,
    required this.song,
    required this.onPlay,
    required this.onContextMenu,
  });

  final Song song;
  final void Function(Song song) onPlay;
  final void Function(ThemeColors colors, Song song) onContextMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeColorsProvider);
    final playingId = ref.watch(playbackControllerProvider.select((s) => s.currentSong?.id));
    final isPlaying = playingId == song.id;

    return GestureDetector(
      onTap: () => onPlay(song),
      onLongPress: () => onContextMenu(colors, song),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: isPlaying ? colors.primary.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: song.mediaStoreId != null
                  ? QueryArtworkWidget(
                      key: ValueKey(song.mediaStoreId),
                      id: song.mediaStoreId!,
                      type: ArtworkType.AUDIO,
                      keepOldArtwork: true,
                      artworkBorder: BorderRadius.circular(AppRadius.sm),
                      artworkFit: BoxFit.cover,
                      nullArtworkWidget: Icon(
                        isPlaying ? Icons.equalizer : Icons.music_note,
                        size: 22,
                        color: isPlaying ? colors.primary : colors.textHint,
                      ),
                    )
                  : Icon(
                      isPlaying ? Icons.equalizer : Icons.music_note,
                      size: 22,
                      color: isPlaying ? colors.primary : colors.textHint,
                    ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  Text(
                    '${song.artist}${song.album != '未知专辑' ? ' · ${song.album}' : ''}',
                    style: TextStyle(fontSize: 12, color: colors.textHint),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (song.duration > 0)
              Text(
                song.displayDuration,
                style: TextStyle(fontSize: 12, color: colors.textHint),
              ),
            const SizedBox(width: AppSpacing.xs),
            GestureDetector(
              onTap: () => onContextMenu(colors, song),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.more_vert, size: 18, color: colors.textHint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
