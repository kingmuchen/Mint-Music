import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../platform/js_engine_service.dart';
import '../data/plugin_host.dart';
import '../data/lx_plugin_converter.dart';
import '../../settings/domain/models/plugin_info.dart';

class PluginService {
  static const String _prefsKey = 'installed_plugins';
  final Map<String, PluginHost> _loadedPlugins = {};
  final Map<String, JsEngineService> _engines = {};

  Future<List<PluginInfo>> loadPlugins() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_prefsKey);
    if (data == null) return [];
    final list = jsonDecode(data) as List<dynamic>;
    return list
        .map((e) => PluginInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> savePlugins(List<PluginInfo> plugins) async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(plugins.map((p) => p.toJson()).toList());
    await prefs.setString(_prefsKey, data);
  }

  Future<String> _getPluginsDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final pluginsDir = Directory('${appDir.path}/plugins');
    if (!await pluginsDir.exists()) {
      await pluginsDir.create(recursive: true);
    }
    return pluginsDir.path;
  }

  Future<PluginInfo> selectAndAddPlugin(String type) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '请选择你的 ${type == 'lx' ? '洛雪' : '澜音'} js插件',
      type: FileType.custom,
      allowedExtensions: ['js'],
    );

    if (result == null || result.files.isEmpty) {
      throw Exception('未选择文件');
    }

    final filePath = result.files.single.path;
    if (filePath == null) {
      throw Exception('无法获取文件路径');
    }

    final file = File(filePath);
    final fileName = file.uri.pathSegments.last;
    String pluginCode = await file.readAsString();

    _validatePluginCode(pluginCode, type);

    if (type == 'lx') {
      final converter = LxPluginConverter();
      pluginCode = converter.convert(pluginCode);
    }

    return await addPlugin(pluginCode, fileName, type);
  }

  Future<PluginInfo> downloadAndAddPlugin(String url, String type) async {
    final dio = Dio();
    final response = await dio.get(
      url,
      options: Options(
        responseType: ResponseType.plain,
        headers: {'User-Agent': 'MintMusic/1.0'},
        receiveTimeout: const Duration(seconds: 30),
      ),
    );

    if (response.statusCode != 200) {
      throw Exception('下载失败: HTTP ${response.statusCode}');
    }

    String pluginCode = response.data.toString();
    if (pluginCode.trim().isEmpty) {
      throw Exception('下载的文件内容为空');
    }

    _validatePluginCode(pluginCode, type);

    if (type == 'lx') {
      final converter = LxPluginConverter();
      pluginCode = converter.convert(pluginCode);
    }

    final fileName = 'downloaded_${DateTime.now().millisecondsSinceEpoch}.js';
    return await addPlugin(pluginCode, fileName, type);
  }

  void _validatePluginCode(String code, String type) {
    if (type == 'cr') {
      if (!code.toLowerCase().contains('cerumusic')) {
        throw Exception('澜音插件格式校验失败：代码中未找到cerumusic关键字');
      }
    } else if (type == 'lx') {
      if (!code.toLowerCase().contains('lx')) {
        throw Exception('洛雪插件格式校验失败：代码中未找到lx关键字');
      }
    }
  }

  Future<PluginInfo> addPlugin(
    String pluginCode,
    String pluginName,
    String type,
  ) async {
    final engine = JsEngineService();
    await engine.init();

    try {
      final host = PluginHost(engine);
      await host.loadPlugin(pluginCode);

      final pluginInfo = host.pluginInfo;
      if (pluginInfo == null) {
        throw Exception('插件信息不完整');
      }

      final plugins = await loadPlugins();
      final duplicate = plugins.where(
        (p) => p.name == pluginInfo.name && p.version == pluginInfo.version,
      );
      if (duplicate.isNotEmpty) {
        engine.dispose();
        throw Exception(
          '插件 "${pluginInfo.name} v${pluginInfo.version}" 已存在，不能重复添加',
        );
      }

      final pluginId = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
      final safeName = pluginName.replaceAll(RegExp(r'[^\w\d-]'), '_');
      final pluginsDir = await _getPluginsDir();
      final destPath = '$pluginsDir/${pluginId}_$safeName';
      final destFile = File(destPath);
      await destFile.writeAsString(pluginCode);

      final sources = host.sources
          .map((s) => PluginSource(name: s.name, qualities: s.qualities))
          .toList();

      final plugin = PluginInfo(
        id: pluginId,
        name: pluginInfo.name,
        version: pluginInfo.version,
        author: pluginInfo.author,
        description: pluginInfo.description ?? '',
        type: type,
        installTime: DateTime.now(),
        supportedSources: sources,
        filePath: destPath,
        isEnabled: plugins.isEmpty,
      );

      plugins.add(plugin);
      await savePlugins(plugins);

      if (plugin.isEnabled) {
        _loadedPlugins[pluginId] = host;
        _engines[pluginId] = engine;
      } else {
        engine.dispose();
      }
      return plugin;
    } catch (e) {
      engine.dispose();
      rethrow;
    }
  }

  Future<void> initializePlugins() async {
    final plugins = await _normalizeEnabledPlugins(await loadPlugins());
    _unloadAllPlugins();
    print('[PluginService] 开始初始化插件，共 ${plugins.length} 个插件');

    for (final plugin in plugins) {
      print(
        '[PluginService] 检查插件: ${plugin.name}, isEnabled: ${plugin.isEnabled}',
      );
      if (!plugin.isEnabled || plugin.filePath == null) continue;

      try {
        print('[PluginService] 加载插件文件: ${plugin.filePath}');
        final host = await _loadPlugin(plugin);

        print(
          '[PluginService] 插件 ${plugin.name} 加载成功，源数量: ${host.sources.length}',
        );
        for (final source in host.sources) {
          print(
            '[PluginService]   - 源: ${source.name}, 音质: ${source.qualities.join(", ")}',
          );
        }
      } catch (e, stackTrace) {
        print('[PluginService] Failed to load plugin ${plugin.name}: $e');
        print('[PluginService] StackTrace: $stackTrace');
      }
    }

    print('[PluginService] 插件初始化完成，已加载 ${_loadedPlugins.length} 个插件');
  }

  PluginHost? getPluginById(String pluginId) {
    return _loadedPlugins[pluginId];
  }

  Future<void> uninstallPlugin(String id) async {
    final plugins = await loadPlugins();
    final plugin = plugins.where((p) => p.id == id).firstOrNull;

    if (plugin?.filePath != null) {
      final file = File(plugin!.filePath!);
      if (await file.exists()) {
        await file.delete();
      }
    }

    _unloadPlugin(id);

    plugins.removeWhere((p) => p.id == id);
    await savePlugins(plugins);
  }

  Future<void> togglePlugin(String id, bool isEnabled) async {
    final plugins = await loadPlugins();
    final index = plugins.indexWhere((p) => p.id == id);
    if (index == -1) return;

    if (!isEnabled) {
      plugins[index] = plugins[index].copyWith(isEnabled: false);
      await savePlugins(plugins);
      _unloadPlugin(id);
      return;
    }

    final selectedPlugin = plugins[index];
    final wasAlreadyLoaded = _loadedPlugins.containsKey(id);
    try {
      // Validate and prepare the new runtime before turning off the active
      // plugin, so a corrupt plugin cannot leave music sources unavailable.
      await _loadPlugin(selectedPlugin);
    } catch (e) {
      print(
        '[PluginService] Failed to enable plugin ${selectedPlugin.name}: $e',
      );
      rethrow;
    }

    final updatedPlugins = plugins
        .map((plugin) => plugin.copyWith(isEnabled: plugin.id == id))
        .toList();
    try {
      await savePlugins(updatedPlugins);
    } catch (_) {
      // Do not leave a newly-created runtime host active when persistence
      // fails, otherwise the in-memory state would disagree with the switch.
      if (!wasAlreadyLoaded) {
        _unloadPlugin(id);
      }
      rethrow;
    }

    for (final plugin in plugins) {
      if (plugin.id != id) {
        _unloadPlugin(plugin.id);
      }
    }
  }

  /// Older versions allowed several plugins to remain enabled. Retain the
  /// first enabled plugin in list order and persist the corrected state.
  Future<List<PluginInfo>> _normalizeEnabledPlugins(
    List<PluginInfo> plugins,
  ) async {
    var hasEnabledPlugin = false;
    var changed = false;
    final normalized = <PluginInfo>[];

    for (final plugin in plugins) {
      if (!plugin.isEnabled) {
        normalized.add(plugin);
      } else if (!hasEnabledPlugin) {
        hasEnabledPlugin = true;
        normalized.add(plugin);
      } else {
        changed = true;
        normalized.add(plugin.copyWith(isEnabled: false));
      }
    }

    if (changed) {
      await savePlugins(normalized);
    }
    return normalized;
  }

  Future<PluginHost> _loadPlugin(PluginInfo plugin) async {
    final existingHost = _loadedPlugins[plugin.id];
    if (existingHost != null) return existingHost;

    final filePath = plugin.filePath;
    if (filePath == null) {
      throw Exception('插件文件路径不存在');
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('插件文件不存在: $filePath');
    }

    final pluginCode = await _prepareStoredPluginCode(plugin, file);
    print('[PluginService] 插件代码长度: ${pluginCode.length} 字符');

    final engine = JsEngineService();
    try {
      await engine.init();
      final host = PluginHost(engine);
      await host.loadPlugin(pluginCode);
      _loadedPlugins[plugin.id] = host;
      _engines[plugin.id] = engine;
      return host;
    } catch (_) {
      engine.dispose();
      rethrow;
    }
  }

  void _unloadPlugin(String id) {
    _loadedPlugins.remove(id);
    _engines.remove(id)?.dispose();
  }

  void _unloadAllPlugins() {
    for (final engine in _engines.values) {
      engine.dispose();
    }
    _engines.clear();
    _loadedPlugins.clear();
  }

  /// Rebuild old LX converter output after an app update. Installed plugins
  /// are stored as converted JavaScript, so otherwise an app update would
  /// leave users running the old adapter forever.
  Future<String> _prepareStoredPluginCode(PluginInfo plugin, File file) async {
    final code = await file.readAsString();
    if (plugin.type != 'lx') return code;

    final originalCode = _extractEmbeddedOriginalCode(code);
    if (originalCode == null || originalCode.trim().isEmpty) return code;

    final convertedCode = LxPluginConverter().convert(originalCode);
    if (convertedCode != code) {
      await file.writeAsString(convertedCode);
      print('[PluginService] migrated legacy LX plugin: ${plugin.name}');
    }
    return convertedCode;
  }

  String? _extractEmbeddedOriginalCode(String code) {
    final match = RegExp(
      r'''(?:var|let|const)\s+originalPluginCode\s*=\s*("(?:\\.|[^"\\])*")\s*;''',
    ).firstMatch(code);
    if (match == null) return null;

    try {
      final value = jsonDecode(match.group(1)!);
      return value is String ? value : null;
    } catch (_) {
      return null;
    }
  }

  List<PluginHost> get enabledPlugins => _loadedPlugins.values.toList();

  List<String> getSupportedSourceIds() {
    final sourceIds = <String>{};
    for (final host in _loadedPlugins.values) {
      for (final source in host.sources) {
        final id = _sourceNameToId(source.name);
        if (id != null) sourceIds.add(id);
      }
    }
    return sourceIds.toList();
  }

  String? _sourceNameToId(String name) {
    final map = {
      '酷我音乐': 'kw',
      '酷狗音乐': 'kg',
      'QQ音乐': 'tx',
      '网易云音乐': 'wy',
      '咪咕音乐': 'mg',
    };
    return map[name];
  }

  void dispose() {
    _unloadAllPlugins();
  }
}
