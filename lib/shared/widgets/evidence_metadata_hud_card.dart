import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../app/theme.dart';
import '../../features/camera/hud/hud_data.dart';
import '../../features/camera/hud/hud_formatter.dart';
import '../../features/camera/hud/hud_layout_spec.dart';
import '../../features/camera/models/camera_ui_state.dart';
import '../../features/camera/widgets/gps_map_thumbnail.dart';

/// Standalone 1.24:1 landscape-rectangular minimap overlay card.
///
/// Features:
/// - Enforces 1.24:1 aspect ratio.
/// - Translucent dark slate glass background (`#BA0D110F`) and hairline border.
/// - Center-cropped live/static Google Map tile with heading cone, pin, and Google attribution.
class StandaloneMinimapWidget extends StatelessWidget {
  final bool isGpsLocked;
  final double latitude;
  final double longitude;
  final double? headingDegrees;
  final bool isHighContrast;
  final double? size;
  final VoidCallback? onTap;

  const StandaloneMinimapWidget({
    super.key,
    required this.isGpsLocked,
    required this.latitude,
    required this.longitude,
    this.headingDegrees,
    this.isHighContrast = false,
    this.size,
    this.onTap,
  });

  factory StandaloneMinimapWidget.fromData({
    Key? key,
    required HudData hudData,
    double? size,
    VoidCallback? onTap,
  }) {
    return StandaloneMinimapWidget(
      key: key,
      isGpsLocked: hudData.isGpsLocked,
      latitude: hudData.latitude,
      longitude: hudData.longitude,
      headingDegrees: hudData.headingDegrees,
      isHighContrast: hudData.isHighContrast,
      size: size,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: isHighContrast
                ? const Color(0xFF0D110F)
                : const Color(0xBA0D110F),
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(
              color: isGpsLocked
                  ? AppColors.primary.withAlpha(140)
                  : Colors.white.withAlpha(50),
              width: 1.0,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black87,
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: GpsMapThumbnail(
              isLocked: isGpsLocked,
              latitude: latitude,
              longitude: longitude,
              headingDegrees: headingDegrees,
            ),
          ),
        ),
      ),
    );
  }
}

/// Standalone forensic metadata overlay card.
///
/// Strictly renders canonical [HudData] across five distinct information tiers:
/// 1. Site / Location Headline + Verification Status Badge (10.5sp / Bold 700)
/// 2. Complete Street Address (8.5sp / Regular 400 / Natural Wrap)
/// 3. Timestamp (UTC Primary + Local & GMT Offset) (8.5sp / Regular 400)
/// 4. Coordinates & Elevation (8.5sp / Regular 400)
/// 5. Site ID & SHA-256 Hash (8.0sp / Monospace 400 / Truncated Hash)
class StandaloneMetadataWidget extends StatelessWidget {
  final HudData hudData;
  final double? maxWidth;
  final double? height;
  final VoidCallback? onTap;

  const StandaloneMetadataWidget({
    super.key,
    required this.hudData,
    this.maxWidth,
    this.height,
    this.onTap,
  });

