import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../shared/widgets/song_list_item.dart';
import '../../player/presentation/mini_player.dart';
import '../application/search_providers.dart';
import '../../player/application/playback_controller.dart';
import '../../player/domain/models/song.dart';
import '../../plugin/domain/plugin_types.dart';
import '../../settings/application/settings_providers.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

DateTime? _globalLastTapTime;

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  static const _tapDebounceMs = 500;
  bool _isFocused = false;
  String _inputText = '';
  Timer? _debounceTimer;
  final _resultsScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final query = ref.read(searchQueryProvider);
    _inputText = query;
    _controller.text = query;
    _focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final defaultSource = ref.read(defaultSourceIdProvider);
      final currentSource = ref.read(searchSourceIdProvider);
      if (currentSource == 'all' || currentSource != defaultSource) {
        ref.read(searchSourceIdProvider.notifier).state = defaultSource;
      }
      final currentQuery = ref.read(searchQueryProvider).trim();
      if (currentQuery.isNotEmpty) {
        unawaited(
          ref
              .read(searchResultsControllerProvider.notifier)
              .start(currentQuery, ref.read(searchSourceIdProvider)),
        );
      }
    });
    _resultsScrollController.addListener(_handleResultsScroll);
    _focusNode.addListener(() {
      setState(() => _isFocused = _focusNode.hasFocus);
    });
    _controller.addListener(() {
      final text = _controller.text;
      if (text != _inputText) {
        setState(() => _inputText = text);
        _debounceTimer?.cancel();
        if (text.isEmpty) {
          ref.read(searchSuggestInputProvider.notifier).state = '';
          return;
        }
        _debounceTimer = Timer(const Duration(milliseconds: 300), () {
          ref.read(searchSuggestInputProvider.notifier).state = text;
        });
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _resultsScrollController.dispose();
    super.dispose();
  }

  bool get _showSuggest => _isFocused && _inputText.isNotEmpty;

  void _performSearch(String query) {
    if (query.trim().isEmpty) return;
    _focusNode.unfocus();
    ref.read(searchSuggestInputProvider.notifier).state = '';
    ref.read(searchQueryProvider.notifier).state = query;
    ref.read(searchHistoryProvider.notifier).addQuery(query);
    ref.read(searchPageProvider.notifier).state = 1;
    unawaited(
      ref
          .read(searchResultsControllerProvider.notifier)
          .start(query, ref.read(searchSourceIdProvider), force: true),
    );
  }

  void _handleResultsScroll() {
    if (!_resultsScrollController.hasClients) return;
    final position = _resultsScrollController.position;
    if (position.maxScrollExtent - position.pixels < 360) {
      unawaited(ref.read(searchResultsControllerProvider.notifier).loadMore());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeColorsProvider);
    final searchState = ref.watch(searchResultsControllerProvider);
    final hotTagsAsync = ref.watch(hotSearchTagsProvider);
    final query = ref.watch(searchQueryProvider);
    final sourceId = ref.watch(searchSourceIdProvider);
    final sources = ref.watch(allAvailableSourcesProvider);
    final searchHistory = ref.watch(searchHistoryProvider);

    ref.listen<String>(defaultSourceIdProvider, (previous, next) {
      if (previous != null && previous != next) {
        ref.read(searchSourceIdProvider.notifier).state = next;
        ref.read(searchPageProvider.notifier).state = 1;
        final query = ref.read(searchQueryProvider);
        if (query.isNotEmpty) {
          unawaited(
            ref
                .read(searchResultsControllerProvider.notifier)
                .start(query, next, force: true),
          );
        }
      }
    });

    ref.listen<String>(searchQueryProvider, (previous, next) {
      if (next.isEmpty) {
        ref.read(searchResultsControllerProvider.notifier).reset();
      } else if (previous != next) {
        unawaited(
          ref
              .read(searchResultsControllerProvider.notifier)
              .start(next, ref.read(searchSourceIdProvider)),
        );
      }
    });

    ref.listen<String>(searchSourceIdProvider, (previous, next) {
      if (previous != null && previous != next) {
        final query = ref.read(searchQueryProvider);
        if (query.isNotEmpty) {
          unawaited(
            ref
                .read(searchResultsControllerProvider.notifier)
                .start(query, next, force: true),
          );
        }
      }
    });

    return Scaffold(
      backgroundColor: colors.background,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildSearchBar(colors, sources, sourceId),
                if (_showSuggest)
                  _buildSearchSuggest(colors)
                else if (query.isEmpty) ...[
                  Expanded(
                    child: hotTagsAsync.when(
                      data: (hotTags) => ListView(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
                        children: [
                          if (searchHistory.isNotEmpty)
                            _buildSearchHistory(colors, searchHistory),
                          const SizedBox(height: AppSpacing.lg),
                          _buildHotTags(colors, hotTags),
                        ],
                      ),
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (_, __) => Center(
                        child: Text(
                          '加载失败',
                          style: TextStyle(color: colors.textHint),
                        ),
                      ),
                    ),
                  ),
                ] else
                  Expanded(
                    child: _buildSearchResults(colors, searchState),
                    /*
                            data: (searchResults) {
                              if (searchResults.isEmpty)
                                return _buildEmptyResult(colors);
                              return _buildSearchResults(colors, searchResults);
                            },
                            loading: () =>
                                const Center(child: CircularProgressIndicator()),
                            error: (_, __) => Center(
                              child: Text(
                                '搜索失败',
                                style: TextStyle(color: colors.textHint),
                              ),
                            ),
                          */
                  ),
              ],
            ),
          ),
          // 底部迷你播放器（键盘弹出时隐藏）
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

  final _sourceButtonKey = GlobalKey();

  Widget _buildSearchBar(
    ThemeColors colors,
    List<SourceInfo> sources,
    String currentSourceId,
  ) {
    final currentSource = sources
        .where((s) => s.id == currentSourceId)
        .firstOrNull;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Icon(Icons.arrow_back, size: 24, color: colors.textPrimary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Container(
              height: 40,
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
                      controller: _controller,
                      focusNode: _focusNode,
                      onSubmitted: _performSearch,
                      onChanged: (value) {
                        if (value.isEmpty) {
                          ref.read(searchQueryProvider.notifier).state = '';
                        }
                      },
                      decoration: InputDecoration(
                        hintText: '搜索音乐、歌手...',
                        border: InputBorder.none,
                        hintStyle: TextStyle(
                          color: colors.textHint,
                          fontSize: 14,
                        ),
                      ),
                      style: TextStyle(color: colors.textPrimary, fontSize: 14),
                    ),
                  ),
                  if (_controller.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _controller.clear();
                        ref.read(searchQueryProvider.notifier).state = '';
                      },
                      child: Icon(
                        Icons.close,
                        size: 18,
                        color: colors.textHint,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          GestureDetector(
            key: _sourceButtonKey,
            onTap: () =>
                _showSourceMenu(context, colors, sources, currentSourceId),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.surface,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: currentSource != null && currentSource.id != 'all'
                    ? _buildSourceIcon(currentSource.id, size: 22)
                    : _buildSourceIcon('all', size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchSuggest(ThemeColors colors) {
    final suggestAsync = ref.watch(searchSuggestResultsProvider);

    return Expanded(
      child: AnimatedOpacity(
        opacity: 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          margin: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            0,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _performSearch(_inputText),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search, size: 18, color: colors.textHint),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: RichText(
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            style: TextStyle(
                              fontSize: 14,
                              color: colors.textSecondary,
                            ),
                            children: [
                              const TextSpan(text: '直接搜索：'),
                              TextSpan(
                                text: _inputText,
                                style: TextStyle(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: colors.surfaceVariant),
              Flexible(
                child: suggestAsync.when(
                  data: (suggestions) {
                    if (suggestions.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Center(
                          child: Text(
                            '暂无搜索建议',
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.textHint,
                            ),
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xs,
                      ),
                      itemCount: suggestions.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        indent: AppSpacing.xxl,
                        color: colors.surfaceVariant,
                      ),
                      itemBuilder: (context, index) {
                        final suggestion = suggestions[index];
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            _controller.text = suggestion;
                            _performSearch(suggestion);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.md,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.music_note,
                                  size: 16,
                                  color: colors.textHint,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    suggestion,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: colors.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  error: (_, __) => Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Center(
                      child: Text(
                        '获取建议失败',
                        style: TextStyle(fontSize: 13, color: colors.textHint),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
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
              const SizedBox(width: AppSpacing.sm),
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
      if (selectedId != null) {
        ref.read(searchSourceIdProvider.notifier).state = selectedId;
        ref.read(searchPageProvider.notifier).state = 1;
        final query = ref.read(searchQueryProvider);
        if (query.isNotEmpty) {
          unawaited(
            ref
                .read(searchResultsControllerProvider.notifier)
                .start(query, selectedId, force: true),
          );
          ref.invalidate(searchSuggestResultsProvider);
        }
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
              '云',
              style: TextStyle(
                fontSize: size * 0.5,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        );
      case 'tx':
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF31C27C), Color(0xFF2AB456)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(size * 0.2),
          ),
          child: Center(
            child: Text(
              'Q',
              style: TextStyle(
                fontSize: size * 0.55,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        );
      case 'kg':
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: const Color(0xFF2EADFB),
            borderRadius: BorderRadius.circular(size * 0.2),
          ),
          child: Center(
            child: Text(
              'K',
              style: TextStyle(
                fontSize: size * 0.55,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        );
      case 'kw':
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF8C00), Color(0xFFFFAA00)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(size * 0.2),
          ),
          child: Center(
            child: Text(
              'K',
              style: TextStyle(
                fontSize: size * 0.55,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        );
      case 'mg':
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B35),
            borderRadius: BorderRadius.circular(size * 0.2),
          ),
          child: Center(
            child: Text(
              'M',
              style: TextStyle(
                fontSize: size * 0.55,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        );
      case 'qsvip':
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF4081), Color(0xFFFF80AB)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(size * 0.2),
          ),
          child: Center(
            child: Text(
              '汽',
              style: TextStyle(
                fontSize: size * 0.5,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        );
      case 'all':
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '聚',
              style: TextStyle(
                fontSize: size * 0.55,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        );
      default:
        return Icon(Icons.music_note, size: size, color: Colors.grey);
    }
  }

  Widget _buildSearchHistory(ThemeColors colors, List<String> history) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '搜索历史',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () =>
                    ref.read(searchHistoryProvider.notifier).clearHistory(),
                child: Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: colors.textHint,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: history.map((tag) {
              return GestureDetector(
                onTap: () {
                  _controller.text = tag;
                  _performSearch(tag);
                },
                onLongPress: () =>
                    ref.read(searchHistoryProvider.notifier).removeQuery(tag),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(fontSize: 13, color: colors.textSecondary),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHotTags(ThemeColors colors, List<String> tags) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '热门搜索',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: tags.asMap().entries.map((entry) {
              final index = entry.key;
              final tag = entry.value;
              return GestureDetector(
                onTap: () {
                  _controller.text = tag;
                  _performSearch(tag);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (index < 3)
                        Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: index == 0
                                ? Colors.red
                                : index == 1
                                ? Colors.orange
                                : Colors.amber,
                          ),
                        )
                      else
                        Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textHint,
                          ),
                        ),
                      const SizedBox(width: 4),
                      Text(
                        tag,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAggregatedResults(
    ThemeColors colors,
    AsyncValue<List<Song>> asyncResults,
  ) {
    final interleavedAsync = ref.watch(interleavedAggregatedProvider);

    return interleavedAsync.when(
      data: (songs) {
        if (songs.isEmpty) return _buildEmptyResult(colors);

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
          itemCount: songs.length,
          itemExtent: SongListItem.itemExtent,
          cacheExtent: 360,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          itemBuilder: (context, index) {
            final song = songs[index];
            return SongListItem(
              song: song,
              index: index,
              showIndex: true,
              showSource: true,
              showCover: true,
              showQuality: true,
              showDuration: true,
              showMenuButton: true,
              onPlayTap: () async {
                final now = DateTime.now();
                final lastTap = _globalLastTapTime;
                final diff = lastTap != null
                    ? now.difference(lastTap).inMilliseconds
                    : null;
                if (lastTap != null && diff! < _tapDebounceMs) {
                  return;
                }
                _globalLastTapTime = now;
                final controller = ref.read(
                  playbackControllerProvider.notifier,
                );
                await controller.setQueue(songs, startIndex: index);
              },
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(
        child: Text('搜索失败', style: TextStyle(color: colors.textHint)),
      ),
    );
  }

  Widget _buildSingleSourceResults(ThemeColors colors, List<Song> songs) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      itemCount: songs.length,
      itemExtent: SongListItem.itemExtent,
      cacheExtent: 360,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemBuilder: (context, index) {
        final song = songs[index];
        return SongListItem(
          song: song,
          index: index,
          showSource: false,
          onPlayTap: () async {
            final now = DateTime.now();
            final lastTap = _globalLastTapTime;
            final diff = lastTap != null
                ? now.difference(lastTap).inMilliseconds
                : null;
            if (lastTap != null && diff! < _tapDebounceMs) {
              return;
            }
            _globalLastTapTime = now;
            final controller = ref.read(playbackControllerProvider.notifier);
            await controller.setQueue(songs, startIndex: index);
          },
        );
      },
    );
  }

  Widget _buildSearchResults(ThemeColors colors, SearchResultsState state) {
    if (state.isLoading && state.songs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.songs.isEmpty) {
      return Center(
        child: Text('鎼滅储澶辫触', style: TextStyle(color: colors.textHint)),
      );
    }
    if (state.songs.isEmpty) return _buildEmptyResult(colors);

    final songs = state.songs;
    final showLoadingRow = state.isLoadingMore;
    return ListView.builder(
      controller: _resultsScrollController,
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      itemCount: songs.length + (showLoadingRow ? 1 : 0),
      cacheExtent: 360,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemBuilder: (context, index) {
        if (index >= songs.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final song = songs[index];
        return SongListItem(
          song: song,
          index: index,
          showIndex: true,
          showSource: true,
          showCover: true,
          showQuality: true,
          showDuration: true,
          showMenuButton: true,
          onPlayTap: () async {
            final now = DateTime.now();
            final lastTap = _globalLastTapTime;
            final diff = lastTap != null
                ? now.difference(lastTap).inMilliseconds
                : null;
            if (lastTap != null && diff! < _tapDebounceMs) return;
            _globalLastTapTime = now;
            final controller = ref.read(playbackControllerProvider.notifier);
            await controller.setQueue(songs, startIndex: index);
          },
        );
      },
    );
  }

  Widget _buildEmptyResult(ThemeColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 48, color: colors.textHint),
          const SizedBox(height: AppSpacing.md),
          Text(
            '未找到相关结果',
            style: TextStyle(fontSize: 14, color: colors.textHint),
          ),
        ],
      ),
    );
  }
}
