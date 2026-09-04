import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../../../core/utils/gps_utils.dart';
import '../hud/hud_data.dart';
import '../hud/hud_formatter.dart';
import '../hud/hud_layout_spec.dart';
import '../models/evidence_metadata_snapshot.dart';

/// Canonical color palette and styling constants for the Evidence HUD.
///
/// Mirrors `AppColors` from `lib/app/theme.dart` and `EvidenceMetadataHudCard`.
class HudColors {
  static const primary = Color(0xFFF27A1A); // Safety Orange
  static const primaryLight = Color(0xFFFF9E43);

  static const metadataCardBg = Color(0xDE0D110F); // Dark Slate 87%
  static const minimapCardBg = Color(0xBA0D110F); // Dark Slate 73%
  static final cardBorderLocked = const Color(0xFFF27A1A).withAlpha(140);
  static final cardBorderUnlocked = Colors.white.withAlpha(50);

  static const statusGreen = Color(0xFF16A34A);
  static const statusGreenBg = Color(0x4616A34A);
  static const statusGreenLight = Color(0xFFDCFCE7);

  static const statusRed = Color(0xFFDC2626);
  static const statusRedBg = Color(0x46DC2626);
  static const statusRedLight = Color(0xFFFEE2E2);

  static const statusAmber = Color(0xFFD97706);
  static const statusAmberBg = Color(0x46D97706);
  static const statusAmberLight = Color(0xFFFEF3C7);

  static const textPrimary = Colors.white;
  static final textTimestamp = Colors.white.withAlpha(230);
  static final textAddress = Colors.white.withAlpha(215);
  static final textTechnical = Colors.white.withAlpha(180);
}

/// Canonical 2D bounding rectangle in pixel coordinates.
class HudRect {
  final double x1;
  final double y1;
  final double x2;
  final double y2;