  /// Factory constructor for live camera metadata.
  factory StandaloneMetadataWidget.live({
    Key? key,
    required String siteCode,
    String? siteName,
    required GpsUiFixture gps,
    double? maxWidth,
    double? height,
    VoidCallback? onTap,
    bool isHighContrast = false,
  }) {
    final hasValidFix =
        gps.isLocked && gps.latitude != 0.0 && gps.longitude != 0.0;
    final hudData = HudFormatter.fromLive(
      siteCode: siteCode,
      siteName: siteName,
      resolvedAddress: gps.resolvedAddress,
      latitude: gps.latitude,
      longitude: gps.longitude,
      altitudeMeters: gps.altitudeMeters,
      accuracyMeters: gps.accuracyMeters,
      isGpsLocked: hasValidFix,
      isDegraded: gps.isDegraded,
      captureTime: DateTime.now(),
      headingDegrees: gps.headingDegrees,
      isHighContrast: isHighContrast,
    );
    return StandaloneMetadataWidget(
      key: key,
      hudData: hudData,
      maxWidth: maxWidth,
      height: height,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. Unpack canonical text from HudData
    final fullHeadline = hudData.fullHeadline;
    final rawAddress = hudData.addressText;

    final utcFormatted = hudData.utcTimestampText;
    final localFormatted = hudData.localTimestampText;
    final timeZoneStr = hudData.timeZoneText;

    final latStr = hudData.latitudeText;
    final lonStr = hudData.longitudeText;
    final altSuffix = hudData.altitudeSuffix ?? '';

    final isVerified = hudData.status == HudStatus.verified;
    final isDegradedGps = hudData.status == HudStatus.degraded;
    final statusColor = isVerified
        ? AppColors.statusGreen
        : (isDegradedGps ? AppColors.statusRed : AppColors.statusAmber);
    final statusColorLight = isVerified
        ? AppColors.statusGreenLight
        : (isDegradedGps
            ? AppColors.statusRedLight
            : AppColors.statusAmberLight);
    final statusText = hudData.statusText;

    final displaySha = hudData.displaySha256;
    final siteCode = hudData.siteCodeText;
    final isHighContrast = hudData.isHighContrast;
    final isGpsLocked = hudData.isGpsLocked;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Dynamic font scaling: smoothly reduces font size when width is constrained
            final metaW =
                constraints.maxWidth.isFinite ? constraints.maxWidth : 260.0;
            final fontScale = HudLayoutSpec.calculateFontScale(metaW);

            final headlineFontSize = HudLayoutSpec.headlineFontSize * fontScale;
            final bodyFontSize = HudLayoutSpec.bodyFontSize * fontScale;
            final smallFontSize = HudLayoutSpec.smallFontSize * fontScale;
            final badgeFontSize = HudLayoutSpec.badgeFontSize * fontScale;

            return Container(
              padding: const EdgeInsets.symmetric(
                horizontal: HudLayoutSpec.refCardPaddingH,
                vertical: HudLayoutSpec.refCardPaddingV,
              ),
              decoration: BoxDecoration(
                color: isHighContrast
                    ? const Color(0xFF0D110F)
                    : const Color(0xDE0D110F),
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(
                  color: isGpsLocked
                      ? AppColors.primary.withAlpha(140)
                      : Colors.white.withAlpha(50),
                  width: 1.0,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black87,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Line 1: Site / Location (Primary Contextual Heading: Bold 700) + Status Badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          fullHeadline,
                          softWrap: true,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontFeatures: const [
                              ui.FontFeature.tabularFigures()
                            ],
                            fontSize: headlineFontSize,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.1,
                            height: HudLayoutSpec.lineHeight,
                          ),
                        ),
                      ),
                      const SizedBox(width: HudLayoutSpec.refHeadlineBadgeGap),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: HudLayoutSpec.refBadgePaddingH,
                          vertical: HudLayoutSpec.refBadgePaddingV,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withAlpha(70),
                          borderRadius: BorderRadius.circular(
                              HudLayoutSpec.refBadgeCornerRadius),
                          border: Border.all(color: statusColor, width: 1.0),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: HudLayoutSpec.refBadgeDotSize,
                              height: HudLayoutSpec.refBadgeDotSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: statusColorLight,
                              ),
                            ),
                            const SizedBox(width: HudLayoutSpec.refBadgeGap),
                            Text(
                              statusText,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontFeatures: const [
                                  ui.FontFeature.tabularFigures()
                                ],
                                fontSize: badgeFontSize,
                                fontWeight: FontWeight.w900,
                                color: statusColorLight,
                                letterSpacing: 0.2,
                                height: HudLayoutSpec.badgeLineHeight,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: HudLayoutSpec.refLineSpacing),

