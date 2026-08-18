import 'package:dio/dio.dart';
import '../../../core/constants/app_constants.dart';
import '../domain/models/update_info.dart';

/// 检查应用更新：通过 GitHub Releases API 获取最新版本。
class UpdateService {
  UpdateService({Dio? dio}) : _dio = dio ?? _createDio();

  /// 项目 GitHub 仓库（releases 页面地址与版本检查 API 共用）。
  static const String repo = 'kingmuchen/Mint-Music';

  static const String releasesPageUrl =
      'https://github.com/kingmuchen/Mint-Music/releases';

  /// GitHub 最新版本 API（无需鉴权，返回最新正式 release）。
  static const String _latestReleaseApi =
      'https://api.github.com/repos/kingmuchen/Mint-Music/releases/latest';

  final Dio _dio;

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        connectTimeout: AppConstants.connectTimeout,
        receiveTimeout: AppConstants.receiveTimeout,
        // GitHub API 要求 User-Agent；app 全局 HttpOverrides 会去掉 UA，
        // 这里显式带上。
        headers: {
          'User-Agent': 'MintMusic/${AppConstants.appVersion}',
          'Accept': 'application/vnd.github+json',
        },
      ),
    );
  }

  /// 拉取最新 release。请求失败或解析失败时返回 null。
  Future<UpdateInfo?> fetchLatestRelease() async {
    try {
      final response = await _dio.get<dynamic>(_latestReleaseApi);
      if (response.statusCode != 200) return null;
      final data = response.data;
      if (data is! Map) return null;
      return _parseRelease(data);
    } catch (e) {
      print('>>> 检查更新失败: $e');
      return null;
    }
  }

  UpdateInfo? _parseRelease(Map<dynamic, dynamic> data) {
    final tag = data['tag_name']?.toString();
    final name = data['name']?.toString();
    if (tag == null || tag.isEmpty) return null;

    final htmlUrl = data['html_url']?.toString() ?? releasesPageUrl;

    // 优先找第一个 .apk 附件，其次用 release 页面。
    String? apkUrl;
    final assets = data['assets'];
    if (assets is List) {
      for (final asset in assets) {
        if (asset is Map) {
          final fileName = asset['name']?.toString() ?? '';
          if (fileName.toLowerCase().endsWith('.apk')) {
            apkUrl = asset['browser_download_url']?.toString();
            if (apkUrl != null) break;
          }
        }
      }
    }

    return UpdateInfo(
      version: tag,
      name: name ?? tag,
      notes: data['body']?.toString(),
      htmlUrl: htmlUrl,
      apkUrl: apkUrl,
    );
  }

  /// 判断远端版本是否比当前版本更新（逐段数字比较，参考 CeruMusic 实现）。
  static bool isNewerVersion(String remoteVersion, String currentVersion) {
    List<int> parseVersion(String version) {
      return version
          .replaceFirst(RegExp('^v'), '')
          .split('.')
          .map((item) => int.tryParse(item) ?? 0)
          .toList();
    }

    final remote = parseVersion(remoteVersion);
    final current = parseVersion(currentVersion);

    for (int i = 0; i < (remote.length > current.length ? remote.length : current.length); i++) {
      final r = i < remote.length ? remote[i] : 0;
      final c = i < current.length ? current[i] : 0;
      if (r > c) return true;
      if (r < c) return false;
    }
    return false;
  }
}
