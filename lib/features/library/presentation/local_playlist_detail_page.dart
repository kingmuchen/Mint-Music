import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../shared/services/playlist_cmpl_codec.dart';
import '../../../shared/widgets/share_preview_dialog.dart';
import '../../../shared/widgets/music_cover_image.dart';
import '../../../shared/widgets/song_action_sheet.dart';
import '../../../shared/widgets/song_list_item.dart';
import '../application/playlist_providers.dart';
import '../domain/models/playlist.dart';
import '../../player/application/playback_controller.dart';
import '../../player/domain/models/song.dart';

enum SongSortMode {
  addedTime,
  title,
  artist,
  custom,
}

class LocalPlaylistDetailPage extends ConsumerStatefulWidget {
  const LocalPlaylistDetailPage({super.key, required this.playlistId});

  final String playlistId;

  @override
  ConsumerState<LocalPlaylistDetailPage> createState() =>
      _LocalPlaylistDetailPageState();
}

class _LocalPlaylistDetailPageState
    extends ConsumerState<LocalPlaylistDetailPage> {
  SongSortMode _sortMode = SongSortMode.addedTime;
  bool _sortAscending = true;
  List<Song> _sortedSongs = [];
  List<Song> _originalSongs = [];
  bool _isCustomSortMode = false;

  List<Song> _applySort(List<Song> songs) {
    final list = List<Song>.from(songs);
    switch (_sortMode) {
      case SongSortMode.addedTime:
        if (!_sortAscending) {
          list.sort((a, b) => songs.indexOf(b).compareTo(songs.indexOf(a)));
        }
        break;
      case SongSortMode.title:
        list.sort((a, b) {
          final cmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          return _sortAscending ? cmp : -cmp;
        });
        break;
      case SongSortMode.artist:
        list.sort((a, b) {
          final cmp = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
          return _sortAscending ? cmp : -cmp;
        });
        break;
      case SongSortMode.custom:
        break;
    }
    return list;
  }

  void _updateSortedSongs(List<Song> songs) {
    _originalSongs = List<Song>.from(songs);
    _sortedSongs = _isCustomSortMode ? List<Song>.from(songs) : _applySort(songs);
  }

  void _onSortModeChanged(SongSortMode mode) {
    setState(() {
      _sortMode = mode;
      _isCustomSortMode = mode == SongSortMode.custom;
      _sortedSongs = _isCustomSortMode
          ? List<Song>.from(_originalSongs)
          : _applySort(_originalSongs);
    });
    Navigator.pop(context);
  }

  void _onCustomReorder(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex--;
    setState(() {
      final song = _sortedSongs.removeAt(oldIndex);
      _sortedSongs.insert(newIndex, song);
    });
  }

  void _saveCustomSort() {
    final playlistsAsync = ref.read(playlistsProvider);
    playlistsAsync.whenData((playlists) {
      final playlist = playlists.where((p) => p.id == widget.playlistId).firstOrNull;
      if (playlist != null) {
        ref.read(playlistsProvider.notifier).updatePlaylist(
          playlist.copyWith(songs: _sortedSongs),
        );
      }
    });
    setState(() {
      _originalSongs = List<Song>.from(_sortedSongs);
      _isCustomSortMode = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('排序已保存'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _cancelCustomSort() {
    setState(() {
      _sortedSongs = List<Song>.from(_originalSongs);
      _isCustomSortMode = false;
      _sortMode = SongSortMode.addedTime;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeColorsProvider);
    final playlistsAsync = ref.watch(playlistsProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: playlistsAsync.when(
          data: (playlists) {
            final playlist =
                playlists.where((p) => p.id == widget.playlistId).firstOrNull;
            if (playlist == null) {
              return Center(
                child:
                    Text('歌单未找到', style: TextStyle(color: colors.textHint)),
              );
            }
            if (_originalSongs.length != playlist.songs.length ||
                !_listEquals(_originalSongs, playlist.songs)) {
              _updateSortedSongs(playlist.songs);
            }
            return Column(
              children: [
                _buildHeader(context, ref, colors, playlist),
                if (_isCustomSortMode) _buildCustomSortBar(colors),
                Expanded(
                  child: _isCustomSortMode
                      ? _buildReorderableSongList(ref, colors, playlist)
                      : _buildSongList(context, ref, colors, playlist),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
            child: Text('加载失败', style: TextStyle(color: colors.textHint)),
          ),
        ),
      ),
    );
  }

  bool _listEquals(List<Song> a, List<Song> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  Widget _buildCustomSortBar(ThemeColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.08),
        border: Border(
          bottom: BorderSide(color: colors.divider, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.drag_handle, size: 18, color: colors.primary),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '拖拽歌曲调整顺序',
            style: TextStyle(fontSize: 13, color: colors.primary),
          ),
          const Spacer(),
          TextButton(
            onPressed: _cancelCustomSort,
            child: Text('取消', style: TextStyle(color: colors.textHint, fontSize: 13)),
          ),
          const SizedBox(width: AppSpacing.xs),
          TextButton(
            onPressed: _saveCustomSort,
            child: Text('保存', style: TextStyle(color: colors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    ThemeColors colors,
    Playlist playlist,
  ) {
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
          Row(
            children: [
              GestureDetector(
                onTap: () => context.pop(),
                child: Icon(Icons.arrow_back,
                    size: 24, color: colors.textPrimary),
              ),
              const Spacer(),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_horiz,
                    size: 24, color: colors.textSecondary),
                color: colors.surface,
                onSelected: (value) {
                  if (value == 'share') {
                    _sharePlaylist(context, ref, colors, playlist);
                  } else if (value == 'export') {
                    _exportPlaylist(context, ref, colors, playlist);
                  } else if (value == 'edit') {
                    _editPlaylist(context, ref, colors, playlist);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text('编辑歌单',
                        style: TextStyle(color: colors.textPrimary)),
                  ),
                  PopupMenuItem(
                    value: 'share',
                    child: Row(
                      children: [
                        Icon(Icons.share, size: 18, color: colors.textSecondary),
                        const SizedBox(width: 8),
                        Text('分享歌单',
                            style: TextStyle(color: colors.textPrimary)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'export',
                    child: Text('导出歌单',
                        style: TextStyle(color: colors.textPrimary)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  color: colors.surfaceVariant,
                ),
                child: _buildPlaylistCover(colors, playlist),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (playlist.description.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        playlist.description,
                        style: TextStyle(
                            fontSize: 13, color: colors.textSecondary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${playlist.songCount}首歌曲',
                      style:
                          TextStyle(fontSize: 12, color: colors.textHint),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        _buildActionButton(
                            colors, Icons.play_arrow, '播放全部', () {
                          if (_sortedSongs.isNotEmpty) {
                            final controller = ref
                                .read(playbackControllerProvider.notifier);
                            controller.setQueue(_sortedSongs);
                          }
                        }),
                        const SizedBox(width: AppSpacing.sm),
                        _buildActionButton(colors, Icons.shuffle, '随机播放',
                            () {
                          if (_sortedSongs.isNotEmpty) {
                            final songs = [..._sortedSongs]..shuffle();
                            final controller = ref
                                .read(playbackControllerProvider.notifier);
                            controller.setQueue(songs);
                          }
                        }),
                        const SizedBox(width: AppSpacing.sm),
                        _buildSortButton(colors),
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

  Widget _buildSortButton(ThemeColors colors) {
    return GestureDetector(
      onTap: () => _showSortBottomSheet(colors),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colors.primary,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Icon(Icons.sort, size: 14, color: colors.textOnPrimary),
      ),
    );
  }

  void _showSortBottomSheet(ThemeColors colors) {
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg),
                    child: Row(
                      children: [
                        Text(
                          '排序方式',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            setModalState(() {
                              _sortAscending = !_sortAscending;
                            });
                            setState(() {
                              _sortedSongs = _applySort(_originalSongs);
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: colors.surfaceVariant,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _sortAscending
                                      ? Icons.arrow_upward
                                      : Icons.arrow_downward,
                                  size: 14,
                                  color: colors.textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _sortAscending ? '升序' : '降序',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _buildSortOption(
                    colors: colors,
                    icon: Icons.access_time,
                    label: '按添加时间',
                    mode: SongSortMode.addedTime,
                    setModalState: setModalState,
                  ),
                  _buildSortOption(
                    colors: colors,
                    icon: Icons.music_note,
                    label: '按歌曲名',
                    mode: SongSortMode.title,
                    setModalState: setModalState,
                  ),
                  _buildSortOption(
                    colors: colors,
                    icon: Icons.person,
                    label: '按歌手名',
                    mode: SongSortMode.artist,
                    setModalState: setModalState,
                  ),
                  _buildSortOption(
                    colors: colors,
                    icon: Icons.drag_handle,
                    label: '自定义排序',
                    mode: SongSortMode.custom,
                    setModalState: setModalState,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSortOption({
    required ThemeColors colors,
    required IconData icon,
    required String label,
    required SongSortMode mode,
    required StateSetter setModalState,
  }) {
    final isActive = _sortMode == mode;
    return ListTile(
      leading: Icon(icon,
          size: 20, color: isActive ? colors.primary : colors.textSecondary),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          color: isActive ? colors.primary : colors.textPrimary,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      trailing: isActive
          ? Icon(Icons.check, size: 18, color: colors.primary)
          : null,
      onTap: () {
        setModalState(() {
          _sortMode = mode;
        });
        _onSortModeChanged(mode);
      },
    );
  }

  Widget _buildPlaylistCover(ThemeColors colors, Playlist playlist) {
    // 优先使用歌单自己的封面
    if (playlist.coverImgUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: MusicCoverImage(
          key: ValueKey(playlist.coverImgUrl),
          url: playlist.coverImgUrl,
          fit: BoxFit.cover,
          errorWidget: Icon(Icons.music_note, size: 40, color: colors.textHint),
        ),
      );
    }

    // 如果没有歌单封面，使用第一首歌的封面
    final firstSong = playlist.songs.isNotEmpty ? playlist.songs.first : null;
    if (firstSong == null) {
      return Icon(Icons.music_note, size: 40, color: colors.textHint);
    }

    if (firstSong.mediaStoreId != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: QueryArtworkWidget(
          key: ValueKey(firstSong.mediaStoreId),
          id: firstSong.mediaStoreId!,
          type: ArtworkType.AUDIO,
          nullArtworkWidget:
              Icon(Icons.music_note, size: 40, color: colors.textHint),
          keepOldArtwork: true,
          artworkBorder: BorderRadius.circular(AppRadius.lg),
          artworkFit: BoxFit.cover,
        ),
      );
    }

    if (firstSong.coverUrl != null && firstSong.coverUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: MusicCoverImage(
          key: ValueKey(firstSong.coverUrl),
          url: firstSong.coverUrl,
          fit: BoxFit.cover,
          errorWidget:
              Icon(Icons.music_note, size: 40, color: colors.textHint),
        ),
      );
    }

    return Icon(Icons.music_note, size: 40, color: colors.textHint);
  }

  Widget _buildSongCover(ThemeColors colors, Song song) {
    if (song.mediaStoreId != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: QueryArtworkWidget(
          id: song.mediaStoreId as int,
          type: ArtworkType.AUDIO,
          nullArtworkWidget:
              Icon(Icons.music_note, size: 20, color: colors.primary),
          keepOldArtwork: true,
          artworkBorder: BorderRadius.circular(AppRadius.sm),
          artworkFit: BoxFit.cover,
        ),
      );
    }

    if (song.coverUrl != null && song.coverUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: MusicCoverImage(
          url: song.coverUrl,
          fit: BoxFit.cover,
          errorWidget:
              Icon(Icons.music_note, size: 20, color: colors.primary),
        ),
      );
    }

    return Icon(Icons.music_note, size: 20, color: colors.primary);
  }

  Widget _buildActionButton(
      ThemeColors colors, IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colors.primary,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: colors.textOnPrimary),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: colors.textOnPrimary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReorderableSongList(
    WidgetRef ref,
    ThemeColors colors,
    Playlist playlist,
  ) {
    if (_sortedSongs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_off,
                size: 48, color: colors.textHint.withValues(alpha: 0.3)),
            const SizedBox(height: AppSpacing.md),
            Text('歌单为空', style: TextStyle(color: colors.textHint)),
          ],
        ),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      itemCount: _sortedSongs.length,
      onReorder: _onCustomReorder,
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final double elevation = animation.value * 6;
            return Material(
              elevation: elevation,
              color: colors.surface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: child,
            );
          },
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final song = _sortedSongs[index];
        return ListTile(
          key: Key('${playlist.id}_${song.id}_$index'),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.drag_handle, size: 20, color: colors.textHint),
              const SizedBox(width: AppSpacing.xs),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: _buildSongCover(colors, song),
              ),
            ],
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
            '${song.artist} - ${song.album}',
            style: TextStyle(fontSize: 12, color: colors.textHint),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }

  Widget _buildSongList(
    BuildContext context,
    WidgetRef ref,
    ThemeColors colors,
    Playlist playlist,
  ) {
    if (_sortedSongs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_off,
                size: 48, color: colors.textHint.withValues(alpha: 0.3)),
            const SizedBox(height: AppSpacing.md),
            Text('歌单为空', style: TextStyle(color: colors.textHint)),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '在发现页搜索歌曲并添加到歌单',
              style: TextStyle(
                  fontSize: 12, color: colors.textHint.withValues(alpha: 0.6)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      itemCount: _sortedSongs.length,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemBuilder: (context, index) {
        final song = _sortedSongs[index];
        return Dismissible(
          key: Key('${playlist.id}_${song.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            color: colors.error,
            child: Icon(Icons.delete, color: colors.textOnPrimary),
          ),
          confirmDismiss: (_) => _confirmRemoveSong(context, colors, playlist, song),
          onDismissed: (_) {
            ref.read(playlistsProvider.notifier).removeSongFromPlaylist(
              playlist.id,
              song.id,
            );
          },
          child: SongListItem(
            song: song,
            index: index,
            onPlayTap: () {
              final controller = ref.read(playbackControllerProvider.notifier);
              controller.setQueue(_sortedSongs, startIndex: index);
            },
            onMenuTap: () => SongActionSheet.show(context, song: song, playlistSongs: _sortedSongs),
          ),
        );
      },
    );
  }

  /// 右滑删除前的确认弹窗，避免误删
  Future<bool> _confirmRemoveSong(
    BuildContext context,
    ThemeColors colors,
    Playlist playlist,
    Song song,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: Text(
          '删除歌曲',
          style: TextStyle(color: colors.textPrimary, fontSize: 16),
        ),
        content: Text(
          '确定要从歌单「${playlist.name}」中删除《${song.title}》吗？',
          style: TextStyle(color: colors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: TextStyle(color: colors.textHint)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '删除',
              style: TextStyle(
                color: colors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  void _sharePlaylist(
    BuildContext context,
    WidgetRef ref,
    ThemeColors colors,
    Playlist playlist,
  ) {
    SharePreviewDialog.show(context, playlist: playlist);
  }

  Future<void> _exportPlaylist(
    BuildContext context,
    WidgetRef ref,
    ThemeColors colors,
    Playlist playlist,
  ) async {
    try {
      // Convert MintMusic songs to CeruMusic-compatible format
      final List<Map<String, dynamic>> ceruSongs = playlist.songs.map((s) {
        // Derive songmid: strip source prefix from id, or use hash
        String songmid = s.hash ?? s.id;
        if (songmid.startsWith('${s.source}_')) {
          songmid = songmid.substring(s.source!.length + 1);
        }

        return {
          'songmid': songmid,
          'name': s.title,
          'singer': s.artist,
          'albumName': s.album,
          'albumId': '',
          'source': s.source ?? 'local',
          'interval': s.displayDuration,
          'img': s.coverUrl ?? '',
          'lrc': s.lrc,
          'hash': s.hash ?? '',
          'types': <String>[],
          '_types': <String, dynamic>{},
          'typeUrl': <String, dynamic>{},
          'url': '',
        };
      }).toList();

      // Encode the array to .cmpl format (AES encrypt + gzip compress)
      final json = jsonEncode(ceruSongs);
      final cmplBytes = encodeCmpl(json);

      // Write to a temp file
      final tempDir = await getTemporaryDirectory();
      final safeName = playlist.name.replaceAll(RegExp(r'[^\w\u4e00-\u9fff\- ]'), '_');
      final file = File('${tempDir.path}/$safeName.cmpl');
      await file.writeAsBytes(cmplBytes);

      // Share the .cmpl file
      if (context.mounted) {
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/octet-stream')],
          text: '分享歌单：${playlist.name}',
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导出歌单失败：$e'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _editPlaylist(
    BuildContext context,
    WidgetRef ref,
    ThemeColors colors,
    Playlist playlist,
  ) {
    final nameController = TextEditingController(text: playlist.name);
    final descController = TextEditingController(text: playlist.description);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title:
            Text('编辑歌单', style: TextStyle(color: colors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '歌单名称',
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
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: descController,
              decoration: InputDecoration(
                hintText: '歌单描述（可选）',
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
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消', style: TextStyle(color: colors.textHint)),
          ),
          TextButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                ref.read(playlistsProvider.notifier).updatePlaylist(
                  playlist.copyWith(
                    name: name,
                    description: descController.text.trim(),
                  ),
                );
                Navigator.pop(ctx);
              }
            },
            child: Text('保存', style: TextStyle(color: colors.primary)),
          ),
        ],
      ),
    );
  }
}
