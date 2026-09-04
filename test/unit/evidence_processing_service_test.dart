import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sitelens/core/utils/crypto_utils.dart';
import 'package:sitelens/features/camera/models/camera_ui_state.dart';
import 'package:sitelens/features/camera/models/evidence_metadata_snapshot.dart';
import 'package:sitelens/features/camera/services/evidence_processing_service.dart';
import 'package:sitelens/features/camera/services/evidence_storage_service.dart';

class MockEvidenceStorageService extends EvidenceStorageService {
  final Map<String, Uint8List> savedFiles = {};
  bool shouldFailEvidenceSave = false;

  @override
  Future<String> saveOriginalBytes(
      Uint8List originalBytes, String mediaId) async {
    final path = '/mock/media/orig_$mediaId.jpg';
    savedFiles[path] = Uint8List.fromList(originalBytes);
    return path;
  }

  @override
  Future<Map<String, String>> saveEvidenceAndThumbnail({
    required String mediaId,
    required Uint8List evidenceBytes,
    required Uint8List thumbnailBytes,
  }) async {
    if (shouldFailEvidenceSave) {
      throw Exception('Simulated disk write failure');
    }
    final evidPath = '/mock/media/evid_$mediaId.jpg';
    final thumbPath = '/mock/media/thumb_$mediaId.jpg';
    savedFiles[evidPath] = Uint8List.fromList(evidenceBytes);
    savedFiles[thumbPath] = Uint8List.fromList(thumbnailBytes);
    return {
      'evidencePath': evidPath,
      'thumbnailPath': thumbPath,
    };
  }

  @override
  Future<void> cleanupPartialArtifacts(String mediaId) async {
    savedFiles.remove('/mock/media/evid_$mediaId.jpg');
    savedFiles.remove('/mock/media/thumb_$mediaId.jpg');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EvidenceProcessingService Unit Tests', () {
    late MockEvidenceStorageService mockStorage;
    late EvidenceProcessingService processingService;
    late Uint8List sampleJpegBytes;

    setUp(() {
      mockStorage = MockEvidenceStorageService();
      processingService = EvidenceProcessingService(mockStorage);

      // Create a test 400x300 JPEG image
      final testImg = img.Image(width: 400, height: 300);
      img.fill(testImg, color: img.ColorRgb8(120, 150, 180));
      sampleJpegBytes = Uint8List.fromList(img.encodeJpg(testImg));
    });

    final sampleSnapshot = EvidenceMetadataSnapshot(
      mediaId: 'test-evidence-uuid-1',
      siteId: 'SITE_001',
      siteCode: 'HOME',
      siteName: 'Sonar Kella Apartment',
      latitude: 22.56298,
      longitude: 88.30085,
      altitudeMeters: -43.4,
      accuracyMeters: 7.6,
      lowAccuracy: false,
      capturedAtUtc: DateTime.utc(2026, 8, 15, 2, 24, 55),
      canonicalTimestampUtc: '2026-08-15 02:24:55 UTC',
      resolvedAddress: 'Sonar Kella Apartment, Kolkata',
    );

    test(
        'Preserves original bytes untouched and computes deterministic SHA-256',
        () async {
      final initialSha = CryptoUtils.computeSha256(sampleJpegBytes);
      final rawCopy = Uint8List.fromList(sampleJpegBytes);

      final result = await processingService.processCapture(
        originalBytes: sampleJpegBytes,
        snapshot: sampleSnapshot,
      );

      expect(result.isSuccess, isTrue);
      expect(result.originalSha256, initialSha);
      expect(result.originalFileSizeBytes, rawCopy.length);

      // Verify original bytes saved in storage are byte-identical
      final savedOriginal = mockStorage
          .savedFiles['/mock/media/orig_${sampleSnapshot.mediaId}.jpg'];
      expect(savedOriginal, isNotNull);
      expect(savedOriginal, equals(rawCopy));
    });

    test(
        'Generates thumbnail with maximum dimension <= 200px and preserved aspect ratio',
        () async {
      final result = await processingService.processCapture(
        originalBytes: sampleJpegBytes,
        snapshot: sampleSnapshot,
      );

      expect(result.isSuccess, isTrue);
      expect(result.thumbnailWidth, 200);
      expect(result.thumbnailHeight, 150); // 400x300 -> 200x150
      expect(result.thumbnailFileSizeBytes, isNotNull);
      expect(result.thumbnailFileSizeBytes!, greaterThan(0));
    });

    test('Generates portrait thumbnail with maximum dimension <= 200px',
        () async {
      // 300x400 portrait image
      final portraitImg = img.Image(width: 300, height: 400);
      img.fill(portraitImg, color: img.ColorRgb8(100, 100, 100));
      final portraitBytes = Uint8List.fromList(img.encodeJpg(portraitImg));

      final result = await processingService.processCapture(
        originalBytes: portraitBytes,
        snapshot: sampleSnapshot,
      );

      expect(result.isSuccess, isTrue);
      expect(result.thumbnailHeight, 200);
      expect(result.thumbnailWidth, 150); // 300x400 -> 150x200
    });

    test('Derived evidence image has non-circular SHA-256 hash', () async {
      final result = await processingService.processCapture(
        originalBytes: sampleJpegBytes,
        snapshot: sampleSnapshot,
      );

      expect(result.isSuccess, isTrue);
      expect(result.evidenceSha256, isNotNull);
      expect(result.evidenceSha256!.length, 64);
      // Evidence hash and original hash are distinct
      expect(result.evidenceSha256, isNot(equals(result.originalSha256)));
    });

    test(
        'Atomically cleans up partial artifacts on storage failure while preserving original',
        () async {
      mockStorage.shouldFailEvidenceSave = true;

      final result = await processingService.processCapture(
        originalBytes: sampleJpegBytes,
        snapshot: sampleSnapshot,
      );

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('Simulated disk write failure'));

      // Original bytes are preserved
      expect(
          mockStorage.savedFiles
              .containsKey('/mock/media/orig_${sampleSnapshot.mediaId}.jpg'),
          isTrue);

      // Derived evidence & thumbnail files are cleaned up
      expect(
          mockStorage.savedFiles
              .containsKey('/mock/media/evid_${sampleSnapshot.mediaId}.jpg'),
          isFalse);
      expect(
          mockStorage.savedFiles
              .containsKey('/mock/media/thumb_${sampleSnapshot.mediaId}.jpg'),
          isFalse);
    });

