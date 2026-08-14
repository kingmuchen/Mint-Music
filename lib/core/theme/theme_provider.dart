import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme_colors.dart';

export 'theme_colors.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);

final themePrimaryColorProvider = StateProvider<String>((ref) => '#1DB954');

Color _parseThemeColor(String hex) {
  try {
    final code = hex.replaceFirst('#', '');
    return Color(int.parse('FF$code', radix: 16));
  } catch (_) {
    return const Color(0xFF1DB954);
  }
}

final _cachedLightColors = <String, ThemeColors>{};
final _cachedDarkColors = <String, ThemeColors>{};

final themeColorsProvider = Provider<ThemeColors>((ref) {
  final themeMode = ref.watch(themeModeProvider);
  final primaryHex = ref.watch(themePrimaryColorProvider);
  final isLight = themeMode == ThemeMode.light;
  final cache = isLight ? _cachedLightColors : _cachedDarkColors;
  return cache.putIfAbsent(primaryHex, () {
    final primaryColor = _parseThemeColor(primaryHex);
    return isLight
        ? ThemeColors.lightWithPrimary(primaryColor)
        : ThemeColors.darkWithPrimary(primaryColor);
  });
});
