import 'package:flutter/material.dart';

class ThemeColors {
  final Color primary;
  final Color primaryLight;
  final Color primaryDark;

  final Color accent;
  final Color accentLight;

  final Color background;
  final Color surface;
  final Color surfaceVariant;

  final Color textPrimary;
  final Color textSecondary;
  final Color textHint;
  final Color textOnPrimary;

  final Color error;
  final Color success;
  final Color warning;

  final Color divider;
  final Color disabled;

  final Color miniPlayerBackground;
  final Color miniPlayerProgress;

  final Color coverShadow;
  final Color shadow;

  const ThemeColors({
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    required this.accent,
    required this.accentLight,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.textPrimary,
    required this.textSecondary,
    required this.textHint,
    required this.textOnPrimary,
    required this.error,
    required this.success,
    required this.warning,
    required this.divider,
    required this.disabled,
    required this.miniPlayerBackground,
    required this.miniPlayerProgress,
    required this.coverShadow,
    required this.shadow,
  });

  static ThemeColors lightWithPrimary(Color primary) {
    return ThemeColors(
      primary: primary,
      primaryLight: Color.lerp(primary, const Color(0xFFFFFFFF), 0.2)!,
      primaryDark: Color.lerp(primary, const Color(0xFF000000), 0.2)!,
      accent: primary,
      accentLight: Color.lerp(primary, const Color(0xFFFFFFFF), 0.2)!,
      background: const Color(0xFFF5F5F5),
      surface: const Color(0xFFFFFFFF),
      surfaceVariant: const Color(0xFFF0F0F0),
      textPrimary: const Color(0xFF1A1A1A),
      textSecondary: const Color(0xFF666666),
      textHint: const Color(0xFF999999),
      textOnPrimary: const Color(0xFFFFFFFF),
      error: const Color(0xFFE91429),
      success: primary,
      warning: const Color(0xFFF59E0B),
      divider: const Color(0xFFE5E5E5),
      disabled: const Color(0xFFE0E0E0),
      miniPlayerBackground: const Color(0xFFFFFFFF),
      miniPlayerProgress: primary,
      coverShadow: const Color(0x1A000000),
      shadow: const Color(0x1A000000),
    );
  }

  static ThemeColors darkWithPrimary(Color primary) {
    return ThemeColors(
      primary: primary,
      primaryLight: Color.lerp(primary, const Color(0xFFFFFFFF), 0.2)!,
      primaryDark: Color.lerp(primary, const Color(0xFF000000), 0.2)!,
      accent: primary,
      accentLight: Color.lerp(primary, const Color(0xFFFFFFFF), 0.2)!,
      background: const Color(0xFF121212),
      surface: const Color(0xFF282828),
      surfaceVariant: const Color(0xFF333333),
      textPrimary: const Color(0xFFFFFFFF),
      textSecondary: const Color(0xFFB3B3B3),
      textHint: const Color(0xFF727272),
      textOnPrimary: const Color(0xFFFFFFFF),
      error: const Color(0xFFE91429),
      success: primary,
      warning: const Color(0xFFF59E0B),
      divider: const Color(0xFF333333),
      disabled: const Color(0xFF404040),
      miniPlayerBackground: const Color(0xFF282828),
      miniPlayerProgress: primary,
      coverShadow: const Color(0x40000000),
      shadow: const Color(0x40000000),
    );
  }

  static const dark = ThemeColors(
    primary: Color(0xFF1DB954),
    primaryLight: Color(0xFF1ED760),
    primaryDark: Color(0xFF158C3F),
    accent: Color(0xFF1DB954),
    accentLight: Color(0xFF1ED760),
    background: Color(0xFF121212),
    surface: Color(0xFF282828),
    surfaceVariant: Color(0xFF333333),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFB3B3B3),
    textHint: Color(0xFF727272),
    textOnPrimary: Color(0xFFFFFFFF),
    error: Color(0xFFE91429),
    success: Color(0xFF1DB954),
    warning: Color(0xFFF59E0B),
    divider: Color(0xFF333333),
    disabled: Color(0xFF404040),
    miniPlayerBackground: Color(0xFF282828),
    miniPlayerProgress: Color(0xFF1DB954),
    coverShadow: Color(0x40000000),
    shadow: Color(0x40000000),
  );

  static const light = ThemeColors(
    primary: Color(0xFF1DB954),
    primaryLight: Color(0xFF1ED760),
    primaryDark: Color(0xFF158C3F),
    accent: Color(0xFF1DB954),
    accentLight: Color(0xFF1ED760),
    background: Color(0xFFF5F5F5),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFF0F0F0),
    textPrimary: Color(0xFF1A1A1A),
    textSecondary: Color(0xFF666666),
    textHint: Color(0xFF999999),
    textOnPrimary: Color(0xFFFFFFFF),
    error: Color(0xFFE91429),
    success: Color(0xFF1DB954),
    warning: Color(0xFFF59E0B),
    divider: Color(0xFFE5E5E5),
    disabled: Color(0xFFE0E0E0),
    miniPlayerBackground: Color(0xFFFFFFFF),
    miniPlayerProgress: Color(0xFF1DB954),
    coverShadow: Color(0x1A000000),
    shadow: Color(0x1A000000),
  );
}