  const HudRect({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  double get width => math.max(0.0, x2 - x1);
  double get height => math.max(0.0, y2 - y1);

  @override
  String toString() =>
      'HudRect(${x1.toStringAsFixed(1)}, ${y1.toStringAsFixed(1)}, ${x2.toStringAsFixed(1)}, ${y2.toStringAsFixed(1)}; ${width.toStringAsFixed(1)}x${height.toStringAsFixed(1)})';
}

/// Reusable geometry model capturing all calculated layout dimensions.
class HudGeometryModel {
  final int targetImageWidth;
  final int targetImageHeight;
  final double scaleFactor;

  final double outerMarginLeft;
  final double outerMarginRight;
  final double outerMarginBottom;
  final double cardPaddingH;
  final double cardPaddingV;
  final double cardGap;
  final double lineSpacing;

  final double cardCornerRadius;
  final double mapTileRadius;
  final double badgeCornerRadius;

  final HudRect minimapBounds;
  final HudRect metadataBounds;
  final HudRect badgeBounds;

  final double finalCardHeight;
  final bool hasMapTile;

  const HudGeometryModel({
    required this.targetImageWidth,
    required this.targetImageHeight,
    required this.scaleFactor,
    required this.outerMarginLeft,
    required this.outerMarginRight,
    required this.outerMarginBottom,
    required this.cardPaddingH,
    required this.cardPaddingV,
    required this.cardGap,
    required this.lineSpacing,
    required this.cardCornerRadius,
    required this.mapTileRadius,
    required this.badgeCornerRadius,
    required this.minimapBounds,
    required this.metadataBounds,
    required this.badgeBounds,
    required this.finalCardHeight,
    required this.hasMapTile,
  });

  /// Validates that Minimap and Metadata cards have strictly equal height.
  bool get hasEqualCardHeights {
    if (!hasMapTile) return true;
    return (minimapBounds.height - metadataBounds.height).abs() < 0.01 &&
        (metadataBounds.height - finalCardHeight).abs() < 0.01;
  }
}

/// Pure geometric layout engine computing exact bounds and equal card heights.
class HudGeometryCalculator {
  static const double referenceWidth = HudLayoutSpec.refCanvasWidth;
  static const double referenceHeight = HudLayoutSpec.refCanvasHeight;

  static const double refMarginH = HudLayoutSpec.refMarginH;
  static const double refMarginB = HudLayoutSpec.refMarginB;
  static const double refCardGap = HudLayoutSpec.refCardGap;
  static const double refCardPaddingH = HudLayoutSpec.refCardPaddingH;
  static const double refCardPaddingV = HudLayoutSpec.refCardPaddingV;
  static const double refLineSpacing = HudLayoutSpec.refLineSpacing;

  static const double refCardCornerRadius = HudLayoutSpec.refCardCornerRadius;
  static const double refMapTileRadius = HudLayoutSpec.refMapTileRadius;
  static const double refBadgeCornerRadius = HudLayoutSpec.refBadgeCornerRadius;

  static const double minimapAspectRatio = HudLayoutSpec.minimapAspectRatio;

  /// Computes the initial constrained metadata content width for Pass 1 text measuring.
  static double computeInitialMetadataContentWidth({
    required int imageWidth,
    required int imageHeight,
    required bool hasMapTile,
  }) {
    final scaleFactor =
        HudLayoutSpec.computeNativeScaleFactor(imageWidth, imageHeight);
    final outerMarginLeft = refMarginH * scaleFactor;
    final outerMarginRight = refMarginH * scaleFactor;
    final cardPaddingH = refCardPaddingH * scaleFactor;
    final cardGap = refCardGap * scaleFactor;

    final isLandscape = imageWidth > imageHeight;
    final availableWidth = isLandscape
        ? math.min(
            imageWidth - outerMarginLeft - outerMarginRight,
            (HudLayoutSpec.refMaxLandscapeWidth - (refMarginH * 2)) * scaleFactor,
          )
        : (imageWidth - outerMarginLeft - outerMarginRight);

    if (!hasMapTile) {
      return math.max(
        HudLayoutSpec.refMinMetadataWidth * scaleFactor,
        availableWidth - (2 * cardPaddingH),
      );
    }

    final initialMinMapWidth = (availableWidth *
            HudLayoutSpec.refInitialMapEstimateFraction)
        .clamp(
      HudLayoutSpec.refInitialMapEstimateMin * scaleFactor,
      HudLayoutSpec.refInitialMapEstimateMax * scaleFactor,
    );
    final initialMetaWidth = math.max(
      HudLayoutSpec.refMinMetadataWidth * scaleFactor,
      availableWidth - initialMinMapWidth - cardGap,
    );
    return initialMetaWidth - (2 * cardPaddingH);
  }

  static HudGeometryModel calculate({
    required int imageWidth,
    required int imageHeight,
    required double measuredTextHeight,
    required double badgeWidth,
    required double badgeHeight,
    required bool hasMapTile,
  }) {
    final scaleFactor =
        HudLayoutSpec.computeNativeScaleFactor(imageWidth, imageHeight);

    final outerMarginLeft = refMarginH * scaleFactor;
    final outerMarginRight = refMarginH * scaleFactor;
    final outerMarginBottom = refMarginB * scaleFactor;
    final cardPaddingH = refCardPaddingH * scaleFactor;
    final cardPaddingV = refCardPaddingV * scaleFactor;
    final cardGap = refCardGap * scaleFactor;
    final lineSpacing = refLineSpacing * scaleFactor;

    final cardCornerRadius = refCardCornerRadius * scaleFactor;
    final mapTileRadius = refMapTileRadius * scaleFactor;
    final badgeCornerRadius = refBadgeCornerRadius * scaleFactor;

    final isLandscape = imageWidth > imageHeight;
    final availableWidth = isLandscape
        ? math.min(
            imageWidth - outerMarginLeft - outerMarginRight,
            (HudLayoutSpec.refMaxLandscapeWidth - (refMarginH * 2)) * scaleFactor,
          )
        : (imageWidth - outerMarginLeft - outerMarginRight);

    // Minimum height required to contain all text without any clipping
    final minMetadataHeight = measuredTextHeight + (2 * cardPaddingV);

    double minimapWidth = 0.0;
    double finalCardHeight = minMetadataHeight;

    if (hasMapTile) {
      // In Live HUD contract: minimap height strictly equals metadata height,
      // and minimap width = cardHeight * minimapAspectRatio (1.24:1).
      minimapWidth = finalCardHeight * minimapAspectRatio;

      // Ensure minimap does not exceed 42% of available width on narrow views
      final maxMapWidth =
          availableWidth * HudLayoutSpec.maxMinimapWidthFraction;
      if (minimapWidth > maxMapWidth) {
        minimapWidth = maxMapWidth;
      }
    }

    final metadataWidth =
        hasMapTile ? (availableWidth - minimapWidth - cardGap) : availableWidth;

    final cardTopY = imageHeight - outerMarginBottom - finalCardHeight;
    final cardBottomY = imageHeight - outerMarginBottom;

    HudRect minimapBounds = const HudRect(x1: 0, y1: 0, x2: 0, y2: 0);
    double metadataLeftX = outerMarginLeft;

    if (hasMapTile) {
      minimapBounds = HudRect(
        x1: outerMarginLeft,
        y1: cardTopY,
        x2: outerMarginLeft + minimapWidth,
        y2: cardBottomY,
      );
      metadataLeftX = outerMarginLeft + minimapWidth + cardGap;
    }

    final metadataBounds = HudRect(
      x1: metadataLeftX,
      y1: cardTopY,
      x2: metadataLeftX + metadataWidth,
      y2: cardBottomY,
    );

    final badgeBounds = HudRect(
      x1: metadataBounds.x2 - cardPaddingH - badgeWidth,
      y1: cardTopY + cardPaddingV,
      x2: metadataBounds.x2 - cardPaddingH,
      y2: cardTopY + cardPaddingV + badgeHeight,
    );

    return HudGeometryModel(
      targetImageWidth: imageWidth,
      targetImageHeight: imageHeight,
      scaleFactor: scaleFactor,
      outerMarginLeft: outerMarginLeft,
      outerMarginRight: outerMarginRight,
      outerMarginBottom: outerMarginBottom,
      cardPaddingH: cardPaddingH,
      cardPaddingV: cardPaddingV,
      cardGap: cardGap,
      lineSpacing: lineSpacing,
      cardCornerRadius: cardCornerRadius,
      mapTileRadius: mapTileRadius,
      badgeCornerRadius: badgeCornerRadius,
      minimapBounds: minimapBounds,
      metadataBounds: metadataBounds,
      badgeBounds: badgeBounds,
      finalCardHeight: finalCardHeight,
      hasMapTile: hasMapTile,
    );
  }
}

/// Native Flutter vector rendering engine for the Evidence HUD.
///
/// Uses `dart:ui.Canvas` and `TextPainter` to achieve true vector typography,
/// anti-aliasing, font weights, tabular figures, and Unicode support (`°`, `•`, `−`).
class WatermarkDrawer {
  /// Renders the complete vector HUD from canonical [HudData] at native evidence resolution and returns compressed PNG bytes.
  static Future<Uint8List> renderVectorHudPngFromData({
    required int width,
    required int height,
    required HudData hudData,
    Uint8List? mapTileBytes,
  }) async {
    final uiImage = await renderVectorHudImageFromData(
      width: width,
      height: height,
      hudData: hudData,
      mapTileBytes: mapTileBytes,
    );

    final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Renders the complete vector HUD at native evidence resolution and returns compressed PNG bytes.
  static Future<Uint8List> renderVectorHudPng({
    required int width,
    required int height,
    required EvidenceMetadataSnapshot snapshot,
    required String originalSha256,
    Uint8List? mapTileBytes,
    bool isGpsLocked = true,
    bool showAddress = true,
    bool showMapTile = true,
    double? headingDegrees,
  }) {
    final hudData = HudFormatter.fromSnapshot(
      snapshot: snapshot,
      originalSha256: originalSha256,
      isGpsLocked: isGpsLocked,
      showAddress: showAddress,
      showMinimap: showMapTile,
      headingDegrees: headingDegrees ?? snapshot.headingDegrees,
    );
    return renderVectorHudPngFromData(
      width: width,
      height: height,
      hudData: hudData,
      mapTileBytes: mapTileBytes,
    );
  }

  /// Renders the complete vector HUD from canonical [HudData] at native evidence resolution as a `ui.Image`.
  static Future<ui.Image> renderVectorHudImageFromData({
    required int width,
    required int height,
    required HudData hudData,
    Uint8List? mapTileBytes,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );

    // Decode map tile if provided
    ui.Image? decodedTile;
    if (mapTileBytes != null && mapTileBytes.isNotEmpty && hudData.showMinimap) {
      try {
        final codec = await ui.instantiateImageCodec(mapTileBytes);
        final frame = await codec.getNextFrame();
        decodedTile = frame.image;
      } catch (_) {
        decodedTile = null;
      }
    }

    drawVectorHudDataToCanvas(
      canvas: canvas,
      targetWidth: width,
      targetHeight: height,
      hudData: hudData,
      decodedMapTile: decodedTile,
    );

    final picture = recorder.endRecording();
    return picture.toImage(width, height);
  }

  /// Renders the complete vector HUD at native evidence resolution as a `ui.Image`.
  static Future<ui.Image> renderVectorHudImage({
    required int width,
    required int height,
    required EvidenceMetadataSnapshot snapshot,
    required String originalSha256,
    Uint8List? mapTileBytes,
    bool isGpsLocked = true,
    bool showAddress = true,
    bool showMapTile = true,
    double? headingDegrees,
  }) {
    final hudData = HudFormatter.fromSnapshot(
      snapshot: snapshot,
      originalSha256: originalSha256,
      isGpsLocked: isGpsLocked,
      showAddress: showAddress,
      showMinimap: showMapTile,
      headingDegrees: headingDegrees ?? snapshot.headingDegrees,
    );
    return renderVectorHudImageFromData(
      width: width,
      height: height,
      hudData: hudData,
      mapTileBytes: mapTileBytes,
    );
  }

  /// Synchronously draws the vector HUD onto any `dart:ui.Canvas`.
  static HudGeometryModel drawVectorHudToCanvas({
    required ui.Canvas canvas,
    required int targetWidth,
    required int targetHeight,
    required EvidenceMetadataSnapshot snapshot,
    required String originalSha256,
    ui.Image? decodedMapTile,
    bool isGpsLocked = true,
    bool showAddress = true,
    bool showMapTile = true,
    double? headingDegrees,
  }) {
    final hudData = HudFormatter.fromSnapshot(
      snapshot: snapshot,
      originalSha256: originalSha256,
      isGpsLocked: isGpsLocked,
      showAddress: showAddress,
      showMinimap: showMapTile,
      headingDegrees: headingDegrees ?? snapshot.headingDegrees,
    );
    return drawVectorHudDataToCanvas(
      canvas: canvas,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      hudData: hudData,
      decodedMapTile: decodedMapTile,
    );
  }

  /// Synchronously draws the vector HUD from canonical [HudData] onto any `dart:ui.Canvas`.
  static HudGeometryModel drawVectorHudDataToCanvas({
    required ui.Canvas canvas,
    required int targetWidth,
    required int targetHeight,
    required HudData hudData,
    ui.Image? decodedMapTile,
  }) {
    // 1. Text from canonical HudData
    final fullHeadline = hudData.fullHeadline;
    final isVerified = hudData.status == HudStatus.verified;
    final isDegraded = hudData.status == HudStatus.degraded;
    final statusColor = isVerified
        ? HudColors.statusGreen
        : (isDegraded ? HudColors.statusRed : HudColors.statusAmber);
    final statusColorLight = isVerified
        ? HudColors.statusGreenLight
        : (isDegraded
            ? HudColors.statusRedLight
            : HudColors.statusAmberLight);
    final statusText = hudData.statusText;

    final utcFormatted = hudData.utcTimestampText;
    final localFormatted = hudData.localTimestampText;
    final timeZoneStr = hudData.timeZoneText;

    final latStr = hudData.latitudeText;
    final lonStr = hudData.longitudeText;
    final altSuffix = hudData.altitudeSuffix ?? '';

    final rawAddress = hudData.addressText;
    final displaySha = hudData.displaySha256;
    final isGpsLocked = hudData.isGpsLocked;
    final showAddress = hudData.showAddress;
    final showMapTile = hudData.showMinimap;
    final headingDegrees = hudData.headingDegrees;

    // 2. Pre-calculate scale factor for typography from native photograph short dimension
    final s = HudLayoutSpec.computeNativeScaleFactor(targetWidth, targetHeight);

    // 3. Configure TextPainters with exact Live HUD typography tokens
    final headlineStyle = TextStyle(
      fontFamily: 'monospace',
      fontFeatures: const [ui.FontFeature.tabularFigures()],
      fontSize: HudLayoutSpec.headlineFontSize * s,
      fontWeight: FontWeight.w700,
      color: Colors.white,
      letterSpacing: 0.1 * s,
      height: HudLayoutSpec.lineHeight,
    );

    final badgeStyle = TextStyle(
      fontFamily: 'monospace',
      fontFeatures: const [ui.FontFeature.tabularFigures()],
      fontSize: HudLayoutSpec.badgeFontSize * s,
      fontWeight: FontWeight.w900,
      color: statusColorLight,
      letterSpacing: 0.2 * s,
      height: HudLayoutSpec.badgeLineHeight,
    );

    final addressBoldStyle = TextStyle(
      fontFamily: 'monospace',
      fontFeatures: const [ui.FontFeature.tabularFigures()],
      fontSize: HudLayoutSpec.bodyFontSize * s,
      fontWeight: FontWeight.w700,
      color: Colors.white,
      letterSpacing: 0.05 * s,
      height: HudLayoutSpec.lineHeight,
    );

    final addressStyle = TextStyle(
      fontFamily: 'monospace',
      fontFeatures: const [ui.FontFeature.tabularFigures()],
      fontSize: HudLayoutSpec.bodyFontSize * s,
      fontWeight: FontWeight.w400,
      color: Colors.white.withAlpha(215),
      letterSpacing: 0.05 * s,
      height: HudLayoutSpec.lineHeight,
    );

    final timestampBoldStyle = TextStyle(
      fontFamily: 'monospace',
      fontFeatures: const [ui.FontFeature.tabularFigures()],
      fontSize: HudLayoutSpec.bodyFontSize * s,
      fontWeight: FontWeight.w700,
      color: Colors.white,
      letterSpacing: 0.05 * s,
      height: HudLayoutSpec.lineHeight,
    );

    final timestampStyle = TextStyle(
      fontFamily: 'monospace',
      fontFeatures: const [ui.FontFeature.tabularFigures()],
      fontSize: HudLayoutSpec.bodyFontSize * s,
      fontWeight: FontWeight.w400,
      color: Colors.white.withAlpha(230),
      letterSpacing: 0.05 * s,
      height: HudLayoutSpec.lineHeight,
    );

    final coordinatesBoldStyle = TextStyle(
      fontFamily: 'monospace',
      fontFeatures: const [ui.FontFeature.tabularFigures()],
      fontSize: HudLayoutSpec.bodyFontSize * s,
      fontWeight: FontWeight.w700,
      color: Colors.white,
      letterSpacing: 0.05 * s,
      height: HudLayoutSpec.lineHeight,
    );

    final coordinatesStyle = TextStyle(
      fontFamily: 'monospace',
      fontFeatures: const [ui.FontFeature.tabularFigures()],
      fontSize: HudLayoutSpec.bodyFontSize * s,
      fontWeight: FontWeight.w400,
      color: Colors.white.withAlpha(230),
      letterSpacing: 0.05 * s,
      height: HudLayoutSpec.lineHeight,
    );

    final shaBoldStyle = TextStyle(
      fontFamily: 'monospace',
      fontFeatures: const [ui.FontFeature.tabularFigures()],
      fontSize: HudLayoutSpec.smallFontSize * s,
      fontWeight: FontWeight.w700,
      color: Colors.white,
      letterSpacing: 0.05 * s,
      height: HudLayoutSpec.lineHeight,
    );

    final shaStyle = TextStyle(
      fontFamily: 'monospace',
      fontFeatures: const [ui.FontFeature.tabularFigures()],
      fontSize: HudLayoutSpec.smallFontSize * s,
      fontWeight: FontWeight.w400,
      color: Colors.white.withAlpha(180),
      letterSpacing: 0.05 * s,
      height: HudLayoutSpec.lineHeight,
    );

    // Badge measurement
    final badgeTextPainter = TextPainter(
      text: TextSpan(text: statusText, style: badgeStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    final badgeDotSize = HudLayoutSpec.refBadgeDotSize * s;
    final badgePaddingH = HudLayoutSpec.refBadgePaddingH * s;
    final badgePaddingV = HudLayoutSpec.refBadgePaddingV * s;
    final badgeGap = HudLayoutSpec.refBadgeGap * s;
    final badgeWidth =
        (badgePaddingH * 2) + badgeDotSize + badgeGap + badgeTextPainter.width;
    final badgeHeight =
        math.max(badgeDotSize, badgeTextPainter.height) + (badgePaddingV * 2);

    // Pass 1: Initial estimate to compute constrained wrapping width
    final initialMetaContentWidth =
        HudGeometryCalculator.computeInitialMetadataContentWidth(
      imageWidth: targetWidth,
      imageHeight: targetHeight,
      hasMapTile: showMapTile,
    );
    var fontScale =
        HudLayoutSpec.calculateFontScale(initialMetaContentWidth, s);

    var effectiveHeadlineStyle =
        headlineStyle.copyWith(fontSize: HudLayoutSpec.headlineFontSize * s * fontScale);
    var effectiveAddressBoldStyle =
        addressBoldStyle.copyWith(fontSize: HudLayoutSpec.bodyFontSize * s * fontScale);
    var effectiveAddressStyle =
        addressStyle.copyWith(fontSize: HudLayoutSpec.bodyFontSize * s * fontScale);
    var effectiveTimestampBoldStyle =
        timestampBoldStyle.copyWith(fontSize: HudLayoutSpec.bodyFontSize * s * fontScale);
    var effectiveTimestampStyle =
        timestampStyle.copyWith(fontSize: HudLayoutSpec.bodyFontSize * s * fontScale);
    var effectiveCoordinatesBoldStyle =
        coordinatesBoldStyle.copyWith(fontSize: HudLayoutSpec.bodyFontSize * s * fontScale);
    var effectiveCoordinatesStyle =
        coordinatesStyle.copyWith(fontSize: HudLayoutSpec.bodyFontSize * s * fontScale);
    var effectiveShaBoldStyle =
        shaBoldStyle.copyWith(fontSize: HudLayoutSpec.smallFontSize * s * fontScale);
    var effectiveShaStyle =
        shaStyle.copyWith(fontSize: HudLayoutSpec.smallFontSize * s * fontScale);

    final headlineAvailableWidth = initialMetaContentWidth -
        badgeWidth -
        (HudLayoutSpec.refHeadlineBadgeGap * s);

    // Layout all text tiers with exact wrapping
    final headlinePainter = TextPainter(
      text: TextSpan(text: fullHeadline, style: effectiveHeadlineStyle),
      maxLines: 1,
      ellipsis: '...',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(HudLayoutSpec.refMinHeadlineWidth * s, headlineAvailableWidth));

    TextPainter? addressPainter;
    if (showAddress) {
      addressPainter = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(text: 'ADDR: ', style: effectiveAddressBoldStyle),
            TextSpan(
              text: rawAddress.isNotEmpty ? rawAddress : 'UNKNOWN LOCATION',
              style: effectiveAddressStyle,
            ),
          ],
        ),
        maxLines: 2,
        ellipsis: '...',
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: initialMetaContentWidth);
    }

    final timestampPainter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(text: 'UTC: ', style: effectiveTimestampBoldStyle),
          TextSpan(text: '$utcFormatted UTC • ', style: effectiveTimestampStyle),
          TextSpan(text: 'Local: ', style: effectiveTimestampBoldStyle),
          TextSpan(
            text: '$localFormatted ($timeZoneStr)',
            style: effectiveTimestampStyle,
          ),
        ],
      ),
      maxLines: 2,
      ellipsis: '...',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: initialMetaContentWidth);

