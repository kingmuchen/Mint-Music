import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

class AppTheme {
  AppTheme._();

  static ThemeData? _lightCache;
  static ThemeData? _darkCache;

  static ThemeData get light => _lightCache ??= ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: AppColors.primary,
          onPrimary: AppColors.textOnPrimary,
          secondary: AppColors.accent,
          onSecondary: AppColors.textOnPrimary,
          surface: Color(0xFFFFFFFF),
          onSurface: Color(0xFF1A1A1A),
          error: AppColors.error,
          onError: AppColors.textOnPrimary,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Color(0xFFF5F5F5),
          foregroundColor: Color(0xFF1A1A1A),
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: const Color(0xFFFFFFFF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFFF5F5F5),
          selectedItemColor: AppColors.primary,
          unselectedItemColor: Color(0xFF999999),
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          unselectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
        ),
        navigationBarTheme: NavigationBarThemeData(
          elevation: 0,
          backgroundColor: const Color(0xFFF5F5F5),
          indicatorColor: AppColors.primary.withValues(alpha: 0.12),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textOnPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.md,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFFFFFFF),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          hintStyle: const TextStyle(color: Color(0xFF999999)),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFE5E5E5),
          thickness: 1,
          space: 1,
        ),
        sliderTheme: const SliderThemeData(
          activeTrackColor: AppColors.primary,
          inactiveTrackColor: Color(0xFFE0E0E0),
          thumbColor: AppColors.primary,
          overlayColor: Color(0x1F1DB954),
          trackHeight: 3,
        ),
        iconTheme: const IconThemeData(
          color: Color(0xFF666666),
          size: 24,
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFFF0F0F0),
          selectedColor: AppColors.primary.withValues(alpha: 0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          side: BorderSide.none,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: AppColors.primary,
          linearTrackColor: Color(0xFFE0E0E0),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.textOnPrimary;
            }
            return const Color(0xFF999999);
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primary;
            }
            return const Color(0xFFE0E0E0);
          }),
        ),
        textTheme: TextTheme(
          displayLarge: AppTypography.displayLarge.copyWith(color: const Color(0xFF1A1A1A)),
          displayMedium: AppTypography.displayMedium.copyWith(color: const Color(0xFF1A1A1A)),
          headlineLarge: AppTypography.headlineLarge.copyWith(color: const Color(0xFF1A1A1A)),
          headlineMedium: AppTypography.headlineMedium.copyWith(color: const Color(0xFF1A1A1A)),
          titleLarge: AppTypography.titleLarge.copyWith(color: const Color(0xFF1A1A1A)),
          titleMedium: AppTypography.titleMedium.copyWith(color: const Color(0xFF1A1A1A)),
          titleSmall: AppTypography.titleSmall.copyWith(color: const Color(0xFF666666)),
          bodyLarge: AppTypography.bodyLarge.copyWith(color: const Color(0xFF1A1A1A)),
          bodyMedium: AppTypography.bodyMedium.copyWith(color: const Color(0xFF666666)),
          bodySmall: AppTypography.bodySmall.copyWith(color: const Color(0xFF666666)),
          labelLarge: AppTypography.labelLarge.copyWith(color: const Color(0xFF1A1A1A)),
          labelMedium: AppTypography.labelMedium.copyWith(color: const Color(0xFF666666)),
          labelSmall: AppTypography.labelSmall.copyWith(color: const Color(0xFF666666)),
        ),
      );

  static ThemeData get dark => _darkCache ??= ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primaryLight,
          onPrimary: AppColors.textOnPrimary,
          secondary: AppColors.accentLight,
          onSecondary: AppColors.textOnPrimary,
          surface: AppColors.darkSurface,
          onSurface: AppColors.darkTextPrimary,
          error: AppColors.error,
          onError: AppColors.textOnPrimary,
        ),
        scaffoldBackgroundColor: AppColors.darkBackground,
        appBarTheme: AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: AppColors.darkBackground.withValues(alpha: 0.95),
          foregroundColor: AppColors.darkTextPrimary,
          centerTitle: true,
          titleTextStyle: AppTypography.headlineMedium.copyWith(
            color: AppColors.darkTextPrimary,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: AppColors.darkSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.darkSurface,
          selectedItemColor: AppColors.primaryLight,
          unselectedItemColor: AppColors.darkTextSecondary,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          unselectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
        ),
        navigationBarTheme: NavigationBarThemeData(
          elevation: 0,
          backgroundColor: AppColors.darkSurface,
          indicatorColor: AppColors.primaryLight.withValues(alpha: 0.15),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: AppColors.primaryLight,
            foregroundColor: AppColors.textOnPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.md,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primaryLight,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.darkSurface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            borderSide: const BorderSide(color: AppColors.primaryLight, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          hintStyle: const TextStyle(color: AppColors.darkTextSecondary),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: AppColors.primaryLight,
          foregroundColor: AppColors.textOnPrimary,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.darkSurface,
          selectedColor: AppColors.primaryLight.withValues(alpha: 0.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          side: BorderSide.none,
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.darkDivider,
          thickness: 1,
          space: 1,
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: AppColors.primaryLight,
          inactiveTrackColor: AppColors.darkDivider,
          thumbColor: AppColors.primaryLight,
          overlayColor: AppColors.primaryLight.withValues(alpha: 0.15),
          trackHeight: 3,
        ),
        textTheme: TextTheme(
          displayLarge: AppTypography.displayLarge.copyWith(color: AppColors.darkTextPrimary),
          displayMedium: AppTypography.displayMedium.copyWith(color: AppColors.darkTextPrimary),
          headlineLarge: AppTypography.headlineLarge.copyWith(color: AppColors.darkTextPrimary),
          headlineMedium: AppTypography.headlineMedium.copyWith(color: AppColors.darkTextPrimary),
          titleLarge: AppTypography.titleLarge.copyWith(color: AppColors.darkTextPrimary),
          titleMedium: AppTypography.titleMedium.copyWith(color: AppColors.darkTextPrimary),
          titleSmall: AppTypography.titleSmall.copyWith(color: AppColors.darkTextSecondary),
          bodyLarge: AppTypography.bodyLarge.copyWith(color: AppColors.darkTextPrimary),
          bodyMedium: AppTypography.bodyMedium.copyWith(color: AppColors.darkTextSecondary),
          bodySmall: AppTypography.bodySmall.copyWith(color: AppColors.darkTextSecondary),
          labelLarge: AppTypography.labelLarge.copyWith(color: AppColors.darkTextPrimary),
          labelMedium: AppTypography.labelMedium.copyWith(color: AppColors.darkTextSecondary),
          labelSmall: AppTypography.labelSmall.copyWith(color: AppColors.darkTextSecondary),
        ),
        iconTheme: const IconThemeData(
          color: AppColors.darkTextSecondary,
          size: 24,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: AppColors.primaryLight,
          linearTrackColor: AppColors.darkDivider,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.textOnPrimary;
            }
            return AppColors.darkTextSecondary;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primaryLight;
            }
            return AppColors.darkDivider;
          }),
        ),
      );
}
