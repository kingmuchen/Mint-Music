import 'dart:convert';
import '../../player/domain/models/song.dart';
import '../../player/domain/models/lyric_line.dart';
import '../../discover/domain/models/playlist.dart';
import '../../discover/domain/models/leaderboard.dart';
import '../domain/music_source_provider.dart';
import '../domain/plugin_types.dart';
import '../data/plugin_service.dart';
import '../data/plugin_host.dart';
import '../data/netease_music_source.dart';
import '../data/kugou_music_source.dart';
import '../data/kw_music_source.dart';
import '../data/tx_music_source.dart';
import '../data/mg_music_source.dart';

class _CacheEntry<T> {
  final T data;
  final DateTime timestamp;
  final Duration ttl;

  _CacheEntry(this.data, this.ttl) : timestamp = DateTime.now();

  bool get isValid => DateTime.now().difference(timestamp) < ttl;
}

class MusicSourceManager {
  final PluginService _pluginService;
  final Map<String, MusicSourceProvider> _builtInSources = {};

  final Map<String, _CacheEntry<List<Playlist>>> _hotPlaylistsCache = {};
  final Map<String, _CacheEntry<Playlist?>> _playlistDetailCache = {};
  final Map<String, _CacheEntry<List<String>>> _searchSuggestionsCache = {};
  final Map<String, _CacheEntry<List<Song>>> _searchPageCache = {};
  final Map<String, _CacheEntry<String?>> _coverCache = {};
  final Map<String, _CacheEntry<Map<String, List<Song>>>> _searchResultsCache =
      {};

  int _suggestRequestId = 0;
  int _searchRequestId = 0;

  static const _hotPlaylistsTTL = Duration(minutes: 5);
  static const _playlistDetailTTL = Duration(minutes: 5);
  static const _searchSuggestionsTTL = Duration(hours: 1);
  static const _searchResultsTTL = Duration(minutes: 5);
  static const _maxConcurrentSources = 5;
  static const _perSourceTimeout = Duration(seconds: 4);

  void clearSearchCache() {
    _searchPageCache.clear();
    _coverCache.clear();
    _searchResultsCache.clear();
  }

  void clearAllCaches() {
    _hotPlaylistsCache.clear();
    _playlistDetailCache.clear();
    _searchSuggestionsCache.clear();
    _searchPageCache.clear();
    _coverCache.clear();
    _searchResultsCache.clear();
  }

  static const Map<String, String> _sourceIdToName = {
    'wy': '网易云音乐',
    'kg': '酷狗音乐',
    'kw': '酷我音乐',
    'tx': 'QQ音乐',
    'mg': '咪咕音乐',
    'qsvip': '汽水VIP',
  };

  static const Map<String, String> _sourceNameToId = {
    '网易云音乐': 'wy',
    '酷狗音乐': 'kg',
    '酷我音乐': 'kw',
    'QQ音乐': 'tx',
    '咪咕音乐': 'mg',
    '汽水VIP': 'qsvip',
  };

