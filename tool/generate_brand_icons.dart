import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

void main() {
  stdout.writeln('🚀 Generating SiteLens brand assets...');

  final iconDir = Directory('assets/icon');
  if (!iconDir.existsSync()) {
    iconDir.createSync(recursive: true);
  }

  // 1. Generate 1024x1024 Master App Icon
  stdout.writeln('  -> Rendering assets/icon/app_icon_1024.png (1024x1024)...');
  final masterIcon = renderMasterIcon(1024);
  File('assets/icon/app_icon_1024.png').writeAsBytesSync(img.encodePng(masterIcon));

  // 2. Generate 432x432 Android Adaptive Foreground
  stdout.writeln('  -> Rendering assets/icon/adaptive_foreground_432.png (432x432)...');
  final adaptiveForeground = renderAdaptiveForeground(432);
  File('assets/icon/adaptive_foreground_432.png').writeAsBytesSync(img.encodePng(adaptiveForeground));

  // 3. Generate 432x432 Android Adaptive Monochrome
  stdout.writeln('  -> Rendering assets/icon/adaptive_monochrome_432.png (432x432)...');
  final adaptiveMonochrome = renderAdaptiveMonochrome(432);
  File('assets/icon/adaptive_monochrome_432.png').writeAsBytesSync(img.encodePng(adaptiveMonochrome));

  // 4. Generate 512x512 Splash Logo
  stdout.writeln('  -> Rendering assets/icon/splash_logo_512.png (512x512)...');
  final splashLogo = renderSplashLogo(512);
  File('assets/icon/splash_logo_512.png').writeAsBytesSync(img.encodePng(splashLogo));

  stdout.writeln('✨ All brand assets generated successfully in assets/icon/!');
}

/// Renders the complete Master App Icon at [size] x [size] with full chassis and elevation.
img.Image renderMasterIcon(int size) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  final cx = size / 2.0;
  final cy = size / 2.0;
  final radius = size / 2.0;

  // Geometry dimensions
  final cornerRadius = size * 0.26;
  final chassisBorderWidth = math.max(2.0, size * 0.022);
  final gridInset = size * 0.10;
  final gridRadius = size * 0.18;
  final gridLineWidth = math.max(1.5, size * 0.014);

  final lensRingRadius = radius * 0.80;
  final innerRingRadius = radius * 0.66;
  final dashRadius = radius * 0.73;
  final dashWidth = math.max(2.0, size * 0.014);

  final tickInner = radius * 0.62;
  final tickOuter = radius * 0.80;
  final tickWidth = math.max(2.0, size * 0.022);

  final bracketDist = radius * 0.62;
  final bracketArm = radius * 0.15;
  final bracketWidth = math.max(2.5, size * 0.026);

  final cardinalOuterR = radius * 0.58;
  final ordinalOuterR = radius * 0.46;
  final valleyR = radius * 0.22;

  final coreR = radius * 0.16;
  final coreBorderWidth = math.max(2.0, size * 0.022);
  final innerDialRadius = coreR * 0.65;
  final innerDialWidth = math.max(1.5, size * 0.012);
  final centerPipRadius = coreR * 0.32;

  // Pre-calculate 8 compass points
  final compassPoints = <_CompassPoint>[];
  for (int i = 0; i < 8; i++) {
    final isCardinal = (i % 2 == 0);
    final tipRadius = isCardinal ? cardinalOuterR : ordinalOuterR;
    final tipAngle = -math.pi / 2.0 + i * (math.pi / 4.0);

    final prevValleyAngle = tipAngle - (math.pi / 8.0);
    final nextValleyAngle = tipAngle + (math.pi / 8.0);

    final tip = _Point(cx + tipRadius * math.cos(tipAngle), cy + tipRadius * math.sin(tipAngle));
    final prevValley = _Point(cx + valleyR * math.cos(prevValleyAngle), cy + valleyR * math.sin(prevValleyAngle));
    final nextValley = _Point(cx + valleyR * math.cos(nextValleyAngle), cy + valleyR * math.sin(nextValleyAngle));

    compassPoints.add(_CompassPoint(tip: tip, prevValley: prevValley, nextValley: nextValley));
  }

  // Pixel rasterization loop (Analytical 2x2 supersampling for crisp anti-aliasing)
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      double rSum = 0, gSum = 0, bSum = 0, aSum = 0;

      for (int sy = 0; sy < 2; sy++) {
        for (int sx = 0; sx < 2; sx++) {
          final px = x + (sx + 0.5) / 2.0;
          final py = y + (sy + 0.5) / 2.0;

          final sample = _sampleMasterIcon(
            px: px,
            py: py,
            cx: cx,
            cy: cy,
            size: size,
            radius: radius,
            cornerRadius: cornerRadius,
            chassisBorderWidth: chassisBorderWidth,
            gridInset: gridInset,
            gridRadius: gridRadius,
            gridLineWidth: gridLineWidth,
            lensRingRadius: lensRingRadius,
            innerRingRadius: innerRingRadius,
            dashRadius: dashRadius,
            dashWidth: dashWidth,
            tickInner: tickInner,
            tickOuter: tickOuter,
            tickWidth: tickWidth,
            bracketDist: bracketDist,
            bracketArm: bracketArm,
            bracketWidth: bracketWidth,
            compassPoints: compassPoints,
            coreR: coreR,
            coreBorderWidth: coreBorderWidth,
            innerDialRadius: innerDialRadius,
            innerDialWidth: innerDialWidth,
            centerPipRadius: centerPipRadius,
          );

          rSum += sample.r;
          gSum += sample.g;
          bSum += sample.b;
          aSum += sample.a;
        }
      }

      final r = (rSum / 4.0).clamp(0.0, 255.0).round();
      final g = (gSum / 4.0).clamp(0.0, 255.0).round();
      final b = (bSum / 4.0).clamp(0.0, 255.0).round();
      final a = (aSum / 4.0).clamp(0.0, 255.0).round();

      image.setPixelRgba(x, y, r, g, b, a);
    }
  }

  return image;
}

