abstract class AppConstants {
  AppConstants._();

  static const String appName = '薄荷音乐';
  static const String appVersion = '1.0.5';

  static const int defaultPageSize = 30;
  static const int maxRetryCount = 3;
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);

  static const String defaultMusicSource = 'wy';
  static const String defaultQuality = '128k';

  static const int maxDownloadConcurrent = 3;
  static const String downloadDirName = 'MintMusic';
}
