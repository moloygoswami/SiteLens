import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../../app/theme.dart';
import '../models/camera_hardware_state.dart';
import '../models/camera_ui_state.dart';
import '../../../shared/widgets/evidence_metadata_hud_card.dart';

class CameraViewfinder extends StatefulWidget {
  final CameraUiState state;
  final CameraController? cameraController;
  final CameraStatus cameraStatus;
  final double currentZoomLevel;
  final String zoomDisplayLabel;
  final Function(Offset localPosition) onTapFocus;
  final ValueChanged<double> onPinchZoom;
  final VoidCallback onToggleFlash;
  final VoidCallback onToggleGrid;
  final VoidCallback onCycleLens;
  final VoidCallback onCycleAspectRatio;
  final VoidCallback onCycleTimer;
  final VoidCallback? onToggleHighContrast;
  final VoidCallback? onRetryCamera;

  const CameraViewfinder({
    super.key,
    required this.state,
    this.cameraController,
    this.cameraStatus = CameraStatus.ready,
    this.currentZoomLevel = 1.0,
    this.zoomDisplayLabel = '1x',
    required this.onTapFocus,
    required this.onPinchZoom,
    required this.onToggleFlash,
    required this.onToggleGrid,
    required this.onCycleLens,
    required this.onCycleAspectRatio,
    required this.onCycleTimer,
    this.onToggleHighContrast,
    this.onRetryCamera,
  });

  @override
  State<CameraViewfinder> createState() => _CameraViewfinderState();
}

class _CameraViewfinderState extends State<CameraViewfinder> {
  double _baseZoom = 1.0;
  bool _isPinching = false;

