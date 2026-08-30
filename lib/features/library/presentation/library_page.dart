import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/utils/responsive_layout.dart';
import '../../../shared/widgets/music_cover_image.dart';
import '../application/playlist_providers.dart';
import '../../player/application/playback_controller.dart';
import '../../plugin/application/plugin_providers.dart';
import '../domain/models/playlist.dart' as local_playlist;
import '../../discover/domain/models/playlist.dart' as discover_playlist;
import '../utils/cerumusic_playlist_importer.dart';

class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeColorsProvider);
    final playlistsAsync = ref.watch(playlistsProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context, colors),
            _buildActionButtons(context, colors, ref),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: playlistsAsync.when(
                data: (playlists) => playlists.isEmpty
                    ? _buildEmptyState(colors)
                    : _buildPlaylistGrid(context, colors, playlists, ref),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text('加载失败', style: TextStyle(color: colors.textHint)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeColors colors) {
    final isTablet = ResponsiveLayout.isTablet(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveLayout.horizontalPadding(context),
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Text(
            '我的歌单',
            style: TextStyle(
              fontSize: isTablet ? 26 : 22,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => context.push('/recently-played'),
            child: Icon(Icons.history, size: isTablet ? 26 : 22, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    ThemeColors colors,
    WidgetRef ref,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: ResponsiveLayout.horizontalPadding(context)),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _showCreateDialog(context, colors, ref),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 16, color: colors.textOnPrimary),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '新建歌单',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colors.textOnPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          GestureDetector(
            onTap: () => _showImportDialog(context, colors, ref),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: colors.textHint),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.file_download,
                    size: 16,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '导入',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
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
          Icon(
            Icons.library_music,
            size: 64,
            color: colors.textHint.withValues(alpha: 0.3),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('还没有歌单', style: TextStyle(fontSize: 16, color: colors.textHint)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '点击上方"新建歌单"开始创建',
            style: TextStyle(
              fontSize: 13,
              color: colors.textHint.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistGrid(
    BuildContext context,
    ThemeColors colors,
    List<local_playlist.Playlist> playlists,
    WidgetRef ref,
  ) {
    final isTablet = ResponsiveLayout.isTablet(context);
    final crossAxisCount = ResponsiveLayout.gridCrossAxisCount(context);

    return GridView.builder(
      // AppShell 将迷你播放器叠放在页面内容之上。为列表底部预留空间，
      // 使最后一行歌单能够完整滚动到播放器上方。
      padding: EdgeInsets.fromLTRB(
        ResponsiveLayout.horizontalPadding(context),
        0,
        ResponsiveLayout.horizontalPadding(context),
        AppSpacing.miniPlayerHeight + AppSpacing.lg,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: isTablet ? 0.85 : 0.8,
        crossAxisSpacing: isTablet ? 16 : AppSpacing.md,
        mainAxisSpacing: isTablet ? 16 : AppSpacing.md,
      ),
      itemCount: playlists.length,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        return _buildPlaylistCard(context, colors, playlist, index, ref);
      },
    );
  }

  Widget _buildPlaylistCard(
    BuildContext context,
    ThemeColors colors,
    local_playlist.Playlist playlist,
    int index,
    WidgetRef ref,
  ) {
    return GestureDetector(
      onTap: () => context.push('/library/playlist/${playlist.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: colors.surfaceVariant,
                    child: _buildPlaylistCover(colors, playlist),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${playlist.songCount}首歌曲',
                    style: TextStyle(fontSize: 11, color: colors.textHint),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _PlaylistAction(
                        icon: Icons.play_arrow,
                        label: '播放',
                        color: colors.primary,
                        onTap: () {
                          if (playlist.songs.isNotEmpty) {
                            ref
                                .read(playbackControllerProvider.notifier)
                                .setQueue(playlist.songs, startIndex: 0);
                          }
                        },
                      ),
                      _PlaylistAction(
                        icon: Icons.edit,
                        label: '编辑',
                        color: colors.textHint,
                        onTap: () =>
                            _showEditDialog(context, colors, ref, playlist),
                      ),
                      _PlaylistAction(
                        icon: Icons.delete,
                        label: '删除',
                        color: colors.textHint,
                        onTap: () =>
                            _confirmDelete(context, colors, ref, playlist),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistCover(
    ThemeColors colors,
    local_playlist.Playlist playlist,
  ) {
    // 优先使用歌单自己的封面
    if (playlist.coverImgUrl.isNotEmpty) {
      return SizedBox.expand(
        child: MusicCoverImage(
          url: playlist.coverImgUrl,
          fit: BoxFit.cover,
          errorWidget: Center(
            child: Icon(Icons.music_note, size: 40, color: colors.textHint),
          ),
        ),
      );
    }

    // 没有歌单封面则使用第一首歌的封面
    final firstSong = playlist.songs.isNotEmpty ? playlist.songs.first : null;
    if (firstSong == null) {
      return Center(
        child: Icon(Icons.music_note, size: 40, color: colors.textHint),
      );
    }

    if (firstSong.mediaStoreId != null) {
      return SizedBox.expand(
        child: QueryArtworkWidget(
          id: firstSong.mediaStoreId!,
          type: ArtworkType.AUDIO,
          artworkBorder: BorderRadius.zero,
          nullArtworkWidget: Center(
            child: Icon(Icons.music_note, size: 40, color: colors.textHint),
          ),
          keepOldArtwork: true,
          artworkFit: BoxFit.cover,
        ),
      );
    }

    if (firstSong.coverUrl != null && firstSong.coverUrl!.isNotEmpty) {
      return SizedBox.expand(
        child: MusicCoverImage(
          url: firstSong.coverUrl,
          fit: BoxFit.cover,
          errorWidget: Center(
            child: Icon(Icons.music_note, size: 40, color: colors.textHint),
          ),
        ),
      );
    }

    return Center(
      child: Icon(Icons.music_note, size: 40, color: colors.textHint),
    );
  }

  void _showCreateDialog(
    BuildContext context,
    ThemeColors colors,
    WidgetRef ref,
  ) {
    final controller = TextEditingController();
    final descController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('新建歌单', style: TextStyle(color: colors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
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
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                ref
                    .read(playlistsProvider.notifier)
                    .createPlaylist(
                      name,
                      description: descController.text.trim(),
                    );
                Navigator.pop(ctx);
              }
            },
            child: Text('创建', style: TextStyle(color: colors.primary)),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(
    BuildContext context,
    ThemeColors colors,
    WidgetRef ref,
    local_playlist.Playlist playlist,
  ) {
    final controller = TextEditingController(text: playlist.name);
    final descController = TextEditingController(text: playlist.description);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('编辑歌单', style: TextStyle(color: colors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
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
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                ref
                    .read(playlistsProvider.notifier)
                    .updatePlaylist(
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

  void _confirmDelete(
    BuildContext context,
    ThemeColors colors,
    WidgetRef ref,
    local_playlist.Playlist playlist,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('删除歌单', style: TextStyle(color: colors.textPrimary)),
        content: Text(
          '确定要删除"${playlist.name}"吗？此操作不可撤销。',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消', style: TextStyle(color: colors.textHint)),
          ),
          TextButton(
            onPressed: () {
              ref.read(playlistsProvider.notifier).deletePlaylist(playlist.id);
              Navigator.pop(ctx);
            },
            child: Text('删除', style: TextStyle(color: colors.error)),
          ),
        ],
      ),
    );
  }

  void _showImportDialog(
    BuildContext context,
    ThemeColors colors,
    WidgetRef ref,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '选择导入方式',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _buildImportOption(
                colors,
                Icons.queue_music,
                '从当前播放列表',
                '将当前播放列表保存为歌单',
                onTap: () {
                  Navigator.pop(ctx);
                  _importFromCurrentPlaylist(context, colors, ref);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              _buildImportOption(
                colors,
                Icons.folder_open,
                '从本地歌单文件',
                '导入 .cmpl/.cpl/.json 歌单文件',
                onTap: () {
                  Navigator.pop(ctx);
                  _importFromLocalFile(context, colors, ref);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              _buildImportOption(
                colors,
                Icons.language,
                '从网络歌单',
                '导入网易云音乐、QQ音乐等平台歌单',
                subtitle: '实验性功能',
                onTap: () {
                  Navigator.pop(ctx);
                  _showNetworkImportDialog(context, colors, ref);
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('取消', style: TextStyle(color: colors.textHint)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImportOption(
    ThemeColors colors,
    IconData icon,
    String title,
    String description, {
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          border: Border.all(color: colors.divider),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, size: 20, color: colors.primary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: colors.textPrimary,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.warning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                          ),
                          child: Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 10,
                              color: colors.warning,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(fontSize: 12, color: colors.textHint),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: colors.textHint),
          ],
        ),
      ),
    );
  }

  void _importFromCurrentPlaylist(
    BuildContext context,
    ThemeColors colors,
    WidgetRef ref,
  ) {
    final playbackState = ref.read(playbackControllerProvider);
    final queue = playbackState.queue;

    if (queue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '当前播放列表为空',
            style: TextStyle(color: colors.textOnPrimary),
          ),
          backgroundColor: colors.warning,
        ),
      );
      return;
    }

    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '从播放列表导入',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '共 ${queue.length} 首歌曲',
                style: TextStyle(fontSize: 13, color: colors.textHint),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '输入歌单名称',
                  hintStyle: TextStyle(color: colors.textHint),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: colors.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: colors.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: colors.primary),
                  ),
                ),
                style: TextStyle(color: colors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('取消', style: TextStyle(color: colors.textHint)),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  TextButton(
                    onPressed: () {
                      final name = controller.text.trim();
                      if (name.isEmpty) return;
                      Navigator.pop(ctx);

                      final localPlaylist = local_playlist.Playlist(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        name: name,
                        description: '从播放列表导入，共 ${queue.length} 首歌曲',
                        source: 'local',
                        createTime: DateTime.now(),
                        updateTime: DateTime.now(),
                        songs: queue,
                      );

                      ref
                          .read(playlistsProvider.notifier)
                          .updatePlaylist(localPlaylist);

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '成功从播放列表导入 ${queue.length} 首歌曲',
                            style: TextStyle(color: colors.textOnPrimary),
                          ),
                          backgroundColor: colors.primary,
                        ),
                      );
                    },
                    child: Text('导入', style: TextStyle(color: colors.primary)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _importFromLocalFile(
    BuildContext context,
    ThemeColors colors,
    WidgetRef ref,
  ) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowCompression: false,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.first;

      if (file.path == null) {
        return;
      }

      final ext = file.path!.split('.').last.toLowerCase();

      List<Map<String, dynamic>> playlistData;

      if (ext == 'cmpl' || ext == 'cpl') {
        playlistData = await CeruMusicPlaylistImporter.importFromFileAsync(
          file.path!,
        );

        if (!CeruMusicPlaylistImporter.validateImportedPlaylist(playlistData)) {
          throw Exception('歌单数据格式不正确或缺少必要字段');
        }
      } else {
        final fileBytes = await File(file.path!).readAsBytes();
        final content = utf8.decode(fileBytes);
        playlistData = _parseJsonPlaylist(content);
      }

      final songs = _convertCeruMusicPlaylistToSongs(playlistData);

      if (songs.isEmpty) {
        throw Exception('歌单中没有有效的歌曲');
      }

      final playlistName = '导入歌单 ${DateTime.now().toString().substring(0, 10)}';

      await ref
          .read(playlistsProvider.notifier)
          .createPlaylistWithSongs(playlistName, songs);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '导入成功！共导入 ${songs.length} 首歌曲',
              style: TextStyle(color: colors.textOnPrimary),
            ),
            backgroundColor: colors.primary,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '导入失败：${e.toString()}',
              style: TextStyle(color: colors.textOnPrimary),
            ),
            backgroundColor: colors.error,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> _parseJsonPlaylist(String jsonText) {
    try {
      final data = jsonDecode(jsonText);
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      } else if (data is Map) {
        if (data.containsKey('songs')) {
          return (data['songs'] as List).cast<Map<String, dynamic>>();
        }
        return [data.cast<String, dynamic>()];
      }
      throw Exception('JSON 格式不正确');
    } catch (e) {
      throw Exception('解析 JSON 失败: $e');
    }
  }

  List<Map<String, dynamic>> _convertCeruMusicPlaylistToSongs(
    List<Map<String, dynamic>> ceruMusicPlaylist,
  ) {
    return ceruMusicPlaylist.map((item) {
      final source = item['source']?.toString() ?? '';
      final songmid = item['songmid']?.toString() ?? '';
      final hash = item['hash']?.toString() ?? '';

      final effectiveId = hash.isNotEmpty
          ? '${source}_$hash'
          : (source.isNotEmpty && songmid.isNotEmpty
                ? '${source}_$songmid'
                : songmid);

      return {
        'id': effectiveId,
        'title': item['name']?.toString() ?? '未知歌曲',
        'artist': item['singer']?.toString() ?? '未知歌手',
        'album': item['albumName']?.toString() ?? '未知专辑',
        'duration': _parseDuration(item['interval']?.toString() ?? '0:00'),
        'coverUrl': item['img']?.toString() ?? '',
        'source': source,
        'sourceUrl': '',
        'lrc': item['lrc']?.toString() ?? '',
        'hash': hash.isNotEmpty ? hash : null,
      };
    }).toList();
  }

  int _parseDuration(String interval) {
    if (interval.isEmpty) return 0;

    try {
      final parts = interval.split(':');
      if (parts.length == 2) {
        final minutes = int.tryParse(parts[0]) ?? 0;
        final seconds = int.tryParse(parts[1]) ?? 0;
        return minutes * 60 + seconds;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  void _showNetworkImportDialog(
    BuildContext context,
    ThemeColors colors,
    WidgetRef ref,
  ) {
    String selectedPlatform = 'wy';
    final urlController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          String placeholderText;
          switch (selectedPlatform) {
            case 'wy':
              placeholderText =
                  '支持链接或ID：https://music.163.com/playlist?id=123456789 或 123456789';
              break;
            case 'tx':
              placeholderText =
                  '支持链接或ID：https://y.qq.com/n/ryqq/playlist/123456789 或 123456789';
              break;
            case 'kw':
              placeholderText =
                  '支持链接或ID：http://www.kuwo.cn/playlist_detail/123456789 或 123456789';
              break;
            case 'kg':
              placeholderText =
                  '支持链接或酷狗码：https://www.kugou.com/yy/special/single/123456789、m.kugou.com/songlist/gcid_xxx 或 酷狗码 123456789';
              break;
            case 'mg':
              placeholderText =
                  '支持链接或ID：https://music.migu.cn/v3/music/playlist/123456789 或 123456789';
              break;
            default:
              placeholderText = '请输入歌单链接或ID';
          }

          return Dialog(
            backgroundColor: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '导入网络歌单',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      '选择导入平台',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        _buildPlatformChip(
                          colors,
                          '网易云音乐',
                          'wy',
                          selectedPlatform,
                          () {
                            setState(() => selectedPlatform = 'wy');
                          },
                        ),
                        _buildPlatformChip(
                          colors,
                          'QQ音乐',
                          'tx',
                          selectedPlatform,
                          () {
                            setState(() => selectedPlatform = 'tx');
                          },
                        ),
                        _buildPlatformChip(
                          colors,
                          '酷我音乐',
                          'kw',
                          selectedPlatform,
                          () {
                            setState(() => selectedPlatform = 'kw');
                          },
                        ),
                        _buildPlatformChip(
                          colors,
                          '酷狗音乐',
                          'kg',
                          selectedPlatform,
                          () {
                            setState(() => selectedPlatform = 'kg');
                          },
                        ),
                        _buildPlatformChip(
                          colors,
                          '咪咕音乐',
                          'mg',
                          selectedPlatform,
                          () {
                            setState(() => selectedPlatform = 'mg');
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      selectedPlatform == 'kg'
                          ? '请输入酷狗音乐歌单链接、手机版链接或酷狗码，系统将自动识别格式并导入歌单中的所有歌曲到本地歌单。'
                          : '请输入${_getPlatformName(selectedPlatform)}歌单链接或歌单ID，系统将自动识别格式并导入歌单中的所有歌曲到本地歌单。',
                      style: TextStyle(fontSize: 12, color: colors.textHint),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: urlController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: placeholderText,
                        hintStyle: TextStyle(
                          color: colors.textHint,
                          fontSize: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          borderSide: BorderSide(color: colors.divider),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          borderSide: BorderSide(color: colors.divider),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          borderSide: BorderSide(color: colors.primary),
                        ),
                      ),
                      style: TextStyle(color: colors.textPrimary, fontSize: 13),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(ctx),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Text(
                              '取消',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        TextButton(
                          onPressed: () async {
                            final url = urlController.text.trim();
                            if (url.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '请输入有效的歌单链接',
                                    style: TextStyle(
                                      color: colors.textOnPrimary,
                                    ),
                                  ),
                                  backgroundColor: colors.error,
                                ),
                              );
                              return;
                            }
                            // 先关闭对话框，然后执行导入
                            if (context.mounted) {
                              Navigator.of(ctx).pop();
                              // 等待一帧确保对话框完全关闭
                              await Future.delayed(
                                const Duration(milliseconds: 50),
                              );
                              if (context.mounted) {
                                await _handleNetworkImport(
                                  context,
                                  colors,
                                  ref,
                                  selectedPlatform,
                                  url,
                                );
                              }
                            }
                          },
                          child: Text(
                            '开始导入',
                            style: TextStyle(color: colors.primary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlatformChip(
    ThemeColors colors,
    String label,
    String value,
    String selected,
    VoidCallback onTap,
  ) {
    final isSelected = value == selected;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? colors.primary : colors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: isSelected ? colors.primary : colors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isSelected ? colors.textOnPrimary : colors.textSecondary,
          ),
        ),
      ),
    );
  }

  String _getPlatformName(String platform) {
    switch (platform) {
      case 'wy':
        return '网易云音乐';
      case 'tx':
        return 'QQ音乐';
      case 'kw':
        return '酷我音乐';
      case 'kg':
        return '酷狗音乐';
      case 'mg':
        return '咪咕音乐';
      default:
        return '音乐平台';
    }
  }

  Future<void> _handleNetworkImport(
    BuildContext context,
    ThemeColors colors,
    WidgetRef ref,
    String platform,
    String input,
  ) async {
    final playlistId = _parsePlaylistId(platform, input);
    if (playlistId == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '无法识别的${_getPlatformName(platform)}歌单链接',
              style: TextStyle(color: colors.textOnPrimary),
            ),
            backgroundColor: colors.error,
          ),
        );
      }
      return;
    }

    if (!context.mounted) return;

    discover_playlist.Playlist? discoverPlaylist;
    String? errorMessage;

    try {
      final manager = ref.read(musicSourceManagerProvider);
      discoverPlaylist = await manager.getPlaylistDetail(
        '${platform}_$playlistId',
        sourceId: platform,
      );
    } catch (e) {
      errorMessage = e.toString();
      print('[导入歌单] 错误: $e');
    }

    if (!context.mounted) return;

    if (errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '导入失败：$errorMessage',
            style: TextStyle(color: colors.textOnPrimary),
          ),
          backgroundColor: colors.error,
        ),
      );
      return;
    }

    if (discoverPlaylist == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '获取歌单失败，请检查链接是否正确',
            style: TextStyle(color: colors.textOnPrimary),
          ),
          backgroundColor: colors.error,
        ),
      );
      return;
    }

    final songs = discoverPlaylist.songs;
    if (songs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '歌单中没有歌曲',
            style: TextStyle(color: colors.textOnPrimary),
          ),
          backgroundColor: colors.warning,
        ),
      );
      return;
    }

    final platformName = _getPlatformName(platform);
    final localPlaylist = local_playlist.Playlist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: '${discoverPlaylist.title} (导入)',
      description: discoverPlaylist.description.isNotEmpty
          ? discoverPlaylist.description
          : '从$platformName导入 - 原歌单：${discoverPlaylist.title}',
      coverImgUrl: discoverPlaylist.coverUrl ?? '',
      source: platform,
      createTime: DateTime.now(),
      updateTime: DateTime.now(),
      songs: songs,
      meta: {'discoverId': '${platform}_$playlistId', 'importSource': platform},
    );

    await ref
        .read(playlistsProvider.notifier)
        .createPlaylistFromModel(localPlaylist);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '从$platformName导入完成！成功导入 ${songs.length} 首歌曲',
            style: TextStyle(color: colors.textOnPrimary),
          ),
          backgroundColor: colors.primary,
        ),
      );
    }
  }

  String? _parsePlaylistId(String platform, String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    switch (platform) {
      case 'wy':
        final wyMatch = RegExp(
          r'(?:music\.163\.com\/.*[?&]id=|playlist\?id=|playlist\/|id=)(\d+)',
          caseSensitive: false,
        ).firstMatch(trimmed);
        if (wyMatch != null) return wyMatch.group(1);
        if (RegExp(r'^\d+$').hasMatch(trimmed)) return trimmed;
        return null;

      case 'tx':
        final txRegexes = [
          RegExp(
            r'(?:y\.qq\.com\/n\/ryqq\/playlist\/|music\.qq\.com\/.*[?&]id=|playlist[?&]id=)(\d+)',
            caseSensitive: false,
          ),
          RegExp(
            r'(?:i\.y\.qq\.com\/n2\/m\/share\/details\/taoge\.html.*[?&]id=)(\d+)',
            caseSensitive: false,
          ),
          RegExp(
            r'(?:i\.y\.qq\.com\/v8\/playsquare\/playlist\.html.*[?&]id=)(\d+)',
            caseSensitive: false,
          ),
          RegExp(r'(?:y\.qq\.com.*[?&]disstid=)(\d+)', caseSensitive: false),
          RegExp(r'[?&]id=(\d+)', caseSensitive: false),
          RegExp(r'[?&]disstid=(\d+)', caseSensitive: false),
          RegExp(r'playlist\/(\d+)', caseSensitive: false),
        ];
        for (final regex in txRegexes) {
          final match = regex.firstMatch(trimmed);
          if (match != null) return match.group(1);
        }
        if (RegExp(r'^\d+$').hasMatch(trimmed)) return trimmed;
        return null;

      case 'kw':
        final kwRegexes = [
          RegExp(
            r'(?:kuwo\.cn\/playlist_detail\/|kuwo\.cn\/.*[?&]pid=)(\d+)',
            caseSensitive: false,
          ),
          RegExp(
            r'(?:m\.kuwo\.cn\/h5app\/playlist\/|kuwo\.cn\/.*[?&]id=)(\d+)',
            caseSensitive: false,
          ),
          RegExp(
            r'm\.kuwo\.cn\/newh5app\/playlist_detail\/(\d+)',
            caseSensitive: false,
          ),
          RegExp(r'[?&](?:pid|id)=(\d+)', caseSensitive: false),
        ];
        for (final regex in kwRegexes) {
          final match = regex.firstMatch(trimmed);
          if (match != null) return match.group(1);
        }
        if (RegExp(r'^\d+$').hasMatch(trimmed)) return trimmed;
        return null;

      case 'kg':
        final kgRegexes = [
          RegExp(
            r'kugou\.com\/yy\/special\/single\/(\d+)',
            caseSensitive: false,
          ),
          RegExp(
            r'm\.kugou\.com\/songlist\/gcid_([a-zA-Z0-9]+)',
            caseSensitive: false,
          ),
          RegExp(r'[?&](?:specialid|id)=(\d+)', caseSensitive: false),
        ];
        for (final regex in kgRegexes) {
          final match = regex.firstMatch(trimmed);
          if (match != null) return match.group(1);
        }
        if (RegExp(r'^\d+$').hasMatch(trimmed)) return trimmed;
        return null;

      case 'mg':
        final mgRegexes = [
          RegExp(
            r'(?:music\.migu\.cn\/v3\/music\/playlist\/)(\d+)',
            caseSensitive: false,
          ),
          RegExp(r'(?:music\.migu\.cn\/.*[?&]id=)(\d+)', caseSensitive: false),
          RegExp(r'[?&]id=(\d+)', caseSensitive: false),
        ];
        for (final regex in mgRegexes) {
          final match = regex.firstMatch(trimmed);
          if (match != null) return match.group(1);
        }
        if (RegExp(r'^\d+$').hasMatch(trimmed)) return trimmed;
        return null;

      default:
        if (RegExp(r'^\d+$').hasMatch(trimmed)) return trimmed;
        return null;
    }
  }
}

class _PlaylistAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _PlaylistAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 2),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}
