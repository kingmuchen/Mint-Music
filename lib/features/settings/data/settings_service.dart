import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

class SettingsService {
  final SharedPreferences _prefs;

  SettingsService(this._prefs);

  // -- theme --
  String getThemeMode() => _prefs.getString('theme_mode') ?? 'light';
  Future<void> setThemeMode(String v) => _prefs.setString('theme_mode', v);
  String getThemePrimaryColor() =>
      _prefs.getString('theme_primary_color') ?? '#1DB954';
  Future<void> setThemePrimaryColor(String v) =>
      _prefs.setString('theme_primary_color', v);

  // -- audio quality --
  String getAudioQuality() => _prefs.getString('audio_quality') ?? '320k';
  Future<void> setAudioQuality(String v) =>
      _prefs.setString('audio_quality', v);

  // -- automatic quality downgrade --
  bool getAutoQualityDowngrade() =>
      _prefs.getBool('auto_quality_downgrade') ?? false;
  Future<void> setAutoQualityDowngrade(bool v) =>
      _prefs.setBool('auto_quality_downgrade', v);

  // -- equalizer enable --
  bool getEqualizerEnabled() => _prefs.getBool('equalizer_enabled') ?? false;
  Future<void> setEqualizerEnabled(bool v) =>
      _prefs.setBool('equalizer_enabled', v);

  // -- equalizer preset --
  String getEqualizerPreset() => _prefs.getString('eq_preset') ?? '流行';
  Future<void> setEqualizerPreset(String v) => _prefs.setString('eq_preset', v);

  // -- equalizer bands (10-band, JSON) --
  String getEqualizerBands() => _prefs.getString('eq_bands') ?? '';
  Future<void> setEqualizerBands(String v) => _prefs.setString('eq_bands', v);

  // -- bass boost --
  bool getBassBoostEnabled() => _prefs.getBool('bass_boost_enabled') ?? false;
  Future<void> setBassBoostEnabled(bool v) =>
      _prefs.setBool('bass_boost_enabled', v);
  double getBassBoostGain() => _prefs.getDouble('bass_boost_gain') ?? 6.0;
  Future<void> setBassBoostGain(double v) =>
      _prefs.setDouble('bass_boost_gain', v);
  String getBassBoostPreset() =>
      _prefs.getString('bass_boost_preset') ?? 'medium';
  Future<void> setBassBoostPreset(String v) =>
      _prefs.setString('bass_boost_preset', v);

  // -- surround --
  bool getSurroundEnabled() => _prefs.getBool('surround_enabled') ?? false;
  Future<void> setSurroundEnabled(bool v) =>
      _prefs.setBool('surround_enabled', v);
  String getSurroundMode() => _prefs.getString('surround_mode') ?? 'small';
  Future<void> setSurroundMode(String v) =>
      _prefs.setString('surround_mode', v);

  // -- balance --
  bool getBalanceEnabled() => _prefs.getBool('balance_enabled') ?? false;
  Future<void> setBalanceEnabled(bool v) =>
      _prefs.setBool('balance_enabled', v);
  double getBalanceValue() => _prefs.getDouble('balance_value') ?? 0.0;
  Future<void> setBalanceValue(double v) =>
      _prefs.setDouble('balance_value', v);

  // -- playback speed --
  double getPlaybackSpeed() => _prefs.getDouble('playback_speed') ?? 1.0;
  Future<void> setPlaybackSpeed(double v) =>
      _prefs.setDouble('playback_speed', v);

  // -- download dir --
  Future<String> getDownloadDir() async {
    final persisted = _prefs.getString('download_dir');
    if (persisted != null && persisted.isNotEmpty) return persisted;
    return '/storage/emulated/0/Music/MintMusic';
  }

  Future<void> setDownloadDir(String v) => _prefs.setString('download_dir', v);

  // -- wifi only --
  bool getWifiOnlyDownload() => _prefs.getBool('wifi_only_download') ?? true;
  Future<void> setWifiOnlyDownload(bool v) =>
      _prefs.setBool('wifi_only_download', v);

  // -- auto play --
  bool getAutoPlay() => _prefs.getBool('auto_play') ?? false;
  Future<void> setAutoPlay(bool v) => _prefs.setBool('auto_play', v);

  // -- remember progress --
  bool getRememberProgress() => _prefs.getBool('remember_progress') ?? true;
  Future<void> setRememberProgress(bool v) =>
      _prefs.setBool('remember_progress', v);

  // -- last playback state (JSON) --
  String? getLastPlaybackStateJson() => _prefs.getString('last_playback_state');
  Future<void> setLastPlaybackStateJson(String json) =>
      _prefs.setString('last_playback_state', json);
  Future<void> clearLastPlaybackState() => _prefs.remove('last_playback_state');

  // -- notification enabled --
  bool getNotificationEnabled() =>
      _prefs.getBool('notification_enabled') ?? true;
  Future<void> setNotificationEnabled(bool v) =>
      _prefs.setBool('notification_enabled', v);

