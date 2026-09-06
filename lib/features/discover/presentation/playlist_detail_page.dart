import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../shared/widgets/music_cover_image.dart';
import '../../../shared/widgets/song_action_sheet.dart';
import '../../../shared/widgets/song_list_item.dart';
import '../application/discover_providers.dart';
import '../../library/application/playlist_providers.dart';
import '../../library/domain/models/playlist.dart' as local;
import '../../player/application/playback_controller.dart';
import '../../player/domain/models/song.dart';
import '../../player/presentation/mini_player.dart';

class PlaylistDetailPage extends ConsumerStatefulWidget {
  const PlaylistDetailPage({super.key, required this.playlistId});

  final String playlistId;

  @override
  ConsumerState<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage> {
  bool _isMultiSelectMode = false;
  final Set<String> _selectedSongIds = {};
  bool _isFavorited = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkIfFavorited();
    });
  }

  void _checkIfFavorited() {
    final playlistsAsync = ref.read(playlistsProvider);
    final playlistAsync = ref.read(playlistDetailProvider(widget.playlistId));

    playlistAsync.whenData((discoverPlaylist) {
      if (discoverPlaylist == null) return;

      playlistsAsync.whenData((localPlaylists) {
        final exists = localPlaylists.any(
          (p) => p.meta['discoverId'] == widget.playlistId,
        );
        if (mounted) {
          setState(() {
            _isFavorited = exists;
          });
        }
      });
    });
  }

  void _toggleMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = !_isMultiSelectMode;
      if (!_isMultiSelectMode) {
        _selectedSongIds.clear();
      }
    });
  }

  void _toggleSongSelection(String songId) {
    setState(() {
      if (_selectedSongIds.contains(songId)) {
        _selectedSongIds.remove(songId);
      } else {
        _selectedSongIds.add(songId);
      }
    });
  }

  void _selectAllSongs(List<Song> songs) {
    setState(() {
      if (_selectedSongIds.length == songs.length) {
        _selectedSongIds.clear();
      } else {
        _selectedSongIds.clear();
        _selectedSongIds.addAll(songs.map((s) => s.id));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeColorsProvider);
    final playlistAsync = ref.watch(playlistDetailProvider(widget.playlistId));

    return Scaffold(
      backgroundColor: colors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: playlistAsync.when(
              data: (playlist) {
                if (playlist == null) {
                  return Center(
                    child: Text(context.tr('歌单未找到'), style: TextStyle(color: colors.textHint)),
                  );
                }
                return Column(
                  children: [
                    _buildHeader(context, ref, colors, playlist),
                    if (_isMultiSelectMode) _buildMultiSelectBar(colors, playlist.songs),
                    Expanded(
                      child: _buildSongList(ref, colors, playlist.songs),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                child: Text(context.tr('加载失败'), style: TextStyle(color: colors.textHint)),
              ),
            ),
          ),
          // 底部迷你播放器（与搜索页面一致：键盘弹出时隐藏）
          MediaQuery.of(context).viewInsets.bottom > 0
              ? const SizedBox.shrink()
              : Positioned(
                  left: 0,
                  right: 0,
                  bottom: 20,
                  child: RepaintBoundary(child: const MiniPlayer()),
                ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref, ThemeColors colors, playlist) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.primary.withValues(alpha: 0.15),
            colors.background,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              GestureDetector(
                onTap: () => context.pop(),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: Icon(Icons.arrow_back, size: 24, color: colors.textPrimary),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _showMoreActions(context, colors, playlist),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: Icon(Icons.more_horiz, size: 24, color: colors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: MusicCoverImage(
                  url: playlist.coverUrl,
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                  errorWidget: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colors.primary.withValues(alpha: 0.4),
                          colors.surfaceVariant,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Icon(Icons.music_note, size: 48, color: colors.textHint),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      playlist.description,
                      style: TextStyle(fontSize: 13, color: colors.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        _buildActionButton(colors, Icons.play_arrow, context.tr('播放全部'), () {
                          _playAll(playlist.songs);
                        }),
                        const SizedBox(width: AppSpacing.md),
                        _buildFavoriteButton(colors, playlist),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(ThemeColors colors, IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: colors.primary,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: colors.textOnPrimary),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: colors.textOnPrimary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoriteButton(ThemeColors colors, playlist) {
    return GestureDetector(
      onTap: () => _toggleFavorite(playlist),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: _isFavorited ? colors.primary.withValues(alpha: 0.15) : colors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: _isFavorited ? colors.primary : colors.divider,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isFavorited ? Icons.favorite : Icons.favorite_border,
              size: 16,
              color: _isFavorited ? colors.primary : colors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              context.tr(_isFavorited ? '已收藏' : '收藏'),
              style: TextStyle(
                fontSize: 12,
                color: _isFavorited ? colors.primary : colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMultiSelectBar(ThemeColors colors, List<Song> songs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Text(
            context.tr('已选择 ${_selectedSongIds.length} 首'),
            style: TextStyle(fontSize: 14, color: colors.textPrimary),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => _selectAllSongs(songs),
            child: Text(
              context.tr(_selectedSongIds.length == songs.length ? '取消全选' : '全选'),
              style: TextStyle(color: colors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSongList(WidgetRef ref, ThemeColors colors, List<Song> songs) {
    if (songs.isEmpty) {
      return Center(
        child: Text(context.tr('暂无歌曲'), style: TextStyle(color: colors.textHint)),
      );
    }

    return ListView.builder(
      // 预留迷你播放器高度（56px + 底部 20px 间距），保证最后一首歌曲
      // 能滚动到迷你播放器上方而不被遮挡。
      padding: const EdgeInsets.only(
        bottom: AppSpacing.miniPlayerHeight + AppSpacing.lg,
      ),
      itemCount: songs.length,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemBuilder: (context, index) {
        final song = songs[index];
        final isSelected = _selectedSongIds.contains(song.id);

        if (_isMultiSelectMode) {
          return _buildMultiSelectItem(colors, song, isSelected, songs);
        }

        return SongListItem(
          song: song,
          index: index,
          onPlayTap: () async {
            final controller = ref.read(playbackControllerProvider.notifier);
            await controller.setQueue(songs, startIndex: index);
          },
          onMenuTap: () => SongActionSheet.show(context, song: song, playlistSongs: songs),
        );
      },
    );
  }

  Widget _buildMultiSelectItem(ThemeColors colors, Song song, bool isSelected, List<Song> allSongs) {
    return ListTile(
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: isSelected,
            onChanged: (_) => _toggleSongSelection(song.id),
            activeColor: colors.primary,
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: MusicCoverImage(
              url: song.coverUrl,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              errorWidget: Container(
                width: 44,
                height: 44,
                color: colors.surfaceVariant,
                child: Icon(Icons.music_note, size: 20, color: colors.primary),
              ),
            ),
          ),
        ],
      ),
      title: Text(
        song.title,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textPrimary),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${song.artist} - ${song.album}',
        style: TextStyle(fontSize: 12, color: colors.textHint),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _toggleSongSelection(song.id),
    );
  }

  void _showMoreActions(BuildContext context, ThemeColors colors, playlist) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomPadding + 72),
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
                _buildMenuItem(
                  colors,
                  icon: Icons.select_all,
                  label: context.tr(_isMultiSelectMode ? '取消批量选择' : '批量选择'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _toggleMultiSelectMode();
                  },
                ),
                _buildMenuItem(
                  colors,
                  icon: Icons.save_alt,
                  label: context.tr('保存到本地'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _saveToLocal(playlist);
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem(ThemeColors colors, {required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        child: Row(
          children: [
            Icon(icon, size: 22, color: colors.textSecondary),
            const SizedBox(width: AppSpacing.md),
            Text(label, style: TextStyle(fontSize: 15, color: colors.textPrimary)),
          ],
        ),
      ),
    );
  }

  Future<void> _playAll(List<Song> songs) async {
    if (songs.isEmpty) return;
    final controller = ref.read(playbackControllerProvider.notifier);
    await controller.setQueue(songs);
  }

  void _toggleFavorite(playlist) {
    if (_isFavorited) {
      _removeFromFavorites();
    } else {
      _addToFavorites(playlist);
    }
  }

  void _addToFavorites(playlist) async {
    final localPlaylist = local.Playlist(
      id: 'discover_${widget.playlistId}',
      name: playlist.title,
      description: playlist.description,
      coverImgUrl: playlist.coverUrl ?? '',
      source: playlist.source,
      createTime: DateTime.now(),
      updateTime: DateTime.now(),
      songs: playlist.songs,
      meta: {
        'discoverId': widget.playlistId,
        'type': 'discover_playlist',
      },
    );

    await ref.read(playlistsProvider.notifier).createPlaylistFromModel(localPlaylist);

    setState(() {
      _isFavorited = true;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('已收藏到我的歌单')), duration: Duration(seconds: 2)),
      );
    }
  }

  void _removeFromFavorites() async {
    final playlistsAsync = ref.read(playlistsProvider);
    await playlistsAsync.whenData((localPlaylists) async {
      final existingPlaylist = localPlaylists.firstWhere(
        (p) => p.meta['discoverId'] == widget.playlistId,
        orElse: () => throw Exception('未找到收藏的歌单'),
      );
      await ref.read(playlistsProvider.notifier).deletePlaylist(existingPlaylist.id);
    });

    setState(() {
      _isFavorited = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('已取消收藏')), duration: Duration(seconds: 2)),
      );
    }
  }

  void _saveToLocal(playlist) async {
    final localPlaylist = local.Playlist(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      name: playlist.title,
      description: playlist.description,
      coverImgUrl: playlist.coverUrl ?? '',
      source: playlist.source,
      createTime: DateTime.now(),
      updateTime: DateTime.now(),
      songs: playlist.songs,
      meta: {
        'discoverId': widget.playlistId,
        'type': 'saved_playlist',
      },
    );

    await ref.read(playlistsProvider.notifier).createPlaylistFromModel(localPlaylist);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('已保存"${playlist.title}"到本地歌单')),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}
