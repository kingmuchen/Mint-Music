import 'package:flutter/material.dart';

/// Device type classification based on screen size.
enum DeviceType { phone, tablet, desktop }

/// Layout mode for different screen orientations and sizes.
enum LayoutMode {
  /// Single column layout (phone portrait, small tablet)
  singleColumn,

  /// Two column layout (tablet landscape, large tablet portrait)
  twoColumn,

  /// Three column layout (wide desktop screens)
  threeColumn,
}

/// Responsive layout utility that provides adaptive sizing and layout decisions
/// based on screen dimensions. Inspired by Mio-Music's responsive sidebar + content pattern.
class ResponsiveLayout {
  ResponsiveLayout._();

  // ── Breakpoint thresholds ──────────────────────────────────────────
  static const double phoneMaxWidth = 600;
  static const double tabletMaxWidth = 900;
  static const double desktopMaxWidth = 1200;

  static const double sidebarWidth = 220.0;
  static const double sidebarCollapsedWidth = 72.0;
  static const double miniPlayerHeight = 64.0;
  static const double bottomNavHeight = 60.0;

  // ── Device classification ──────────────────────────────────────────

  /// Returns the current device type based on shortest screen dimension.
  static DeviceType getDeviceType(BuildContext context) {
    final width = MediaQuery.sizeOf(context).shortestSide;
    if (width < phoneMaxWidth) return DeviceType.phone;
    if (width < tabletMaxWidth) return DeviceType.tablet;
    return DeviceType.desktop;
  }

  /// Whether the current screen is considered a tablet or larger.
  static bool isTablet(BuildContext context) {
    return MediaQuery.sizeOf(context).shortestSide >= phoneMaxWidth;
  }

  /// Whether the device is in landscape orientation.
  static bool isLandscape(BuildContext context) {
    return MediaQuery.orientationOf(context) == Orientation.landscape;
  }

  /// Whether the device is a tablet in landscape mode (primary target for sidebar).
  static bool isTabletLandscape(BuildContext context) {
    return isTablet(context) && isLandscape(context);
  }

  // ── Layout mode ────────────────────────────────────────────────────

  /// Returns the optimal layout mode for the current screen.
  static LayoutMode getLayoutMode(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = size.width;
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;

    if (isLandscape && width >= desktopMaxWidth) return LayoutMode.threeColumn;
    if (isLandscape && width >= tabletMaxWidth) return LayoutMode.twoColumn;
    if (!isLandscape && width >= tabletMaxWidth) return LayoutMode.twoColumn;
    return LayoutMode.singleColumn;
  }

  /// Whether the sidebar should be shown (tablet landscape or wider).
  static bool shouldShowSidebar(BuildContext context) {
    return isTabletLandscape(context);
  }

  // ── Grid configuration ─────────────────────────────────────────────

  /// Returns the optimal cross-axis count for a grid based on available width.
  static int gridCrossAxisCount(
    BuildContext context, {
    double minItemWidth = 160,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final availableWidth = shouldShowSidebar(context) ? width - sidebarWidth : width;

    if (availableWidth >= 1100) return isLandscape ? 5 : 4;
    if (availableWidth >= 800) return isLandscape ? 4 : 3;
    if (availableWidth >= 550) return 3;
    if (availableWidth >= 360) return 2;
    return 2;
  }

  /// Returns responsive grid delegate based on screen size.
  static SliverGridDelegate gridDelegate(
    BuildContext context, {
    double childAspectRatio = 0.82,
    double? mainAxisSpacing,
    double? crossAxisSpacing,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final availableWidth = shouldShowSidebar(context) ? width - sidebarWidth : width;

    final spacing = mainAxisSpacing ?? (isTablet(context) ? 16.0 : 12.0);
    final cSpacing = crossAxisSpacing ?? (isTablet(context) ? 16.0 : 12.0);

    return SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: isLandscape ? 220 : 200,
      mainAxisSpacing: spacing,
      crossAxisSpacing: cSpacing,
      childAspectRatio: childAspectRatio,
    );
  }

  // ── Spacing and sizing helpers ─────────────────────────────────────

  /// Returns responsive padding based on screen size.
  static EdgeInsets pagePadding(BuildContext context) {
    if (isTablet(context)) {
      return const EdgeInsets.symmetric(horizontal: 24, vertical: 16);
    }
    return const EdgeInsets.symmetric(horizontal: 16, vertical: 12);
  }

  /// Returns responsive horizontal padding.
  static double horizontalPadding(BuildContext context) {
    if (isTablet(context)) return 24;
    return 16;
  }

  /// Returns responsive font size scale factor.
  static double fontScale(BuildContext context) {
    if (isTablet(context)) return 1.05;
    return 1.0;
  }

  /// Returns a responsive album art size.
  static double albumArtSize(BuildContext context) {
    if (isTabletLandscape(context)) return 380;
    if (isTablet(context)) return 300;
    return 280;
  }

  /// Returns a responsive mini album art size.
  static double miniAlbumArtSize(BuildContext context) {
    if (isTablet(context)) return 52;
    return 44;
  }

  /// Returns responsive icon size.
  static double iconSize(BuildContext context, {double base = 24}) {
    if (isTablet(context)) return base * 1.1;
    return base;
  }

  /// Returns the width constraint for content when sidebar is visible.
  static double contentMaxWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (shouldShowSidebar(context)) {
      return width - sidebarWidth;
    }
    return width;
  }
}

/// A responsive wrapper widget that provides layout information through InheritedWidget.
class ResponsiveWrapper extends InheritedWidget {
  final DeviceType deviceType;
  final LayoutMode layoutMode;
  final bool isLandscape;
  final bool isTablet;

  const ResponsiveWrapper({
    super.key,
    required this.deviceType,
    required this.layoutMode,
    required this.isLandscape,
    required this.isTablet,
    required super.child,
  });

  static ResponsiveWrapper of(BuildContext context) {
    final wrapper = context.dependOnInheritedWidgetOfExactType<ResponsiveWrapper>();
    assert(wrapper != null, 'No ResponsiveWrapper found in context');
    return wrapper!;
  }

  @override
  bool updateShouldNotify(ResponsiveWrapper oldWidget) {
    return deviceType != oldWidget.deviceType ||
        layoutMode != oldWidget.layoutMode ||
        isLandscape != oldWidget.isLandscape ||
        isTablet != oldWidget.isTablet;
  }
}
