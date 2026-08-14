import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../shared/widgets/music_cover_image.dart';
import '../application/discover_providers.dart';
import '../domain/models/playlist.dart';
import '../domain/models/leaderboard.dart';
import '../../plugin/domain/plugin_types.dart';
import '../../settings/application/settings_providers.dart';

class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _sourceButtonKey = GlobalKey();
  bool _hasInitialized = false;

  @override
  void initState() {
    super.initState();
    _requestNotificationPermission();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final notifier = ref.read(categoryPlaylistsProvider.notifier);
      if (!notifier.noMore && !notifier.loadingMore) {
        final tagId = ref.read(activeTagIdProvider);
        final srcId = ref.read(discoverSourceIdProvider);
        notifier.fetchPlaylists(sortId: 'hot', tagId: tagId, sourceId: srcId);
      }
    }
  }

  Future<void> _requestNotificationPermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.notification.request();
      if (!status.isGranted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请开启通知权限以使用后台播放功能'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeColorsProvider);
    final tab = ref.watch(discoverTabProvider);

    ref.listen<String>(defaultSourceIdProvider, (previous, next) {
      if (previous != null && previous != next) {
        ref.read(discoverSourceIdProvider.notifier).state = next;
      }
    });

    // 监听源切换，自动重新加载歌单
    ref.listen<String>(discoverSourceIdProvider, (previous, next) {
      if (previous != null && previous != next) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(activeTagIdProvider.notifier).state = '';
            ref.read(activeCategoryNameProvider.notifier).state = '热门';
            ref
                .read(categoryPlaylistsProvider.notifier)
                .fetchPlaylists(
                  sortId: 'hot',
                  tagId: '',
                  sourceId: next,
                  reset: true,
                );
          }
        });
      }
    });

    // 初始化歌单
    if (!_hasInitialized) {
      _hasInitialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final currentSourceId = ref.read(discoverSourceIdProvider);
          ref
              .read(categoryPlaylistsProvider.notifier)
              .fetchPlaylists(
                sortId: 'hot',
                tagId: '',
                sourceId: currentSourceId,
                reset: true,
              );
        }
      });
    }

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context, colors),
            _buildSearchBar(context, colors),
            const SizedBox(height: AppSpacing.md),
            _buildTabBar(colors, tab),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: tab == DiscoverTab.playlists
                  ? _buildPlaylistsTab(colors)
                  : _buildLeaderboardsTab(colors),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Text(
            '发现音乐',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => context.push('/recognize'),
            child: Icon(
              Icons.mic_rounded,
              size: 22,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, ThemeColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: GestureDetector(
        onTap: () => context.push('/search'),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 18, color: colors.textHint),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '搜索音乐、歌手...',
                  style: TextStyle(color: colors.textHint, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(ThemeColors colors, DiscoverTab currentTab) {
    final sourceId = ref.watch(discoverSourceIdProvider);
    final sources = ref.watch(discoverSupportedSourcesProvider);
    final currentSource = sources.where((s) => s.id == sourceId).firstOrNull;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          _buildTabChip(
            label: '歌单',
            isActive: currentTab == DiscoverTab.playlists,
            colors: colors,
            onTap: () => ref.read(discoverTabProvider.notifier).state =
                DiscoverTab.playlists,
          ),
          const SizedBox(width: AppSpacing.sm),
          _buildTabChip(
            label: '排行榜',
            isActive: currentTab == DiscoverTab.leaderboards,
            colors: colors,
            onTap: () => ref.read(discoverTabProvider.notifier).state =
                DiscoverTab.leaderboards,
          ),
          const SizedBox(width: AppSpacing.sm),
          const Spacer(),
          GestureDetector(
            key: _sourceButtonKey,
            onTap: () => _showSourceMenu(context, colors, sources, sourceId),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.surface,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: currentSource != null
                    ? _buildSourceIcon(currentSource.id, size: 20)
                    : Icon(
                        Icons.music_note,
                        size: 20,
                        color: colors.textSecondary,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSourceMenu(
    BuildContext context,
    ThemeColors colors,
    List<SourceInfo> sources,
    String currentSourceId,
  ) {
    final renderBox =
        _sourceButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        renderBox.localToGlobal(Offset.zero, ancestor: overlay),
        renderBox.localToGlobal(
          renderBox.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: colors.surface,
      elevation: 8,
      items: sources.map((source) {
        return PopupMenuItem<String>(
          value: source.id,
          height: 44,
          child: Row(
            children: [
              source.id != 'all'
                  ? _buildSourceIcon(source.id, size: 18)
                  : _buildSourceIcon('all', size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  source.name,
                  style: TextStyle(
                    fontSize: 13,
                    color: source.id == currentSourceId
                        ? colors.primary
                        : colors.textPrimary,
                    fontWeight: source.id == currentSourceId
                        ? FontWeight.w500
                        : FontWeight.normal,
                  ),
                ),
              ),
              if (source.id == currentSourceId)
                Icon(Icons.check, size: 16, color: colors.primary),
            ],
          ),
        );
      }).toList(),
    ).then((selectedId) {
      if (selectedId != null && selectedId != currentSourceId) {
        ref.read(discoverSourceIdProvider.notifier).state = selectedId;
        ref.read(activeTagIdProvider.notifier).state = '';
        ref.read(activeCategoryNameProvider.notifier).state = '热门';
        ref
            .read(categoryPlaylistsProvider.notifier)
            .fetchPlaylists(
              sortId: 'hot',
              tagId: '',
              sourceId: selectedId,
              reset: true,
            );
      }
    });
  }

  Widget _buildSourceIcon(String sourceId, {double size = 20}) {
    switch (sourceId) {
      case 'wy':
        return Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: Color(0xFFE60026),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '网',
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.55,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      case 'kg':
        return Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: Color(0xFF2EADFB),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '狗',
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.55,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      case 'kw':
        return Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: Color(0xFFFF8500),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '我',
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.55,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      case 'tx':
        return Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: Color(0xFF31C27C),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              'Q',
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.55,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      case 'mg':
        return Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: Color(0xFFFF7E00),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '咪',
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.55,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      default:
        return Icon(Icons.music_note, size: size, color: Colors.grey);
    }
  }

  Widget _buildTabChip({
    required String label,
    required bool isActive,
    required ThemeColors colors,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isActive ? colors.primary : colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isActive ? colors.textOnPrimary : colors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildPlaylistsTab(ThemeColors colors) {
    final tagsAsync = ref.watch(playlistTagsProvider);
    final hotTagsAsync = ref.watch(hotPlaylistTagsProvider);
    final activeTagId = ref.watch(activeTagIdProvider);
    final activeCategoryName = ref.watch(activeCategoryNameProvider);
    final playlistsAsync = ref.watch(categoryPlaylistsProvider);

    return Column(
      children: [
        _buildCategoryBar(
          colors,
          tagsAsync,
          hotTagsAsync,
          activeTagId,
          activeCategoryName,
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: playlistsAsync.when(
            data: (playlists) {
              if (playlists.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.library_music_outlined,
                        size: 48,
                        color: colors.textHint,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text('暂无歌单数据', style: TextStyle(color: colors.textHint)),
                      const SizedBox(height: AppSpacing.md),
                      TextButton(
                        onPressed: () {
                          final srcId = ref.read(discoverSourceIdProvider);
                          ref
                              .read(categoryPlaylistsProvider.notifier)
                              .fetchPlaylists(
                                sortId: 'hot',
                                tagId: activeTagId,
                                sourceId: srcId,
                                reset: true,
                              );
                        },
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                );
              }
              return _buildPlaylistGrid(colors, playlists);
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: colors.textHint),
                  const SizedBox(height: AppSpacing.md),
                  Text('加载失败', style: TextStyle(color: colors.textHint)),
                  const SizedBox(height: AppSpacing.md),
                  TextButton(
                    onPressed: () {
                      final srcId = ref.read(discoverSourceIdProvider);
                      ref
                          .read(categoryPlaylistsProvider.notifier)
                          .fetchPlaylists(
                            sortId: 'hot',
                            tagId: activeTagId,
                            sourceId: srcId,
                            reset: true,
                          );
                    },
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryBar(
    ThemeColors colors,
    AsyncValue<List<PlaylistTagGroup>> tagsAsync,
    AsyncValue<List<PlaylistTag>> hotTagsAsync,
    String activeTagId,
    String activeCategoryName,
  ) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        children: [
          _buildTagChip(
            label: '热门',
            isActive: activeTagId.isEmpty,
            colors: colors,
            onTap: () => _onSelectTag('', '热门'),
          ),
          hotTagsAsync.when(
            data: (hotTags) => Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: hotTags.map((tag) {
                return Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.sm),
                  child: _buildTagChip(
                    label: tag.name,
                    isActive: activeTagId == tag.id,
                    colors: colors,
                    onTap: () => _onSelectTag(tag.id, tag.name),
                  ),
                );
              }).toList(),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(width: AppSpacing.sm),
          _buildMoreCategoryButton(colors, tagsAsync, activeTagId),
        ],
      ),
    );
  }

  Widget _buildTagChip({
    required String label,
    required bool isActive,
    required ThemeColors colors,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive
              ? colors.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            color: isActive ? colors.primary : colors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildMoreCategoryButton(
    ThemeColors colors,
    AsyncValue<List<PlaylistTagGroup>> tagsAsync,
    String activeTagId,
  ) {
    return GestureDetector(
      onTap: () => _showCategoryBottomSheet(colors, tagsAsync, activeTagId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '更多分类',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 16, color: colors.textSecondary),
          ],
        ),
      ),
    );
  }

  void _showCategoryBottomSheet(
    ThemeColors colors,
    AsyncValue<List<PlaylistTagGroup>> tagsAsync,
    String activeTagId,
  ) {
    showModalBottomSheet(
      context: context,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 220),
        reverseDuration: Duration(milliseconds: 180),
      ),
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) {
        return tagsAsync.when(
          data: (groups) {
            if (groups.isEmpty) {
              return const SizedBox(
                height: 200,
                child: Center(child: Text('暂无分类数据')),
              );
            }
            return DefaultTabController(
              length: groups.length,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: AppSpacing.md),
                  TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelColor: colors.primary,
                    unselectedLabelColor: colors.textSecondary,
                    indicatorColor: colors.primary,
                    tabs: groups.map((g) => Tab(text: g.name)).toList(),
                  ),
                  SizedBox(
                    height: 250,
                    child: TabBarView(
                      children: groups.map((group) {
                        return Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: group.tags.map((tag) {
                              final isActive = activeTagId == tag.id;
                              return GestureDetector(
                                onTap: () {
                                  _onSelectTag(tag.id, tag.name);
                                  Navigator.pop(ctx);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? colors.primary.withValues(alpha: 0.15)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    tag.name,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isActive
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: isActive
                                          ? colors.primary
                                          : colors.textSecondary,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            );
          },
          loading: () => const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, __) =>
              const SizedBox(height: 200, child: Center(child: Text('加载分类失败'))),
        );
      },
    );
  }

  void _onSelectTag(String tagId, String name) {
    ref.read(activeTagIdProvider.notifier).state = tagId;
    ref.read(activeCategoryNameProvider.notifier).state = name;
    final srcId = ref.read(discoverSourceIdProvider);
    ref
        .read(categoryPlaylistsProvider.notifier)
        .fetchPlaylists(
          sortId: 'hot',
          tagId: tagId,
          sourceId: srcId,
          reset: true,
        );
  }

  Widget _buildPlaylistGrid(ThemeColors colors, List<Playlist> playlists) {
    final notifier = ref.read(categoryPlaylistsProvider.notifier);

    return CustomScrollView(
      controller: _scrollController,
      cacheExtent: 360,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: 0,
            bottom: AppSpacing.xxxl,
          ),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: AppSpacing.md,
              crossAxisSpacing: AppSpacing.md,
              childAspectRatio: 0.82,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final playlist = playlists[index];
              return RepaintBoundary(
                child: _buildPlaylistCard(colors, playlist, index),
              );
            }, childCount: playlists.length),
          ),
        ),
        if (notifier.loadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        if (notifier.noMore && playlists.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(
                child: Text(
                  '没有更多内容',
                  style: TextStyle(fontSize: 12, color: colors.textHint),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPlaylistCard(ThemeColors colors, Playlist playlist, int index) {
    return GestureDetector(
      onTap: () {
        context.push('/playlist/${playlist.id}');
      },
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
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colors.primary.withValues(alpha: 0.3 + index * 0.05),
                          colors.surfaceVariant,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: MusicCoverImage(
                      url: playlist.coverUrl,
                      fit: BoxFit.cover,
                      errorWidget: Icon(
                        Icons.music_note,
                        size: 40,
                        color: colors.textHint,
                      ),
                    ),
                  ),
                  if (playlist.playCount != null &&
                      playlist.playCount!.isNotEmpty)
                    Positioned(
                      top: AppSpacing.xs,
                      right: AppSpacing.xs,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.play_arrow,
                              size: 10,
                              color: colors.textOnPrimary,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              playlist.playCount!,
                              style: TextStyle(
                                fontSize: 10,
                                color: colors.textOnPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
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
                    playlist.title,
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaderboardsTab(ThemeColors colors) {
    final leaderboardsAsync = ref.watch(leaderboardsProvider);

    return leaderboardsAsync.when(
      data: (leaderboards) {
        if (leaderboards.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.show_chart, size: 48, color: colors.textHint),
                const SizedBox(height: AppSpacing.md),
                Text('暂无榜单数据', style: TextStyle(color: colors.textHint)),
              ],
            ),
          );
        }
        return _buildLeaderboardGrid(colors, leaderboards);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: colors.textHint),
            const SizedBox(height: AppSpacing.md),
            Text('加载失败', style: TextStyle(color: colors.textHint)),
            const SizedBox(height: AppSpacing.md),
            TextButton(
              onPressed: () => ref.invalidate(leaderboardsProvider),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaderboardGrid(
    ThemeColors colors,
    List<Leaderboard> leaderboards,
  ) {
    return GridView.builder(
      padding: const EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        bottom: AppSpacing.xxxl,
      ),
      cacheExtent: 360,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
        childAspectRatio: 0.82,
      ),
      itemCount: leaderboards.length,
      itemBuilder: (context, index) {
        final board = leaderboards[index];
        return _buildLeaderboardCard(colors, board, index);
      },
    );
  }

  Widget _buildLeaderboardCard(
    ThemeColors colors,
    Leaderboard board,
    int index,
  ) {
    return GestureDetector(
      onTap: () {
        context.push('/playlist/${board.id}');
      },
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
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colors.primary.withValues(alpha: 0.3 + index * 0.05),
                          colors.surfaceVariant,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: MusicCoverImage(
                      url: board.coverUrl,
                      fit: BoxFit.cover,
                      errorWidget: Icon(
                        Icons.show_chart,
                        size: 40,
                        color: colors.textHint,
                      ),
                    ),
                  ),
                  if (board.playCount != null && board.playCount!.isNotEmpty)
                    Positioned(
                      top: AppSpacing.xs,
                      right: AppSpacing.xs,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.play_arrow,
                              size: 10,
                              color: colors.textOnPrimary,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              board.playCount!,
                              style: TextStyle(
                                fontSize: 10,
                                color: colors.textOnPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
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
                    board.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (board.updateFrequency != null)
                    Text(
                      board.updateFrequency!,
                      style: TextStyle(fontSize: 11, color: colors.textHint),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