                  // Line 2: Street Address (ADDR bold + address text)
                  if (hudData.showAddress) ...[
                    Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(
                            text: 'ADDR: ',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          TextSpan(
                            text: rawAddress.isNotEmpty
                                ? rawAddress
                                : 'RESOLVING...',
                            style: TextStyle(
                              fontWeight: FontWeight.w400,
                              fontStyle: hudData.isAddressResolving
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                              color: hudData.isAddressResolving
                                  ? AppColors.statusAmber.withAlpha(230)
                                  : Colors.white.withAlpha(215),
                            ),
                          ),
                        ],
                      ),
                      softWrap: true,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontFeatures: const [ui.FontFeature.tabularFigures()],
                        fontSize: bodyFontSize,
                        letterSpacing: 0.05,
                        height: HudLayoutSpec.lineHeight,
                      ),
                    ),
                    const SizedBox(height: HudLayoutSpec.refLineSpacing),
                  ],

                  // Line 3: Capture Date / Time (UTC and Local bold)
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'UTC: ',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        TextSpan(
                          text: '$utcFormatted UTC • ',
                          style: TextStyle(
                            fontWeight: FontWeight.w400,
                            color: Colors.white.withAlpha(230),
                          ),
                        ),
                        const TextSpan(
                          text: 'Local: ',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        TextSpan(
                          text: '$localFormatted ($timeZoneStr)',
                          style: TextStyle(
                            fontWeight: FontWeight.w400,
                            color: Colors.white.withAlpha(230),
                          ),
                        ),
                      ],
                    ),
                    softWrap: true,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontFeatures: const [ui.FontFeature.tabularFigures()],
                      fontSize: bodyFontSize,
                      letterSpacing: 0.05,
                      height: HudLayoutSpec.lineHeight,
                    ),
                  ),

                  const SizedBox(height: HudLayoutSpec.refLineSpacing),

                  // Line 4: Coordinates & Elevation (Lat and Long bold)
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'Lat ',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        TextSpan(
                          text: '$latStr  ',
                          style: TextStyle(
                            fontWeight: FontWeight.w400,
                            color: Colors.white.withAlpha(230),
                          ),
                        ),
                        const TextSpan(
                          text: 'Long ',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        TextSpan(
                          text: '$lonStr$altSuffix',
                          style: TextStyle(
                            fontWeight: FontWeight.w400,
                            color: Colors.white.withAlpha(230),
                          ),
                        ),
                      ],
                    ),
                    softWrap: true,
                    maxLines: 2,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontFeatures: const [ui.FontFeature.tabularFigures()],
                      fontSize: bodyFontSize,
                      letterSpacing: 0.05,
                      height: HudLayoutSpec.lineHeight,
                    ),
                  ),

                  const SizedBox(height: HudLayoutSpec.refLineSpacing),

                  // Line 5: Site ID / SHA (SITE: and SHA: bold / Truncated compact hash)
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'SITE: ',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        TextSpan(
                          text: '${siteCode.toUpperCase()} • ',
                          style: TextStyle(
                            fontWeight: FontWeight.w400,
                            color: Colors.white.withAlpha(180),
                          ),
                        ),
                        if (displaySha != null) ...[
                          const TextSpan(
                            text: 'SHA: ',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryLight,
                            ),
                          ),
                          TextSpan(
                            text: displaySha,
                            style: const TextStyle(
                              fontWeight: FontWeight.w400,
                              color: AppColors.primaryLight,
                            ),
                          ),
                        ] else
                          TextSpan(
                            text: 'Integrity hash: Pending until saved',
                            style: TextStyle(
                              fontWeight: FontWeight.w400,
                              color: Colors.white.withAlpha(180),
                            ),
                          ),
                      ],
                    ),
                    softWrap: true,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontFeatures: const [ui.FontFeature.tabularFigures()],
                      fontSize: smallFontSize,
                      letterSpacing: 0.05,
                      height: HudLayoutSpec.lineHeight,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HudCardParentData extends ContainerBoxParentData<RenderBox> {}

class _HudCardLayout extends MultiChildRenderObjectWidget {
  final double gap;
  final double minimapAspectRatio;

  _HudCardLayout({
    required Widget minimap,
    required Widget metadata,
    this.gap = HudLayoutSpec.refCardGap,
    this.minimapAspectRatio = HudLayoutSpec.minimapAspectRatio,
  }) : super(children: [minimap, metadata]);

  @override
  _RenderHudCard createRenderObject(BuildContext context) {
    return _RenderHudCard(
      gap: gap,
      minimapAspectRatio: minimapAspectRatio,
    );
  }

  @override
  void updateRenderObject(BuildContext context, _RenderHudCard renderObject) {
    renderObject
      ..gap = gap
      ..minimapAspectRatio = minimapAspectRatio;
  }
}

class _RenderHudCard extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HudCardParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HudCardParentData> {
  double gap;
  double minimapAspectRatio;

