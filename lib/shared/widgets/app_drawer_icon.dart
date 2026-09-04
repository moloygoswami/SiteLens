import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/theme.dart';

/// Bespoke SiteLens App Drawer / Brand Icon Component.
///
/// Designed with tactical construction geometry:
/// - 8-pointed faceted compass rose / star in safety orange dual-tone gradient
/// - Tactical lens chassis with precision reticle tick marks, dashed calibration dial, and corner framing brackets
/// - Central optical reticle with target dial and high-visibility center pip
/// - Physics-based interactive micro-states:
///   * **Hover**: Smooth spring expansion (1.05x), subtle rotation, and radiant glow
///   * **Active / Pressed**: Tactile spring compression (0.94x)
///   * **Focus**: High-visibility safety-orange focus ring
class AppDrawerIcon extends StatefulWidget {
  final double size;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool enableInteractivity;
  final bool showBackgroundChassis;

  const AppDrawerIcon({
    super.key,
    this.size = 84.0,
    this.onTap,
    this.tooltip,
    this.enableInteractivity = true,
    this.showBackgroundChassis = true,
  });

  @override
  State<AppDrawerIcon> createState() => _AppDrawerIconState();
}

class _AppDrawerIconState extends State<AppDrawerIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _rotationAnimation;
  late final Animation<double> _glowAnimation;

  bool _isHovered = false;
  bool _isPressed = false;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      ),
    );

    _rotationAnimation = Tween<double>(begin: 0.0, end: math.pi / 12).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );

    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _handleHover(bool hovered) {
    if (!widget.enableInteractivity) return;
    setState(() => _isHovered = hovered);
    if (hovered) {
      _animController.forward();
    } else if (!_isPressed && !_isFocused) {
      _animController.reverse();
    }
  }

  void _handleFocus(bool focused) {
    if (!widget.enableInteractivity) return;
    setState(() => _isFocused = focused);
    if (focused) {
      _animController.forward();
    } else if (!_isHovered && !_isPressed) {
      _animController.reverse();
    }
  }

  void _handleTapDown(TapDownDetails _) {
    if (!widget.enableInteractivity) return;
    setState(() => _isPressed = true);
  }

  void _handleTapUp(TapUpDetails _) {
    if (!widget.enableInteractivity) return;
    setState(() => _isPressed = false);
  }

  void _handleTapCancel() {
    if (!widget.enableInteractivity) return;
    setState(() => _isPressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final effectiveSize = widget.size;
    final borderRadius = BorderRadius.circular(effectiveSize * 0.26);

    Widget content = AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        final currentScale = _isPressed
            ? 0.94
            : (_isHovered || _isFocused ? _scaleAnimation.value : 1.0);

        return Transform.scale(
          scale: currentScale,
          child: Container(
            width: effectiveSize,
            height: effectiveSize,
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              border: _isFocused
                  ? Border.all(color: AppColors.primary, width: 2.5)
                  : null,
              boxShadow: [
                // Base ambient shadow
                BoxShadow(
                  color: Colors.black.withAlpha(80),
                  blurRadius: effectiveSize * 0.2,
                  offset: Offset(0, effectiveSize * 0.08),
                ),
                // Dynamic tactical safety orange glow on hover / active
                if (_glowAnimation.value > 0)
                  BoxShadow(
                    color: AppColors.primary.withAlpha(
                      (60 * _glowAnimation.value).round(),
                    ),
                    blurRadius: effectiveSize * 0.3 * _glowAnimation.value,
                    spreadRadius: effectiveSize * 0.04 * _glowAnimation.value,
                    offset: Offset(0, effectiveSize * 0.04),
                  ),
              ],
            ),
            child: CustomPaint(
              size: Size(effectiveSize, effectiveSize),
              painter: _SiteLensAperturePainter(
                rotation: _rotationAnimation.value,
                showBackground: widget.showBackgroundChassis,
                isHovered: _isHovered,
                isPressed: _isPressed,
              ),
            ),
          ),
        );
      },
    );

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      content = Tooltip(
        message: widget.tooltip!,
        child: content,
      );
    }

    if (!widget.enableInteractivity) {
      return content;
    }

    return FocusableActionDetector(
      onShowFocusHighlight: _handleFocus,
      onShowHoverHighlight: _handleHover,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: _handleTapDown,
        onTapUp: _handleTapUp,
        onTapCancel: _handleTapCancel,
        behavior: HitTestBehavior.opaque,
        child: content,
      ),
    );
  }
}