  @override
  Widget build(BuildContext context) {
    final isPreviewActive = (widget.cameraStatus == CameraStatus.ready ||
            widget.cameraStatus == CameraStatus.capturing ||
            widget.cameraStatus == CameraStatus.recordingVideo) &&
        widget.cameraController != null &&
        widget.cameraController!.value.isInitialized;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        final viewportHeight = constraints.maxHeight;

        final isLandscape = viewportWidth > viewportHeight;
        // Calculate bottom mask height for non-full aspect ratio letterboxing to keep HUD inside active sensor viewport
        double maskBottomOffset = 0.0;
        if (widget.state.aspectRatio != CameraAspectRatio.ratioFull &&
            viewportHeight > 0 &&
            viewportWidth > 0) {
          double targetRatio;
          switch (widget.state.aspectRatio) {
            case CameraAspectRatio.ratio1_1:
              targetRatio = 1.0;
              break;
            case CameraAspectRatio.ratio4_3:
              targetRatio = isLandscape ? (4.0 / 3.0) : (3.0 / 4.0);
              break;
            case CameraAspectRatio.ratio16_9:
              targetRatio = isLandscape ? (16.0 / 9.0) : (9.0 / 16.0);
              break;
            case CameraAspectRatio.ratioFull:
              targetRatio = viewportWidth / viewportHeight;
              break;
          }
          final viewRatio = viewportWidth / viewportHeight;
          if (targetRatio >= viewRatio) {
            final visibleHeight = viewportWidth / targetRatio;
            maskBottomOffset =
                math.max(0.0, (viewportHeight - visibleHeight) / 2);
          }
        }

        const leftHudMargin = 14.0;
        const rightHudMargin = 14.0;
        final effectiveHudWidth = math.max(
          160.0,
          viewportWidth - leftHudMargin - rightHudMargin,
        );
        final effectiveHudBottom = 16.0 + maskBottomOffset;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (details) {
            if (details.pointerCount > 1) {
              _isPinching = true;
              _baseZoom = widget.currentZoomLevel;
            }
          },
          onScaleUpdate: (details) {
            if (details.pointerCount > 1) {
              _isPinching = true;
              final newZoom = _baseZoom * details.scale;
              widget.onPinchZoom(newZoom);
            }
          },
          onScaleEnd: (details) {
            _isPinching = false;
          },
          onTapUp: (details) {
            if (!_isPinching) {
              widget.onTapFocus(details.localPosition);
            }
          },
          child: Container(
            width: double.infinity,
            height: double.infinity,
            color: const Color(0xFF131512),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. Live Optical Preview, Subtle Initializing Spinner, or Error Viewport
                if (isPreviewActive)
                  ClipRect(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: widget.state.aspectRatio ==
                                CameraAspectRatio.ratioFull
                            ? (constraints.maxWidth /
                                (constraints.maxHeight > 0
                                    ? constraints.maxHeight
                                    : 1.0))
                            : (widget.state.aspectRatio ==
                                    CameraAspectRatio.ratio4_3
                                ? (isLandscape ? (4.0 / 3.0) : (3.0 / 4.0))
                                : (widget.state.aspectRatio ==
                                        CameraAspectRatio.ratio16_9
                                    ? (isLandscape ? (16.0 / 9.0) : (9.0 / 16.0))
                                    : 1.0)),
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: isLandscape
                                ? (widget.cameraController!.value.previewSize
                                        ?.width ??
                                    constraints.maxWidth)
                                : (widget.cameraController!.value.previewSize
                                        ?.height ??
                                    constraints.maxWidth),
                            height: isLandscape
                                ? (widget.cameraController!.value.previewSize
                                        ?.height ??
                                    constraints.maxHeight)
                                : (widget.cameraController!.value.previewSize
                                        ?.width ??
                                    constraints.maxHeight),
                            child: CameraPreview(
                              widget.cameraController!,
                              key: ObjectKey(widget.cameraController),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                else if (widget.cameraStatus == CameraStatus.initializing)
                  const Center(
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.primary,
                      ),
                    ),
                  )
                else
                  CameraStatusViewport(
                    status: widget.cameraStatus,
                    onRetryCamera: widget.onRetryCamera,
                  ),

                // 1.5 Aspect Ratio Framing Mask
                AspectRatioFraming(aspectRatio: widget.state.aspectRatio),

                // 2. Technical Corner Registration Marks (L-Brackets)
                const RegistrationMarks(),

                // 3. Rule of Thirds Alignment Grid
                if (widget.state.isGridVisible) const ThirdsGrid(),

                // 4. Interactive Focus Reticle
                if (widget.state.focusPoint != null)
                  FocusReticle(
                    focusPoint: widget.state.focusPoint!,
                    key: ValueKey(widget.state.focusTimestamp),
                  ),

                // 5. Figure-8 Compass / GPS Calibration Hint (Visible when GPS accuracy is degraded)
                if (widget.state.gps.isDegraded)
                  Positioned(
                    top: 14,
                    left: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(210),
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                        border: Border.all(
                            color: AppColors.statusAmber.withAlpha(140),
                            width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.all_inclusive_rounded,
                            size: 14,
                            color: AppColors.statusAmber,
                          ),
                          const SizedBox(width: 5),
                          const Text(
                            'Calibrate: Tilt in figure-8 motion',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // 6. Live Geotag Watermark Preview Card with Mini GPS Map Thumbnail (Bottom-Left HUD)
                Positioned(
                  left: leftHudMargin,
                  bottom: effectiveHudBottom,
                  child: WatermarkPreview(
                    siteCode: widget.state.siteCode,
                    siteName: widget.state.siteName,
                    gps: widget.state.gps,
                    isHighContrast: widget.state.isHighContrastMode,
                    availableWidth: effectiveHudWidth,
                  ),
                ),

                // 7. Floating Quick Settings Controls (Right-Side Vertical Action Stack in Middle)
                Positioned(
                  right: 24,
                  top: 0,
                  bottom: (viewportWidth > viewportHeight) ? 16 : 120,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SingleChildScrollView(
                      child: ViewfinderControls(
                        flashMode: widget.state.flashMode,
                        lensZoom: widget.state.lensZoom,
                        aspectRatio: widget.state.aspectRatio,
                        captureTimer: widget.state.captureTimer,
                        zoomDisplayLabel: widget.zoomDisplayLabel,
                        isGridVisible: widget.state.isGridVisible,
                        isHighContrast: widget.state.isHighContrastMode,
                        onToggleFlash: widget.onToggleFlash,
                        onToggleGrid: widget.onToggleGrid,
                        onCycleLens: widget.onCycleLens,
                        onCycleAspectRatio: widget.onCycleAspectRatio,
                        onCycleTimer: widget.onCycleTimer,
                        onToggleHighContrast: widget.onToggleHighContrast,
                      ),
                    ),
                  ),
                ),

                // 8. Countdown Timer Display Overlay
                if (widget.state.isCountingDown)
                  CountdownOverlay(
                    remainingSeconds: widget.state.countdownRemaining,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class CameraStatusViewport extends StatelessWidget {
  final CameraStatus status;
  final VoidCallback? onRetryCamera;

  const CameraStatusViewport({
    super.key,
    this.status = CameraStatus.ready,
    this.onRetryCamera,
  });

  @override
  Widget build(BuildContext context) {
    String titleText;
    String subtitleText;
    final isAlert =
        status == CameraStatus.unavailable || status == CameraStatus.error;
    final isInitializing = status == CameraStatus.initializing;

    switch (status) {
      case CameraStatus.initializing:
        titleText = 'INITIALIZING CAMERA FEED...';
        subtitleText = 'Acquiring optical hardware stream';
        break;
      case CameraStatus.unavailable:
        titleText = 'CAMERA ACCESS REQUIRED';
        subtitleText = 'Camera access is required to capture evidence.';
        break;
      case CameraStatus.error:
        titleText = 'CAMERA HARDWARE UNAVAILABLE';
        subtitleText =
            'No valid evidence can be captured until camera is restored.';
        break;
      case CameraStatus.capturing:
      case CameraStatus.recordingVideo:
      case CameraStatus.ready:
        titleText = 'ACTIVE SENSOR VIEWPORT';
        subtitleText = 'Live optical stream • Tap screen to focus reticle';
        break;
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF181B16),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isAlert
                ? AppColors.statusRed.withAlpha(160)
                : Colors.white.withAlpha(20),
            width: isAlert ? 2 : 1,
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isAlert
                      ? AppColors.statusRed.withAlpha(30)
                      : Colors.white.withAlpha(10),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isAlert
                        ? AppColors.statusRed.withAlpha(120)
                        : AppColors.primary.withAlpha(40),
                    width: 1.5,
                  ),
                ),
                child: isInitializing
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.primary,
                        ),
                      )
                    : Icon(
                        isAlert
                            ? Icons.videocam_off_rounded
                            : Icons.camera_enhance_rounded,
                        size: 26,
                        color: isAlert
                            ? AppColors.statusRed
                            : (status == CameraStatus.error
                                ? AppColors.statusAmber
                                : AppColors.primary),
                      ),
              ),
              const SizedBox(height: 10),
              Text(
                titleText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isAlert ? AppColors.statusRed : Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitleText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: isAlert
                      ? Colors.white.withAlpha(200)
                      : Colors.white.withAlpha(140),
                ),
              ),
              if (isAlert && onRetryCamera != null) ...[
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: onRetryCamera,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text(
                    'RETRY CAMERA',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.black,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    minimumSize: const Size(140, 36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class LocationDetailOverlay extends StatelessWidget {
  final String sectorName;
  final String geofenceStatus;
  final String altitudeDisplay;

  const LocationDetailOverlay({
    super.key,
    required this.sectorName,
    required this.geofenceStatus,
    required this.altitudeDisplay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(190),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withAlpha(35), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.pin_drop_rounded,
                  size: 12, color: AppColors.primaryLight),
              const SizedBox(width: 4),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    sectorName,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            geofenceStatus,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: AppColors.statusGreenLight,
            ),
          ),
          Text(
            'Elev: $altitudeDisplay',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 9,
              color: Colors.white.withAlpha(180),
            ),
          ),
        ],
      ),
    );
  }
}

