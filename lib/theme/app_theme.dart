import 'package:flutter/material.dart';

/// The visual language, in one place.
///
/// Stealth dark: deep anthracite rather than pure black, tiles a shade
/// *lighter* than the page so the Bento grid reads without borders or
/// shadows. Strictly monochrome — no accent colour anywhere, which is what
/// makes the interface feel like instrumentation rather than an app.
abstract final class AppColors {
  /// Page background.
  static const surface = Color(0xFF1C1C1E);

  /// Bento tile background — lighter than [surface], never darker.
  static const tile = Color(0xFF2B2B2D);

  /// A tile in its active or highlighted state.
  static const tileActive = Color(0xFF3A3A3C);

  /// Primary text and line-art icons.
  static const ink = Color(0xFFF5F5F7);

  /// Secondary text: labels, units, timestamps.
  static const inkMuted = Color(0xFF8E8E93);

  /// Disabled or placeholder content.
  static const inkFaint = Color(0xFF5A5A5E);

  /// The dot-matrix pattern drawn on the hero tile.
  static const matrix = Color(0xFF343436);
}

abstract final class AppMetrics {
  static const double tileRadius = 14;
  static const double gutter = 10;
  static const EdgeInsets tilePadding = EdgeInsets.all(18);
  static const EdgeInsets pagePadding = EdgeInsets.symmetric(horizontal: 14);
}

abstract final class AppTheme {
  /// Monospace stands in for the dot-matrix numerals of the glasses display.
  /// Swap this for a bundled bitmap font to match the hardware exactly.
  static const String technicalFont = 'monospace';

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      primary: AppColors.ink,
      onPrimary: AppColors.surface,
      secondary: AppColors.inkMuted,
      onSecondary: AppColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.surface,
      canvasColor: AppColors.surface,
      dividerColor: AppColors.tileActive,
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.ink,
          fontSize: 20,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
        ),
      ),

      cardTheme: CardThemeData(
        color: AppColors.tile,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppMetrics.tileRadius),
        ),
      ),

      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.ink,
        textColor: AppColors.ink,
        subtitleTextStyle: TextStyle(color: AppColors.inkMuted, fontSize: 13),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.surface
              : AppColors.inkMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.ink
              : AppColors.tileActive,
        ),
        trackOutlineColor:
            const WidgetStatePropertyAll(Colors.transparent),
      ),

      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.ink,
        inactiveTrackColor: AppColors.tileActive,
        thumbColor: AppColors.ink,
        overlayColor: Color(0x22FFFFFF),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.ink
              : AppColors.inkFaint,
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.tileActive,
          foregroundColor: AppColors.ink,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppMetrics.tileRadius),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),

      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.tileActive,
        contentTextStyle: TextStyle(color: AppColors.ink),
        behavior: SnackBarBehavior.floating,
      ),

      textTheme: const TextTheme(
        // Readouts that imitate the glasses display.
        displayLarge: TextStyle(
          fontFamily: technicalFont,
          fontSize: 44,
          height: 1,
          color: AppColors.ink,
          letterSpacing: 1,
        ),
        titleMedium: TextStyle(
          fontSize: 17,
          color: AppColors.ink,
          fontWeight: FontWeight.w500,
        ),
        bodyMedium: TextStyle(fontSize: 14, color: AppColors.ink),
        bodySmall: TextStyle(fontSize: 12, color: AppColors.inkMuted),
        labelLarge: TextStyle(
          fontFamily: technicalFont,
          fontSize: 15,
          color: AppColors.ink,
        ),
      ),
    );
  }
}
