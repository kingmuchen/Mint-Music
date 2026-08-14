import 'dart:convert';
import '../../player/domain/models/lyric_line.dart';
import '../platform/js_engine_service.dart';
import '../domain/plugin_types.dart';

class PluginHost {
  final JsEngineService _engine;
  PluginMetadata? _pluginInfo;
  List<PluginSourceInfo> _sources = [];
  Map<String, List<String>> _sourceActions = {};
  bool _loaded = false;
  bool _apiInjected = false;

  PluginHost(this._engine);

  bool get isLoaded => _loaded;
  PluginMetadata? get pluginInfo => _pluginInfo;
  List<PluginSourceInfo> get sources => _sources;
  Map<String, List<String>> get sourceActions => _sourceActions;

  Future<void> loadPlugin(String pluginCode) async {
    if (!_apiInjected) {
      final apiCode = _engine.injectCeruMusicApi();
      _engine.evaluate(apiCode);
      _apiInjected = true;
    }

    try {
      print('[PluginHost] 开始加载插件...');
      _engine.evaluate('var module = { exports: {} };');
      _engine.evaluate('var exports = module.exports;');

      print('[PluginHost] 执行插件代码...');
      _engine.evaluate(pluginCode);

      // Older converted LX files kept a usable handler but left a late,
      // non-critical init error set. Normalize that runtime state so already
      // installed plugins receive the same compatibility behavior as newly
      // imported files.
      _engine.evaluate('''
(function() {
  if (typeof __lxRequestHandler === 'function') {
    if (typeof requestHandler !== 'function') requestHandler = __lxRequestHandler;
    if (typeof __lxInitError !== 'undefined') __lxInitError = null;
  }
  return true;
})()
''');

      print('[PluginHost] 等待插件异步初始化...');
      final initDeadline = DateTime.now().add(const Duration(seconds: 30));
      var sourceCount = -1;
      while (DateTime.now().isBefore(initDeadline)) {
        _engine.executePendingJob();
        final countResult = _engine.evaluate(
          'module.exports && module.exports.sources ? Object.keys(module.exports.sources).length : 0',
        );
        if (!countResult.isError) {
          sourceCount = int.tryParse(countResult.stringResult) ?? 0;
          if (sourceCount > 0) break;
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }
      print('[PluginHost] 插件初始化完成，解析到 $sourceCount 个源');

      print('[PluginHost] 获取插件导出...');
      final exportsResult = _engine.evaluate('JSON.stringify(module.exports)');
      if (exportsResult.isError) {
        throw Exception(
          'Plugin code execution failed: ${exportsResult.stringResult}',
        );
      }

      final exportsStr = exportsResult.stringResult;
      print('[PluginHost] 导出结果长度: ${exportsStr.length}');

      if (exportsStr == 'undefined' || exportsStr == 'null') {
        throw Exception('Plugin did not export anything');
      }

      try {
        final exports = jsonDecode(exportsStr) as Map<String, dynamic>;

        _pluginInfo = _parsePluginInfo(exports['pluginInfo']);
        final sourcesResult = _parseSourcesWithActions(exports['sources']);
        _sources = sourcesResult['sources'] as List<PluginSourceInfo>;
        _sourceActions = sourcesResult['actions'] as Map<String, List<String>>;

        if (_sources.isEmpty && _sourceActions.isNotEmpty) {
          for (final entry in _sourceActions.entries) {
            final sourceId = entry.key;
            _sources.add(
              PluginSourceInfo(
                name: _getSourceDisplayName(sourceId),
                qualities: ['128k', '320k', 'flac'],
              ),
            );
          }
        }

        print('[PluginHost] 解析插件信息: ${_pluginInfo?.name ?? "null"}');
        print('[PluginHost] 解析源数量: ${_sources.length}');
        for (final entry in _sourceActions.entries) {
          print('[PluginHost] 源 ${entry.key} 支持的操作: ${entry.value}');
        }

        if (_pluginInfo == null) {
          _pluginInfo = PluginMetadata(
            name: '未知插件',
            version: '1.0',
            author: '未知',
          );
        }

        _loaded = true;
        print('[PluginHost] 插件加载成功');
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception('Failed to parse plugin exports: $e');
      }
    } catch (e) {
      _loaded = false;
      print('[PluginHost] 插件加载失败: $e');
      _pluginInfo = PluginMetadata(
        name: '加载失败',
        version: '0.0',
        author: '',
        description: '错误: $e',
      );
      throw Exception('Failed to load plugin: $e');
    }
  }

  String _getSourceDisplayName(String sourceId) {
    final names = {
      'wy': '网易云音乐',
      'tx': 'QQ音乐',
      'kg': '酷狗音乐',
      'kw': '酷我音乐',
      'mg': '咪咕音乐',
      'qsvip': '汽水VIP',
    };
    return names[sourceId] ?? '${sourceId.toUpperCase()}音乐';
  }

  PluginMetadata? _parsePluginInfo(dynamic data) {
    if (data == null) return null;
    if (data is! Map<String, dynamic>) return null;

    final name = data['name'] as String?;
    final version = data['version'] as String?;
    final author = data['author'] as String?;

    if (name == null || version == null || author == null) return null;

    return PluginMetadata(
      name: name,
      version: version,
      author: author,
      description: data['description'] as String?,
    );
  }

  Map<String, dynamic> _parseSourcesWithActions(dynamic data) {
    final sources = <PluginSourceInfo>[];
    final actions = <String, List<String>>{};

    if (data == null) return {'sources': sources, 'actions': actions};

    if (data is Map<String, dynamic>) {
      data.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          final name = value['name'] as String? ?? SourceInfo.getNameById(key);
          final qualitys =
              (value['qualitys'] as List?)?.cast<String>() ??
              (value['qualities'] as List?)?.cast<String>() ??
              [];
          final sourceActions =
              ((value['actions'] as List?) ?? const ['musicUrl'])
                  .map((e) => e.toString().toLowerCase())
                  .toList();

          sources.add(PluginSourceInfo(name: name, qualities: qualitys));
          actions[key] = sourceActions;
        }
      });
    }

    return {'sources': sources, 'actions': actions};
  }

  bool supportsSearch(String sourceId) {
    final actions = _sourceActions[sourceId];
    if (actions == null) return false;
    return actions
        .map((action) => action.toLowerCase())
        .any((action) => action == 'musicsearch' || action == 'search');
  }

  Future<String> getMusicUrl(
    String source,
    MusicInfoForPlugin musicInfo,
    String quality,
  ) async {
    final result = await getMusicUrlResult(source, musicInfo, quality);
    return result.url;
  }

  Future<PluginMusicUrlResult> getMusicUrlResult(
    String source,
    MusicInfoForPlugin musicInfo,
    String quality,
  ) async {
    _ensureLoaded();

    final infoJson = jsonEncode(musicInfo.toJson());
    final escapedInfo = _escapeForJs(infoJson);

    final result = await _engine.callPluginMethod(
      "module.exports.musicUrl('$source', JSON.parse('$escapedInfo'), '$quality')",
    );

    if (result == null || result.isEmpty) {
      throw Exception('Plugin returned empty result for musicUrl');
    }

    return _parseMusicUrlResult(result);
  }

  PluginMusicUrlResult _parseMusicUrlResult(String result) {
    try {
      final decoded = _decodeLooseJson(result);
      final url = _extractMusicUrl(decoded);
      if (url != null && url.isNotEmpty) {
        return PluginMusicUrlResult(
          url: url,
          quality: _extractMusicQuality(decoded) ?? '',
          headers: _extractMusicHeaders(decoded),
        );
      }
    } catch (e) {
      if (e is Exception && e.toString().startsWith('Exception:')) {
        rethrow;
      }
    }

    final fallback = result.trim();
    if (_isHttpUrl(fallback)) {
      return PluginMusicUrlResult(url: fallback, quality: '');
    }
    throw Exception('Plugin returned an invalid musicUrl result');
  }

  dynamic _decodeLooseJson(dynamic value) {
    var current = value;
    for (var i = 0; i < 3; i++) {
      if (current is! String) return current;
      final trimmed = current.trim();
      if (trimmed.isEmpty) return trimmed;
      final looksJson =
          (trimmed.startsWith('{') && trimmed.endsWith('}')) ||
          (trimmed.startsWith('[') && trimmed.endsWith(']')) ||
          (trimmed.startsWith('"') && trimmed.endsWith('"'));
      if (!looksJson) return trimmed;
      current = jsonDecode(trimmed);
    }
    return current;
  }

  String? _extractMusicUrl(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final trimmed = value.trim();
      if (_isHttpUrl(trimmed)) return trimmed;
      final decoded = _decodeLooseJson(trimmed);
      if (decoded is! String) return _extractMusicUrl(decoded);
      return null;
    }
    if (value is Map) {
      final error = value['error'] ?? value['message'];
      if (error != null &&
          value['url'] == null &&
          value['data'] == null &&
          value['body'] == null) {
        throw Exception(error.toString());
      }

      for (final key in const [
        'url',
        'src',
        'playUrl',
        'play_url',
        'location',
        'audioUrl',
        'audio_url',
      ]) {
        final url = _extractMusicUrl(value[key]);
        if (url != null && url.isNotEmpty) return url;
      }

      for (final key in const ['data', 'body', 'result', 'response']) {
        final url = _extractMusicUrl(value[key]);
        if (url != null && url.isNotEmpty) return url;
      }
    }
    if (value is List) {
      for (final item in value) {
        final url = _extractMusicUrl(item);
        if (url != null && url.isNotEmpty) return url;
      }
    }
    return null;
  }

  String? _extractMusicQuality(dynamic value) {
    if (value is String) {
      final decoded = _decodeLooseJson(value.trim());
      if (decoded is! String) return _extractMusicQuality(decoded);
    }
    if (value is Map) {
      for (final key in const ['quality', 'type', 'format', 'level']) {
        final candidate = value[key];
        if (candidate is String && candidate.trim().isNotEmpty) {
          return candidate.trim();
        }
      }
      for (final key in const ['data', 'body', 'result', 'response']) {
        final nested = _extractMusicQuality(value[key]);
        if (nested != null) return nested;
      }
    }
    if (value is List) {
      for (final item in value) {
        final nested = _extractMusicQuality(item);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  Map<String, String> _extractMusicHeaders(dynamic value) {
    final headers = <String, String>{};

    void read(dynamic current) {
      if (current is String) {
        final decoded = _decodeLooseJson(current.trim());
        if (decoded is! String) read(decoded);
        return;
      }
      if (current is Map) {
        for (final key in const ['requestHeaders', 'httpHeaders', 'headers']) {
          final candidate = current[key];
          if (candidate is Map) {
            candidate.forEach((header, headerValue) {
              if (headerValue == null) return;
              final name = header.toString().trim();
              final value = headerValue.toString().trim();
              if (name.isNotEmpty && value.isNotEmpty) {
                headers[name] = value;
              }
            });
          }
        }
        for (final key in const ['data', 'body', 'result', 'response']) {
          read(current[key]);
        }
      } else if (current is List) {
        for (final item in current) {
          read(item);
        }
      }
    }

    read(value);
    return headers;
  }

  bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  String? _parseLyricResult(String? result) {
    final bundle = _parseLyricBundle(result);
    if (bundle == null) return null;
    return _firstNonEmpty([bundle.crlyric, bundle.lrc]);
  }

  LyricResult? _parseLyricBundle(String? result) {
    if (result == null || result.isEmpty) return null;
    if (result == 'null' || result == 'undefined') return null;

    dynamic decoded = result;
    if (result.startsWith('"') && result.endsWith('"')) {
      try {
        decoded = jsonDecode(result);
      } catch (_) {
        return LyricResult(lrc: result);
      }
    }

    if (decoded is String) {
      final trimmed = decoded.trim();
      if (trimmed.isEmpty || trimmed == 'null' || trimmed == 'undefined') {
        return null;
      }
      try {
        decoded = jsonDecode(trimmed);
      } catch (_) {
        return _looksLikeWordLyric(trimmed)
            ? LyricResult(crlyric: trimmed)
            : LyricResult(lrc: trimmed);
      }
    }

    if (decoded is Map) {
      final wordLyric = _readFirstText(decoded, const [
        'crlyric',
        'lxlyric',
        'yrc',
        'krc',
        'qrc',
        'mrc',
        'lrcx',
        'lyricx',
        'wordLyric',
        'wordlyric',
        'word',
        'words',
        'ttml',
        'ttmlLyric',
      ]);
      final plainLyric = _readFirstText(decoded, const [
        'lrc',
        'lyric',
        'text',
        'content',
        'raw',
      ]);
      final tlyric = _readFirstText(decoded, const [
        'tlyric',
        'tlrc',
        'translation',
        'translatedLyric',
        'trans',
      ]);
      final rlyric = _readFirstText(decoded, const [
        'rlyric',
        'rlrc',
        'roma',
        'romanLyric',
        'roman',
      ]);

      if ([
        wordLyric,
        plainLyric,
        tlyric,
        rlyric,
      ].any((value) => value != null && value.trim().isNotEmpty)) {
        return LyricResult(
          lrc: plainLyric,
          crlyric: wordLyric,
          tlyric: tlyric,
          rlyric: rlyric,
        );
      }

      final nested = _parseLyricBundle(_stringifyJsonValue(decoded['data']));
      if (nested != null) return nested;
    }

    return null;
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) return value;
    }
    return null;
  }

  String? _readFirstText(Map source, List<String> keys) {
    String? readValue(dynamic value) {
      if (value == null) return null;
      if (value is String) {
        final trimmed = value.trim();
        return trimmed.isEmpty || trimmed == 'null' || trimmed == 'undefined'
            ? null
            : trimmed;
      }
      if (value is Map) {
        for (final key in keys) {
          final nested = readValue(value[key]);
          if (nested != null) return nested;
        }
        for (final fallbackKey in const [
          'data',
          'lyric',
          'lrc',
          'content',
          'text',
          'raw',
        ]) {
          final nested = readValue(value[fallbackKey]);
          if (nested != null) return nested;
        }
      }
      if (value is List) {
        final parts = value
            .map(readValue)
            .whereType<String>()
            .where((text) => text.isNotEmpty)
            .toList();
        if (parts.isNotEmpty) return parts.join('\n');
      }
      return null;
    }

    for (final key in keys) {
      final value = readValue(source[key]);
      if (value != null) return value;
    }
    final data = source['data'];
    if (data is Map) {
      for (final key in keys) {
        final value = readValue(data[key]);
        if (value != null) return value;
      }
    }
    return null;
  }

  String? _stringifyJsonValue(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    try {
      return jsonEncode(value);
    } catch (_) {
      return null;
    }
  }

  bool _looksLikeWordLyric(String text) {
    final trimmed = text.trimLeft();
    return RegExp(r'^\[\d+,\d+\]', multiLine: true).hasMatch(text) ||
        RegExp(
          r'^\[\d{1,2}:\d{2}\.\d{2,3}\].*<\d{1,2}:\d{2}\.\d{2,3}>',
          multiLine: true,
        ).hasMatch(text) ||
        trimmed.startsWith('<tt') ||
        text.contains('LyricContent=');
  }

  Future<String?> search(
    String source,
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async {
    _ensureLoaded();

    final hasMethod = _engine.evaluate(
      'typeof module.exports.search === "function"',
    );
    if (hasMethod.stringResult != 'true') {
      print('[PluginHost] search方法不存在');
      return null;
    }

    final escapedKeyword = _escapeForJs(keyword);

    try {
      print(
        '[PluginHost] 调用search: source=$source, keyword=$keyword, page=$page, limit=$limit',
      );
      final result = await _engine.callPluginMethod(
        "module.exports.search('$source', '$escapedKeyword', $page, $limit)",
        timeout: const Duration(seconds: 45),
      );
      print('[PluginHost] search结果长度: ${result?.length ?? 0}');
      return result;
    } catch (e) {
      print('[PluginHost] search异常: $e');
      return null;
    }
  }

  Future<String?> searchWithHandler(
    String source,
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async {
    _ensureLoaded();

    final hasRequestHandler = _engine.evaluate(
      'typeof requestHandler === "function" || typeof __lxRequestHandler === "function"',
    );
    if (hasRequestHandler.stringResult == 'true') {
      try {
        final escSource = _escapeForJs(source);
        final escKeyword = _escapeForJs(keyword);
        final result = await _engine.callPluginMethod(
          "(function(){" +
              "var handler=typeof requestHandler==='function'?requestHandler:__lxRequestHandler;" +
              "if(typeof handler!=='function')return JSON.stringify({list:[],total:0});" +
              "try{" +
              "var res=handler({" +
              "source:'$escSource',action:'musicSearch'," +
              "info:{keyword:'$escKeyword',page:$page,limit:$limit,pagesize:$limit}" +
              "});" +
              "if(res&&typeof res.then==='function'){" +
              "return res.then(function(r){return JSON.stringify(r||{list:[],total:0});});" +
              "}" +
              "return JSON.stringify(res||{list:[],total:0});" +
              "}catch(e){return JSON.stringify({list:[],total:0,error:e.message});}" +
              "})()",
          timeout: const Duration(seconds: 45),
        );
        return result;
      } catch (e) {
        print('[PluginHost] searchWithHandler异常: $e');
      }
    }
    return null;
  }

  Future<String?> getPic(String source, MusicInfoForPlugin musicInfo) async {
    _ensureLoaded();

    final hasMethod = _engine.evaluate(
      'typeof module.exports.getPic === "function"',
    );
    if (hasMethod.stringResult != 'true') return null;

    final infoJson = jsonEncode(musicInfo.toJson());
    final escapedInfo = _escapeForJs(infoJson);

    try {
      final result = await _engine.callPluginMethod(
        "module.exports.getPic('$source', JSON.parse('$escapedInfo'))",
      );
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<String?> getLyric(String source, MusicInfoForPlugin musicInfo) async {
    _ensureLoaded();

    final infoJson = jsonEncode(musicInfo.toJson());
    final escapedInfo = _escapeForJs(infoJson);
    final escapedSource = _escapeForJs(source);

    final hasMethod = _engine.evaluate(
      'typeof module.exports.getLyric === "function"',
    );
    if (hasMethod.stringResult == 'true') {
      try {
        final result = await _engine.callPluginMethod(
          "module.exports.getLyric('$escapedSource', JSON.parse('$escapedInfo'))",
          timeout: const Duration(seconds: 45),
        );
        final lyric = _parseLyricResult(result);
        if (lyric != null && lyric.isNotEmpty) return lyric;
      } catch (e) {
        print('[PluginHost] getLyric 方法失败: $e');
      }
    }

    return _getLyricWithHandler(escapedSource, escapedInfo);
  }

  Future<String?> _getLyricWithHandler(
    String escapedSource,
    String escapedInfo,
  ) async {
    final hasRequestHandler = _engine.evaluate(
      'typeof requestHandler === "function" || typeof __lxRequestHandler === "function"',
    );
    if (hasRequestHandler.stringResult != 'true') return null;

    for (final action in const ['lyric', 'getLyric']) {
      try {
        final result = await _engine.callPluginMethod(
          "(function(){" +
              "var handler=typeof requestHandler==='function'?requestHandler:__lxRequestHandler;" +
              "if(typeof handler!=='function')return null;" +
              "var musicInfo=JSON.parse('$escapedInfo');" +
              "var info=Object.assign({musicInfo:musicInfo,type:'lrc'},musicInfo);" +
              "var res=handler({" +
              "source:'$escapedSource',action:'$action'," +
              "info:info" +
              "});" +
              "if(res&&typeof res.then==='function'){" +
              "return res.then(function(r){return r;});" +
              "}" +
              "return res;" +
              "})()",
          timeout: const Duration(seconds: 45),
        );
        final lyric = _parseLyricResult(result);
        if (lyric != null && lyric.isNotEmpty) return lyric;
      } catch (e) {
        print('[PluginHost] requestHandler 歌词动作 $action 失败: $e');
      }
    }

    return null;
  }

  Future<LyricResult?> getLyricResult(
    String source,
    MusicInfoForPlugin musicInfo,
  ) async {
    _ensureLoaded();

    final infoJson = jsonEncode(musicInfo.toJson());
    final escapedInfo = _escapeForJs(infoJson);
    final escapedSource = _escapeForJs(source);

    final hasMethod = _engine.evaluate(
      'typeof module.exports.getLyric === "function"',
    );
    if (hasMethod.stringResult == 'true') {
      try {
        final result = await _engine.callPluginMethod(
          "module.exports.getLyric('$escapedSource', JSON.parse('$escapedInfo'))",
          timeout: const Duration(seconds: 45),
        );
        final lyric = _parseLyricBundle(result);
        if (_hasAnyLyric(lyric)) return lyric;
      } catch (e) {
        print('[PluginHost] getLyricResult failed: $e');
      }
    }

    return _getLyricResultWithHandler(escapedSource, escapedInfo);
  }

  Future<LyricResult?> _getLyricResultWithHandler(
    String escapedSource,
    String escapedInfo,
  ) async {
    final hasRequestHandler = _engine.evaluate(
      'typeof requestHandler === "function"',
    );
    if (hasRequestHandler.stringResult != 'true') return null;

    for (final action in const ['lyric', 'getLyric']) {
      try {
        final result = await _engine.callPluginMethod(
          "(function(){" +
              "if(typeof requestHandler!=='function')return null;" +
              "var musicInfo=JSON.parse('$escapedInfo');" +
              "var info=Object.assign({musicInfo:musicInfo,type:'lrc'},musicInfo);" +
              "var res=requestHandler({" +
              "source:'$escapedSource',action:'$action'," +
              "info:info" +
              "});" +
              "if(res&&typeof res.then==='function'){" +
              "return res.then(function(r){return r;});" +
              "}" +
              "return res;" +
              "})()",
          timeout: const Duration(seconds: 45),
        );
        final lyric = _parseLyricBundle(result);
        if (_hasAnyLyric(lyric)) return lyric;
      } catch (e) {
        print('[PluginHost] requestHandler lyric action $action failed: $e');
      }
    }

    return null;
  }

  bool _hasAnyLyric(LyricResult? lyric) {
    return lyric != null &&
        ((lyric.lrc?.trim().isNotEmpty ?? false) ||
            (lyric.crlyric?.trim().isNotEmpty ?? false) ||
            (lyric.tlyric?.trim().isNotEmpty ?? false) ||
            (lyric.rlyric?.trim().isNotEmpty ?? false));
  }

  bool hasMethod(String name) {
    if (!_loaded) return false;
    final result = _engine.evaluate(
      'typeof module.exports.$name === "function"',
    );
    return result.stringResult == 'true';
  }

  void _ensureLoaded() {
    if (!_loaded) {
      throw StateError('Plugin not loaded');
    }
  }

  String _escapeForJs(String input) {
    return input
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t')
        .replaceAll('\$', '\\\$');
  }
}