  // -- music source --
  String getMusicSource() => _prefs.getString('music_source') ?? '网易云';
  Future<void> setMusicSource(String v) => _prefs.setString('music_source', v);

  // -- source quality per platform (stored as JSON) --
  Map<String, String> getSourceQuality() {
    final raw = _prefs.getString('source_quality');
    if (raw == null)
      return {
        '网易云': '320k',
        'QQ音乐': '320k',
        '酷狗': '320k',
        '酷我': '320k',
        '咪咕': '320k',
      };
    try {
      return Map<String, String>.fromEntries(
        raw.split('|').map((e) {
          final parts = e.split('=');
          return MapEntry(parts[0], parts[1]);
        }),
      );
    } catch (_) {
      return {
        '网易云': '320k',
        'QQ音乐': '320k',
        '酷狗': '320k',
        '酷我': '320k',
        '咪咕': '320k',
      };
    }
  }

  Future<void> setSourceQuality(Map<String, String> v) => _prefs.setString(
    'source_quality',
    v.entries.map((e) => '${e.key}=${e.value}').join('|'),
  );

  String getGlobalQuality() => _prefs.getString('global_quality') ?? '320k';
  Future<void> setGlobalQuality(String v) =>
      _prefs.setString('global_quality', v);

  // -- cache size (display string, actual calculation is real-time) --
  String getCacheSize() => _prefs.getString('cache_size') ?? '128 MB';
  Future<void> setCacheSize(String v) => _prefs.setString('cache_size', v);

  // -- filename template --
  String getFilenameTemplate() =>
      _prefs.getString('filename_template') ?? '%t - %s';
  Future<void> setFilenameTemplate(String v) =>
      _prefs.setString('filename_template', v);

  // -- tag write --
  bool getTagWriteBasicInfo() => _prefs.getBool('tag_write_basic_info') ?? true;
  Future<void> setTagWriteBasicInfo(bool v) =>
      _prefs.setBool('tag_write_basic_info', v);
  bool getTagWriteCover() => _prefs.getBool('tag_write_cover') ?? true;
  Future<void> setTagWriteCover(bool v) => _prefs.setBool('tag_write_cover', v);
  bool getTagWriteLyrics() => _prefs.getBool('tag_write_lyrics') ?? true;
  Future<void> setTagWriteLyrics(bool v) =>
      _prefs.setBool('tag_write_lyrics', v);

  // -- audio effect --
  bool getAudioEffectEnabled() =>
      _prefs.getBool('audio_effect_enabled') ?? false;
  Future<void> setAudioEffectEnabled(bool v) =>
      _prefs.setBool('audio_effect_enabled', v);

  // -- audio visualizer --
  bool getAudioVisualizerEnabled() =>
      _prefs.getBool('audio_visualizer_enabled') ?? false;
  Future<void> setAudioVisualizerEnabled(bool v) =>
      _prefs.setBool('audio_visualizer_enabled', v);

  // -- appearance performance --
  bool getAppearanceJumpLyric() =>
      _prefs.getBool('appearance_jump_lyric') ?? true;
  Future<void> setAppearanceJumpLyric(bool v) =>
      _prefs.setBool('appearance_jump_lyric', v);
  bool getAppearanceBgAnimation() =>
      _prefs.getBool('appearance_bg_animation') ?? true;
  Future<void> setAppearanceBgAnimation(bool v) =>
      _prefs.setBool('appearance_bg_animation', v);

  // -- lyric settings --
  double getLyricFontSize() => _prefs.getDouble('lyric_font_size') ?? 1.0;
  Future<void> setLyricFontSize(double v) =>
      _prefs.setDouble('lyric_font_size', v);
  bool getLyricShowTranslation() =>
      _prefs.getBool('lyric_show_translation') ?? true;
  Future<void> setLyricShowTranslation(bool v) =>
      _prefs.setBool('lyric_show_translation', v);
  bool getLyricShowRoman() => _prefs.getBool('lyric_show_roman') ?? true;
  Future<void> setLyricShowRoman(bool v) =>
      _prefs.setBool('lyric_show_roman', v);
  bool getLyricEnableBlur() => _prefs.getBool('lyric_enable_blur') ?? true;
  Future<void> setLyricEnableBlur(bool v) =>
      _prefs.setBool('lyric_enable_blur', v);
  bool getLyricEnableScale() => _prefs.getBool('lyric_enable_scale') ?? true;
  Future<void> setLyricEnableScale(bool v) =>
      _prefs.setBool('lyric_enable_scale', v);
  bool getLyricCenterAlign() => _prefs.getBool('lyric_center_align') ?? true;
  Future<void> setLyricCenterAlign(bool v) =>
      _prefs.setBool('lyric_center_align', v);
  bool getAmllCenterAlign() => _prefs.getBool('amll_center_align') ?? false;
  Future<void> setAmllCenterAlign(bool v) =>
      _prefs.setBool('amll_center_align', v);
  bool getLyricImmersiveColor() =>
      _prefs.getBool('lyric_immersive_color') ?? true;
  Future<void> setLyricImmersiveColor(bool v) =>
      _prefs.setBool('lyric_immersive_color', v);

