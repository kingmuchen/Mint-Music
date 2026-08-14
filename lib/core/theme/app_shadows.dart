import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppShadows {
  AppShadows._();

  static BoxShadow get card => BoxShadow(
        color: AppColors.glassShadow,
        blurRadius: 12,
        offset: const Offset(0, 2),
      );

  static BoxShadow get miniPlayer => BoxShadow(
        color: const Color(0x1A000000),
        blurRadius: 16,
        offset: const Offset(0, -2),
      );

  static BoxShadow get button => BoxShadow(
        color: AppColors.primary.withValues(alpha: 0.3),
        blurRadius: 8,
        offset: const Offset(0, 2),
      );

  static BoxShadow get floating => BoxShadow(
        color: const Color(0x29000000),
        blurRadius: 24,
        offset: const Offset(0, 8),
      );

  static BoxShadow get cover => BoxShadow(
        color: AppColors.coverShadow,
        blurRadius: 40,
        offset: const Offset(0, 16),
      );
}
