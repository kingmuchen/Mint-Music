import 'package:flutter/services.dart';

const _channel = MethodChannel('com.mintmusic/media');

Future<void> scanFileInMediaStore(String filePath) async {
  try {
    await _channel.invokeMethod('scanFile', filePath);
  } catch (_) {}
}

Future<bool> openManageStorageSettings() async {
  try {
    final result = await _channel.invokeMethod<bool>('openManageStorageSettings');
    return result ?? false;
  } catch (_) {
    return false;
  }
}