  bool _isValidAudioUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  /// 判断 URL 是否为酷我不可播放地址（提示音或加密格式）。
  ///
  /// 玉宁熙等 LX 插件走 `nmobi.kuwo.cn` 车机端，正常情况下返回真实音频；
  /// 仅当响应中包含 `kw_promo` 等标记、或返回 `.mflac` / `.mgg` 加密封装
  /// 时才需要丢弃。不再因 host 是 `nmobi.kuwo.cn` 就全盘拒绝，避免误杀
  /// 可用的车机地址。
  bool _isKuwoPromptUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('kw_promo')) return true;
    if (lower.contains('kuwo_promo')) return true;
    if (lower.contains('/promo/')) return true;
    if (lower.contains('permission_prompt')) return true;
    if (lower.contains('trial')) return true;
    final pathWithoutQuery = lower.split('?').first;
    if (pathWithoutQuery.endsWith('.mflac')) return true;
    if (pathWithoutQuery.endsWith('.mgg')) return true;
    return false;
  }

  MusicSourceManager(this._pluginService) {
    _builtInSources['wy'] = NeteaseMusicSource();
    _builtInSources['kg'] = KugouMusicSource();
    _builtInSources['kw'] = KuwoMusicSource();
    _builtInSources['tx'] = QQMusicSource();
    _builtInSources['mg'] = MiguMusicSource();
  }

  void dispose() {
    for (final entry in _builtInSources.entries) {
      final source = entry.value;
      try {
        if (source is NeteaseMusicSource) source.dispose();
        if (source is KugouMusicSource) source.dispose();
      } catch (_) {}
    }
    _builtInSources.clear();
  }

  MusicSourceProvider? getBuiltInSource(String sourceId) {
    return _builtInSources[sourceId];
  }

  List<SourceInfo> getAvailableSources() {
    final sources = getPluginSupportedSources();
    if (sources.isEmpty) {
      return SourceInfo.builtInSources;
    }
    return sources;
  }

  List<SourceInfo> getPluginSupportedSources() {
    final sources = <SourceInfo>[];
    final seenIds = <String>{};
    for (final host in _pluginService.enabledPlugins) {
      for (final source in host.sources) {
        String id;
        final knownId = _sourceNameToId[source.name];
        if (knownId != null) {
          id = knownId;
        } else {
          id = source.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
          if (id.isEmpty) {
            id = 'src_${source.name.hashCode.toRadixString(36)}';
          }
        }

        if (!seenIds.contains(id)) {
          seenIds.add(id);
          sources.add(SourceInfo(id: id, name: source.name));
        }
      }
    }
    return sources;
  }

  List<SourceInfo> getSearchSupportedSources() {
    final sources = <SourceInfo>[];
    final seenIds = <String>{};

    for (final host in _pluginService.enabledPlugins) {
      for (final entry in host.sourceActions.entries) {
        final sourceId = entry.key;
        final actions = entry.value;

        if (actions
            .map((action) => action.toLowerCase())
            .any((action) => action == 'musicsearch' || action == 'search')) {
          final sourceName =
              _sourceIdToName[sourceId] ??
              host.sources
                  .firstWhere(
                    (s) => _sourceNameToId[s.name] == sourceId,
                    orElse: () =>
                        PluginSourceInfo(name: sourceId, qualities: []),
                  )
                  .name;

          if (!seenIds.contains(sourceId)) {
            seenIds.add(sourceId);
            sources.add(SourceInfo(id: sourceId, name: sourceName));
          }
        }
      }
    }

    for (final entry in _builtInSources.entries) {
      if (!seenIds.contains(entry.key)) {
        sources.add(
          SourceInfo(
            id: entry.key,
            name: _sourceIdToName[entry.key] ?? entry.key,
          ),
        );
        seenIds.add(entry.key);
      }
    }

    return sources;
  }

  List<String> getSupportedQualitiesForSourceId(String sourceId) {
    // 插件优先：返回 JS 插件定义的 qualities 列表
    final host = _findPluginForSource(sourceId);
    if (host != null) {
      final pluginSourceId = _getSourceIdForHost(host, sourceId);
      if (pluginSourceId != null) {
        for (final source in host.sources) {
          final knownId = _sourceNameToId[source.name];
          final effectiveId =
              knownId ??
              source.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
          if (effectiveId == pluginSourceId && source.qualities.isNotEmpty) {
            return source.qualities;
          }
        }
        // 插件有该源的 action 但没有 source info，尝试通过 host.actionKeys 查找
        for (final entry in host.sourceActions.entries) {
          if (entry.key == pluginSourceId) {
            final actions = entry.value;
            if (actions.contains('musicUrl')) {
              return _defaultQualities[sourceId] ?? ['128k', '320k', 'flac'];
            }
          }
        }
      }
    }
    // 无插件时回退到内置默认
    return _defaultQualities[sourceId] ?? ['128k', '320k', 'flac'];
  }

  static const Map<String, List<String>> _defaultQualities = {
    'wy': ['128k', '320k', 'flac', 'flac24bit', 'hires', 'atmos'],
    'tx': ['128k', '320k', 'flac', 'flac24bit', 'hires', 'atmos', 'master'],
    'kg': ['128k', '320k', 'flac', 'flac24bit', 'hires'],
    'kw': ['128k', '320k', 'flac', 'flac24bit', 'hires'],
    'mg': ['128k', '320k', 'flac', 'flac24bit', 'hires', 'atmos', 'master'],
  };

  PluginHost? _findPluginForSource(String sourceId) {
    final hosts = _findPluginHostsForSource(sourceId);
    return hosts.isEmpty ? null : hosts.first;
  }

  String _canonicalSourceId(String sourceId) {
    final normalized = sourceId.trim().toLowerCase();
    if (_builtInSources.containsKey(normalized)) return normalized;

    for (final entry in _sourceNameToId.entries) {
      if (entry.key.toLowerCase() == normalized || entry.value == normalized) {
        return entry.value;
      }
    }

    for (final host in _pluginService.enabledPlugins) {
      for (final pluginSourceId in host.sourceActions.keys) {
        final pluginId = pluginSourceId.trim().toLowerCase();
        if (pluginId == normalized) return pluginSourceId;
        if (_sourceNameToId[pluginSourceId] == normalized) return normalized;
      }
    }

    return sourceId;
  }

  List<PluginHost> _findPluginHostsForSource(String sourceId) {
    final hosts = <PluginHost>[];
    for (final host in _pluginService.enabledPlugins) {
      if (_getSourceIdForHost(host, sourceId) != null) hosts.add(host);
    }
    return hosts;
  }

  String? _getSourceIdForHost(PluginHost host, String sourceId) {
    print('[MusicSourceManager] _getSourceIdForHost: 查找 sourceId=$sourceId');
    print(
      '[MusicSourceManager] sourceActions keys: ${host.sourceActions.keys.toList()}',
    );

    if (host.sourceActions.containsKey(sourceId)) {
      print('[MusicSourceManager] 直接匹配: $sourceId');
      return sourceId;
    }

    for (final entry in host.sourceActions.entries) {
      final pluginSourceId = entry.key;
      final knownId = _sourceNameToId[pluginSourceId];
      if (knownId == sourceId) {
        print('[MusicSourceManager] 通过名称映射匹配: $pluginSourceId -> $sourceId');
        return pluginSourceId;
      }

      final normalizedName = pluginSourceId.toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9]'),
        '',
      );
      if (normalizedName == sourceId) {
        print(
          '[MusicSourceManager] 通过规范化匹配: $pluginSourceId -> $normalizedName',
        );
        return pluginSourceId;
      }
    }

    for (final source in host.sources) {
      final knownId = _sourceNameToId[source.name];
      if (knownId == sourceId) {
        print('[MusicSourceManager] 通过sources匹配: ${source.name} -> $sourceId');
        return sourceId;
      }
    }

    print('[MusicSourceManager] 未找到匹配');
    return null;
  }

  String _resolvePluginSourceId(String sourceId) {
    return sourceId;
  }

  Future<List<Song>> search(
    String query, {
    String sourceId = 'wy',
    int page = 1,
    int limit = 30,
  }) async {
    if (query.isEmpty) return [];

    final effectiveSourceId = _canonicalSourceId(sourceId);
    final cacheKey = '$effectiveSourceId:$query:$page:$limit';
    final cached = _searchPageCache[cacheKey];
    if (cached != null && cached.isValid) return cached.data;

    final hosts = _findPluginHostsForSource(effectiveSourceId);
    for (final host in hosts) {
      final pluginSourceId = _getSourceIdForHost(host, effectiveSourceId);
      if (pluginSourceId != null) {
        final resolvedSourceId = _resolvePluginSourceId(pluginSourceId);

        if (host.supportsSearch(resolvedSourceId)) {
          try {
            print(
              '[MusicSourceManager] 尝试插件搜索: source=$sourceId, query=$query',
            );
            final resultJson = await host.search(
              resolvedSourceId,
              query,
              page: page,
              limit: limit,
            );
            if (resultJson != null && resultJson.isNotEmpty) {
              print(
                '[MusicSourceManager] 插件搜索成功: source=$sourceId, 结果长度=${resultJson.length}',
              );
              final results = _parsePluginSearchResult(
                resultJson,
                effectiveSourceId,
              );
              if (results.isNotEmpty) {
                _searchPageCache[cacheKey] = _CacheEntry(
                  results,
                  _searchResultsTTL,
                );
                return results;
              }
            }
          } catch (e) {
            print(
              '[MusicSourceManager] Plugin search failed for $sourceId: $e',
            );
          }

          try {
            final resultJson = await host.searchWithHandler(
              resolvedSourceId,
              query,
              page: page,
              limit: limit,
            );
            if (resultJson != null && resultJson.isNotEmpty) {
              print(
                '[MusicSourceManager] 插件searchWithHandler成功: source=$sourceId',
              );
              final results = _parsePluginSearchResult(
                resultJson,
                effectiveSourceId,
              );
              if (results.isNotEmpty) {
                _searchPageCache[cacheKey] = _CacheEntry(
                  results,
                  _searchResultsTTL,
                );
                return results;
              }
            }
          } catch (e) {
            print(
              '[MusicSourceManager] Plugin searchWithHandler failed for $sourceId: $e',
            );
          }
        }
      }
    }

    final builtIn = _builtInSources[effectiveSourceId];
    if (builtIn != null) {
      try {
        print('[MusicSourceManager] 使用内置源搜索: source=$sourceId, query=$query');
        final results = await builtIn.search(query, page: page, limit: limit);
        print(
          '[MusicSourceManager] 内置源搜索完成: source=$sourceId, 结果数量=${results.length}',
        );
        _searchPageCache[cacheKey] = _CacheEntry(results, _searchResultsTTL);
        return results;
      } catch (e) {
        print('[MusicSourceManager] Built-in search failed for $sourceId: $e');
        return [];
      }
    }

    print('[MusicSourceManager] 没有找到可用的搜索源: $sourceId');
    return [];
  }

  Future<Map<String, List<Song>>> aggregateSearch(
    String query, {
    List<String>? sourceIds,
    int page = 1,
    int limit = 20,
  }) async {
    if (query.isEmpty) return {};

    final ids =
        sourceIds ?? getSearchSupportedSources().map((s) => s.id).toList();
    final cacheKey = 'all:${ids.join(",")}:$query:$page:$limit';
    final cached = _searchResultsCache[cacheKey];
    if (cached != null && cached.isValid) {
      print('[MusicSourceManager] 搜索结果缓存命中: $cacheKey');
      return cached.data;
    }

    final requestId = ++_searchRequestId;

    final results = <String, List<Song>>{};
    final remainingIds = List<String>.from(ids);
    final sourceOrder = ['wy', 'kg', 'tx', 'kw', 'mg'];
    remainingIds.sort((a, b) {
      final ai = sourceOrder.indexOf(a);
      final bi = sourceOrder.indexOf(b);
      if (ai == -1 && bi == -1) return 0;
      if (ai == -1) return 1;
      if (bi == -1) return -1;
      return ai.compareTo(bi);
    });

    while (remainingIds.isNotEmpty) {
      if (requestId != _searchRequestId) {
        print('[MusicSourceManager] 搜索查询已变更，取消聚合搜索');
        return results;
      }

      final batch = remainingIds.take(_maxConcurrentSources).toList();
      remainingIds.removeRange(0, batch.length);

      final futures = batch.map((id) async {
        try {
          final songs = await search(
            query,
            sourceId: id,
            page: page,
            limit: limit,
          ).timeout(_perSourceTimeout);
          if (requestId == _searchRequestId) {
            results[id] = songs;
          }
        } catch (e) {
          print('[MusicSourceManager] 聚合搜索超时或失败: $id, $e');
          if (requestId == _searchRequestId) {
            results[id] = [];
          }
        }
      });

      await Future.wait(futures);
    }

    _searchResultsCache[cacheKey] = _CacheEntry(results, _searchResultsTTL);
    return results;
  }

  Future<List<String>> getSearchSuggestions(
    String query, {
    String sourceId = 'wy',
  }) async {
    if (query.isEmpty) return [];

    final cacheKey = '$sourceId:$query';
    final cached = _searchSuggestionsCache[cacheKey];
    if (cached != null && cached.isValid) {
      print('[MusicSourceManager] 搜索建议缓存命中: $cacheKey');
      return cached.data;
    }

    final requestId = ++_suggestRequestId;

    final result = await _getSearchSuggestionsInternal(
      query,
      sourceId: sourceId,
      requestId: requestId,
    );
    _searchSuggestionsCache[cacheKey] = _CacheEntry(
      result,
      _searchSuggestionsTTL,
    );
    return result;
  }

  Future<List<String>> _getSearchSuggestionsInternal(
    String query, {
    String sourceId = 'wy',
    int requestId = 0,
  }) async {
    if (sourceId == 'all') {
      final suggestions = <String>[];
      final seen = <String>{};

      void addSuggestion(String item) {
        final normalized = item.trim();
        if (normalized.isEmpty || seen.contains(normalized)) return;
        seen.add(normalized);
        suggestions.add(normalized);
      }

      final sources = getSearchSupportedSources()
          .where((s) => s.id != 'all')
          .toList();
      final futures = sources.map((source) async {
        if (requestId != _suggestRequestId) return;
        try {
          final sourceSuggestions = await _getSearchSuggestionsForSource(
            query,
            sourceId: source.id,
          );
          if (requestId != _suggestRequestId) return;
          for (final item in sourceSuggestions) {
            addSuggestion(item);
            if (suggestions.length >= 10) return;
          }
        } catch (_) {}
      });

      await Future.wait(futures);

      if (suggestions.isEmpty && requestId == _suggestRequestId) {
        try {
          final aggregated = await aggregateSearch(query, limit: 5);
          for (final songs in aggregated.values) {
            for (final song in songs) {
              addSuggestion('${song.title} - ${song.artist}');
              if (suggestions.length >= 10) break;
            }
            if (suggestions.length >= 10) break;
          }
        } catch (_) {}
      }

      return suggestions;
    }

    return _getSearchSuggestionsForSource(query, sourceId: sourceId);
  }

  Future<List<String>> _getSearchSuggestionsForSource(
    String query, {
    String sourceId = 'wy',
  }) async {
    final effectiveSourceId = _canonicalSourceId(sourceId);
    final hosts = _findPluginHostsForSource(effectiveSourceId);
    for (final host in hosts) {
      final pluginSourceId =
          _getSourceIdForHost(host, effectiveSourceId) ?? effectiveSourceId;
      try {
        final hasMethod = host.hasMethod('search');
        if (hasMethod) {
          final result = await host.search(
            pluginSourceId,
            query,
            page: 1,
            limit: 8,
          );
          if (result != null) {
            final songs = _parsePluginSearchResult(result, effectiveSourceId);
            final suggestions = songs
                .map((s) => '${s.title} - ${s.artist}')
                .where((s) => s.trim().isNotEmpty)
                .toList();
            if (suggestions.isNotEmpty) return suggestions;
          }
        }
      } catch (_) {}

      try {
        final result = await host.searchWithHandler(
          pluginSourceId,
          query,
          page: 1,
          limit: 8,
        );
        if (result != null && result.isNotEmpty) {
          final songs = _parsePluginSearchResult(result, effectiveSourceId);
          final suggestions = songs
              .map((s) => '${s.title} - ${s.artist}')
              .where((s) => s.trim().isNotEmpty)
              .toList();
          if (suggestions.isNotEmpty) return suggestions;
        }
      } catch (_) {}
    }

    final builtIn = _builtInSources[effectiveSourceId];
    if (builtIn != null) {
      try {
        final suggestions = await builtIn.getSearchSuggestions(query);
        if (suggestions.isNotEmpty) return suggestions;
      } catch (_) {}

      try {
        final songs = await search(
          query,
          sourceId: effectiveSourceId,
          page: 1,
          limit: 8,
        );
        final suggestions = songs
            .map((s) => '${s.title} - ${s.artist}')
            .where((s) => s.trim().isNotEmpty)
            .toList();
        if (suggestions.isNotEmpty) return suggestions;
      } catch (_) {}
    }

    return [];
  }

  Future<List<String>> getHotSearchTags({String sourceId = 'wy'}) async {
    // The search menu may contain a plugin's display/name ID instead of the
    // canonical built-in ID. Resolve it before looking up the built-in source
    // so hot search follows the same source mapping as search itself.
    final effectiveSourceId = _canonicalSourceId(sourceId);
    final builtIn = _builtInSources[effectiveSourceId];
    if (builtIn != null) {
      try {
        final result = await builtIn.getHotSearchTags();
        print(
          '[MusicSourceManager] 热门搜索: source=$sourceId -> $effectiveSourceId, count=${result.length}',
        );
        return result;
      } catch (_) {}
    }

    // Do not show hard-coded keywords when the selected source is unavailable.
    // Returning an empty list lets the UI represent the actual source state.
    return const <String>[];
  }

  List<Song> _parsePluginSearchResult(String resultJson, String sourceId) {
    try {
      var decoded = jsonDecode(resultJson);

      if (decoded is String) {
        try {
          decoded = jsonDecode(decoded);
        } catch (_) {}
      }

      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map((item) => _musicInfoToSong(item, sourceId))
            .toList();
      }

      if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('list')) {
          final list = decoded['list'] as List? ?? [];
          return list
              .whereType<Map<String, dynamic>>()
              .map((item) => _musicInfoToSong(item, sourceId))
              .toList();
        }

        if (decoded.containsKey('data')) {
          final data = decoded['data'];
          if (data is List) {
            return data
                .whereType<Map<String, dynamic>>()
                .map((item) => _musicInfoToSong(item, sourceId))
                .toList();
          }
          if (data is Map && data.containsKey('list')) {
            final list = data['list'] as List? ?? [];
            return list
                .whereType<Map<String, dynamic>>()
                .map((item) => _musicInfoToSong(item, sourceId))
                .toList();
          }
        }
      }

      print('[MusicSourceManager] 无法识别的搜索结果格式: ${decoded.runtimeType}');
      return [];
    } catch (e) {
      print('[MusicSourceManager] Failed to parse plugin search result: $e');
      return [];
    }
  }

  Song _musicInfoToSong(Map<String, dynamic> info, String sourceId) {
    String? songId;
    final pluginSongId = info['songId'] ?? info['songid'];
    if (info['songmid'] != null) {
      songId = info['songmid'].toString();
    } else if (info['hash'] != null) {
      songId = info['hash'].toString();
    } else if (info['id'] != null) {
      songId = info['id'].toString();
    } else if (info['songId'] != null) {
      songId = info['songId'].toString();
    }

    String? artist;
    if (info['singer'] != null) {
      artist = info['singer'].toString();
    } else if (info['artist'] != null) {
      if (info['artist'] is List) {
        artist = (info['artist'] as List).map((e) => e.toString()).join('/');
      } else {
        artist = info['artist'].toString();
      }
    } else if (info['artists'] != null) {
      if (info['artists'] is List) {
        artist = (info['artists'] as List)
            .map((e) {
              if (e is Map) return e['name']?.toString() ?? e.toString();
              return e.toString();
            })
            .join('/');
      } else {
        artist = info['artists'].toString();
      }
    }

    String? album;
    if (info['albumName'] != null) {
      album = info['albumName'].toString();
    } else if (info['album'] != null) {
      if (info['album'] is Map) {
        album = info['album']['name']?.toString();
      } else {
        album = info['album'].toString();
      }
    } else if (info['album_name'] != null) {
      album = info['album_name'].toString();
    }

    String? coverUrl;
    if (info['picUrl'] != null) {
      coverUrl = info['picUrl'].toString();
    } else if (info['pic'] != null) {
      coverUrl = info['pic'].toString();
    } else if (info['cover'] != null) {
      coverUrl = info['cover'].toString();
    } else if (info['img'] != null) {
      coverUrl = info['img'].toString();
    } else if (info['albumImg'] != null) {
      coverUrl = info['albumImg'].toString();
    } else if (info['album'] != null && info['album'] is Map) {
      final album = info['album'] as Map;
      if (album['picUrl'] != null) {
        coverUrl = album['picUrl'].toString();
      } else if (album['pic'] != null) {
        coverUrl = album['pic'].toString();
      }
    } else if (info['al'] != null && info['al'] is Map) {
      final al = info['al'] as Map;
      if (al['picUrl'] != null) {
        coverUrl = al['picUrl'].toString();
      }
    } else if (info['pic_id'] != null) {
      final picId = info['pic_id'].toString();
      if (sourceId == 'wy') {
        coverUrl = 'https://p3.music.126.net/$picId/${picId}_300x300.jpg';
      }
    } else if (info['img3'] != null) {
      coverUrl = info['img3'].toString();
      if (!coverUrl!.startsWith('http')) {
        coverUrl = 'http://d.musicapp.migu.cn$coverUrl';
      }
    } else if (info['img2'] != null) {
      coverUrl = info['img2'].toString();
      if (!coverUrl!.startsWith('http')) {
        coverUrl = 'http://d.musicapp.migu.cn$coverUrl';
      }
    } else if (info['img1'] != null) {
      coverUrl = info['img1'].toString();
      if (!coverUrl!.startsWith('http')) {
        coverUrl = 'http://d.musicapp.migu.cn$coverUrl';
      }
    } else if (info['songmid'] != null && sourceId == 'kw') {
      final songmid = info['songmid'].toString();
      coverUrl =
          'http://artistpicserver.kuwo.cn/pic.web?corp=kuwo&type=rid_pic&pictype=500&size=500&rid=$songmid';
    }

    String? title;
    if (info['name'] != null) {
      title = info['name'].toString();
    } else if (info['songname'] != null) {
      title = info['songname'].toString();
    } else if (info['title'] != null) {
      title = info['title'].toString();
    } else if (info['songName'] != null) {
      title = info['songName'].toString();
    }

    final lxMeta = Map<String, dynamic>.from(info);
    lxMeta.addAll({
      'songmid': info['songmid']?.toString() ?? songId,
      'songId': pluginSongId,
      'songid': pluginSongId,
      'hash': info['hash']?.toString(),
      'albumName': album ?? '',
      'img': coverUrl,
      'name': title ?? '',
      'singer': artist ?? '',
      'source': sourceId,
    });

    return Song(
      id: songId ?? '${DateTime.now().millisecondsSinceEpoch}',
      title: title ?? '未知歌曲',
      artist: artist ?? '未知艺术家',
      album: album ?? '',
      coverUrl: coverUrl,
      source: sourceId,
      lyricUrl: sourceId == 'tx' ? pluginSongId?.toString() : null,
      duration: info['duration'] != null
          ? _parseDurationSeconds(info['duration'])
          : 0,
      hash: info['hash']?.toString(),
      lx: lxMeta,
    );
  }

  int _parseDurationSeconds(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.round();
    final text = value.toString();
    final direct = int.tryParse(text);
    if (direct != null) return direct;
    final parts = text.split(':').map((e) => int.tryParse(e) ?? 0).toList();
    if (parts.length == 2) return parts[0] * 60 + parts[1];
    if (parts.length == 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
    return 0;
  }

  Future<List<Song>> resolveSongUrls(List<Song> songs) async {
    // Remote LX URLs are short-lived and some plugins use one JS request
    // context. Keep explicit eager resolution sequential; normal playback
    // resolves only the current song.
    final resolved = <Song>[];
    for (final song in songs) {
      if (song.source == null ||
          song.source == 'local' ||
          song.sourceUrl != null) {
        resolved.add(song);
        continue;
      }

      try {
        final result = await getMusicUrlResult(song);
        resolved.add(
          result == null
              ? song.copyWith(sourceUrl: '')
              : _applyMusicUrlResult(song, result),
        );
      } catch (_) {
        resolved.add(song.copyWith(sourceUrl: ''));
      }
    }
    return resolved;
  }

  Future<Song> resolveSingleSongUrl(
    Song song, {
    Set<String> excludedUrls = const <String>{},
  }) async {
    if (song.source == null || song.source == 'local') return song;
    final result = await getMusicUrlResult(song, excludedUrls: excludedUrls);
    if (result != null && result.url.isNotEmpty) {
      return _applyMusicUrlResult(song, result);
    }
    return song;
  }

  Song _applyMusicUrlResult(Song song, PluginMusicUrlResult result) {
    return song.copyWith(
      sourceUrl: result.url,
      sourceHeaders: result.headers.isEmpty ? null : result.headers,
      sourceQuality: result.quality.isEmpty ? null : result.quality,
      clearSourceHeaders: result.headers.isEmpty,
      clearSourceQuality: result.quality.isEmpty,
    );
  }

  List<String> _qualityFallbackChain(
    String requested, {
    List<String>? supported,
    bool preferKuwoCompatibleQuality = false,
  }) {
    const order = <String>[
      '128k',
      '192k',
      '320k',
      'flac',
      'flac24bit',
      'hires',
      'atmos',
      'master',
      '24bit',
    ];
    final allowed = supported == null || supported.isEmpty
        ? order.toSet()
        : supported.toSet();
    final result = <String>[];

    void add(String value) {
      final isKuwoCompatibilityFallback =
          preferKuwoCompatibleQuality && value == '320k';
      if ((allowed.contains(value) || isKuwoCompatibilityFallback) &&
          !result.contains(value)) {
        result.add(value);
      }
    }

    // Kuwo may return a valid audio URL for an unrestricted lossless request,
    // but the media is the "free listening permission" prompt instead of the
    // requested song.  LX Music and CeruMusic avoid this by normally resolving
    // a regular MP3 URL first. Keep lossless URLs as retry candidates.
    if (preferKuwoCompatibleQuality &&
        requested != '128k' &&
        requested != '192k' &&
        requested != '320k') {
      add('320k');
    }

    add(requested);
    final index = order.indexOf(requested);
    if (index >= 0) {
      for (var i = index - 1; i >= 0; i--) {
        add(order[i]);
      }
    }
    if (index < 0) {
      add('320k');
      add('128k');
    }
    return result.isEmpty ? <String>[requested] : result;
  }

  List<String> _getPluginQualities(PluginHost host, String sourceId) {
    for (final source in host.sources) {
      final knownId = _sourceNameToId[source.name];
      final effectiveId =
          knownId ??
          source.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (effectiveId == sourceId && source.qualities.isNotEmpty) {
        return source.qualities;
      }
    }
    return const <String>[];
  }

  Future<List<String>> getMusicUrlCandidates(
    Song song, {
    String quality = '320k',
    Set<String> excludedUrls = const <String>{},
  }) async {
    final results = await getMusicUrlResultCandidates(
      song,
      quality: quality,
      excludedUrls: excludedUrls,
    );
    return results.map((result) => result.url).toList();
  }

  Future<List<PluginMusicUrlResult>> getMusicUrlResultCandidates(
    Song song, {
    String quality = '320k',
    Set<String> excludedUrls = const <String>{},
    bool includeQualityFallbacks = false,
  }) async {
    final sourceId = song.source;
    if (sourceId == null) return const <PluginMusicUrlResult>[];

    final musicInfo = _buildPluginMusicInfo(song, sourceId);
    final results = <PluginMusicUrlResult>[];

    // 酷我源特殊处理：玉宁熙等 LX 插件走 nmobi.kuwo.cn 车机端，对 VIP 歌曲
    // 会返回“已为您开启免费听歌权限”提示音。内置 kw 源同样走 nmobi 接口，
    // 但使用随机 user/loginUid 并校验响应时长/码率，可过滤提示音。
    // 因此 kw 源先尝试内置解析；若内置成功，直接返回内置结果，避免插件
    // 返回的提示音 URL 进入候选列表触发误播放或自动换源。
    final preferBuiltIn = sourceId == 'kw';
    final builtInQualities = includeQualityFallbacks
        ? _qualityFallbackChain(
            quality,
            preferKuwoCompatibleQuality: sourceId == 'kw',
          )
        : <String>[quality];
    if (preferBuiltIn) {
      for (final candidateQuality in builtInQualities) {
        await _addBuiltInMusicUrlCandidate(
          song,
          quality: candidateQuality,
          excludedUrls: excludedUrls,
          results: results,
        );
      }
      if (results.isNotEmpty) {
        print('[MusicSourceManager] kw 内置源已提供有效 URL，跳过插件解析');
        return results;
      }
    }

    // Match CeruMusic/LX Music: an enabled LX plugin is the authoritative
    // resolver because it receives the provider-specific song metadata and
    // requested quality. The built-in resolver is only a fallback. In
    // particular, Kuwo's legacy endpoint can return HTTP 200 for its
    // free-listening permission prompt instead of the requested song.
    for (final host in _findPluginHostsForSource(sourceId)) {
      final pluginSourceId = _getSourceIdForHost(host, sourceId);
      if (pluginSourceId == null) continue;

      final qualities = includeQualityFallbacks
          ? _qualityFallbackChain(
              quality,
              supported: _getPluginQualities(host, pluginSourceId),
              preferKuwoCompatibleQuality: sourceId == 'kw',
            )
          : <String>[quality];
      for (final candidateQuality in qualities) {
        try {
          final result = await host.getMusicUrlResult(
            pluginSourceId,
            musicInfo,
            candidateQuality,
          );
          final url = result.url.trim();
          final normalized = PluginMusicUrlResult(
            url: url,
            quality: result.quality.isEmpty ? candidateQuality : result.quality,
            headers: result.headers,
          );
          print(
            '[MusicSourceManager] LX URL candidate: source=$sourceId '
            'requested=$quality quality=$candidateQuality '
            'resolved=${normalized.quality} host=${_urlHost(url)}',
          );
          // 拒绝酷我提示音 / 加密格式 URL
          if (sourceId == 'kw' && _isKuwoPromptUrl(url)) {
            print('[MusicSourceManager] 拒绝酷我无效 URL: $url');
            continue;
          }
          if (url.isNotEmpty &&
              _isValidAudioUrl(url) &&
              !excludedUrls.contains(url) &&
              !results.any((item) => item.url == url)) {
            results.add(normalized);
          }
        } catch (e) {
          print(
            '[MusicSourceManager] LX URL failed: '
            'source=$sourceId quality=$candidateQuality error=$e',
          );
        }
      }
    }

    if (!preferBuiltIn) {
      for (final candidateQuality in builtInQualities) {
        await _addBuiltInMusicUrlCandidate(
          song,
          quality: candidateQuality,
          excludedUrls: excludedUrls,
          results: results,
        );
      }
    }

    return results;
  }

  /// Quality order used after the current quality is rejected by the real
  /// audio player. The initial URL lookup intentionally does not use this.
  List<String> getMusicQualityFallbacks(Song song, String requested) {
    final sourceId = song.source;
    if (sourceId == null || sourceId == 'local') return <String>[requested];

    final host = _findPluginForSource(sourceId);
    final pluginSourceId = host == null
        ? null
        : _getSourceIdForHost(host, sourceId);
    final builtInQualities = _defaultQualities[sourceId];
    return _qualityFallbackChain(
      requested,
      supported: host == null || pluginSourceId == null
          ? builtInQualities
          : _getPluginQualities(host, pluginSourceId),
      preferKuwoCompatibleQuality: sourceId == 'kw',
    );
  }

  Future<void> _addBuiltInMusicUrlCandidate(
    Song song, {
    required String quality,
    required Set<String> excludedUrls,
    required List<PluginMusicUrlResult> results,
  }) async {
    final builtIn = _builtInSources[song.source];
    if (builtIn == null) return;

    try {
      // 酷我源使用音质感知的解析接口，支持 128k/320k/flac/hires 等音质，
      // 避免只回退到 128k。其它源仍走原 getSongUrl。
      String? url;
      if (builtIn is KuwoMusicSource) {
        url = await builtIn.getSongUrlWithQuality(
          song.id,
          quality: quality,
          expectedDurationSeconds: song.duration,
        );
      } else {
        url = await builtIn.getSongUrl(song.id);
      }
      if (url != null &&
          url.isNotEmpty &&
          _isValidAudioUrl(url) &&
          !excludedUrls.contains(url) &&
          !results.any((item) => item.url == url)) {
        // 内置 kw 源也可能返回提示音，二次校验
        if (song.source == 'kw' && _isKuwoPromptUrl(url)) {
          print('[MusicSourceManager] 内置 kw URL 被识别为提示音，丢弃: $url');
          return;
        }
        results.add(PluginMusicUrlResult(url: url, quality: quality));
        print(
          '[MusicSourceManager] built-in URL candidate: '
          'source=${song.source} quality=$quality host=${_urlHost(url)}',
        );
      }
    } catch (e) {
      print('[MusicSourceManager] built-in URL failed: $e');
    }
  }

  String _urlHost(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return 'invalid';
    return uri.host;
  }

  Future<PluginMusicUrlResult?> getMusicUrlResult(
    Song song, {
    String quality = '320k',
    Set<String> excludedUrls = const <String>{},
  }) async {
    final candidates = await getMusicUrlResultCandidates(
      song,
      quality: quality,
      excludedUrls: excludedUrls,
    );
    return candidates.isEmpty ? null : candidates.first;
  }

  Future<String?> getMusicUrl(
    Song song, {
    String quality = '320k',
    Set<String> excludedUrls = const <String>{},
  }) async {
    final candidates = await getMusicUrlCandidates(
      song,
      quality: quality,
      excludedUrls: excludedUrls,
    );
    return candidates.isEmpty ? null : candidates.first;
  }

  String _stripSourcePrefix(String songId, String sourceId) {
    final prefix = '${sourceId}_';
    if (songId.startsWith(prefix)) {
      return songId.substring(prefix.length);
    }
    return songId;
  }

  MusicInfoForPlugin _buildPluginMusicInfo(Song song, String sourceId) {
    final cleanId = _stripSourcePrefix(song.id, sourceId);
    final lx = song.lx ?? const <String, dynamic>{};

    dynamic read(List<String> keys) {
      for (final key in keys) {
        final value = lx[key];
        if (value != null && value.toString().isNotEmpty) return value;
      }
      return null;
    }

    String? readString(List<String> keys) {
      final value = read(keys);
      return value == null ? null : value.toString();
    }

    Map<String, dynamic>? readMap(String key) {
      final value = lx[key];
      return value is Map ? Map<String, dynamic>.from(value) : null;
    }

    List<dynamic>? readList(String key) {
      final value = lx[key];
      return value is List ? List<dynamic>.from(value) : null;
    }

    final songId =
        read(['songId', 'songid', 'copyrightId']) ??
        (sourceId == 'tx' ? song.lyricUrl : null);
    final songmid = readString(['songmid', 'mid']) ?? cleanId;
    final interval = readString(['interval']) ?? _formatInterval(song.duration);

    return MusicInfoForPlugin(
      songmid: songmid,
      songId: songId,
      hash: readString(['hash']) ?? song.hash ?? cleanId,
      name: readString(['name', 'songName', 'title']) ?? song.title,
      singer: readString(['singer', 'artist']) ?? song.artist,
      albumName: readString(['albumName', 'album_name']) ?? song.album,
      albumId: read(['albumId', 'albumid']),
      albumMid: read(['albumMid', 'albummid']),
      strMediaMid: read(['strMediaMid']),
      copyrightId: read(['copyrightId']),
      source: sourceId,
      interval: interval,
      img: readString(['img', 'pic', 'picUrl', 'cover']) ?? song.coverUrl,
      lrc: song.lrc,
      lrcUrl: readString(['lrcUrl']),
      mrcUrl: readString(['mrcUrl']),
      trcUrl: readString(['trcUrl']),
      types: readList('types'),
      typeMap: readMap('_types'),
      typeUrl: readMap('typeUrl') ?? <String, dynamic>{},
    );
  }

  String _formatInterval(int durationSeconds) {
    if (durationSeconds <= 0) return '';
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<String?> getLyric(Song song) async {
    final sourceId = song.source;
    if (sourceId == null) {
      print('[MusicSourceManager] getLyric: source is null');
      return null;
    }

    print(
      '[MusicSourceManager] getLyric: source=$sourceId, songId=${song.id}, title=${song.title}',
    );

    // 对齐 CeruMusic：插件优先
    final host = _findPluginForSource(sourceId);
    if (host != null) {
      final pluginSourceId = _getSourceIdForHost(host, sourceId);
      if (pluginSourceId != null) {
        final musicInfo = _buildPluginMusicInfo(song, sourceId);
        try {
          print('[MusicSourceManager] getLyric: calling plugin getLyric');
          final result = await host.getLyric(pluginSourceId, musicInfo);
          print(
            '[MusicSourceManager] getLyric: plugin result: ${result != null ? "has ${result.length} chars" : "null"}',
          );
          if (result != null && result.isNotEmpty) {
            return result;
          }
        } catch (e) {
          print('[MusicSourceManager] getLyric: plugin error: $e');
        }
      }
    }

    final builtIn = _builtInSources[sourceId];
    print(
      '[MusicSourceManager] getLyric: using built-in source: ${builtIn != null}',
    );
    if (builtIn != null) {
      try {
        print('[MusicSourceManager] getLyric: calling built-in getLyric');
        final result = await builtIn.getLyric(song.id);
        print(
          '[MusicSourceManager] getLyric: built-in result: ${result != null ? "has ${result.length} chars" : "null"}',
        );
        return result;
      } catch (e) {
        print('[MusicSourceManager] getLyric: built-in error: $e');
      }
    }

    print('[MusicSourceManager] getLyric: no source available');
    return null;
  }

  Future<LyricResult?> getLyricResult(Song song) async {
    final sourceId = song.source;
    if (sourceId == null) return null;

    final builtIn = _builtInSources[sourceId];
    LyricResult? pluginFallback;
    LyricResult? builtInFallback;

    // 0. 对齐 CeruMusic：插件优先于内建源
    final host = _findPluginForSource(sourceId);
    if (host != null) {
      final pluginSourceId = _getSourceIdForHost(host, sourceId);
      if (pluginSourceId != null) {
        final musicInfo = _buildPluginMusicInfo(song, sourceId);
        try {
          final result = await host.getLyricResult(pluginSourceId, musicInfo);
          if (_hasWordLyric(result)) return result;
          if (_hasLyric(result)) {
            if (sourceId != 'tx') return result;
            pluginFallback = result;
          }
        } catch (e) {
          print('[MusicSourceManager] getLyricResult: plugin error: $e');
        }
      }
    }

    // 1. 内建源（可能有 crlyric 逐字歌词）
    if (builtIn != null) {
      try {
        final result = await builtIn.getLyricResult(song.id);
        if (_hasWordLyric(result)) return result;
        if (_hasLyric(result)) builtInFallback = result;

        // tx 单独处理 numeric ID
        if (sourceId == 'tx' && song.lyricUrl?.trim().isNotEmpty == true) {
          final numericResult = await builtIn.getLyricResult(
            'tx_${song.lyricUrl}',
          );
          if (_hasWordLyric(numericResult)) return numericResult;
          if (builtInFallback == null && _hasLyric(numericResult)) {
            builtInFallback = numericResult;
          }
        }
      } catch (e) {
        print(
          '[MusicSourceManager] getLyricResult: $sourceId built-in error: $e',
        );
      }
    }

    // 2. 原生 fallback
    if (pluginFallback != null) return pluginFallback;
    if (builtInFallback != null) return builtInFallback;

    // 3. 纯文本回退
    final rawLyric = await getLyric(song);
    if (rawLyric == null || rawLyric.isEmpty) return null;
    return LyricResult(lrc: rawLyric);
  }

  bool _hasLyric(LyricResult? result) {
    return (result?.lrc?.trim().isNotEmpty ?? false) ||
        (result?.crlyric?.trim().isNotEmpty ?? false);
  }

  bool _hasWordLyric(LyricResult? result) {
    return result?.crlyric?.trim().isNotEmpty ?? false;
  }

  /// Promotes a Kuwo search thumbnail to its original-artwork CDN variant.
  ///
  /// This is synchronous so playback can display the sharp cover immediately,
  /// rather than waiting until audio URL resolution has completed.
  String? getHighResolutionCoverUrl(Song song) {
    if (song.source != 'kw') return null;
    final raw = song.coverUrl?.trim() ?? '';
    if (raw.isEmpty) return null;
    final match = RegExp(r'/(albumcover|starheads)/(\d+)/').firstMatch(raw);
    if (match == null) return null;
    if (match.group(2) == '1500') return raw;
    return raw.replaceFirstMapped(
      RegExp(r'/(albumcover|starheads)/\d+/'),
      (match) => '/${match.group(1)}/1500/',
    );
  }

  Future<String?> getPic(
    Song song, {
    Set<String> excludedUrls = const <String>{},
    bool preferBuiltIn = false,
    bool bypassCache = false,
  }) async {
    final sourceId = song.source;
    if (sourceId == null) return null;

    final cacheKey = '$sourceId:${song.id}';
    final cached = _coverCache[cacheKey];
    if (!bypassCache &&
        cached != null &&
        cached.isValid &&
        (cached.data == null || !excludedUrls.contains(cached.data))) {
      return cached.data;
    }

    String? result;

    Future<String?> resolveBuiltIn() async {
      final builtIn = _builtInSources[sourceId];
      if (builtIn == null) return null;
      try {
        final cover = await builtIn.getCoverUrl(song.id);
        if (cover != null &&
            cover.isNotEmpty &&
            !excludedUrls.contains(cover)) {
          _coverCache[cacheKey] = _CacheEntry(cover, _searchResultsTTL);
          return cover;
        }
      } catch (_) {}
      return null;
    }

    // Built-in search results and an imported LX plugin may share the `kw`
    // source ID, but their song IDs are not interchangeable. Use Kuwo's own
    // cover resolver first for built-in Kuwo playback.
    if (preferBuiltIn || sourceId == 'kw') {
      final existingKuwoCover = getHighResolutionCoverUrl(song);
      if (existingKuwoCover != null &&
          !excludedUrls.contains(existingKuwoCover)) {
        _coverCache[cacheKey] = _CacheEntry(
          existingKuwoCover,
          _searchResultsTTL,
        );
        return existingKuwoCover;
      }
      final cover = await resolveBuiltIn();
      if (cover != null) return cover;
    }

    final host = _findPluginForSource(sourceId);
    if (host != null) {
      final pluginSourceId = _getSourceIdForHost(host, sourceId);
      if (pluginSourceId != null) {
        final musicInfo = _buildPluginMusicInfo(song, sourceId);
        try {
          result = await host.getPic(pluginSourceId, musicInfo);
          if (result != null &&
              result.isNotEmpty &&
              !excludedUrls.contains(result)) {
            _coverCache[cacheKey] = _CacheEntry(result, _searchResultsTTL);
            return result;
          }
        } catch (_) {}
      }
    }

    if (!preferBuiltIn && sourceId != 'kw') {
      final cover = await resolveBuiltIn();
      if (cover != null) return cover;
    }

    _coverCache[cacheKey] = _CacheEntry(null, _searchResultsTTL);
    return null;
  }

  Future<List<Playlist>> getHotPlaylists({String sourceId = 'wy'}) async {
    final cached = _hotPlaylistsCache[sourceId];
    if (cached != null && cached.isValid) {
      print('[MusicSourceManager] 热门歌单缓存命中: $sourceId');
      return cached.data;
    }

    final builtIn = _builtInSources[sourceId];
    if (builtIn != null) {
      try {
        final hot = await builtIn.getHotPlaylists();
        if (hot.isNotEmpty) {
          _hotPlaylistsCache[sourceId] = _CacheEntry(hot, _hotPlaylistsTTL);
          return hot;
        }
      } catch (e) {
        print('[MusicSourceManager] getHotPlaylists failed for $sourceId: $e');
      }

      try {
        final categoryHot = await builtIn.getCategoryPlaylists(
          sortId: 'hot',
          tagId: '',
          page: 1,
          limit: 30,
        );
        if (categoryHot.isNotEmpty) {
          _hotPlaylistsCache[sourceId] = _CacheEntry(
            categoryHot,
            _hotPlaylistsTTL,
          );
          return categoryHot;
        }
      } catch (e) {
        print('[MusicSourceManager] 热门歌单分类兜底失败 source=$sourceId: $e');
      }

      try {
        final tags = await builtIn.getHotPlaylistTags();
        for (final tag in tags.take(3)) {
          final tagged = await builtIn.getCategoryPlaylists(
            sortId: 'hot',
            tagId: tag.id,
            page: 1,
            limit: 30,
          );
          if (tagged.isNotEmpty) {
            _hotPlaylistsCache[sourceId] = _CacheEntry(
              tagged,
              _hotPlaylistsTTL,
            );
            return tagged;
          }
        }
      } catch (e) {
        print('[MusicSourceManager] 热门歌单标签兜底失败 source=$sourceId: $e');
      }
    }
    return [];
  }

  Future<List<PlaylistTagGroup>> getPlaylistTags({
    String sourceId = 'wy',
  }) async {
    final builtIn = _builtInSources[sourceId];
    if (builtIn != null) {
      try {
        return await builtIn.getPlaylistTags();
      } catch (e) {
        print('[MusicSourceManager] getPlaylistTags failed for $sourceId: $e');
        return [];
      }
    }
    return [];
  }

  Future<List<PlaylistTag>> getHotPlaylistTags({String sourceId = 'wy'}) async {
    final builtIn = _builtInSources[sourceId];
    if (builtIn != null) {
      try {
        return await builtIn.getHotPlaylistTags();
      } catch (e) {
        print(
          '[MusicSourceManager] getHotPlaylistTags failed for $sourceId: $e',
        );
        return [];
      }
    }
    return [];
  }

  Future<List<Playlist>> getCategoryPlaylists({
    required String sortId,
    required String tagId,
    required int page,
    required int limit,
    String sourceId = 'wy',
  }) async {
    final builtIn = _builtInSources[sourceId];
    if (builtIn != null) {
      try {
        final playlists = await builtIn.getCategoryPlaylists(
          sortId: sortId,
          tagId: tagId,
          page: page,
          limit: limit,
        );
        if (playlists.isNotEmpty) return playlists;
      } catch (e) {
        print(
          '[MusicSourceManager] getCategoryPlaylists failed for $sourceId: $e',
        );
      }

      if (page == 1 && tagId.isEmpty && sortId == 'hot') {
        try {
          final hot = await builtIn.getHotPlaylists();
          if (hot.isNotEmpty) return hot.take(limit).toList();
        } catch (e) {
          print('[MusicSourceManager] 分类热门歌单直接兜底失败 source=$sourceId: $e');
        }

        try {
          final tags = await builtIn.getHotPlaylistTags();
          for (final tag in tags.take(3)) {
            final tagged = await builtIn.getCategoryPlaylists(
              sortId: sortId,
              tagId: tag.id,
              page: page,
              limit: limit,
            );
            if (tagged.isNotEmpty) return tagged;
          }
        } catch (e) {
          print('[MusicSourceManager] 分类热门歌单标签兜底失败 source=$sourceId: $e');
        }
      }
    }
    return [];
  }

  Future<List<Leaderboard>> getLeaderboards({String sourceId = 'wy'}) async {
    final builtIn = _builtInSources[sourceId];
    if (builtIn != null) {
      try {
        return await builtIn.getLeaderboards();
      } catch (e) {
        print('[MusicSourceManager] getLeaderboards failed for $sourceId: $e');
        return [];
      }
    }
    return [];
  }

  Future<Playlist?> getPlaylistDetail(
    String playlistId, {
    String sourceId = 'wy',
  }) async {
    final cached = _playlistDetailCache[playlistId];
    if (cached != null && cached.isValid) {
      print('[MusicSourceManager] 歌单详情缓存命中: $playlistId');
      return cached.data;
    }

    String actualSourceId = sourceId;

    if (playlistId.startsWith('wy_')) {
      actualSourceId = 'wy';
    } else if (playlistId.startsWith('kg_')) {
      actualSourceId = 'kg';
    } else if (playlistId.startsWith('kw_')) {
      actualSourceId = 'kw';
    } else if (playlistId.startsWith('tx_')) {
      actualSourceId = 'tx';
    } else if (playlistId.startsWith('mg_')) {
      actualSourceId = 'mg';
    }

    print(
      '[MusicSourceManager] getPlaylistDetail: playlistId=$playlistId, sourceId=$sourceId, actualSourceId=$actualSourceId',
    );

    Playlist? result;
    final builtIn = _builtInSources[actualSourceId];
    if (builtIn != null) {
      try {
        result = await builtIn.getPlaylistDetail(playlistId);
        if (result != null && result.songs.isNotEmpty) {
          print(
            '[MusicSourceManager] getPlaylistDetail success: ${result.songs.length} songs',
          );
          _playlistDetailCache[playlistId] = _CacheEntry(
            result,
            _playlistDetailTTL,
          );
          return result;
        }

        if (actualSourceId != 'wy') {
          final boardResult = await builtIn.getLeaderboardDetail(playlistId);
          if (boardResult != null && boardResult.songs.isNotEmpty) {
            print(
              '[MusicSourceManager] getPlaylistDetail fallback leaderboard success: ${boardResult.songs.length} songs',
            );
            _playlistDetailCache[playlistId] = _CacheEntry(
              boardResult,
              _playlistDetailTTL,
            );
            return boardResult;
          }
        }

        if (result != null) {
          print(
            '[MusicSourceManager] getPlaylistDetail returned empty playlist for $actualSourceId',
          );
          _playlistDetailCache[playlistId] = _CacheEntry(
            result,
            _playlistDetailTTL,
          );
          return result;
        } else {
          print(
            '[MusicSourceManager] getPlaylistDetail returned null for $actualSourceId',
          );
        }
        return null;
      } catch (e) {
        print(
          '[MusicSourceManager] getPlaylistDetail failed for $actualSourceId: $e',
        );
        return null;
      }
    }
    print('[MusicSourceManager] no built-in source found for $actualSourceId');
    return null;
  }

  Future<Playlist?> getLeaderboardDetail(
    String boardId, {
    int page = 1,
    String sourceId = 'wy',
  }) async {
    final builtIn = _builtInSources[sourceId];
    if (builtIn != null) {
      try {
        return await builtIn.getLeaderboardDetail(boardId, page: page);
      } catch (e) {
        print(
          '[MusicSourceManager] getLeaderboardDetail failed for $sourceId: $e',
        );
        return null;
      }
    }
    return null;
  }

  List<SourceInfo> getDiscoverSupportedSources() {
    final sources = <SourceInfo>[];
    final seenIds = <String>{};

    for (final entry in _builtInSources.entries) {
      if (!seenIds.contains(entry.key)) {
        sources.add(
          SourceInfo(
            id: entry.key,
            name: _sourceIdToName[entry.key] ?? entry.key,
          ),
        );
        seenIds.add(entry.key);
      }
    }

    return sources;
  }
}