    test('Crops evidence photo to 1:1 aspect ratio when ratio1_1 is requested',
        () async {
      // 400x300 image -> 1:1 crop should yield 300x300 thumbnail
      final result = await processingService.processCapture(
        originalBytes: sampleJpegBytes,
        snapshot: sampleSnapshot,
        targetAspectRatio: CameraAspectRatio.ratio1_1,
      );

      expect(result.isSuccess, isTrue);
      expect(result.thumbnailWidth, 200);
      expect(result.thumbnailHeight, 200);
    });

    test(
        'Gallery thumbnail is derived from burned Evidence JPEG and contains the evidence HUD',
        () async {
      // Create a solid white 400x300 original image
      final whiteImg = img.Image(width: 400, height: 300);
      img.fill(whiteImg, color: img.ColorRgb8(255, 255, 255));
      final whiteBytes = Uint8List.fromList(img.encodeJpg(whiteImg));

      final result = await processingService.processCapture(
        originalBytes: whiteBytes,
        snapshot: sampleSnapshot,
      );

      expect(result.isSuccess, isTrue);

      // 1. Saved original remains pure untouched white
      final savedOriginal = mockStorage
          .savedFiles['/mock/media/orig_${sampleSnapshot.mediaId}.jpg']!;
      final decodedOrig = img.decodeImage(savedOriginal)!;
      final origBottomPixel = decodedOrig.getPixel(200, 280);
      expect(origBottomPixel.r, 255);
      expect(origBottomPixel.g, 255);
      expect(origBottomPixel.b, 255);

      // 2. Saved evidence JPEG has dark watermark container pixels in bottom region
      final savedEvidence = mockStorage
          .savedFiles['/mock/media/evid_${sampleSnapshot.mediaId}.jpg']!;
      final decodedEvid = img.decodeImage(savedEvidence)!;
      final evidBottomPixel = decodedEvid.getPixel(200, 280);
      expect(evidBottomPixel.b, isNot(255));

      // 3. Saved thumbnail is derived from evidenceCanvas and contains the burned HUD (dark bottom pixels)
      final savedThumb = mockStorage
          .savedFiles['/mock/media/thumb_${sampleSnapshot.mediaId}.jpg']!;
      final decodedThumb = img.decodeImage(savedThumb)!;
      expect(decodedThumb.width, 200);
      expect(decodedThumb.height, 150);
      final thumbBottomPixel = decodedThumb.getPixel(100, 140);
      expect(thumbBottomPixel.b, isNot(255));
    });

    test(
        'processCapture preserves portrait orientation canonical to portrait capture policy',
        () async {
      // Create a vertical 300x400 portrait image
      final portraitImg = img.Image(width: 300, height: 400);
      img.fill(portraitImg, color: img.ColorRgb8(100, 150, 200));
      final portraitBytes = Uint8List.fromList(img.encodeJpg(portraitImg));

      final result = await processingService.processCapture(
        originalBytes: portraitBytes,
        snapshot: sampleSnapshot,
      );

      expect(result.isSuccess, isTrue);

      final savedEvidence = mockStorage
          .savedFiles['/mock/media/evid_${sampleSnapshot.mediaId}.jpg']!;
      final decodedEvid = img.decodeImage(savedEvidence)!;

      // Evidence MUST remain portrait: height > width
      expect(decodedEvid.height, greaterThan(decodedEvid.width));
      expect(decodedEvid.width, 300);
      expect(decodedEvid.height, 400);

      // Thumbnail must also remain portrait
      final savedThumb = mockStorage
          .savedFiles['/mock/media/thumb_${sampleSnapshot.mediaId}.jpg']!;
      final decodedThumb = img.decodeImage(savedThumb)!;
      expect(decodedThumb.height, greaterThan(decodedThumb.width));
    });
  });
}
