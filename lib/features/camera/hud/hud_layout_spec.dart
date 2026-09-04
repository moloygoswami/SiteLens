/// Canonical Evidence HUD Layout Specification.
///
/// STRICT ARCHITECTURAL INVARIANTS:
/// 1. PURE DART ONLY: Zero imports from `package:flutter/...` and zero imports from `dart:ui`.
/// 2. EXPLICIT COORDINATE-SPACE SEMANTICS:
///    - Dimensionless ratios and fractions (normalized: 0.0 .. 1.0).
///    - Reference Design Plane units (logical dp on 390x844 reference screen).
///    - Scaling to native target pixels ($s = \min(W/\text{refW}, H/\text{refH})$) is
///      performed by the Canvas renderer, while Flutter renderer applies $s = 1.0$.
library;

import 'dart:math' as math;

class HudLayoutSpec {
  // --- Coordinate Space: Reference Design Plane (390 x 844 Logical dp) ---
  static const double refCanvasWidth = 390.0;
  static const double refCanvasHeight = 844.0;

  static const double refMarginH = 14.0;
  static const double refMarginB = 16.0;

  static const double refCardGap = 4.0;
  static const double refCardPaddingH = 8.0;
  static const double refCardPaddingV = 6.0;
  static const double refLineSpacing = 3.0;

  static const double refCardCornerRadius = 8.0;
  static const double refMapTileRadius = 4.0;
  static const double refBadgeCornerRadius = 3.0;

  static const double refBadgePaddingH = 5.0;
  static const double refBadgePaddingV = 1.5;
  static const double refBadgeDotSize = 4.5;
  static const double refBadgeGap = 3.5;
  static const double refHeadlineBadgeGap = 6.0;

  static const double refMinHeadlineWidth = 50.0;
  static const double refMinMetadataWidth = 60.0;
  static const double refInitialMapEstimateMin = 64.0;
  static const double refInitialMapEstimateMax = 140.0;
  static const double refInitialMapEstimateFraction = 0.28;

  /// Maximum reference width constraint for landscape presentation (520.0 logical dp).
  /// Sourced from ResponsiveBreakpoints.maxFormWidth for readable single-column forms.
  static const double refMaxLandscapeWidth = 520.0;

  /// Computes the uniform scale factor mapping reference design units (390 dp)
  /// into native evidence photograph pixels based on the photograph's short dimension.
  static double computeNativeScaleFactor(int imageWidth, int imageHeight) {
    final shortEdge = math.min(imageWidth, imageHeight).toDouble();
    if (shortEdge <= 0) return 1.0;
    return shortEdge / refCanvasWidth;
  }

  // --- Coordinate Space: Dimensionless Ratios & Normalized Bounds ---
  /// Landscape-rectangular minimap aspect ratio (width / height = 1.24:1).
  static const double minimapAspectRatio = 1.24;

  /// Maximum allowed width fraction for the minimap card (42% of available width).
  static const double maxMinimapWidthFraction = 0.42;

  /// Dynamic font scaling minimum clamp.
  static const double fontScaleMin = 0.82;

  /// Dynamic font scaling maximum clamp.
  static const double fontScaleMax = 1.0;

  /// Reference width for dynamic font scaling (250 logical dp).
  static const double fontScaleReferenceWidth = 250.0;

  // --- Typography: Reference Font Sizes (sp / pt) ---
  static const double headlineFontSize = 10.5;
  static const double bodyFontSize = 8.5;
  static const double smallFontSize = 8.0;
  static const double badgeFontSize = 8.0;

  static const double lineHeight = 1.15;
  static const double badgeLineHeight = 1.0;

  /// Computes the dynamic font scale factor based on available metadata content width.
  static double calculateFontScale(double contentWidth, [double scaleFactor = 1.0]) {
    final base = fontScaleReferenceWidth * scaleFactor;
    return (contentWidth / base).clamp(fontScaleMin, fontScaleMax);
  }
}

/// Pure 32-bit ARGB color tokens for the Evidence HUD.
///
/// Pure Dart (no `dart:ui` or `package:flutter` dependencies).
class HudColorTokens {
  static const int primary = 0xFFF27A1A; // Safety Orange
  static const int primaryLight = 0xFFFF9E43;

  static const int metadataCardBg = 0xDE0D110F; // Dark Slate 87%
  static const int metadataCardBgHighContrast = 0xFF0D110F; // Dark Slate 100%
  static const int minimapCardBg = 0xBA0D110F; // Dark Slate 73%

  static const int cardBorderLocked = 0x8CF27A1A; // Primary with ~140 alpha
  static const int cardBorderUnlocked = 0x32FFFFFF; // White with 50 alpha

  static const int statusGreen = 0xFF16A34A;
  static const int statusGreenBg = 0x4616A34A;
  static const int statusGreenLight = 0xFFDCFCE7;

  static const int statusRed = 0xFFDC2626;
  static const int statusRedBg = 0x46DC2626;
  static const int statusRedLight = 0xFFFEE2E2;

  static const int statusAmber = 0xFFD97706;
  static const int statusAmberBg = 0x46D97706;
  static const int statusAmberLight = 0xFFFEF3C7;

  static const int textPrimary = 0xFFFFFFFF;
  static const int textTimestamp = 0xE6FFFFFF; // White with 230 alpha
  static const int textAddress = 0xD7FFFFFF; // White with 215 alpha
  static const int textTechnical = 0xB4FFFFFF; // White with 180 alpha
}