/// Evaluates color & alpha at subpixel (px, py) for the Master App Icon
_Color _sampleMasterIcon({
  required double px,
  required double py,
  required double cx,
  required double cy,
  required int size,
  required double radius,
  required double cornerRadius,
  required double chassisBorderWidth,
  required double gridInset,
  required double gridRadius,
  required double gridLineWidth,
  required double lensRingRadius,
  required double innerRingRadius,
  required double dashRadius,
  required double dashWidth,
  required double tickInner,
  required double tickOuter,
  required double tickWidth,
  required double bracketDist,
  required double bracketArm,
  required double bracketWidth,
  required List<_CompassPoint> compassPoints,
  required double coreR,
  required double coreBorderWidth,
  required double innerDialRadius,
  required double innerDialWidth,
  required double centerPipRadius,
}) {
  // 1. Chassis Rounded Box SDF
  final dChassis = _sdRoundedBox(px - cx, py - cy, cx, cy, cornerRadius);
  if (dChassis > 0.5) {
    return _Color(0, 0, 0, 0); // Outside chassis
  }

  // Base Radial Background Gradient
  final distToLightCenter = math.sqrt(math.pow(px - cx, 2) + math.pow(py - (cy - size * 0.1), 2));
  final gradT = (distToLightCenter / (size * 0.85)).clamp(0.0, 1.0);
  
  _Color color;
  if (gradT < 0.6) {
    final t = gradT / 0.6;
    color = _lerpColor(_Color(38, 41, 50, 255), _Color(24, 26, 31, 255), t);
  } else {
    final t = (gradT - 0.6) / 0.4;
    color = _lerpColor(_Color(24, 26, 31, 255), _Color(15, 16, 19, 255), t);
  }

  // Grid line
  final dGrid = _sdRoundedBox(px - cx, py - cy, cx - gridInset, cy - gridInset, gridRadius);
  if (dGrid.abs() <= gridLineWidth / 2.0) {
    color = _blend(color, _Color(52, 56, 66, 160));
  }

  // Outer border
  if (dChassis >= -chassisBorderWidth && dChassis <= 0.0) {
    color = _Color(66, 70, 82, 255);
  }

  // 2. Outer Lens Ring
  final distToCenter = math.sqrt(math.pow(px - cx, 2) + math.pow(py - cy, 2));
  if (distToCenter <= lensRingRadius) {
    // Fill
    color = _Color(30, 32, 38, 255);

    // Outer lens border
    if (distToCenter >= lensRingRadius - math.max(2.0, size * 0.02)) {
      color = _Color(68, 72, 84, 255);
    }
  }

  // Dashed Calibration Ring (Safety Orange #F27A1A)
  if ((distToCenter - dashRadius).abs() <= dashWidth / 2.0) {
    final angle = (math.atan2(py - cy, px - cx) + 2 * math.pi) % (2 * math.pi);
    const dashCount = 16;
    final sweep = (2 * math.pi) / dashCount;
    final inDash = (angle % sweep) <= (sweep * 0.55);
    if (inDash) {
      color = _blend(color, _Color(242, 122, 26, 210));
    }
  }

  // Inner Dark Cavity
  if (distToCenter <= innerRingRadius) {
    color = _Color(18, 19, 22, 255);
  }

  // 3. Reticle Crosshair Ticks (N, S, E, W)
  final dx = (px - cx).abs();
  final dy = (py - cy).abs();
  // North/South ticks
  if (dx <= tickWidth / 2.0 && py >= cy - tickOuter && py <= cy - tickInner) {
    color = _Color(255, 255, 255, 230);
  } else if (dx <= tickWidth / 2.0 && py >= cy + tickInner && py <= cy + tickOuter) {
    color = _Color(255, 255, 255, 230);
  }
  // East/West ticks
  if (dy <= tickWidth / 2.0 && px >= cx - tickOuter && px <= cx - tickInner) {
    color = _Color(255, 255, 255, 230);
  } else if (dy <= tickWidth / 2.0 && px >= cx + tickInner && px <= cx + tickOuter) {
    color = _Color(255, 255, 255, 230);
  }

  // 4. Corner Framing Brackets
  final inBracket = _pointInCornerBrackets(
    px: px,
    py: py,
    cx: cx,
    cy: cy,
    bracketDist: bracketDist,
    bracketArm: bracketArm,
    bracketWidth: bracketWidth,
  );
  if (inBracket) {
    color = _Color(242, 122, 26, 255);
  }

  // 5. 8-Pointed Faceted Compass Rose Emblem
  final p = _Point(px, py);
  final centerPt = _Point(cx, cy);

  for (final cp in compassPoints) {
    // Left facet: triangle(centerPt, prevValley, tip)
    if (_pointInTriangle(p, centerPt, cp.prevValley, cp.tip)) {
      // Light facet gradient (#FFB05C to #F27A1A)
      final t = ((px - cx) + (py - cy) + size) / (2.0 * size);
      color = _lerpColor(_Color(255, 176, 92, 255), _Color(242, 122, 26, 255), t.clamp(0.0, 1.0));
      break;
    }
    // Right facet: triangle(centerPt, tip, nextValley)
    if (_pointInTriangle(p, centerPt, cp.tip, cp.nextValley)) {
      // Dark facet gradient (#E0680C to #B84E00)
      final t = ((px - cx) + (py - cy) + size) / (2.0 * size);
      color = _lerpColor(_Color(224, 104, 12, 255), _Color(184, 78, 0, 255), t.clamp(0.0, 1.0));
      break;
    }
  }

  // 6. Central Optical Reticle Core
  if (distToCenter <= coreR) {
    color = _Color(14, 15, 18, 255); // Core dark fill

    // Core border (Safety orange)
    if (distToCenter >= coreR - coreBorderWidth) {
      color = _Color(242, 122, 26, 255);
    }
    // Inner concentric target dial
    else if ((distToCenter - innerDialRadius).abs() <= innerDialWidth / 2.0) {
      color = _Color(255, 168, 74, 255);
    }
    // Center optical white pip
    else if (distToCenter <= centerPipRadius) {
      color = _Color(255, 255, 255, 255);
    }
  }

  return color;
}

