import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'media_scanner.dart';

/// 检查是否有权限写入指定路径
Future<bool> hasWriteAccess(String path) async {
  // app 私有目录永远可写（不需要额外检查）
  if (path.contains('/Android/data/')) return true;

  // Android 11+ 需要 MANAGE_EXTERNAL_STORAGE
  if (Platform.isAndroid) {
    final status = await Permission.manageExternalStorage.status;
    return status.isGranted;
  }

  return true;
}

/// 请求 MANAGE_EXTERNAL_STORAGE 权限，返回是否已获得
Future<bool> requestManageStorage() async {
  if (!Platform.isAndroid) return true;

  final status = await Permission.manageExternalStorage.request();
  if (status.isGranted) return true;

  // 如果被拒绝（非永久），打开系统设置让用户手动开启
  if (status.isDenied && Platform.isAndroid) {
    await openManageStorageSettings();
    // 重新检查状态
    final newStatus = await Permission.manageExternalStorage.status;
    return newStatus.isGranted;
  }

  return status.isGranted;
}

/// 是否是公共存储目录（非 app 私有目录）
bool isPublicDirectory(String path) {
  return !path.contains('/Android/data/');
}
