/// 最新版本信息（来自 GitHub Releases API）。
class UpdateInfo {
  /// 最新版本号（如 v1.0.3）
  final String version;

  /// 版本名称（release 标题）
  final String name;

  /// 更新说明（release body）
  final String? notes;

  /// 版本详情页地址
  final String htmlUrl;

  /// APK 下载地址（无 APK 附件时为 null，回退到 htmlUrl）
  final String? apkUrl;

  const UpdateInfo({
    required this.version,
    required this.name,
    this.notes,
    required this.htmlUrl,
    this.apkUrl,
  });

  /// 去除版本号前缀 'v'，取纯净版本号。
  String get cleanVersion => version.replaceFirst(RegExp('^v'), '');
}
