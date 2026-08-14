import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models/plugin_info.dart';

class PluginRepository {
  static const _key = 'installed_plugins';
  final Dio _dio = Dio();

  Future<List<PluginInfo>> loadPlugins() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    if (data == null) return [];
    final list = jsonDecode(data) as List<dynamic>;
    return list
        .map((e) => PluginInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> savePlugins(List<PluginInfo> plugins) async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(plugins.map((p) => p.toJson()).toList());
    await prefs.setString(_key, data);
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

    return await addPlugin(pluginCode, fileName, type);
  }

  Future<PluginInfo> downloadAndAddPlugin(String url, String type) async {
    final response = await _dio.get(
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
    final pluginInfo = _parsePluginInfo(pluginCode);

    if (pluginInfo['name'] == null ||
        pluginInfo['version'] == null ||
        pluginInfo['author'] == null) {
      throw Exception('插件信息不完整，必须包含名称、版本和作者信息');
    }

    final plugins = await loadPlugins();
    final duplicate = plugins.where(
      (p) => p.name == pluginInfo['name'] && p.version == pluginInfo['version'],
    );
    if (duplicate.isNotEmpty) {
      throw Exception(
        '插件 "${pluginInfo['name']} v${pluginInfo['version']}" 已存在，不能重复添加',
      );
    }

    final pluginId = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    final safeName = (pluginName).replaceAll(RegExp(r'[^\w\d-]'), '_');
    final pluginsDir = await _getPluginsDir();
    final destPath = '$pluginsDir/${pluginId}_$safeName';
    final destFile = File(destPath);
    await destFile.writeAsString(pluginCode);

    final sources = _parseSupportedSources(pluginCode);

    final plugin = PluginInfo(
      id: pluginId,
      name: pluginInfo['name'] as String,
      version: pluginInfo['version'] as String,
      author: pluginInfo['author'] as String,
      description: pluginInfo['description'] ?? '',
      type: type,
      installTime: DateTime.now(),
      supportedSources: sources,
      filePath: destPath,
      isEnabled: plugins.isEmpty,
    );

    plugins.add(plugin);
    await savePlugins(plugins);
    return plugin;
  }

  Map<String, String?> _parsePluginInfo(String code) {
    final nameMatch = RegExp(
      "name\\s*:\\s*['\"]([^'\"]+)['\"]",
    ).firstMatch(code);
    final versionMatch = RegExp(
      "version\\s*:\\s*['\"]([^'\"]+)['\"]",
    ).firstMatch(code);
    final authorMatch = RegExp(
      "author\\s*:\\s*['\"]([^'\"]+)['\"]",
    ).firstMatch(code);
    final descMatch = RegExp(
      "description\\s*:\\s*['\"]([^'\"]+)['\"]",
    ).firstMatch(code);

    return {
      'name': nameMatch?.group(1),
      'version': versionMatch?.group(1),
      'author': authorMatch?.group(1),
      'description': descMatch?.group(1),
    };
  }

  List<PluginSource> _parseSupportedSources(String code) {
    final sources = <PluginSource>[];
    final sourceMatch = RegExp(
      "sources\\s*:\\s*\\[([\\s\\S]*?)\\]",
      multiLine: true,
    ).firstMatch(code);
    if (sourceMatch != null) {
      final sourcesBlock = sourceMatch.group(1)!;
      final sourceEntries = RegExp(
        "\\{[\\s\\S]*?name\\s*:\\s*['\"]([^'\"]+)['\"][\\s\\S]*?qualities\\s*:\\s*\\[([^\\]]*)\\]",
      ).allMatches(sourcesBlock);
      for (final entry in sourceEntries) {
        final name = entry.group(1)!;
        final qualitiesStr = entry.group(2)!;
        final qualities = RegExp(
          "['\"]([^'\"]+)['\"]",
        ).allMatches(qualitiesStr).map((m) => m.group(1)!).toList();
        sources.add(PluginSource(name: name, qualities: qualities));
      }
    }
    return sources;
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
    plugins.removeWhere((p) => p.id == id);
    await savePlugins(plugins);
  }

  Future<void> togglePlugin(String id, bool isEnabled) async {
    final plugins = await loadPlugins();
    final index = plugins.indexWhere((p) => p.id == id);
    if (index != -1) {
      if (isEnabled) {
        final updatedPlugins = plugins
            .map((plugin) => plugin.copyWith(isEnabled: plugin.id == id))
            .toList();
        await savePlugins(updatedPlugins);
      } else {
        plugins[index] = plugins[index].copyWith(isEnabled: false);
        await savePlugins(plugins);
      }
    }
  }

  Future<void> updatePlugin(PluginInfo plugin) async {
    final plugins = await loadPlugins();
    final index = plugins.indexWhere((p) => p.id == plugin.id);
    if (index != -1) {
      plugins[index] = plugin;
      await savePlugins(plugins);
    }
  }
}
