/// 应用支持的语言(参考 Mio-Music 的 AppLocale 设计)。
enum AppLocale {
  /// 简体中文(默认)。
  zhCn('zh-CN', '简体中文'),

  /// 繁体中文。
  zhTw('zh-TW', '繁體中文');

  const AppLocale(this.code, this.label);

  /// 与系统/持久化使用的 locale code,如 `zh-CN`、`zh-TW`。
  final String code;

  /// 该语言自身的显示名(用于设置页选项)。
  final String label;

  /// 从持久化字符串解析,未知值回退简体中文。
  static AppLocale fromCode(String? code) {
    switch (code) {
      case 'zh-TW':
      case 'zh-tw':
      case 'zh_Hant':
        return AppLocale.zhTw;
      default:
        return AppLocale.zhCn;
    }
  }
}