/// Custom painter rendering the crisp mathematical geometry of the SiteLens Aperture.
class _SiteLensAperturePainter extends CustomPainter {
  final double rotation;
  final bool showBackground;
  final bool isHovered;
  final bool isPressed;

  _SiteLensAperturePainter({
    required this.rotation,
    required this.showBackground,
    required this.isHovered,
    required this.isPressed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final radius = w / 2;

    // 1. Background Chassis
    if (showBackground) {
      final bgRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        Radius.circular(w * 0.26),
      );

      // Dark radial chassis gradient with rich contrast
      final bgGradient = RadialGradient(
        center: const Alignment(0, -0.1),
        radius: 0.85,
        colors: const [
          Color(0xFF262932),
          Color(0xFF181A1F),
          Color(0xFF0F1013),
        ],
        stops: const [0.0, 0.6, 1.0],
      );

      final bgPaint = Paint()..shader = bgGradient.createShader(bgRect.outerRect);
      canvas.drawRRect(bgRect, bgPaint);

      // Subtle engineering grid lines
      final gridPaint = Paint()
        ..color = const Color(0xFF343842).withAlpha(150)
        ..strokeWidth = math.max(1.2, w * 0.014)
        ..style = PaintingStyle.stroke;

      final inset = w * 0.10;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(inset, inset, w - 2 * inset, h - 2 * inset),
          Radius.circular(w * 0.18),
        ),
        gridPaint,
      );

