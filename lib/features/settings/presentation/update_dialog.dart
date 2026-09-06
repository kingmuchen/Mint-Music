import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/theme_provider.dart';
import '../domain/models/update_info.dart';

/// 打开系统浏览器访问指定链接。
Future<void> openExternalUrl(BuildContext context, String url) async {
  final uri = Uri.parse(url);
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('无法打开链接: $url')),
        backgroundColor: Colors.red,
      ),
    );
  }
}

/// 弹出「发现新版本」升级提示框。
/// 点击「立即更新」跳转浏览器下载 APK（无 APK 附件时打开 release 页面）。
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) async {
  final colors = ProviderScope.containerOf(context).read(themeColorsProvider);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: colors.surface,
      title: Row(
        children: [
          Icon(Icons.system_update_alt, color: colors.primary, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ctx.tr('发现新版本 v${info.cleanVersion}'),
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ctx.tr('当前版本：v${AppConstants.appVersion}'),
              style: TextStyle(color: colors.textHint, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Text(
              (info.notes?.isNotEmpty ?? false)
                  ? info.notes!
                  : ctx.tr('请前往下载页面获取最新版本。'),
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(ctx.tr('稍后'), style: TextStyle(color: colors.textHint)),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            openExternalUrl(
              ctx,
              info.apkUrl ?? info.htmlUrl,
            );
          },
          child: Text(
            ctx.tr('立即更新'),
            style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
