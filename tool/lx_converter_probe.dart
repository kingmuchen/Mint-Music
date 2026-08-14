import 'dart:convert';
import 'dart:io';

import '../lib/features/plugin/data/lx_plugin_converter.dart';

void main() {
  final downloadDir = Directory(r'C:\Users\wujuntao\Downloads');
  final plugin = downloadDir
      .listSync()
      .whereType<File>()
      .where((file) => file.path.contains(r'\lx-') && file.path.endsWith('.js'))
      .first;
  final converted = LxPluginConverter().convert(plugin.readAsStringSync());
  stdout.write(base64Encode(utf8.encode(converted)));
}
