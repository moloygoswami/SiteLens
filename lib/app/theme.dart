import 'package:flutter/material.dart';

class AppColors {
  // Brand & Accents (Safety Orange)
  static const Color primary = Color(0xFFF27A1A); // High-visibility Field Orange
  static const Color primaryDark = Color(0xFFC85E07);
  static const Color primaryLight = Color(0xFFFF9E43);
  static const Color primaryContainer = Color(0xFFFFECE0);

  // Surfaces & Backgrounds (Crisp Industrial Neutrals)
  static const Color background = Color(0xFFF8FAFC); // Slate 50
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceContainer = Color(0xFFF1F5F9); // Slate 100
  static const Color surfaceContainerHigh = Color(0xFFE2E8F0); // Slate 200
  static const Color surfaceTranslucentDark = Color(0xEE0F172A); // Slate 900 93%

  // Typography & Content (WCAG AAA/AA Compliance)
  static const Color textPrimary = Color(0xFF0F172A); // Slate 900 (High contrast)
  static const Color textSecondary = Color(0xFF475569); // Slate 600
  static const Color textMuted = Color(0xFF64748B); // Slate 500
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // Precision Hairline Borders (No fuzzy drop shadows)
  static const Color border = Color(0xFFCBD5E1); // Slate 300
  static const Color borderLight = Color(0xFFE2E8F0); // Slate 200

  // Status & Telemetry Semantics
  static const Color statusGreen = Color(0xFF16A34A); // Green 600 (GPS High / Synced)
  static const Color statusGreenLight = Color(0xFFDCFCE7); // Green 100
  static const Color statusAmber = Color(0xFFD97706); // Amber 600 (GPS Weak / Pending)
  static const Color statusAmberLight = Color(0xFFFEF3C7); // Amber 100
  static const Color statusRed = Color(0xFFDC2626); // Red 600 (GPS Poor / Recording / Error)
  static const Color statusRedLight = Color(0xFFFEE2E2); // Red 100
  static const Color statusBlue = Color(0xFF0284C7); // Sky 600 (Info / Geotag badge)
  static const Color statusBlueLight = Color(0xFFE0F2FE); // Sky 100
}

class AppTypography {
  static const TextStyle displayLarge = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
    height: 1.2,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.3,
    height: 1.25,
  );

  static const TextStyle titleMedium = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  static const TextStyle labelLarge = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.textOnPrimary,
    letterSpacing: 0.1,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );

  static const TextStyle monoData = TextStyle(
    fontFamily: 'monospace',
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    letterSpacing: 0.2,
  );

  static const TextStyle monoDataSmall = TextStyle(
    fontFamily: 'monospace',
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: Colors.white,
    letterSpacing: 0.2,
  );
}

class AppRadii {
  static const double xs = 2.0;
  static const double sm = 4.0;
  static const double md = 8.0;
  static const double lg = 12.0;
  static const double card = 8.0;
  static const double pill = 4.0; // Anti-slop: replaced 9999.0 with tight 4.0px radius
}

class SiteLensTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: AppColors.primary,
        onPrimary: AppColors.textOnPrimary,
        secondary: AppColors.primaryDark,
        onSecondary: Colors.white,
        error: AppColors.statusRed,
        onError: Colors.white,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: AppTypography.titleMedium,
        shape: Border(
          bottom: BorderSide(color: AppColors.borderLight, width: 1),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          elevation: 0,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          textStyle: AppTypography.labelLarge,
        ),
      ),
    );
  }
}