/// Renders Android Adaptive Icon Foreground on transparent background (432x432).
img.Image renderAdaptiveForeground(int size) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  final cx = size / 2.0;
  final cy = size / 2.0;
  // Adaptive icon safe zone diameter ~260-280px within 432px canvas
  final scale = (size * 0.66) / 1024.0;

  final lensRingRadius = 409.6 * scale;
  final innerRingRadius = 337.92 * scale;
  final dashRadius = 373.76 * scale;
  final dashWidth = math.max(1.8, 14.0 * scale);

  final tickInner = 317.44 * scale;
  final tickOuter = 409.6 * scale;
  final tickWidth = math.max(2.0, 22.0 * scale);

  final bracketDist = 317.44 * scale;
  final bracketArm = 76.8 * scale;
  final bracketWidth = math.max(2.5, 26.0 * scale);

  final cardinalOuterR = 296.96 * scale;
  final ordinalOuterR = 235.52 * scale;
  final valleyR = 112.64 * scale;

  final coreR = 81.92 * scale;
  final coreBorderWidth = math.max(2.0, 22.0 * scale);
  final innerDialRadius = coreR * 0.65;
  final innerDialWidth = math.max(1.2, 12.0 * scale);
  final centerPipRadius = coreR * 0.32;

  // Pre-calculate 8 compass points
  final compassPoints = <_CompassPoint>[];
  for (int i = 0; i < 8; i++) {
    final isCardinal = (i % 2 == 0);
    final tipRadius = isCardinal ? cardinalOuterR : ordinalOuterR;
    final tipAngle = -math.pi / 2.0 + i * (math.pi / 4.0);

    final prevValleyAngle = tipAngle - (math.pi / 8.0);
    final nextValleyAngle = tipAngle + (math.pi / 8.0);

    final tip = _Point(cx + tipRadius * math.cos(tipAngle), cy + tipRadius * math.sin(tipAngle));
    final prevValley = _Point(cx + valleyR * math.cos(prevValleyAngle), cy + valleyR * math.sin(prevValleyAngle));
    final nextValley = _Point(cx + valleyR * math.cos(nextValleyAngle), cy + valleyR * math.sin(nextValleyAngle));

    compassPoints.add(_CompassPoint(tip: tip, prevValley: prevValley, nextValley: nextValley));
  }

  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      double rSum = 0, gSum = 0, bSum = 0, aSum = 0;

      for (int sy = 0; sy < 2; sy++) {
        for (int sx = 0; sx < 2; sx++) {
          final px = x + (sx + 0.5) / 2.0;
          final py = y + (sy + 0.5) / 2.0;
          final distToCenter = math.sqrt(math.pow(px - cx, 2) + math.pow(py - cy, 2));

          _Color sample = _Color(0, 0, 0, 0);

          if (distToCenter <= lensRingRadius) {
            sample = _Color(30, 32, 38, 255);
            if (distToCenter >= lensRingRadius - math.max(2.0, 20.0 * scale)) {
              sample = _Color(68, 72, 84, 255);
            }
          }

          // Dashed Calibration Ring
          if ((distToCenter - dashRadius).abs() <= dashWidth / 2.0) {
            final angle = (math.atan2(py - cy, px - cx) + 2 * math.pi) % (2 * math.pi);
            const dashCount = 16;
            final sweep = (2 * math.pi) / dashCount;
            final inDash = (angle % sweep) <= (sweep * 0.55);
            if (inDash) {
              sample = _blend(sample, _Color(242, 122, 26, 220));
            }
          }

          // Inner Dark Cavity
          if (distToCenter <= innerRingRadius) {
            sample = _Color(18, 19, 22, 255);
          }

          // Reticle Ticks
          final dx = (px - cx).abs();
          final dy = (py - cy).abs();
          if (dx <= tickWidth / 2.0 && py >= cy - tickOuter && py <= cy - tickInner) {
            sample = _Color(255, 255, 255, 230);
          } else if (dx <= tickWidth / 2.0 && py >= cy + tickInner && py <= cy + tickOuter) {
            sample = _Color(255, 255, 255, 230);
          }
          if (dy <= tickWidth / 2.0 && px >= cx - tickOuter && px <= cx - tickInner) {
            sample = _Color(255, 255, 255, 230);
          } else if (dy <= tickWidth / 2.0 && px >= cx + tickInner && px <= cx + tickOuter) {
            sample = _Color(255, 255, 255, 230);
          }

          // Corner Brackets
          final inBracket = _pointInCornerBrackets(
            px: px,
            py: py,
            cx: cx,
            cy: cy,
            bracketDist: bracketDist,
            bracketArm: bracketArm,
            bracketWidth: bracketWidth,
          );
          if (inBracket) {
            sample = _Color(242, 122, 26, 255);
          }

          // Compass Rose Facets
          final p = _Point(px, py);
          final centerPt = _Point(cx, cy);
          for (final cp in compassPoints) {
            if (_pointInTriangle(p, centerPt, cp.prevValley, cp.tip)) {
              final t = ((px - cx) + (py - cy) + size) / (2.0 * size);
              sample = _lerpColor(_Color(255, 176, 92, 255), _Color(242, 122, 26, 255), t.clamp(0.0, 1.0));
              break;
            }
            if (_pointInTriangle(p, centerPt, cp.tip, cp.nextValley)) {
              final t = ((px - cx) + (py - cy) + size) / (2.0 * size);
              sample = _lerpColor(_Color(224, 104, 12, 255), _Color(184, 78, 0, 255), t.clamp(0.0, 1.0));
              break;
            }
          }

          // Central Reticle
          if (distToCenter <= coreR) {
            sample = _Color(14, 15, 18, 255);
            if (distToCenter >= coreR - coreBorderWidth) {
              sample = _Color(242, 122, 26, 255);
            } else if ((distToCenter - innerDialRadius).abs() <= innerDialWidth / 2.0) {
              sample = _Color(255, 168, 74, 255);
            } else if (distToCenter <= centerPipRadius) {
              sample = _Color(255, 255, 255, 255);
            }
          }

          rSum += sample.r;
          gSum += sample.g;
          bSum += sample.b;
          aSum += sample.a;
        }
      }

      final r = (rSum / 4.0).clamp(0.0, 255.0).round();
      final g = (gSum / 4.0).clamp(0.0, 255.0).round();
      final b = (bSum / 4.0).clamp(0.0, 255.0).round();
      final a = (aSum / 4.0).clamp(0.0, 255.0).round();

      image.setPixelRgba(x, y, r, g, b, a);
    }
  }

  return image;
}

