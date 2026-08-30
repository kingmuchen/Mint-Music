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
  bool get isRuntimeHealthy => _engine.isRuntimeHealthy;
  PluginMetadata? get pluginInfo => _pluginInfo;
  List<PluginSourceInfo> get sources => _sources;
  Map<String, List<String>> get sourceActions => _sourceActions;

  /// Stream of update notices emitted by this plugin's JS engine.
  /// Each event is the raw notice map from the engine (with `type` and `data`).
  Stream<Map<String, dynamic>> get updateNotices =>
      _engine.pluginNoticeStream.where((e) => e['type'] == 'update');

  /// Convenience getter for the engine's raw notice stream.
  JsEngineService get engine => _engine;

  Future<void> loadPlugin(
    String pluginCode, {
    String? originalPluginCode,
  }) async {
    try {
      if (!_apiInjected) {
        final apiEvalResult = _engine.injectCeruMusicApi();
        if (apiEvalResult.isError) {
          throw Exception('引擎 API 注入失败: ${apiEvalResult.stringResult}');
        }
        _apiInjected = true;
      }
      print('[PluginHost] 开始加载插件...');
      _engine.evaluate('var module = { exports: {} };');
      _engine.evaluate('var exports = module.exports;');

      print('[PluginHost] 执行插件代码...');
      // Force an undefined completion value. This prevents flutter_js from
      // recursively converting a large module.exports object through FFI.
      final pluginEvalResult = _engine.evaluate('$pluginCode\n;void 0;');
      if (pluginEvalResult.isError) {
        // 例如大型插件超出 JS 栈上限时 QuickJS 返回
        // "InternalError: stack overflow"。此处直接暴露真实原因，
        // 而不是让后续 exports 解析失败产生误导性的提示。
        throw Exception('插件代码执行失败: ${pluginEvalResult.stringResult}');
      }

      if (originalPluginCode != null && originalPluginCode.trim().isNotEmpty) {
        print('[PluginHost] 单独执行原始 LX 脚本...');
        // The LX adapter has already installed its globals and event bridge.
        // Use a block scope so top-level `const` declarations in an LX script
        // (for example `const { EVENT_NAMES } = globalThis.lx`) cannot collide
        // with adapter globals. This is still a direct evaluate: the source is
        // not embedded in a string passed to new Function.
        final originalEvalResult = _engine.evaluate(
          '{\n$originalPluginCode\n}\n;void 0;',
        );
        if (originalEvalResult.isError) {
          throw Exception('原始 LX 插件执行失败: ${originalEvalResult.stringResult}');
        }
        // Keep the mobile LX contract intact without putting the large source
        // back into the adapter or a nested Function constructor. The result
        // is forced to a boolean so flutter_js never converts the source back
        // through the Dart bridge.
        final scriptInfoResult = _engine.evaluate(
          'if (typeof mockLx !== "undefined" && mockLx.currentScriptInfo) {'
          ' mockLx.currentScriptInfo.rawScript = ${jsonEncode(originalPluginCode)};'
          ' true; } else { false; }',
        );
        if (scriptInfoResult.isError) {
          throw Exception('LX 运行时信息初始化失败: ${scriptInfoResult.stringResult}');
        }
        final finalizeResult = _engine.evaluate(
          'typeof __lxFinalizePluginInitialization === "function"'
          ' ? (__lxFinalizePluginInitialization(), true) : true',
        );
        if (finalizeResult.isError) {
          throw Exception('LX 插件初始化失败: ${finalizeResult.stringResult}');
        }
      }

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
      final exportsResult = _engine.evaluate('''
JSON.stringify((function() {
  var value = module.exports || {};
  return {
    pluginInfo: value.pluginInfo,
    sources: value.sources,
    sourceActions: value.sourceActions
  };
})())
''');
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
      final message = _friendlyPluginError(e);
      print('[PluginHost] 插件加载失败: $e');
      _pluginInfo = PluginMetadata(
        name: '加载失败',
        version: '0.0',
        author: '',
        description: message,
      );
      throw Exception(message);
    }
  }

  /// 把底层 JS/Dart 异常转成用户可读的失败原因。
  ///
  /// 大型混淆插件（如“全音质”赞助版洛雪脚本）体积大、递归深，加载时可能
  /// 触发 JS 引擎或 Dart 桥接层的栈溢出。这类错误直接抛给 UI 只会显示
  /// 一句晦涩的 "Stack Overflow"，这里统一翻译成可执行的提示。
  static String _friendlyPluginError(Object error) {
    final text = error.toString();
    if (text.contains('stack overflow') || text.contains('Stack Overflow')) {
      return '插件脚本过大或递归过深，JS 引擎栈溢出，请更换精简版插件';
    }
    if (text.startsWith('Exception: ')) {
      return text.substring('Exception: '.length);
    }
    return text;
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
    if (data is! Map) return null;

    final name = _safeString(data['name']);
    final version = _safeString(data['version']);
    final author = _safeString(data['author']);

    if (name == null || version == null || author == null) return null;

    return PluginMetadata(
      name: name,
      version: version,
      author: author,
      description: _safeString(data['description']),
      homepage: _safeString(data['homepage']),
    );
  }

  /// Safely convert a dynamic value to String, handling Lists and other
  /// non-String types that LX scripts may export.
  static String? _safeString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is List) {
      // Some LX scripts export arrays — join non-null elements
      final parts = value
          .where((e) => e != null && e.toString().isNotEmpty)
          .map((e) => e.toString())
          .toList();
      return parts.isEmpty ? null : parts.join(', ');
    }
    return value.toString();
  }

  Map<String, dynamic> _parseSourcesWithActions(dynamic data) {
    final sources = <PluginSourceInfo>[];
    final actions = <String, List<String>>{};

    if (data == null) return {'sources': sources, 'actions': actions};

    if (data is Map) {
      data.forEach((key, value) {
        if (value is Map) {
          final name = _safeString(value['name']) ??
              SourceInfo.getNameById(key as String);
          final qualitys = _safeStringList(value['qualitys']) ??
              _safeStringList(value['qualities']) ??
              [];
          final sourceActions =
              (_safeStringList(value['actions']) ?? const ['musicUrl'])
                  .map((e) => e.toLowerCase())
                  .toList();

          sources.add(PluginSourceInfo(name: name, qualities: qualitys));
          actions[key.toString()] = sourceActions;
        }
      });
    }

    return {'sources': sources, 'actions': actions};
  }

  /// Safely convert a dynamic value to List<String>.
  static List<String>? _safeStringList(dynamic value) {
    if (value == null) return null;
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return null;
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
    String quality, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final result = await getMusicUrlResult(
      source,
      musicInfo,
      quality,
      timeout: timeout,
    );
    return result.url;
  }

  Future<PluginMusicUrlResult> getMusicUrlResult(
    String source,
    MusicInfoForPlugin musicInfo,
    String quality, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    _ensureLoaded();

    final infoJson = jsonEncode(musicInfo.toJson());
    final escapedInfo = _escapeForJs(infoJson);

    final result = await _engine.callPluginMethod(
      "module.exports.musicUrl('$source', JSON.parse('$escapedInfo'), '$quality')",
      timeout: timeout,
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
    if (!_engine.isRuntimeHealthy) {
      _loaded = false;
      throw StateError('插件 JS 运行时已隔离，请重新加载插件');
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