  // -- lyric font settings --
  String getLyricFontFamily() =>
      _prefs.getString('lyric_font_family') ?? 'system';
  Future<void> setLyricFontFamily(String v) =>
      _prefs.setString('lyric_font_family', v);
  double getLyricFontRate() => _prefs.getDouble('lyric_font_rate') ?? 1.0;
  Future<void> setLyricFontRate(double v) =>
      _prefs.setDouble('lyric_font_rate', v);
  int getLyricFontWeight() => _prefs.getInt('lyric_font_weight') ?? 700;
  Future<void> setLyricFontWeight(int v) =>
      _prefs.setInt('lyric_font_weight', v);
  String getLyricFontColor() => _prefs.getString('lyric_font_color') ?? '';
  Future<void> setLyricFontColor(String v) =>
      _prefs.setString('lyric_font_color', v);

  // -- equalizer custom presets (JSON array) --
  String getEqualizerCustomPresets() =>
      _prefs.getString('eq_custom_presets') ?? '[]';
  Future<void> setEqualizerCustomPresets(String v) =>
      _prefs.setString('eq_custom_presets', v);

  // -- tag write extended --
  bool getTagWriteDownloadLyrics() =>
      _prefs.getBool('tag_write_download_lyrics') ?? false;
  Future<void> setTagWriteDownloadLyrics(bool v) =>
      _prefs.setBool('tag_write_download_lyrics', v);
  String getTagWriteLyricFormat() =>
      _prefs.getString('tag_write_lyric_format') ?? 'word-by-word';
  Future<void> setTagWriteLyricFormat(String v) =>
      _prefs.setString('tag_write_lyric_format', v);

  // -- auto cache music --
  bool getAutoCacheMusic() => _prefs.getBool('auto_cache_music') ?? true;
  Future<void> setAutoCacheMusic(bool v) =>
      _prefs.setBool('auto_cache_music', v);

  // -- route preload --
  bool getRoutePreloadEnabled() =>
      _prefs.getBool('route_preload_enabled') ?? true;
  Future<void> setRoutePreloadEnabled(bool v) =>
      _prefs.setBool('route_preload_enabled', v);

  // -- auto update --
  bool getAutoUpdate() => _prefs.getBool('auto_update') ?? true;
  Future<void> setAutoUpdate(bool v) => _prefs.setBool('auto_update', v);

  // -- close to tray --
  bool getCloseToTray() => _prefs.getBool('close_to_tray') ?? true;
  Future<void> setCloseToTray(bool v) => _prefs.setBool('close_to_tray', v);

  // -- app language (界面语言, 参考 Mio-Music 的 AppLocale 设置) --
  String getAppLocale() => _prefs.getString('app_locale') ?? 'zh-CN';
  Future<void> setAppLocale(String v) => _prefs.setString('app_locale', v);

  // -- lyric language mode ('follow' 跟随界面 | 'zh-CN' | 'zh-TW') --
  String getLyricLocaleMode() => _prefs.getString('lyric_locale_mode') ?? 'follow';
  Future<void> setLyricLocaleMode(String v) =>
      _prefs.setString('lyric_locale_mode', v);

  // -- full screen background mode --
  String getFullScreenBgMode() =>
      _prefs.getString('full_screen_bg_mode') ?? 'theme';
  Future<void> setFullScreenBgMode(String v) =>
      _prefs.setString('full_screen_bg_mode', v);

  // -- cache directory --
  Future<String> getCacheDir() async {
    final persisted = _prefs.getString('cache_dir');
    if (persisted != null && persisted.isNotEmpty) return persisted;
    final temp = await getTemporaryDirectory();
    return temp.path;
  }

  Future<void> setCacheDir(String v) => _prefs.setString('cache_dir', v);

  // -- directory size calculation --
  Future<String> getDirectorySize(String path) async {
    try {
      final dir = Directory(path);
      if (!dir.existsSync()) return '0 B';
      int total = 0;
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) total += await entity.length();
      }
      return _formatBytes(total);
    } catch (_) {
      return '0 B';
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(i == 0 ? 0 : 1)} ${suffixes[i]}';
  }

  // -- cache clearing (non-persistent action) --
  Future<int> clearCache() async {
    final tempDir = await getTemporaryDirectory();
    final cacheDir = await getApplicationCacheDirectory();
    int total = 0;

    if (tempDir.existsSync()) {
      final files = tempDir.listSync(recursive: true);
      for (final f in files) {
        if (f is File) {
          total += await f.length();
          await f.delete();
        }
      }
    }
    if (cacheDir.existsSync()) {
      final files = cacheDir.listSync(recursive: true);
      for (final f in files) {
        if (f is File) {
          total += await f.length();
          await f.delete();
        }
      }
    }
    return total;
  }
}