      // Chassis outer border
      final borderPaint = Paint()
        ..color = isHovered ? AppColors.primary.withAlpha(180) : const Color(0xFF424652)
        ..strokeWidth = math.max(1.5, w * 0.022)
        ..style = PaintingStyle.stroke;
      canvas.drawRRect(bgRect, borderPaint);
    }

    // 2. Outer Lens Rings (Scaled Up)
    final lensRingRadius = radius * 0.80;
    final innerRingRadius = radius * 0.66;

    // Outer dark chassis ring
    final lensChassisPaint = Paint()
      ..color = const Color(0xFF1E2026)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, lensRingRadius, lensChassisPaint);

    final lensBorderPaint = Paint()
      ..color = const Color(0xFF444854)
      ..strokeWidth = math.max(1.4, w * 0.02)
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, lensRingRadius, lensBorderPaint);

    // Dashed / Dotted Calibration Ring (Civil Orange)
    _drawDashedCircle(
      canvas: canvas,
      center: center,
      radius: radius * 0.73,
      color: AppColors.primary.withAlpha(200),
      strokeWidth: math.max(1.2, w * 0.014),
      dashCount: 16,
    );

    // Inner Dark Cavity
    final cavityPaint = Paint()
      ..color = const Color(0xFF121316)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, innerRingRadius, cavityPaint);

    // 3. Tactical Reticle Crosshairs (North, South, East, West)
    final tickPaint = Paint()
      ..color = Colors.white.withAlpha(220)
      ..strokeWidth = math.max(1.5, w * 0.022)
      ..strokeCap = StrokeCap.round;

    final tickInner = radius * 0.62;
    final tickOuter = radius * 0.80;

    // Top
    canvas.drawLine(Offset(center.dx, center.dy - tickOuter), Offset(center.dx, center.dy - tickInner), tickPaint);
    // Bottom
    canvas.drawLine(Offset(center.dx, center.dy + tickInner), Offset(center.dx, center.dy + tickOuter), tickPaint);
    // Left
    canvas.drawLine(Offset(center.dx - tickOuter, center.dy), Offset(center.dx - tickInner, center.dy), tickPaint);
    // Right
    canvas.drawLine(Offset(center.dx + tickInner, center.dy), Offset(center.dx + tickOuter, center.dy), tickPaint);

    // 4. Corner Alignment Framing Brackets (Safety Orange)
    final bracketPaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = math.max(1.8, w * 0.026)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    final bracketDist = radius * 0.62;
    final bracketArm = radius * 0.15;

    // Top-Left
    final tl = Offset(center.dx - bracketDist, center.dy - bracketDist);
    canvas.drawPath(
      Path()
        ..moveTo(tl.dx, tl.dy + bracketArm)
        ..lineTo(tl.dx, tl.dy)
        ..lineTo(tl.dx + bracketArm, tl.dy),
      bracketPaint,
    );

    // Top-Right
    final tr = Offset(center.dx + bracketDist, center.dy - bracketDist);
    canvas.drawPath(
      Path()
        ..moveTo(tr.dx - bracketArm, tr.dy)
        ..lineTo(tr.dx, tr.dy)
        ..lineTo(tr.dx, tr.dy + bracketArm),
      bracketPaint,
    );

    // Bottom-Left
    final bl = Offset(center.dx - bracketDist, center.dy + bracketDist);
    canvas.drawPath(
      Path()
        ..moveTo(bl.dx, bl.dy - bracketArm)
        ..lineTo(bl.dx, bl.dy)
        ..lineTo(bl.dx + bracketArm, bl.dy),
      bracketPaint,
    );

    // Bottom-Right
    final br = Offset(center.dx + bracketDist, center.dy + bracketDist);
    canvas.drawPath(
      Path()
        ..moveTo(br.dx - bracketArm, br.dy)
        ..lineTo(br.dx, br.dy)
        ..lineTo(br.dx, br.dy - bracketArm),
      bracketPaint,
    );

    // 5. Eight-Pointed Compass Rose / Star Emblem (Safety Orange Facets)
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);

    const int pointCount = 8;
    final cardinalOuterR = radius * 0.58;
    final ordinalOuterR = radius * 0.46;
    final valleyR = radius * 0.22;

    // Facet Paints (Light side & Shaded side)
    final lightFacetGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: const [
        Color(0xFFFFB05C), // Highlight amber
        Color(0xFFF27A1A), // Core safety orange
      ],
    );
    final darkFacetGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: const [
        Color(0xFFE0680C), // Mid safety orange
        Color(0xFFB84E00), // Deep construction tone
      ],
    );

    final emblemRect = Rect.fromCircle(center: Offset.zero, radius: cardinalOuterR);
    final lightPaint = Paint()
      ..shader = lightFacetGradient.createShader(emblemRect)
      ..style = PaintingStyle.fill;
    final darkPaint = Paint()
      ..shader = darkFacetGradient.createShader(emblemRect)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < pointCount; i++) {
      final isCardinal = (i % 2 == 0);
      final tipRadius = isCardinal ? cardinalOuterR : ordinalOuterR;
      final tipAngle = i * (math.pi / 4);

      final prevValleyAngle = tipAngle - (math.pi / 8);
      final nextValleyAngle = tipAngle + (math.pi / 8);

      final tip = Offset(tipRadius * math.cos(tipAngle), tipRadius * math.sin(tipAngle));
      final prevValley = Offset(valleyR * math.cos(prevValleyAngle), valleyR * math.sin(prevValleyAngle));
      final nextValley = Offset(valleyR * math.cos(nextValleyAngle), valleyR * math.sin(nextValleyAngle));

      // Left facet (Light / Highlight)
      final leftFacetPath = Path()
        ..moveTo(0, 0)
        ..lineTo(prevValley.dx, prevValley.dy)
        ..lineTo(tip.dx, tip.dy)
        ..close();
      canvas.drawPath(leftFacetPath, lightPaint);

      // Right facet (Deep / Shaded)
      final rightFacetPath = Path()
        ..moveTo(0, 0)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(nextValley.dx, nextValley.dy)
        ..close();
      canvas.drawPath(rightFacetPath, darkPaint);
    }

    // 6. Central Optical Reticle Core (High Contrast)
    final coreR = radius * 0.16;
    final corePaint = Paint()
      ..color = const Color(0xFF0E0F12)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset.zero, coreR, corePaint);

    final coreBorder = Paint()
      ..color = AppColors.primary
      ..strokeWidth = math.max(1.8, w * 0.022)
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset.zero, coreR, coreBorder);

    // Inner concentric target dial
    final innerDialPaint = Paint()
      ..color = const Color(0xFFFFA84A)
      ..strokeWidth = math.max(1.0, w * 0.012)
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset.zero, coreR * 0.65, innerDialPaint);

    // High-visibility center optical white pip
    final centerPip = Paint()
      ..color = Colors.white.withAlpha(250)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset.zero, coreR * 0.32, centerPip);

    canvas.restore();
  }

  void _drawDashedCircle({
    required Canvas canvas,
    required Offset center,
    required double radius,
    required Color color,
    required double strokeWidth,
    required int dashCount,
  }) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final sweepAngle = (2 * math.pi) / dashCount;
    final dashSweep = sweepAngle * 0.55;

    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * sweepAngle;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        dashSweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SiteLensAperturePainter oldDelegate) {
    return oldDelegate.rotation != rotation ||
        oldDelegate.showBackground != showBackground ||
        oldDelegate.isHovered != isHovered ||
        oldDelegate.isPressed != isPressed;
  }
}
