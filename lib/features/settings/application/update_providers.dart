import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../data/update_service.dart';
import '../domain/models/update_info.dart';
import 'settings_providers.dart';

/// 更新检查服务实例。
final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService();
});

/// 最新 release 信息（可为 null 表示无更新或获取失败）。
/// 每次读取都会重新拉取，避免缓存过期。
final latestReleaseProvider = FutureProvider<UpdateInfo?>((ref) async {
  final service = ref.watch(updateServiceProvider);
  return service.fetchLatestRelease();
});

/// 应用会话级标记：避免本次启动重复弹窗。
bool _startupCheckDone = false;

/// 启动时检查更新（由 AppShell 首帧调用一次）。
/// 返回检测到的新版本信息；无更新、未开启自动更新或获取失败时返回 null。
Future<UpdateInfo?> runStartupUpdateCheck(WidgetRef ref) async {
  if (_startupCheckDone) return null;
  _startupCheckDone = true;
  final autoUpdate = ref.read(autoUpdateProvider);
  if (!autoUpdate) return null;
  final service = ref.read(updateServiceProvider);
  final info = await service.fetchLatestRelease();
  if (info == null) return null;
  if (!UpdateService.isNewerVersion(info.version, AppConstants.appVersion)) {
    return null;
  }
  return info;
}
