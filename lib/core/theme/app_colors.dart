import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF1DB954);
  static const Color primaryLight = Color(0xFF1ED760);
  static const Color primaryDark = Color(0xFF158C3F);

  static const Color accent = Color(0xFF1DB954);
  static const Color accentLight = Color(0xFF1ED760);

  static const Color background = Color(0xFF121212);
  static const Color surface = Color(0xFF282828);
  static const Color surfaceVariant = Color(0xFF333333);

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB3B3B3);
  static const Color textHint = Color(0xFF727272);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  static const Color error = Color(0xFFE91429);
  static const Color success = Color(0xFF1DB954);
  static const Color warning = Color(0xFFF59E0B);

  static const Color divider = Color(0xFF333333);
  static const Color disabled = Color(0xFF404040);

  static const Color miniPlayerBackground = Color(0xFF282828);
  static const Color miniPlayerProgress = Color(0xFF1DB954);

  static const Color coverShadow = Color(0x40000000);

  static const Color darkBackground = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF282828);
  static const Color darkGlassBackground = Color(0xFF282828);
  static const Color darkDivider = Color(0xFF333333);
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFFB3B3B3);

  static const Color glassBackground = Color(0xFF282828);
  static const Color glassBorder = Color(0xFF333333);
  static const Color glassThinBackground = Color(0xFF333333);
  static const Color glassShadow = Color(0x1A000000);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient primaryGradientHorizontal = LinearGradient(
    colors: [primary, primaryLight],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static LinearGradient backgroundGradient = const LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF121212),
      Color(0xFF121212),
    ],
  );
}
