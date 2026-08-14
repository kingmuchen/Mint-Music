import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../player/domain/models/song.dart';
import '../../plugin/application/plugin_providers.dart';
import '../../plugin/application/music_source_manager.dart';
import '../../plugin/domain/plugin_types.dart';

final searchQueryProvider = StateProvider<String>((ref) => '');

final searchSourceIdProvider = StateProvider<String>((ref) => 'all');

final searchPageProvider = StateProvider<int>((ref) => 1);

final searchSuggestInputProvider = StateProvider<String>((ref) => '');

final searchSuggestResultsProvider = FutureProvider<List<String>>((ref) async {
  final input = ref.watch(searchSuggestInputProvider);
  if (input.isEmpty) return [];

  final sourceId = ref.watch(searchSourceIdProvider);
  final manager = ref.watch(musicSourceManagerProvider);
  return manager.getSearchSuggestions(input, sourceId: sourceId);
});

final searchResultsProvider = FutureProvider<List<Song>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.isEmpty) return [];

  final sourceId = ref.watch(searchSourceIdProvider);
  final manager = ref.watch(musicSourceManagerProvider);
  final page = ref.watch(searchPageProvider);

  if (sourceId == 'all') {
    final aggregated = await manager.aggregateSearch(
      query,
      page: page,
      limit: 20,
    );
    final allSongs = <Song>[];
    for (final songs in aggregated.values) {
      allSongs.addAll(songs);
    }
    return allSongs;
  }

  return manager.search(query, sourceId: sourceId, page: page, limit: 30);
});

/// State for the visible search list. Pages are appended here instead of
/// replacing the previous FutureProvider value when the list reaches its end.
class SearchResultsState {
  final String query;
  final String sourceId;
  final List<Song> songs;
  final int page;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;

  const SearchResultsState({
    this.query = '',
    this.sourceId = 'all',
    this.songs = const [],
    this.page = 0,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.error,
  });