/// Renders Monochrome silhouette of the emblem for Android 13+ themed icons (432x432).
img.Image renderAdaptiveMonochrome(int size) {
  final fg = renderAdaptiveForeground(size);
  final mono = img.Image(width: size, height: size, numChannels: 4);

  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final pixel = fg.getPixel(x, y);
      final a = pixel.a.toInt();
      if (a > 20) {
        mono.setPixelRgba(x, y, 255, 255, 255, a);
      } else {
        mono.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
  }

  return mono;
}

/// Renders Splash Screen Centered Logo (512x512).
img.Image renderSplashLogo(int size) {
  return renderMasterIcon(size);
}

// ──────────────── Helper Geometry & Math Functions ────────────────

class _Color {
  final double r;
  final double g;
  final double b;
  final double a;

  _Color(num r, num g, num b, [num a = 255])
      : r = r.toDouble(),
        g = g.toDouble(),
        b = b.toDouble(),
        a = a.toDouble();
}

class _Point {
  final double x;
  final double y;
  _Point(this.x, this.y);
}

class _CompassPoint {
  final _Point tip;
  final _Point prevValley;
  final _Point nextValley;
  _CompassPoint({required this.tip, required this.prevValley, required this.nextValley});
}

_Color _lerpColor(_Color c1, _Color c2, double t) {
  return _Color(
    c1.r + (c2.r - c1.r) * t,
    c1.g + (c2.g - c1.g) * t,
    c1.b + (c2.b - c1.b) * t,
    c1.a + (c2.a - c1.a) * t,
  );
}

