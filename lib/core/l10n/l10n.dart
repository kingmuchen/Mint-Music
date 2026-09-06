import 'package:flutter/widgets.dart';
import 'app_locale.dart';
import 'han_converter.dart';

/// 当前应用语言(全局镜像,供无 BuildContext 的场景使用,
/// 如 LyricController 等非 widget 代码)。
///
/// 由 [appLocaleProvider] 写入(见 settings_providers.dart),与
/// InheritedWidget [L10n] 保持一致。
AppLocale currentLocale = AppLocale.zhCn;

/// 将简体中文源文本按当前语言转换:
/// - 简体:原样返回
/// - 繁体:OpenCC 简 -> 繁转换
String tr(String text) {
  if (currentLocale == AppLocale.zhTw) return HanConverter.s2t(text);
  return text;
}

/// 语言 InheritedWidget(参考 Mio-Music 的 i18n runtime 设计):
/// 挂在 MaterialApp 之上,`context.tr()` 通过它读取当前语言,
/// 语言变化时自动重建所有依赖它的 widget。
class L10n extends InheritedWidget {
  final AppLocale locale;

  const L10n({super.key, required this.locale, required super.child});

  static L10n of(BuildContext context) {
    final l10n = context.dependOnInheritedWidgetOfExactType<L10n>();
    assert(l10n != null, 'L10n not found in widget tree');
    return l10n!;
  }

  @override
  bool updateShouldNotify(L10n oldWidget) => oldWidget.locale != locale;
}

/// `context.tr('中文')`:在 widget 中响应式获取当前语言文本。
/// 需要 widget 树中存在 [L10n](App 根已挂载)。
extension L10nBuildContext on BuildContext {
  String tr(String text) {
    final locale = L10n.of(this).locale;
    if (locale == AppLocale.zhTw) return HanConverter.s2t(text);
    return text;
  }
}
