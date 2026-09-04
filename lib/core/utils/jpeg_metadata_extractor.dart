import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../../features/camera/models/camera_ui_state.dart';

/// Lightweight JPEG dimension & orientation extractor that avoids full-frame bitmap decompression.
class JpegMetadataExtractor {
  final int rawWidth;
  final int rawHeight;
  final int orientation; // EXIF orientation: 1 (normal) to 8

  const JpegMetadataExtractor({
    required this.rawWidth,
    required this.rawHeight,
    this.orientation = 1,
  });

  /// True if EXIF orientation swaps width and height (90° or 270° rotation / transposition).
  bool get isTransposed => orientation >= 5 && orientation <= 8;

  int get orientedWidth => isTransposed ? rawHeight : rawWidth;
  int get orientedHeight => isTransposed ? rawWidth : rawHeight;

  /// Calculates the final cropped dimensions corresponding to [targetAspectRatio]
  /// after EXIF orientation is applied.
  (int, int) getTargetDimensions(CameraAspectRatio? targetAspectRatio) {
    return calculateCroppedDimensions(orientedWidth, orientedHeight, targetAspectRatio);
  }

  /// Calculates exact cropped dimensions matching the behavior of image cropping.
  static (int, int) calculateCroppedDimensions(
    int origW,
    int origH,
    CameraAspectRatio? aspectRatio,
  ) {
    if (aspectRatio == null) return (origW, origH);
    final isPortrait = origH >= origW;
    double targetRatio;
    switch (aspectRatio) {
      case CameraAspectRatio.ratioFull:
      case CameraAspectRatio.ratio16_9:
        targetRatio = isPortrait ? (9.0 / 16.0) : (16.0 / 9.0);
        break;
      case CameraAspectRatio.ratio4_3:
        targetRatio = isPortrait ? (3.0 / 4.0) : (4.0 / 3.0);
        break;
      case CameraAspectRatio.ratio1_1:
        targetRatio = 1.0;
        break;
    }

    final currentRatio = origW / origH;
    if ((currentRatio - targetRatio).abs() < 0.01) {
      return (origW, origH);
    }

    int cropW;
    int cropH;
    if (currentRatio > targetRatio) {
      cropH = origH;
      cropW = math.max(1, (origH * targetRatio).round());
    } else {
      cropW = origW;
      cropH = math.max(1, (origW / targetRatio).round());
    }
    return (cropW, cropH);
  }

  /// Parses JPEG headers directly from byte buffer in sub-millisecond time.
  static JpegMetadataExtractor extract(Uint8List bytes) {
    int? rawW;
    int? rawH;
    int orientation = 1;

    try {
      if (bytes.length > 4 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
        int offset = 2;
        final len = bytes.length;

        while (offset < len - 1) {
          if (bytes[offset] != 0xFF) {
            offset++;
            continue;
          }

          // Skip 0xFF fill bytes
          while (offset < len && bytes[offset] == 0xFF) {
            offset++;
          }
          if (offset >= len) break;

          final marker = bytes[offset++];
          if (marker == 0xD9 || marker == 0xDA) {
            // EOI or SOS (Start of Scan - image data begins)
            break;
          }

          if (offset + 1 >= len) break;
          final segmentLength = (bytes[offset] << 8) | bytes[offset + 1];
          if (segmentLength < 2 || offset + segmentLength > len) break;

          // SOF markers: SOF0 (0xC0), SOF1 (0xC1), SOF2 (0xC2), SOF3 (0xC3)
          if ((marker >= 0xC0 && marker <= 0xC3) || (marker >= 0xC5 && marker <= 0xC7) || (marker >= 0xC9 && marker <= 0xCB) || (marker >= 0xCD && marker <= 0xCF)) {
            if (segmentLength >= 7 && offset + 7 <= len) {
              rawH = (bytes[offset + 3] << 8) | bytes[offset + 4];
              rawW = (bytes[offset + 5] << 8) | bytes[offset + 6];
            }
          }
          // APP1 (0xE1) marker: EXIF metadata
          else if (marker == 0xE1 && segmentLength >= 14) {
            final exifOffset = offset + 2;
            if (bytes[exifOffset] == 0x45 && // 'E'
                bytes[exifOffset + 1] == 0x78 && // 'x'
                bytes[exifOffset + 2] == 0x69 && // 'i'
                bytes[exifOffset + 3] == 0x66 && // 'f'
                bytes[exifOffset + 4] == 0x00 &&
                bytes[exifOffset + 5] == 0x00) {
              final tiffStart = exifOffset + 6;
              final parsedOrient = _parseExifOrientation(bytes, tiffStart, offset + segmentLength);
              if (parsedOrient != null && parsedOrient >= 1 && parsedOrient <= 8) {
                orientation = parsedOrient;
              }
            }
          }

          offset += segmentLength;
          if (rawW != null && rawH != null && orientation != 1) {
            // Found both dimensions and EXIF orientation
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('[JpegMetadataExtractor] Lightweight header parsing warning: $e');
    }

    // Robust fallback: if lightweight parser did not find dimensions, decode info via package:image
    if (rawW == null || rawH == null || rawW == 0 || rawH == 0) {
      try {
        final info = img.decodeJpg(bytes);
        if (info != null) {
          rawW = info.width;
          rawH = info.height;
        }
      } catch (_) {}
    }

    return JpegMetadataExtractor(
      rawWidth: rawW ?? 1920,
      rawHeight: rawH ?? 1080,
      orientation: orientation,
    );
  }

  static int? _parseExifOrientation(Uint8List bytes, int tiffStart, int maxOffset) {
    if (tiffStart + 8 > maxOffset) return null;

    final isLittleEndian = bytes[tiffStart] == 0x49 && bytes[tiffStart + 1] == 0x49; // 'II'
    final isBigEndian = bytes[tiffStart] == 0x4D && bytes[tiffStart + 1] == 0x4D; // 'MM'
    if (!isLittleEndian && !isBigEndian) return null;

    int readUint16(int offset) {
      if (isLittleEndian) {
        return bytes[offset] | (bytes[offset + 1] << 8);
      } else {
        return (bytes[offset] << 8) | bytes[offset + 1];
      }
    }

    int readUint32(int offset) {
      if (isLittleEndian) {
        return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24);
      } else {
        return (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3];
      }
    }

    final ifd0Offset = readUint32(tiffStart + 4);
    int currentOffset = tiffStart + ifd0Offset;
    if (currentOffset + 2 > maxOffset) return null;

    final numEntries = readUint16(currentOffset);
    currentOffset += 2;

    for (int i = 0; i < numEntries; i++) {
      if (currentOffset + 12 > maxOffset) break;
      final tag = readUint16(currentOffset);
      if (tag == 0x0112) {
        // Orientation tag
        final val = readUint16(currentOffset + 8);
        return val;
      }
      currentOffset += 12;
    }
    return null;
  }
}