_Color _blend(_Color bg, _Color fg) {
  final alpha = fg.a / 255.0;
  final invAlpha = 1.0 - alpha;
  return _Color(
    fg.r * alpha + bg.r * invAlpha,
    fg.g * alpha + bg.g * invAlpha,
    fg.b * alpha + bg.b * invAlpha,
    math.max(bg.a, fg.a),
  );
}

double _sdRoundedBox(double px, double py, double halfW, double halfH, double r) {
  final qx = px.abs() - halfW + r;
  final qy = py.abs() - halfH + r;
  return math.min(math.max(qx, qy), 0.0) +
      math.sqrt(math.pow(math.max(qx, 0.0), 2) + math.pow(math.max(qy, 0.0), 2)) -
      r;
}

bool _pointInTriangle(_Point p, _Point a, _Point b, _Point c) {
  final d1 = _sign(p, a, b);
  final d2 = _sign(p, b, c);
  final d3 = _sign(p, c, a);

  final hasNeg = (d1 < 0) || (d2 < 0) || (d3 < 0);
  final hasPos = (d1 > 0) || (d2 > 0) || (d3 > 0);

  return !(hasNeg && hasPos);
}

double _sign(_Point p1, _Point p2, _Point p3) {
  return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y);
}

bool _pointInCornerBrackets({
  required double px,
  required double py,
  required double cx,
  required double cy,
  required double bracketDist,
  required double bracketArm,
  required double bracketWidth,
}) {
  final hw = bracketWidth / 2.0;

  // Top-Left: Corner at (cx - bracketDist, cy - bracketDist)
  final tlX = cx - bracketDist;
  final tlY = cy - bracketDist;
  if ((px - tlX).abs() <= hw && py >= tlY - hw && py <= tlY + bracketArm) return true;
  if ((py - tlY).abs() <= hw && px >= tlX - hw && px <= tlX + bracketArm) return true;

  // Top-Right: Corner at (cx + bracketDist, cy - bracketDist)
  final trX = cx + bracketDist;
  final trY = cy - bracketDist;
  if ((px - trX).abs() <= hw && py >= trY - hw && py <= trY + bracketArm) return true;
  if ((py - trY).abs() <= hw && px >= trX - bracketArm && px <= trX + hw) return true;

  // Bottom-Left: Corner at (cx - bracketDist, cy + bracketDist)
  final blX = cx - bracketDist;
  final blY = cy + bracketDist;
  if ((px - blX).abs() <= hw && py >= blY - bracketArm && py <= blY + hw) return true;
  if ((py - blY).abs() <= hw && px >= blX - hw && px <= blX + bracketArm) return true;

  // Bottom-Right: Corner at (cx + bracketDist, cy + bracketDist)
  final brX = cx + bracketDist;
  final brY = cy + bracketDist;
  if ((px - brX).abs() <= hw && py >= brY - bracketArm && py <= brY + hw) return true;
  if ((py - brY).abs() <= hw && px >= brX - bracketArm && px <= brX + hw) return true;

  return false;
}