    final coordinatesPainter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(text: 'Lat ', style: effectiveCoordinatesBoldStyle),
          TextSpan(text: '$latStr  ', style: effectiveCoordinatesStyle),
          TextSpan(text: 'Long ', style: effectiveCoordinatesBoldStyle),
          TextSpan(text: '$lonStr$altSuffix', style: effectiveCoordinatesStyle),
        ],
      ),
      maxLines: 2,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: initialMetaContentWidth);

    final shaPainter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(text: 'SITE: ', style: effectiveShaBoldStyle),
          TextSpan(
            text: '${hudData.siteCodeText} • ',
            style: effectiveShaStyle,
          ),
          if (displaySha != null) ...[
            TextSpan(
              text: 'SHA: ',
              style: effectiveShaBoldStyle.copyWith(color: HudColors.primaryLight),
            ),
            TextSpan(
              text: displaySha,
              style: effectiveShaStyle.copyWith(color: HudColors.primaryLight),
            ),
          ] else
            TextSpan(
              text: 'Integrity hash: Pending until saved',
              style: effectiveShaStyle,
            ),
        ],
      ),
      maxLines: 1,
      ellipsis: '...',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: initialMetaContentWidth);

    final lineSpacing = HudLayoutSpec.refLineSpacing * s;
    double totalTextHeight = headlinePainter.height;
    if (addressPainter != null) {
      totalTextHeight += lineSpacing + addressPainter.height;
    }
    totalTextHeight += lineSpacing +
        timestampPainter.height +
        lineSpacing +
        coordinatesPainter.height +
        lineSpacing +
        shaPainter.height;

    // Pass 2: Compute Final Geometry with exact measured text height
    var geom = HudGeometryCalculator.calculate(
      imageWidth: targetWidth,
      imageHeight: targetHeight,
      measuredTextHeight: totalTextHeight,
      badgeWidth: badgeWidth,
      badgeHeight: badgeHeight,
      hasMapTile: showMapTile,
    );

    // If final metadata width is different from Pass 1 width, re-layout to exact final width
    final finalMetaContentWidth =
        geom.metadataBounds.width - (geom.cardPaddingH * 2);
    if ((finalMetaContentWidth - initialMetaContentWidth).abs() > 0.5) {
      fontScale =
          HudLayoutSpec.calculateFontScale(finalMetaContentWidth, s);

      effectiveHeadlineStyle =
          headlineStyle.copyWith(fontSize: HudLayoutSpec.headlineFontSize * s * fontScale);
      effectiveAddressBoldStyle =
          addressBoldStyle.copyWith(fontSize: HudLayoutSpec.bodyFontSize * s * fontScale);
      effectiveAddressStyle =
          addressStyle.copyWith(fontSize: HudLayoutSpec.bodyFontSize * s * fontScale);
      effectiveTimestampBoldStyle =
          timestampBoldStyle.copyWith(fontSize: HudLayoutSpec.bodyFontSize * s * fontScale);
      effectiveTimestampStyle =
          timestampStyle.copyWith(fontSize: HudLayoutSpec.bodyFontSize * s * fontScale);
      effectiveCoordinatesBoldStyle =
          coordinatesBoldStyle.copyWith(fontSize: HudLayoutSpec.bodyFontSize * s * fontScale);
      effectiveCoordinatesStyle =
          coordinatesStyle.copyWith(fontSize: HudLayoutSpec.bodyFontSize * s * fontScale);
      effectiveShaBoldStyle =
          shaBoldStyle.copyWith(fontSize: HudLayoutSpec.smallFontSize * s * fontScale);
      effectiveShaStyle =
          shaStyle.copyWith(fontSize: HudLayoutSpec.smallFontSize * s * fontScale);

      final finalHeadlineWidth = finalMetaContentWidth -
          badgeWidth -
          (HudLayoutSpec.refHeadlineBadgeGap * s);
      headlinePainter.text =
          TextSpan(text: fullHeadline, style: effectiveHeadlineStyle);
      headlinePainter.layout(maxWidth: math.max(HudLayoutSpec.refMinHeadlineWidth * s, finalHeadlineWidth));

      if (addressPainter != null) {
        addressPainter.text = TextSpan(
          children: [
            TextSpan(text: 'ADDR: ', style: effectiveAddressBoldStyle),
            TextSpan(
              text: rawAddress.isNotEmpty ? rawAddress : 'UNKNOWN LOCATION',
              style: effectiveAddressStyle,
            ),
          ],
        );
        addressPainter.layout(maxWidth: finalMetaContentWidth);
      }

      timestampPainter.text = TextSpan(
        children: [
          TextSpan(text: 'UTC: ', style: effectiveTimestampBoldStyle),
          TextSpan(text: '$utcFormatted UTC • ', style: effectiveTimestampStyle),
          TextSpan(text: 'Local: ', style: effectiveTimestampBoldStyle),
          TextSpan(
            text: '$localFormatted ($timeZoneStr)',
            style: effectiveTimestampStyle,
          ),
        ],
      );
      timestampPainter.layout(maxWidth: finalMetaContentWidth);

      coordinatesPainter.text = TextSpan(
        children: [
          TextSpan(text: 'Lat ', style: effectiveCoordinatesBoldStyle),
          TextSpan(text: '$latStr  ', style: effectiveCoordinatesStyle),
          TextSpan(text: 'Long ', style: effectiveCoordinatesBoldStyle),
          TextSpan(text: '$lonStr$altSuffix', style: effectiveCoordinatesStyle),
        ],
      );
      coordinatesPainter.layout(maxWidth: finalMetaContentWidth);

      shaPainter.text = TextSpan(
        children: [
          TextSpan(text: 'SITE: ', style: effectiveShaBoldStyle),
          TextSpan(
            text: '${hudData.siteCodeText} • ',
            style: effectiveShaStyle,
          ),
          if (displaySha != null) ...[
            TextSpan(
              text: 'SHA: ',
              style: effectiveShaBoldStyle.copyWith(color: HudColors.primaryLight),
            ),
            TextSpan(
              text: displaySha,
              style: effectiveShaStyle.copyWith(color: HudColors.primaryLight),
            ),
          ] else
            TextSpan(
              text: 'Integrity hash: Pending until saved',
              style: effectiveShaStyle,
            ),
        ],
      );
      shaPainter.layout(maxWidth: finalMetaContentWidth);

      double recomputedTextHeight = headlinePainter.height;
      if (addressPainter != null) {
        recomputedTextHeight += lineSpacing + addressPainter.height;
      }
      recomputedTextHeight += lineSpacing +
          timestampPainter.height +
          lineSpacing +
          coordinatesPainter.height +
          lineSpacing +
          shaPainter.height;

      geom = HudGeometryCalculator.calculate(
        imageWidth: targetWidth,
        imageHeight: targetHeight,
        measuredTextHeight: recomputedTextHeight,
        badgeWidth: badgeWidth,
        badgeHeight: badgeHeight,
        hasMapTile: showMapTile,
      );
    }

    final strokeWidth = math.max(1.0, 1.0 * s);
    final borderPaint = Paint()
      ..color = isGpsLocked
          ? HudColors.cardBorderLocked
          : HudColors.cardBorderUnlocked
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    // 5. Draw Minimap Card (if enabled)
    if (showMapTile && geom.minimapBounds.width > 0) {
      final mapRect = ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(
          geom.minimapBounds.x1,
          geom.minimapBounds.y1,
          geom.minimapBounds.width,
          geom.minimapBounds.height,
        ),
        ui.Radius.circular(geom.cardCornerRadius),
      );

      // Card Drop Shadow
      canvas.drawRRect(
        mapRect.shift(Offset(0, 2.0 * s)),
        Paint()
          ..color = const Color(0xAA000000)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4.0 * s),
      );

      // Card Background
      canvas.drawRRect(
        mapRect,
        Paint()
          ..color = HudColors.minimapCardBg
          ..style = PaintingStyle.fill,
      );

      // Map Tile with Inner Clip
      final innerMapRect = ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(
          geom.minimapBounds.x1 + (2.0 * s),
          geom.minimapBounds.y1 + (2.0 * s),
          geom.minimapBounds.width - (4.0 * s),
          geom.minimapBounds.height - (4.0 * s),
        ),
        ui.Radius.circular(geom.mapTileRadius),
      );

      canvas.save();
      canvas.clipRRect(innerMapRect);

      final centerX = geom.minimapBounds.x1 + (geom.minimapBounds.width / 2);
      final centerY = geom.minimapBounds.y1 + (geom.minimapBounds.height / 2);

      if (decodedMapTile != null) {
        // Center crop map tile to fill minimap card
        final srcW = decodedMapTile.width.toDouble();
        final srcH = decodedMapTile.height.toDouble();
        final dstW = geom.minimapBounds.width;
        final dstH = geom.minimapBounds.height;

        final scale = math.max(dstW / srcW, dstH / srcH);
        final renderW = srcW * scale;
        final renderH = srcH * scale;
        final dstX = centerX - (renderW / 2);
        final dstY = centerY - (renderH / 2);

        canvas.drawImageRect(
          decodedMapTile,
          ui.Rect.fromLTWH(0, 0, srcW, srcH),
          ui.Rect.fromLTWH(dstX, dstY, renderW, renderH),
          Paint(),
        );
      } else {
        // When no canonical map representation was captured at shutter time,
        // fill the map slot with the canonical background color.
        // Synthetic vector reticles (fabricated roads/grids) MUST NOT be used as evidence content.
        canvas.drawColor(const Color(0xFF131714), ui.BlendMode.srcOver);
      }

      // Radar Scan Circle
      if (isGpsLocked) {
        final radarRadius =
            math.min(geom.minimapBounds.width, geom.minimapBounds.height) *
                0.30;
        canvas.drawCircle(
          ui.Offset(centerX, centerY),
          radarRadius,
          Paint()
            ..color = const Color(0x20F27A1A)
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          ui.Offset(centerX, centerY),
          radarRadius,
          Paint()
            ..color = const Color(0xFFF27A1A).withAlpha(90)
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.2, 1.2 * s),
        );
      }

      // Heading Cone (rendered strictly when GPS is locked AND compass heading is established)
      if (isGpsLocked && headingDegrees != null) {
        final conePaint = Paint()
          ..color = const Color(0x444285F4)
          ..style = PaintingStyle.fill;

        canvas.save();
        final rad = (headingDegrees * math.pi / 180.0);
        canvas.translate(centerX, centerY);
        canvas.rotate(rad);
        canvas.translate(-centerX, -centerY);

        final conePath = Path()
          ..moveTo(centerX, centerY - (2.0 * s))
          ..lineTo(centerX - geom.minimapBounds.width * 0.35,
              centerY - geom.minimapBounds.height * 0.45)
          ..arcToPoint(
            Offset(centerX + geom.minimapBounds.width * 0.35,
                centerY - geom.minimapBounds.height * 0.45),
            radius: Radius.circular(geom.minimapBounds.width * 0.5),
          )
          ..close();

        canvas.drawPath(conePath, conePaint);
        canvas.restore();
      }

      // Canonical Location Pin (reproducing Camera Capture's Icons.location_on_rounded)
      // 1. Base contact shadow oval under pin tip
      final contactShadow = ui.RRect.fromRectAndRadius(
        ui.Rect.fromCenter(
          center: Offset(centerX, centerY + (9.5 * s)),
          width: 6.0 * s,
          height: 3.0 * s,
        ),
        ui.Radius.circular(1.5 * s),
      );
      canvas.drawRRect(
        contactShadow,
        Paint()
          ..color = Colors.black.withAlpha(140)
          ..style = PaintingStyle.fill,
      );

      // 2. Teardrop pin geometry matching Icons.location_on_rounded (20dp icon height)
      final hx = centerX;
      final hy = centerY - (2.5 * s);
      final R = 6.0 * s;
      final tx = centerX;
      final ty = centerY + (8.5 * s);
      final xLeft = hx - (5.03 * s);
      final yLeft = hy + (3.27 * s);
      final xRight = hx + (5.03 * s);
      final yRight = hy + (3.27 * s);

      final pinPath = Path()
        ..moveTo(tx, ty)
        ..lineTo(xLeft, yLeft)
        ..arcToPoint(
          Offset(xRight, yRight),
          radius: Radius.circular(R),
          largeArc: true,
          clockwise: true,
        )
        ..lineTo(tx, ty)
        ..close();

      // High-contrast drop shadow behind pin icon
      final shadowPath = pinPath.shift(Offset(0, 1.5 * s));
      canvas.drawPath(
        shadowPath,
        Paint()
          ..color = Colors.black87
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.5 * s),
      );

      // Teardrop pin body (Red 0xFFEA4335 when locked, Amber when unlocked)
      final pinColor =
          isGpsLocked ? const Color(0xFFEA4335) : HudColors.statusAmber;
      canvas.drawPath(
        pinPath,
        Paint()
          ..color = pinColor
          ..style = PaintingStyle.fill,
      );

      // Inner circular cutout in pin head
      canvas.drawCircle(
        Offset(hx, hy),
        2.3 * s,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill,
      );

      // Google Attribution Watermark at bottom-left of map (rendered strictly when actual map tiles are present)
      if (decodedMapTile != null) {
        final googlePainter = TextPainter(
          text: TextSpan(
            text: 'Google',
            style: TextStyle(
              fontFamily: 'sans-serif',
              fontSize: 7.5 * s,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.2 * s,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        final gBgPadH = 2.5 * s;
        final gBgPadV = 0.5 * s;
        final gX = geom.minimapBounds.x1 + (4.0 * s);
        final gY = geom.minimapBounds.y2 - (3.0 * s) - googlePainter.height;

        canvas.drawRRect(
          ui.RRect.fromRectAndRadius(
            ui.Rect.fromLTWH(
              gX - gBgPadH,
              gY - gBgPadV,
              googlePainter.width + (gBgPadH * 2),
              googlePainter.height + (gBgPadV * 2),
            ),
            ui.Radius.circular(2.0 * s),
          ),
          Paint()
            ..color = Colors.black.withAlpha(120)
            ..style = PaintingStyle.fill,
        );
        googlePainter.paint(canvas, ui.Offset(gX, gY));
      }

      canvas.restore();

      // Card Border
      canvas.drawRRect(mapRect, borderPaint);
    }

    // 6. Draw Metadata Card
    final metaRect = ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(
        geom.metadataBounds.x1,
        geom.metadataBounds.y1,
        geom.metadataBounds.width,
        geom.metadataBounds.height,
      ),
      ui.Radius.circular(geom.cardCornerRadius),
    );

    // Card Drop Shadow
    canvas.drawRRect(
      metaRect.shift(Offset(0, 2.0 * s)),
      Paint()
        ..color = const Color(0xAA000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4.0 * s),
    );

    // Card Background
    canvas.drawRRect(
      metaRect,
      Paint()
        ..color = HudColors.metadataCardBg
        ..style = PaintingStyle.fill,
    );

    // Card Border
    canvas.drawRRect(metaRect, borderPaint);

    // 7. Paint Text Tiers & Status Badge inside Metadata Card
    final startX = geom.metadataBounds.x1 + geom.cardPaddingH;
    double currentY = geom.metadataBounds.y1 + geom.cardPaddingV;

    // Line 1: Headline
    headlinePainter.paint(canvas, ui.Offset(startX, currentY));

    // Status Badge (Top-Right of Metadata Card)
    final badgeRRect = ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(
        geom.badgeBounds.x1,
        geom.badgeBounds.y1,
        geom.badgeBounds.width,
        geom.badgeBounds.height,
      ),
      ui.Radius.circular(geom.badgeCornerRadius),
    );

    canvas.drawRRect(
      badgeRRect,
      Paint()
        ..color = statusColor.withAlpha(70)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      badgeRRect,
      Paint()
        ..color = statusColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, 1.0 * s),
    );

    // Badge Dot
    final badgeDotCenter = ui.Offset(
      geom.badgeBounds.x1 + badgePaddingH + (badgeDotSize / 2),
      geom.badgeBounds.y1 + (geom.badgeBounds.height / 2),
    );
    canvas.drawCircle(
      badgeDotCenter,
      badgeDotSize / 2,
      Paint()
        ..color = statusColorLight
        ..style = PaintingStyle.fill,
    );

    // Badge Text
    final badgeTextOffset = ui.Offset(
      geom.badgeBounds.x1 + badgePaddingH + badgeDotSize + badgeGap,
      geom.badgeBounds.y1 + badgePaddingV,
    );
    badgeTextPainter.paint(canvas, badgeTextOffset);

    currentY += headlinePainter.height + lineSpacing;

    // Line 2: Address (ADDR: in bold)
    if (addressPainter != null) {
      addressPainter.paint(canvas, ui.Offset(startX, currentY));
      currentY += addressPainter.height + lineSpacing;
    }

    // Line 3: Timestamp (UTC: and Local: in bold)
    timestampPainter.paint(canvas, ui.Offset(startX, currentY));
    currentY += timestampPainter.height + lineSpacing;

    // Line 4: Coordinates & Alt (Lat and Long in bold)
    coordinatesPainter.paint(canvas, ui.Offset(startX, currentY));
    currentY += coordinatesPainter.height + lineSpacing;

    // Line 5: Site & SHA (SITE: and SHA: in bold)
    shaPainter.paint(canvas, ui.Offset(startX, currentY));

    return geom;
  }

  /// Headless / test helper that renders vector HUD and composites onto `image`.
  static Future<img.Image> drawWatermark({
    required img.Image image,
    required EvidenceMetadataSnapshot snapshot,
    required String originalSha256,
    Uint8List? mapTileBytes,
    bool isGpsLocked = true,
    bool showAddress = true,
    bool showMapTile = true,
    double? headingDegrees,
  }) async {
    final hudPng = await renderVectorHudPng(
      width: image.width,
      height: image.height,
      snapshot: snapshot,
      originalSha256: originalSha256,
      mapTileBytes: mapTileBytes,
      isGpsLocked: isGpsLocked,
      showAddress: showAddress,
      showMapTile: showMapTile,
      headingDegrees: headingDegrees,
    );

    final hudImg = img.decodePng(hudPng);
    if (hudImg != null) {
      img.compositeImage(image, hudImg);
    }
    return image;
  }

  /// Computes geometry and typography layout for testing and layout inspection.
  static (HudGeometryModel, HudTypographyInfo) computeHudLayout({
    required int imageWidth,
    required int imageHeight,
    required EvidenceMetadataSnapshot snapshot,
    required String originalSha256,
    bool isGpsLocked = true,
    bool showAddress = true,
    bool showMapTile = true,
    double? headingDegrees,
  }) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, imageWidth.toDouble(), imageHeight.toDouble()),
    );

    final geom = drawVectorHudToCanvas(
      canvas: canvas,
      targetWidth: imageWidth,
      targetHeight: imageHeight,
      snapshot: snapshot,
      originalSha256: originalSha256,
      isGpsLocked: isGpsLocked,
      showAddress: showAddress,
      showMapTile: showMapTile,
      headingDegrees: headingDegrees,
    );

    recorder.endRecording();

    final isVerified =
        isGpsLocked && !snapshot.lowAccuracy && originalSha256.isNotEmpty;
    final statusText = isVerified
        ? 'VERIFIED'
        : (snapshot.lowAccuracy ? 'DEGRADED' : 'PENDING');

    final headline = GPSUtils.formatInspectionHeadline(
      siteName: snapshot.siteName,
      siteCode: snapshot.siteCode,
      resolvedAddress: snapshot.resolvedAddress,
    );
    final flagSuffix = GPSUtils.countryFlagForAddress(snapshot.resolvedAddress);
    final fullHeadline = '$headline$flagSuffix';

    final altDisplay = snapshot.altitudeMeters != null
        ? '${snapshot.altitudeMeters! >= 0 ? "+" : ""}${snapshot.altitudeMeters!.toStringAsFixed(1)}m'
        : null;

    final coordinatesLine = GPSUtils.formatInspectionCoordinates(
      snapshot.latitude,
      snapshot.longitude,
      altitudeDisplay: altDisplay,
    );

    final formattedDateTime =
        GPSUtils.formatInspectionTimestamp(snapshot.capturedAtUtc);
    final rawAddress = snapshot.resolvedAddress.trim();
    final addressLine =
        rawAddress.isNotEmpty ? 'ADDR: $rawAddress' : 'ADDR: UNKNOWN LOCATION';
    final displaySha = originalSha256.isNotEmpty
        ? (originalSha256.length > 18
            ? '${originalSha256.substring(0, 8)}...${originalSha256.substring(originalSha256.length - 8)}'
            : originalSha256)
        : null;
    final shaLine = displaySha != null
        ? 'SITE: ${snapshot.siteCode.toUpperCase()} • SHA: $displaySha'
        : 'SITE: ${snapshot.siteCode.toUpperCase()} • Integrity hash: Pending until saved';

    final typo = HudTypographyInfo(
      badgeText: statusText,
      headlineText: fullHeadline,
      coordinatesText: coordinatesLine,
      timestampText: formattedDateTime,
      addressText: addressLine,
      siteShaText: shaLine,
      addressLines: [addressLine, if (addressLine.length > 50) addressLine],
      siteShaLines: [shaLine, if (originalSha256.isNotEmpty) originalSha256],
      headlineLines: [fullHeadline],
    );

    return (geom, typo);
  }
}

/// Metadata typography inspection data container.
class HudTypographyInfo {
  final String badgeText;
  final String headlineText;
  final String coordinatesText;
  final String timestampText;
  final String addressText;
  final String siteShaText;
  final List<String> addressLines;
  final List<String> siteShaLines;
  final List<String> headlineLines;

  const HudTypographyInfo({
    required this.badgeText,
    required this.headlineText,
    required this.coordinatesText,
    required this.timestampText,
    required this.addressText,
    required this.siteShaText,
    this.addressLines = const [],
    this.siteShaLines = const [],
    this.headlineLines = const [],
  });
}
