import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/theme_provider.dart';
import '../data/settings_service.dart';

final settingsServiceProvider = FutureProvider<SettingsService>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return SettingsService(prefs);
});

// -- audio quality --
final audioQualityProvider = StateProvider<String>((ref) => '320k');
final autoQualityDowngradeProvider = StateProvider<bool>((ref) => false);

// -- equalizer --
final equalizerEnabledProvider = StateProvider<bool>((ref) => false);

// -- playback --
final playbackSpeedProvider = StateProvider<double>((ref) => 1.0);
final autoPlayProvider = StateProvider<bool>((ref) => false);
final rememberProgressProvider = StateProvider<bool>((ref) => true);

// -- download --
final downloadDirProvider = StateProvider<String>(
  (ref) => '/storage/emulated/0/Music/MintMusic',
);
final wifiOnlyDownloadProvider = StateProvider<bool>((ref) => true);

// -- notification --
final notificationEnabledProvider = StateProvider<bool>((ref) => true);

// -- music source --
final musicSourceProvider = StateProvider<String>((ref) => '网易云');

const kSourceNameToId = <String, String>{
  '网易云': 'wy',
  'QQ音乐': 'tx',
  '酷狗': 'kg',
  '酷我': 'kw',
  '咪咕': 'mg',
};

const kSourceIdToName = <String, String>{
  'wy': '网易云',
  'tx': 'QQ音乐',
  'kg': '酷狗',
  'kw': '酷我',
  'mg': '咪咕',
};

final defaultSourceIdProvider = Provider<String>((ref) {
  final name = ref.watch(musicSourceProvider);
  return kSourceNameToId[name] ?? 'wy';
});

const kQualityDisplayName = <String, String>{
  '128k': '标准 128K',
  '192k': '高品质 192K',
  '320k': '超高品质 320K',
  'flac': '无损 FLAC',
  'flac24bit': '高解析度无损',
  'hires': '高清臻音',
  'atmos': '沉浸环绕声',
  'master': '超清母带',
};

const kQualityDescription = <String, String>{
  '128k': '基础音质，文件较小',
  '192k': '良好音质，适合大多数场景',
  '320k': '高品质音质，接近CD品质',
  'flac': '无损音质，完美还原原始录音',
  'flac24bit': '高解析度无损，最高192kHz/24bit',
  'hires': '声音听感加强，96kHz/24bit',
  'atmos': '沉浸式空间环绕音感',
  'master': '母带级音质，192kHz/24bit',
};

const kSourceSupportedQualities = <String, List<String>>{
  'wy': ['128k', '320k', 'flac', 'flac24bit', 'hires', 'atmos'],
  'tx': ['128k', '320k', 'flac', 'hires', 'atmos', 'master'],
  'kg': ['128k', '320k', 'flac', 'flac24bit', 'hires'],
  'kw': ['128k', '320k', 'flac', 'flac24bit', 'hires'],
  'mg': ['128k', '320k', 'flac', 'flac24bit', 'hires', 'atmos', 'master'],
};

List<String> getSupportedQualitiesForSource(String sourceName) {
  final id = kSourceNameToId[sourceName];
  if (id == null) return ['128k', '320k', 'flac'];
  return kSourceSupportedQualities[id] ?? ['128k', '320k', 'flac'];
}

String getQualityDisplayName(String qualityId) {
  return kQualityDisplayName[qualityId] ?? qualityId;
}

final sourceQualityProvider = StateProvider<Map<String, String>>(
  (ref) => {
    '网易云': '320k',
    'QQ音乐': '320k',
    '酷狗': '320k',
    '酷我': '320k',
    '咪咕': '320k',
  },
);

final globalQualityProvider = StateProvider<String>((ref) => '320k');

// -- cache --
final cacheSizeProvider = StateProvider<String>((ref) => '128 MB');

// -- filename template --
final filenameTemplateProvider = StateProvider<String>((ref) => '%t - %s');