  _RenderHudCard({
    required this.gap,
    required this.minimapAspectRatio,
  });

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HudCardParentData) {
      child.parentData = _HudCardParentData();
    }
  }

  @override
  void performLayout() {
    final RenderBox? minimap = firstChild;
    final RenderBox? metadata = minimap != null ? childAfter(minimap) : null;

    if (minimap == null || metadata == null) {
      size = constraints.biggest;
      return;
    }

    final double maxW = constraints.maxWidth;
    final double maxMapAllowed = maxW * HudLayoutSpec.maxMinimapWidthFraction;
    final double initialMapEstimate =
        (maxW * HudLayoutSpec.refInitialMapEstimateFraction).clamp(
      HudLayoutSpec.refInitialMapEstimateMin,
      HudLayoutSpec.refInitialMapEstimateMax,
    );
    final double metadataMaxW =
        math.max(80.0, maxW - initialMapEstimate - gap);

    // 1. Layout Metadata child with unconstrained height to measure natural content
    metadata.layout(
      BoxConstraints(
        minWidth: 0,
        maxWidth: metadataMaxW,
        minHeight: 0,
        maxHeight: constraints.maxHeight,
      ),
      parentUsesSize: true,
    );

    // 2. Minimap height strictly matches Metadata height, constrained by aspect ratio and max width
    double cardHeight = metadata.size.height;
    double mapWidth = cardHeight * minimapAspectRatio;
    if (mapWidth > maxMapAllowed) {
      mapWidth = maxMapAllowed;
    }

    // 3. If mapWidth + gap + metadata.size.width > maxW, re-layout metadata with precise remaining width
    final double availableForMeta =
        math.max(HudLayoutSpec.refMinMetadataWidth, maxW - mapWidth - gap);
    if (metadata.size.width > availableForMeta) {
      metadata.layout(
        BoxConstraints(
          minWidth: 0,
          maxWidth: availableForMeta,
          minHeight: 0,
          maxHeight: constraints.maxHeight,
        ),
        parentUsesSize: true,
      );
      // Recompute equal height based on newly wrapped metadata
      cardHeight = metadata.size.height;
      mapWidth = cardHeight * minimapAspectRatio;
      if (mapWidth > maxMapAllowed) {
        mapWidth = maxMapAllowed;
      }
    }

    // 4. Force minimap child to strictly equal the measured metadata height
    minimap.layout(
      BoxConstraints.tightFor(
        width: mapWidth,
        height: cardHeight,
      ),
      parentUsesSize: true,
    );

    // 5. Position both cards along the exact same bottom baseline
    final _HudCardParentData minimapParentData =
        minimap.parentData! as _HudCardParentData;
    final _HudCardParentData metadataParentData =
        metadata.parentData! as _HudCardParentData;

    minimapParentData.offset = Offset.zero;
    metadataParentData.offset = Offset(mapWidth + gap, 0.0);

    // 6. Set overall layout dimensions
    final double totalW = mapWidth + gap + metadata.size.width;
    size = Size(totalW, cardHeight);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}

/// Composite HUD card presenting the Minimap and Metadata widget as standalone
/// overlay elements pinned along the same bottom baseline with matching height.
class EvidenceMetadataHudCard extends StatelessWidget {
  final HudData hudData;
  final double? availableWidth;
  final VoidCallback? onTap;
  final bool showGoogleAttribution;

  const EvidenceMetadataHudCard({
    super.key,
    required this.hudData,
    this.availableWidth,
    this.onTap,
    this.showGoogleAttribution = true,
  });

  /// Factory constructor for live Camera Viewfinder HUD.
  factory EvidenceMetadataHudCard.live({
    Key? key,
    required String siteCode,
    String? siteName,
    required GpsUiFixture gps,
    double? availableWidth,
    VoidCallback? onTap,
    bool isHighContrast = false,
  }) {
    final hasValidFix =
        gps.isLocked && gps.latitude != 0.0 && gps.longitude != 0.0;
    final hudData = HudFormatter.fromLive(
      siteCode: siteCode,
      siteName: siteName,
      resolvedAddress: gps.resolvedAddress,
      latitude: gps.latitude,
      longitude: gps.longitude,
      altitudeMeters: gps.altitudeMeters,
      accuracyMeters: gps.accuracyMeters,
      isGpsLocked: hasValidFix,
      isDegraded: gps.isDegraded,
      captureTime: DateTime.now(),
      headingDegrees: gps.headingDegrees,
      isHighContrast: isHighContrast,
    );
    return EvidenceMetadataHudCard(
      key: key,
      hudData: hudData,
      availableWidth: availableWidth,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape =
            MediaQuery.orientationOf(context) == Orientation.landscape;
        final parentWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        final targetWidth =
            availableWidth ?? (isLandscape ? 400.0 : parentWidth);
        final maxAllowedWidth = isLandscape
            ? math.min(HudLayoutSpec.refMaxLandscapeWidth, targetWidth)
            : math.min(parentWidth, targetWidth);

        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxAllowedWidth),
          child: _HudCardLayout(
            gap: HudLayoutSpec.refCardGap,
            minimapAspectRatio: HudLayoutSpec.minimapAspectRatio,
            minimap: StandaloneMinimapWidget.fromData(
              hudData: hudData,
              onTap: onTap,
            ),
            metadata: StandaloneMetadataWidget(
              hudData: hudData,
              onTap: onTap,
            ),
          ),
        );
      },
    );
  }
}

// Aliases for clear standalone semantic use
typedef EvidenceMinimapCard = StandaloneMinimapWidget;
typedef EvidenceMetadataCard = StandaloneMetadataWidget;