  SearchResultsState copyWith({
    String? query,
    String? sourceId,
    List<Song>? songs,
    int? page,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    bool clearError = false,
  }) {
    return SearchResultsState(
      query: query ?? this.query,
      sourceId: sourceId ?? this.sourceId,
      songs: songs ?? this.songs,
      page: page ?? this.page,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class SearchResultsNotifier extends StateNotifier<SearchResultsState> {
  SearchResultsNotifier(this._manager) : super(const SearchResultsState());

  static const _pageSize = 30;
  final MusicSourceManager _manager;
  int _requestId = 0;
  String _requestKey = '';
  List<String> _aggregateSources = const [];
  final Map<String, int> _aggregatePages = {};
  final Set<String> _aggregateSourcesWithMore = {};

  Future<void> start(
    String query,
    String sourceId, {
    bool force = false,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      reset();
      return;
    }

    final key = '$sourceId:$normalizedQuery';
    if (key == _requestKey &&
        (state.isLoading ||
            state.isLoadingMore ||
            (!force && state.songs.isNotEmpty))) {
      return;
    }

    final requestId = ++_requestId;
    _requestKey = key;
    _aggregatePages.clear();
    _aggregateSourcesWithMore.clear();
    _aggregateSources = const [];
    state = SearchResultsState(
      query: normalizedQuery,
      sourceId: sourceId,
      isLoading: true,
      hasMore: true,
    );
    await _loadPage(requestId, 1, replace: true);
  }

  Future<void> loadMore() async {
    if (state.query.isEmpty ||
        state.isLoading ||
        state.isLoadingMore ||
        !state.hasMore) {
      return;
    }
    await _loadPage(_requestId, state.page + 1, replace: false);
  }

  void reset() {
    _requestId++;
    _requestKey = '';
    _aggregatePages.clear();
    _aggregateSourcesWithMore.clear();
    _aggregateSources = const [];
    state = const SearchResultsState();
  }

  Future<void> _loadPage(
    int requestId,
    int page, {
    required bool replace,
  }) async {
    if (requestId != _requestId) return;
    state = state.copyWith(
      isLoading: replace,
      isLoadingMore: !replace,
      clearError: true,
    );

    try {
      final pageSongs = state.sourceId == 'all'
          ? await _loadAggregatePage(requestId, page)
          : await _loadSingleSourcePage(state.sourceId, state.query, page);
      if (requestId != _requestId) return;

      final merged = replace
          ? pageSongs
          : _appendUnique(state.songs, pageSongs);
      final appendedAny = merged.length > state.songs.length;
      final hasMore = state.sourceId == 'all'
          ? _aggregateSourcesWithMore.isNotEmpty && (replace || appendedAny)
          // Different source endpoints do not consistently honor the requested
          // page size. In particular, QQ may return a partial non-final page.
          // Continue until the source actually returns no new songs, rather
          // than treating a page shorter than 30 as the final page.
          : pageSongs.isNotEmpty && (replace || appendedAny);
      state = state.copyWith(
        songs: merged,
        page: page,
        isLoading: false,
        isLoadingMore: false,
        hasMore: hasMore,
        clearError: true,
      );
    } catch (error) {
      if (requestId != _requestId) return;
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        error: error.toString(),
        hasMore: false,
      );
    }
  }

  Future<List<Song>> _loadSingleSourcePage(
    String sourceId,
    String query,
    int page,
  ) async {
    return _manager.search(
      query,
      sourceId: sourceId,
      page: page,
      limit: _pageSize,
    );
  }

  Future<List<Song>> _loadAggregatePage(int requestId, int page) async {
    if (page == 1) {
      _aggregateSources = _manager
          .getSearchSupportedSources()
          .map((source) => source.id)
          .where((id) => id != 'all')
          .toSet()
          .toList();
    }

    final sourcePages = <String, int>{};
    for (final source in _aggregateSources) {
      final nextPage = page == 1 ? 1 : (_aggregatePages[source] ?? 0) + 1;
      if (page > 1 && !_aggregateSourcesWithMore.contains(source)) continue;
      sourcePages[source] = nextPage;
    }

    final entries = await Future.wait(
      sourcePages.entries.map((entry) async {
        try {
          final songs = await _manager
              .search(
                state.query,
                sourceId: entry.key,
                page: entry.value,
                limit: _pageSize,
              )
              .timeout(const Duration(seconds: 5));
          return MapEntry(entry.key, songs);
        } catch (_) {
          return MapEntry(entry.key, <Song>[]);
        }
      }),
    );

    if (requestId != _requestId) return [];
    final bySource = <String, List<Song>>{};
    for (final entry in entries) {
      _aggregatePages[entry.key] = sourcePages[entry.key]!;
      if (entry.value.length >= _pageSize) {
        _aggregateSourcesWithMore.add(entry.key);
      } else {
        _aggregateSourcesWithMore.remove(entry.key);
      }
      bySource[entry.key] = entry.value;
    }

    // Keep the familiar aggregate ordering while still appending each page.
    final orderedSources = [
      ...const ['wy', 'kg', 'tx', 'kw', 'mg'],
      ..._aggregateSources.where(
        (source) => !const ['wy', 'kg', 'tx', 'kw', 'mg'].contains(source),
      ),
    ];
    final result = <Song>[];
    var index = 0;
    while (true) {
      var added = false;
      for (final source in orderedSources) {
        final songs = bySource[source];
        if (songs != null && index < songs.length) {
          result.add(songs[index]);
          added = true;
        }
      }
      if (!added) break;
      index++;
    }
    return result;
  }

  List<Song> _appendUnique(List<Song> current, List<Song> next) {
    final result = [...current];
    final seen = result.map((song) => '${song.source}:${song.id}').toSet();
    for (final song in next) {
      if (seen.add('${song.source}:${song.id}')) result.add(song);
    }
    return result;
  }
}

final searchResultsControllerProvider =
    StateNotifierProvider<SearchResultsNotifier, SearchResultsState>((ref) {
      return SearchResultsNotifier(ref.watch(musicSourceManagerProvider));
    });

final aggregatedSearchProvider = FutureProvider<Map<String, List<Song>>>((
  ref,
) async {
  final query = ref.watch(searchQueryProvider);
  if (query.isEmpty) return {};

  final manager = ref.watch(musicSourceManagerProvider);
  return manager.aggregateSearch(query, limit: 15);
});

final interleavedAggregatedProvider = FutureProvider<List<Song>>((ref) async {
  final aggregated = await ref.watch(aggregatedSearchProvider.future);
  if (aggregated.isEmpty) return [];

  const sourceOrder = ['wy', 'kg', 'tx', 'kw', 'mg'];
  final sourceLists = <String, List<Song>>{};
  for (final s in sourceOrder) {
    sourceLists[s] = aggregated[s] ?? [];
  }

  final maxLen = sourceLists.values.fold<int>(
    0,
    (max, list) => list.length > max ? list.length : max,
  );
  final result = <Song>[];

  for (var i = 0; i < maxLen; i++) {
    for (final s in sourceOrder) {
      final list = sourceLists[s]!;
      if (i < list.length) {
        result.add(list[i]);
      }
    }
  }

  return result;
});

final hotSearchTagsProvider = FutureProvider<List<String>>((ref) async {
  final sourceId = ref.watch(searchSourceIdProvider);
  final manager = ref.watch(musicSourceManagerProvider);
  final effectiveSourceId = sourceId == 'all' ? 'wy' : sourceId;
  return manager.getHotSearchTags(sourceId: effectiveSourceId);
});

final searchSuggestionsProvider = FutureProvider<List<String>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.isEmpty) return [];