// -- tag write --
final tagWriteBasicInfoProvider = StateProvider<bool>((ref) => true);
final tagWriteCoverProvider = StateProvider<bool>((ref) => true);
final tagWriteLyricsProvider = StateProvider<bool>((ref) => true);
final tagWriteDownloadLyricsProvider = StateProvider<bool>((ref) => false);
final tagWriteLyricFormatProvider = StateProvider<String>(
  (ref) => 'word-by-word',
);

// -- audio effects --
final audioEffectEnabledProvider = StateProvider<bool>((ref) => false);
final audioVisualizerEnabledProvider = StateProvider<bool>((ref) => false);

// -- bass boost --
final bassBoostEnabledProvider = StateProvider<bool>((ref) => false);
final bassBoostGainProvider = StateProvider<double>((ref) => 6.0);
final bassBoostPresetProvider = StateProvider<String>((ref) => 'medium');

// -- surround --
final surroundEnabledProvider = StateProvider<bool>((ref) => false);
final surroundModeProvider = StateProvider<String>((ref) => 'small');

// -- balance --
final balanceEnabledProvider = StateProvider<bool>((ref) => false);
final balanceValueProvider = StateProvider<double>((ref) => 0.0);

// -- equalizer preset --
final equalizerPresetProvider = StateProvider<String>((ref) => '流行');
final equalizerBandsProvider = StateProvider<List<double>>(
  (ref) => [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
);
final equalizerCustomPresetsProvider =
    StateProvider<List<Map<String, dynamic>>>((ref) => []);

// -- lyric display --
final lyricFontSizeProvider = StateProvider<double>((ref) => 1.0);
final lyricShowTranslationProvider = StateProvider<bool>((ref) => true);
final lyricShowRomanProvider = StateProvider<bool>((ref) => true);
final lyricEnableBlurProvider = StateProvider<bool>((ref) => true);
final lyricEnableScaleProvider = StateProvider<bool>((ref) => true);
final lyricCenterAlignProvider = StateProvider<bool>((ref) => true);
final amllCenterAlignProvider = StateProvider<bool>((ref) => false);
final lyricImmersiveColorProvider = StateProvider<bool>((ref) => true);

// -- lyric font --
final lyricFontFamilyProvider = StateProvider<String>((ref) => 'system');
final lyricFontRateProvider = StateProvider<double>((ref) => 1.0);
final lyricFontWeightProvider = StateProvider<int>((ref) => 700);

/// 歌词字体颜色（hex ARGB 字符串，空表示使用默认/沉浸色）
final lyricFontColorProvider = StateProvider<String>((ref) => '');

// -- appearance --
final appearanceJumpLyricProvider = StateProvider<bool>((ref) => true);
final appearanceBgAnimationProvider = StateProvider<bool>((ref) => true);

// -- auto cache music --
final autoCacheMusicProvider = StateProvider<bool>((ref) => true);

// -- route preload --
final routePreloadEnabledProvider = StateProvider<bool>((ref) => true);

final autoUpdateProvider = StateProvider<bool>((ref) => true);
final closeToTrayProvider = StateProvider<bool>((ref) => true);
final cacheDirProvider = StateProvider<String>((ref) => '');

final downloadDirSizeProvider = FutureProvider<String>((ref) async {
  final svc = await ref.read(settingsServiceProvider.future);
  final dir = ref.read(downloadDirProvider);
  return svc.getDirectorySize(dir);
});

final cacheDirSizeProvider = FutureProvider<String>((ref) async {
  final svc = await ref.read(settingsServiceProvider.future);
  final dir = ref.read(cacheDirProvider);
  if (dir.isEmpty) return '0 B';
  return svc.getDirectorySize(dir);
});

enum FullScreenBackgroundMode { theme, cover, dark }

final fullScreenBackgroundModeProvider =
    StateProvider<FullScreenBackgroundMode>(
      (ref) => FullScreenBackgroundMode.theme,
    );

// -- app version (loaded once) --
final appVersionProvider = FutureProvider<String>((ref) async {
  return '1.0.3';
});

class EqPreset {
  final String name;
  final List<double> gains;
  final List<double>? originalGains;
  const EqPreset({required this.name, required this.gains, this.originalGains});
  Map<String, dynamic> toJson() => {
    'name': name,
    'gains': gains,
    'originalGains': originalGains,
  };
  factory EqPreset.fromJson(Map<String, dynamic> json) => EqPreset(
    name: json['name'] as String,
    gains: (json['gains'] as List).cast<double>(),
    originalGains: (json['originalGains'] as List?)?.cast<double>(),
  );
}

const kEqFrequencies = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

const kBuiltInPresets = <EqPreset>[
  EqPreset(name: 'Flat(原声)', gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
  EqPreset(name: 'Pop(流行)', gains: [1, 3, 4, 3, 1, -1, -1, 1, 2, 3]),
  EqPreset(name: 'Rock(摇滚)', gains: [4, 3, 1, 0, -1, -1, 0, 2, 3, 4]),
  EqPreset(name: 'Jazz(爵士)', gains: [3, 2, 1, 2, -1, -1, 0, 1, 2, 3]),
  EqPreset(name: 'Classical(古典)', gains: [4, 3, 2, 1, -1, -1, 0, 2, 3, 4]),
  EqPreset(name: 'Bass Boost(低音增强)', gains: [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
  EqPreset(name: 'Vocal Boost(人声增强)', gains: [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1]),
  EqPreset(name: 'Treble Boost(高音增强)', gains: [0, 0, 0, 0, 0, 1, 3, 5, 6, 6]),
];

// -- init: load all persisted settings into providers --
final settingsInitProvider = FutureProvider<void>((ref) async {
  final svc = await ref.watch(settingsServiceProvider.future);

  final themeStr = svc.getThemeMode();
  if (themeStr == 'light') {
    ref.read(themeModeProvider.notifier).state = ThemeMode.light;
  } else if (themeStr == 'dark') {
    ref.read(themeModeProvider.notifier).state = ThemeMode.dark;
  } else {
    ref.read(themeModeProvider.notifier).state = ThemeMode.light;
  }
  ref.read(themePrimaryColorProvider.notifier).state = svc
      .getThemePrimaryColor();

  ref.read(audioQualityProvider.notifier).state = svc.getAudioQuality();
  ref.read(autoQualityDowngradeProvider.notifier).state = svc
      .getAutoQualityDowngrade();
  ref.read(equalizerEnabledProvider.notifier).state = svc.getEqualizerEnabled();
  ref.read(equalizerPresetProvider.notifier).state = svc.getEqualizerPreset();
  final bandsStr = svc.getEqualizerBands();
  if (bandsStr.isNotEmpty) {
    try {
      final list = (jsonDecode(bandsStr) as List)
          .map((value) => (value as num).toDouble())
          .toList();
      ref.read(equalizerBandsProvider.notifier).state = list;
    } catch (_) {}
  }
  final customPresetsStr = svc.getEqualizerCustomPresets();
  try {
    final list = (jsonDecode(customPresetsStr) as List)
        .cast<Map<String, dynamic>>();
    ref.read(equalizerCustomPresetsProvider.notifier).state = list;
  } catch (_) {}
  ref.read(playbackSpeedProvider.notifier).state = svc.getPlaybackSpeed();
  ref.read(downloadDirProvider.notifier).state = await svc.getDownloadDir();
  ref.read(wifiOnlyDownloadProvider.notifier).state = svc.getWifiOnlyDownload();
  ref.read(autoPlayProvider.notifier).state = svc.getAutoPlay();
  ref.read(rememberProgressProvider.notifier).state = svc.getRememberProgress();
  ref.read(notificationEnabledProvider.notifier).state = svc
      .getNotificationEnabled();
  ref.read(musicSourceProvider.notifier).state = svc.getMusicSource();
  ref.read(sourceQualityProvider.notifier).state = svc.getSourceQuality();
  ref.read(globalQualityProvider.notifier).state = svc.getGlobalQuality();
  ref.read(cacheSizeProvider.notifier).state = svc.getCacheSize();
  ref.read(filenameTemplateProvider.notifier).state = svc.getFilenameTemplate();
  ref.read(tagWriteBasicInfoProvider.notifier).state = svc
      .getTagWriteBasicInfo();
  ref.read(tagWriteCoverProvider.notifier).state = svc.getTagWriteCover();
  ref.read(tagWriteLyricsProvider.notifier).state = svc.getTagWriteLyrics();
  ref.read(tagWriteDownloadLyricsProvider.notifier).state = svc
      .getTagWriteDownloadLyrics();
  ref.read(tagWriteLyricFormatProvider.notifier).state = svc
      .getTagWriteLyricFormat();
  ref.read(audioEffectEnabledProvider.notifier).state = svc
      .getAudioEffectEnabled();
  ref.read(audioVisualizerEnabledProvider.notifier).state = svc
      .getAudioVisualizerEnabled();
  ref.read(bassBoostEnabledProvider.notifier).state = svc.getBassBoostEnabled();
  ref.read(bassBoostGainProvider.notifier).state = svc.getBassBoostGain();
  ref.read(bassBoostPresetProvider.notifier).state = svc.getBassBoostPreset();
  ref.read(surroundEnabledProvider.notifier).state = svc.getSurroundEnabled();
  ref.read(surroundModeProvider.notifier).state = svc.getSurroundMode();
  ref.read(balanceEnabledProvider.notifier).state = svc.getBalanceEnabled();
  ref.read(balanceValueProvider.notifier).state = svc.getBalanceValue();
  ref.read(lyricFontSizeProvider.notifier).state = svc.getLyricFontSize();
  ref.read(lyricShowTranslationProvider.notifier).state = svc
      .getLyricShowTranslation();
  ref.read(lyricShowRomanProvider.notifier).state = svc.getLyricShowRoman();
  ref.read(lyricEnableBlurProvider.notifier).state = svc.getLyricEnableBlur();
  ref.read(lyricEnableScaleProvider.notifier).state = svc.getLyricEnableScale();
  ref.read(lyricCenterAlignProvider.notifier).state = svc.getLyricCenterAlign();
  ref.read(amllCenterAlignProvider.notifier).state = svc.getAmllCenterAlign();
  ref.read(lyricImmersiveColorProvider.notifier).state = svc
      .getLyricImmersiveColor();
  ref.read(lyricFontFamilyProvider.notifier).state = svc.getLyricFontFamily();
  ref.read(lyricFontRateProvider.notifier).state = svc.getLyricFontRate();
  ref.read(lyricFontWeightProvider.notifier).state = svc.getLyricFontWeight();
  ref.read(lyricFontColorProvider.notifier).state = svc.getLyricFontColor();
  ref.read(appearanceJumpLyricProvider.notifier).state = svc
      .getAppearanceJumpLyric();
  ref.read(appearanceBgAnimationProvider.notifier).state = svc
      .getAppearanceBgAnimation();
  ref.read(autoCacheMusicProvider.notifier).state = svc.getAutoCacheMusic();
  ref.read(routePreloadEnabledProvider.notifier).state = svc
      .getRoutePreloadEnabled();
  ref.read(autoUpdateProvider.notifier).state = svc.getAutoUpdate();
  ref.read(closeToTrayProvider.notifier).state = svc.getCloseToTray();
  ref.read(cacheDirProvider.notifier).state = await svc.getCacheDir();
  final bgMode = svc.getFullScreenBgMode();
  ref
      .read(fullScreenBackgroundModeProvider.notifier)
      .state = FullScreenBackgroundMode.values.firstWhere(
    (e) => e.name == bgMode,
    orElse: () => FullScreenBackgroundMode.theme,
  );
});

Future<void> persistSetting(
  Ref ref,
  Future<void> Function(SettingsService svc) saveFn,
) async {
  final svc = await ref.read(settingsServiceProvider.future);
  await saveFn(svc);
}