class RegistrationMarks extends StatelessWidget {
  const RegistrationMarks({super.key});

  @override
  Widget build(BuildContext context) {
    const markColor = Color(0xFFE4E2E1);
    const markLength = 28.0;
    const markThickness = 2.5;
    const inset = 16.0;

    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: inset,
            left: inset,
            child: SizedBox(
              width: markLength,
              height: markLength,
              child: CustomPaint(
                painter: _CornerBracketPainter(
                  color: markColor,
                  thickness: markThickness,
                  isTop: true,
                  isLeft: true,
                ),
              ),
            ),
          ),
          Positioned(
            top: inset,
            right: inset,
            child: SizedBox(
              width: markLength,
              height: markLength,
              child: CustomPaint(
                painter: _CornerBracketPainter(
                  color: markColor,
                  thickness: markThickness,
                  isTop: true,
                  isLeft: false,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: inset,
            left: inset,
            child: SizedBox(
              width: markLength,
              height: markLength,
              child: CustomPaint(
                painter: _CornerBracketPainter(
                  color: markColor,
                  thickness: markThickness,
                  isTop: false,
                  isLeft: true,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: inset,
            right: inset,
            child: SizedBox(
              width: markLength,
              height: markLength,
              child: CustomPaint(
                painter: _CornerBracketPainter(
                  color: markColor,
                  thickness: markThickness,
                  isTop: false,
                  isLeft: false,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CornerBracketPainter extends CustomPainter {
  final Color color;
  final double thickness;
  final bool isTop;
  final bool isLeft;

  _CornerBracketPainter({
    required this.color,
    required this.thickness,
    required this.isTop,
    required this.isLeft,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke;

    final path = Path();
    if (isTop && isLeft) {
      path.moveTo(0, size.height);
      path.lineTo(0, 0);
      path.lineTo(size.width, 0);
    } else if (isTop && !isLeft) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
    } else if (!isTop && isLeft) {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, size.height);
      path.lineTo(size.width, size.height);
      path.lineTo(size.width, 0);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ThirdsGrid extends StatelessWidget {
  const ThirdsGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _ThirdsGridPainter(),
      ),
    );
  }
}

class _ThirdsGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(30)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    final oneThirdW = size.width / 3;
    final twoThirdsW = 2 * size.width / 3;
    canvas.drawLine(
        Offset(oneThirdW, 0), Offset(oneThirdW, size.height), paint);
    canvas.drawLine(
        Offset(twoThirdsW, 0), Offset(twoThirdsW, size.height), paint);

    final oneThirdH = size.height / 3;
    final twoThirdsH = 2 * size.height / 3;
    canvas.drawLine(Offset(0, oneThirdH), Offset(size.width, oneThirdH), paint);
    canvas.drawLine(
        Offset(0, twoThirdsH), Offset(size.width, twoThirdsH), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class FocusReticle extends StatefulWidget {
  final Offset focusPoint;

  const FocusReticle({
    super.key,
    required this.focusPoint,
  });

  @override
  State<FocusReticle> createState() => _FocusReticleState();
}

class _FocusReticleState extends State<FocusReticle>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _scaleAnim = Tween<double>(begin: 1.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 68.0;

    return Positioned(
      left: widget.focusPoint.dx - (size / 2),
      top: widget.focusPoint.dy - (size / 2),
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _scaleAnim,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnim.value,
              child: child,
            );
          },
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primary, width: 1.8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                Positioned(
                  top: 2,
                  left: 2,
                  child: Container(
                      width: 6, height: 2, color: AppColors.statusGreen),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                      width: 6, height: 2, color: AppColors.statusGreen),
                ),
                Positioned(
                  bottom: 2,
                  left: 2,
                  child: Container(
                      width: 6, height: 2, color: AppColors.statusGreen),
                ),
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                      width: 6, height: 2, color: AppColors.statusGreen),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class WatermarkPreview extends StatelessWidget {
  final String siteCode;
  final String? siteName;
  final GpsUiFixture gps;
  final bool isHighContrast;
  final double? availableWidth;

  const WatermarkPreview({
    super.key,
    required this.siteCode,
    this.siteName,
    required this.gps,
    this.isHighContrast = false,
    this.availableWidth,
  });

  @override
  Widget build(BuildContext context) {
    return EvidenceMetadataHudCard.live(
      siteCode: siteCode,
      siteName: siteName,
      gps: gps,
      isHighContrast: isHighContrast,
      availableWidth: availableWidth,
    );
  }
}

class ViewfinderControls extends StatelessWidget {
  final CameraFlashMode flashMode;
  final CameraLensZoom lensZoom;
  final CameraAspectRatio aspectRatio;
  final CameraCaptureTimer captureTimer;
  final String zoomDisplayLabel;
  final bool isGridVisible;
  final bool isHighContrast;
  final VoidCallback onToggleFlash;
  final VoidCallback onToggleGrid;
  final VoidCallback onCycleLens;
  final VoidCallback onCycleAspectRatio;
  final VoidCallback onCycleTimer;
  final VoidCallback? onToggleHighContrast;

  const ViewfinderControls({
    super.key,
    required this.flashMode,
    required this.lensZoom,
    this.aspectRatio = CameraAspectRatio.ratioFull,
    this.captureTimer = CameraCaptureTimer.off,
    this.zoomDisplayLabel = '1x',
    required this.isGridVisible,
    this.isHighContrast = false,
    required this.onToggleFlash,
    required this.onToggleGrid,
    required this.onCycleLens,
    required this.onCycleAspectRatio,
    required this.onCycleTimer,
    this.onToggleHighContrast,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(190),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: Colors.white.withAlpha(45), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(100),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Flash toggle
          IconButton(
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: const EdgeInsets.all(4),
            icon: Icon(
              flashMode.icon,
              color: flashMode == CameraFlashMode.off
                  ? Colors.white.withAlpha(180)
                  : AppColors.primary,
              size: 20,
            ),
            tooltip: 'Flash: ${flashMode.label}',
            onPressed: onToggleFlash,
          ),
          const SizedBox(height: 2),
          // Grid toggle
          IconButton(
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: const EdgeInsets.all(4),
            icon: Icon(
              isGridVisible ? Icons.grid_on_rounded : Icons.grid_off_rounded,
              color: isGridVisible
                  ? AppColors.primary
                  : Colors.white.withAlpha(160),
              size: 20,
            ),
            tooltip: 'Grid ${isGridVisible ? "On" : "Off"}',
            onPressed: onToggleGrid,
          ),
          const SizedBox(height: 2),
          // Outdoor High-Contrast toggle
          if (onToggleHighContrast != null) ...[
            IconButton(
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: const EdgeInsets.all(4),
              icon: Icon(
                isHighContrast
                    ? Icons.brightness_high_rounded
                    : Icons.brightness_6_rounded,
                color: isHighContrast
                    ? AppColors.primary
                    : Colors.white.withAlpha(160),
                size: 20,
              ),
              tooltip:
                  'Outdoor High-Contrast: ${isHighContrast ? "On" : "Off"}',
              onPressed: onToggleHighContrast,
            ),
            const SizedBox(height: 2),
          ],
          // Aspect Ratio toggle
          Semantics(
            button: true,
            label: 'Aspect ratio: ${aspectRatio.label}',
            hint: 'Tap to cycle aspect ratio',
            child: InkWell(
              onTap: onCycleAspectRatio,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      aspectRatio.icon,
                      size: 19,
                      color: aspectRatio == CameraAspectRatio.ratioFull
                          ? Colors.white.withAlpha(180)
                          : AppColors.primary,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      aspectRatio.label,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: aspectRatio == CameraAspectRatio.ratioFull
                            ? Colors.white.withAlpha(180)
                            : AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          // Timer toggle
          Semantics(
            button: true,
            label: 'Timer: ${captureTimer.label}',
            hint: 'Tap to cycle timer duration',
            child: InkWell(
              onTap: onCycleTimer,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      captureTimer.icon,
                      size: 19,
                      color: captureTimer == CameraCaptureTimer.off
                          ? Colors.white.withAlpha(180)
                          : AppColors.primary,
                    ),
                    if (captureTimer != CameraCaptureTimer.off) ...[
                      const SizedBox(height: 1),
                      Text(
                        captureTimer.label,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          // Lens zoom cycle button
          Semantics(
            button: true,
            label: 'Camera lens zoom: $zoomDisplayLabel',
            hint: 'Double tap to cycle zoom level',
            child: InkWell(
              onTap: onCycleLens,
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                width: 36,
                height: 36,
                child: Center(
                  child: Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(35),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppColors.primary.withAlpha(80), width: 1.2),
                    ),
                    child: Text(
                      zoomDisplayLabel,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Visual framing mask that letterboxes non-full aspect ratios on the viewfinder.
class AspectRatioFraming extends StatelessWidget {
  final CameraAspectRatio aspectRatio;

  const AspectRatioFraming({
    super.key,
    required this.aspectRatio,
  });

  @override
  Widget build(BuildContext context) {
    if (aspectRatio == CameraAspectRatio.ratioFull) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        if (w <= 0 || h <= 0) return const SizedBox.shrink();

        final isLandscape = w > h;
        double targetRatio;
        switch (aspectRatio) {
          case CameraAspectRatio.ratio1_1:
            targetRatio = 1.0;
            break;
          case CameraAspectRatio.ratio4_3:
            targetRatio = isLandscape ? (4.0 / 3.0) : (3.0 / 4.0);
            break;
          case CameraAspectRatio.ratio16_9:
            targetRatio = isLandscape ? (16.0 / 9.0) : (9.0 / 16.0);
            break;
          case CameraAspectRatio.ratioFull:
            targetRatio = w / h;
            break;
        }

        final viewRatio = w / h;
        if (targetRatio >= viewRatio) {
          // Target is wider/taller vertically, letterbox top and bottom
          final visibleHeight = w / targetRatio;
          final maskHeight = math.max(0.0, (h - visibleHeight) / 2);

          return IgnorePointer(
            child: Column(
              children: [
                Container(
                    height: maskHeight, color: Colors.black.withAlpha(160)),
                const Spacer(),
                Container(
                    height: maskHeight, color: Colors.black.withAlpha(160)),
              ],
            ),
          );
        } else {
          // Letterbox left and right
          final visibleWidth = h * targetRatio;
          final maskWidth = math.max(0.0, (w - visibleWidth) / 2);

          return IgnorePointer(
            child: Row(
              children: [
                Container(width: maskWidth, color: Colors.black.withAlpha(160)),
                const Spacer(),
                Container(width: maskWidth, color: Colors.black.withAlpha(160)),
              ],
            ),
          );
        }
      },
    );
  }
}

/// Large pulsing countdown overlay displayed in the center of the camera viewfinder.
class CountdownOverlay extends StatelessWidget {
  final int remainingSeconds;

  const CountdownOverlay({
    super.key,
    required this.remainingSeconds,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withAlpha(140),
            border: Border.all(color: AppColors.primary, width: 3),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withAlpha(100),
                blurRadius: 24,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Center(
            child: Text(
              '$remainingSeconds',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 64,
                fontWeight: FontWeight.w900,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
