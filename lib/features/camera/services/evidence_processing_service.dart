import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import '../../../core/utils/crypto_utils.dart';
import '../../../core/utils/jpeg_metadata_extractor.dart';
import '../hud/hud_formatter.dart';
import '../models/camera_ui_state.dart';
import '../models/evidence_metadata_snapshot.dart';
import '../models/processed_evidence_payload.dart';
import 'evidence_storage_service.dart';
import 'watermark_drawer.dart';

final evidenceProcessingServiceProvider =
    Provider<EvidenceProcessingService>((ref) {
  final storageService = ref.watch(evidenceStorageServiceProvider);
  return EvidenceProcessingService(storageService);
});

class _IsolateInput {
  final Uint8List originalBytes;
  final Uint8List? hudPngBytes;
  final CameraAspectRatio? targetAspectRatio;

  _IsolateInput({
    required this.originalBytes,
    this.hudPngBytes,
    this.targetAspectRatio,
  });
}

class _IsolateOutput {
  final Uint8List evidenceBytes;
  final Uint8List thumbnailBytes;
  final String evidenceSha256;
  final int thumbnailWidth;
  final int thumbnailHeight;

  _IsolateOutput({
    required this.evidenceBytes,
    required this.thumbnailBytes,
    required this.evidenceSha256,
    required this.thumbnailWidth,
    required this.thumbnailHeight,
  });
}

/// Center crops [image] to match the desired [aspectRatio].
img.Image _cropToAspectRatio(img.Image image, CameraAspectRatio aspectRatio) {
  final origW = image.width;
  final origH = image.height;
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
    return image;
  }

  int cropW;
  int cropH;
  if (currentRatio > targetRatio) {
    // Image is wider than target -> crop horizontal edges symmetrically
    cropH = origH;
    cropW = math.max(1, (origH * targetRatio).round());
  } else {
    // Image is taller than target -> crop vertical edges symmetrically
    cropW = origW;
    cropH = math.max(1, (origW / targetRatio).round());
  }

  final cropX = (origW - cropW) ~/ 2;
  final cropY = (origH - cropH) ~/ 2;

  return img.copyCrop(
    image,
    x: cropX,
    y: cropY,
    width: cropW,
    height: cropH,
  );
}

/// Top-level worker function executing strictly inside background Isolate.
_IsolateOutput _processImageWorker(_IsolateInput input) {
  final decoded = img.decodeImage(input.originalBytes);
  if (decoded == null) {
    throw Exception('Failed to decode camera image bytes');
  }

  // 1. Bake EXIF orientation so orientation is canonicalized
  var orientedImage = img.bakeOrientation(decoded);

  // 1.5 Center crop to match selected framing aspect ratio if requested
  if (input.targetAspectRatio != null) {
    orientedImage = _cropToAspectRatio(orientedImage, input.targetAspectRatio!);
  }

  // 2. Composite high-DPI vector HUD rendered on the UI isolate directly into orientedImage
  if (input.hudPngBytes != null && input.hudPngBytes!.isNotEmpty) {
    final hudImg = img.decodePng(input.hudPngBytes!);
    if (hudImg != null) {
      img.compositeImage(orientedImage, hudImg);
    }
  }

  final evidenceBytes =
      Uint8List.fromList(img.encodeJpg(orientedImage, quality: 95));
  final evidenceSha256 = CryptoUtils.computeSha256(evidenceBytes);

  // 3. Generate 200px Max-Dimension Thumbnail from burned Evidence JPEG
  final evidW = orientedImage.width;
  final evidH = orientedImage.height;

  int thumbW;
  int thumbH;
  if (evidW >= evidH) {
    thumbW = 200;
    thumbH = math.max(1, (200 * evidH / evidW).round());
  } else {
    thumbH = 200;
    thumbW = math.max(1, (200 * evidW / evidH).round());
  }

  final thumbnailImage = img.copyResize(
    orientedImage,
    width: thumbW,
    height: thumbH,
    interpolation: img.Interpolation.linear,
  );

  final thumbnailBytes =
      Uint8List.fromList(img.encodeJpg(thumbnailImage, quality: 80));

  return _IsolateOutput(
    evidenceBytes: evidenceBytes,
    thumbnailBytes: thumbnailBytes,
    evidenceSha256: evidenceSha256,
    thumbnailWidth: thumbW,
    thumbnailHeight: thumbH,
  );
}