  final sourceId = ref.watch(searchSourceIdProvider);
  final manager = ref.watch(musicSourceManagerProvider);
  return manager.getSearchSuggestions(query, sourceId: sourceId);
});

final searchHistoryProvider =
    StateNotifierProvider<SearchHistoryNotifier, List<String>>((ref) {
      return SearchHistoryNotifier();
    });

class SearchHistoryNotifier extends StateNotifier<List<String>> {
  SearchHistoryNotifier() : super([]) {
    _loadPersisted();
  }

  /// 最多保留的搜索历史条数，超出时自动删除最旧的。
  static const int _maxHistory = 10;

  static const String _storageKey = 'search_history';

  /// 启动时从 SharedPreferences 恢复搜索历史。
  /// 若加载期间用户已新增搜索词，则合并去重，避免覆盖用户操作。
  Future<void> _loadPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(_storageKey) ?? const [];
      final merged = [...state, ...stored.where((q) => !state.contains(q))];
      if (!mounted) return;
      state = merged.take(_maxHistory).toList();
    } catch (_) {
      // 读取失败时保持空历史，不影响搜索功能
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_storageKey, state);
    } catch (_) {
      // 写入失败时仅丢失持久化，不影响内存中的历史
    }
  }

  void addQuery(String query) {
    if (query.trim().isEmpty) return;
    final trimmed = query.trim();
    final updated = [trimmed, ...state.where((q) => q != trimmed)];
    state = updated.take(_maxHistory).toList();
    unawaited(_persist());
  }

  void removeQuery(String query) {
    state = state.where((q) => q != query).toList();
    unawaited(_persist());
  }

  void clearHistory() {
    state = [];
    unawaited(_persist());
  }
}

final allAvailableSourcesProvider = Provider<List<SourceInfo>>((ref) {
  ref.watch(pluginInitializedProvider);

  final searchSources = ref.watch(searchSupportedSourcesProvider);

  final allSources = <SourceInfo>[const SourceInfo(id: 'all', name: '聚合搜索')];
  final seenIds = <String>{'all'};

  for (final source in searchSources) {
    if (!seenIds.contains(source.id)) {
      allSources.add(source);
      seenIds.add(source.id);
    }
  }

  if (allSources.length == 1) {
    allSources.addAll(SourceInfo.builtInSources);
  }

  return allSources;
});