class EvidenceProcessingService {
  final EvidenceStorageService _storageService;

  EvidenceProcessingService(this._storageService);

  /// Processes raw camera capture using hybrid vector HUD rendering + background JPEG isolate.
  Future<ProcessedEvidencePayload> processCapture({
    required Uint8List originalBytes,
    required EvidenceMetadataSnapshot snapshot,
    Uint8List? mapTileBytes,
    bool isGpsLocked = true,
    bool showAddress = true,
    bool showMapTile = true,
    CameraAspectRatio? targetAspectRatio,
  }) async {
    final originalFileSizeBytes = originalBytes.length;

    // 1. Compute original immutable SHA-256 hash immediately
    final originalSha256 = CryptoUtils.computeSha256(originalBytes);

    // 2. Persist original camera bytes untouched
    final originalFilePath = await _storageService.saveOriginalBytes(
      originalBytes,
      snapshot.mediaId,
    );

    try {
      // 3. Determine target image dimensions on UI isolate using lightweight header parser (no full decode)
      final metadata = JpegMetadataExtractor.extract(originalBytes);
      final (targetW, targetH) = metadata.getTargetDimensions(
        targetAspectRatio,
      );

      // 4. Adapt snapshot to canonical HudData and render native vector HUD using dart:ui on UI isolate (~20ms)
      final hudData = HudFormatter.fromSnapshot(
        snapshot: snapshot,
        originalSha256: originalSha256,
        isGpsLocked: isGpsLocked,
        showAddress: showAddress,
        showMinimap: showMapTile,
        headingDegrees: snapshot.headingDegrees,
      );

      Uint8List? hudPngBytes;
      try {
        hudPngBytes = await WatermarkDrawer.renderVectorHudPngFromData(
          width: targetW,
          height: targetH,
          hudData: hudData,
          mapTileBytes: mapTileBytes,
        );
      } catch (_) {
        hudPngBytes = null;
      }

      // 5. Offload CPU-heavy bitmap processing & JPEG encoding to background Isolate
      final isolateInput = _IsolateInput(
        originalBytes: originalBytes,
        hudPngBytes: hudPngBytes,
        targetAspectRatio: targetAspectRatio,
      );

      final isolateResult =
          await Isolate.run(() => _processImageWorker(isolateInput));

      // 6. Save derived evidence and thumbnail files atomically
      final paths = await _storageService.saveEvidenceAndThumbnail(
        mediaId: snapshot.mediaId,
        evidenceBytes: isolateResult.evidenceBytes,
        thumbnailBytes: isolateResult.thumbnailBytes,
      );

      return ProcessedEvidencePayload(
        isSuccess: true,
        mediaId: snapshot.mediaId,
        originalFilePath: originalFilePath,
        evidenceFilePath: paths['evidencePath'],
        thumbnailFilePath: paths['thumbnailPath'],
        originalSha256: originalSha256,
        evidenceSha256: isolateResult.evidenceSha256,
        originalFileSizeBytes: originalFileSizeBytes,
        evidenceFileSizeBytes: isolateResult.evidenceBytes.length,
        thumbnailFileSizeBytes: isolateResult.thumbnailBytes.length,
        thumbnailWidth: isolateResult.thumbnailWidth,
        thumbnailHeight: isolateResult.thumbnailHeight,
        metadataSnapshot: snapshot,
      );
    } catch (e) {
      // 7. Clean up partial derived artifacts on failure while preserving original bytes
      await _storageService.cleanupPartialArtifacts(snapshot.mediaId);

      return ProcessedEvidencePayload.failure(
        mediaId: snapshot.mediaId,
        originalFilePath: originalFilePath,
        originalSha256: originalSha256,
        originalFileSizeBytes: originalFileSizeBytes,
        metadataSnapshot: snapshot,
        errorMessage: 'Evidence processing failed: $e',
      );
    }
  }
}
