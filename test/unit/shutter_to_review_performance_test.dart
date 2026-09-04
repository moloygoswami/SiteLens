import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sitelens/core/controllers/map_type_settings_controller.dart';
import 'package:sitelens/core/services/map_thumbnail_service.dart';
import 'package:sitelens/core/utils/jpeg_metadata_extractor.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/features/camera/models/camera_ui_state.dart';
import 'package:sitelens/features/camera/models/evidence_metadata_snapshot.dart';
import 'package:sitelens/features/camera/models/processed_evidence_payload.dart';
import 'package:sitelens/features/review/models/pending_capture_payload.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Satellite Minimap & Map Configuration Pipeline Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('1. No saved map preference -> defaults to AppMapType.satellite', () {
      final notifier = MapTypeSettingsNotifier();
      expect(notifier.state, equals(AppMapType.satellite));
      expect(notifier.state.staticMapParam, equals('satellite'));
    });

    test('2. Explicit saved normal preference is preserved without override', () async {
      SharedPreferences.setMockInitialValues({'setting_map_type': 'normal'});
      final notifier = MapTypeSettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(notifier.state, equals(AppMapType.normal));
      expect(notifier.state.staticMapParam, equals('roadmap'));
    });

    test('3. Explicit saved satellite preference is preserved without override', () async {
      SharedPreferences.setMockInitialValues({'setting_map_type': 'satellite'});
      final notifier = MapTypeSettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(notifier.state, equals(AppMapType.satellite));
      expect(notifier.state.staticMapParam, equals('satellite'));
    });

    test('4. MapThumbnailService cache key computation defaults to satellite', () {
      final key = MapThumbnailService.computeCacheKey(lat: 22.57, lon: 88.36);
      final expectedHash = MapThumbnailService.computeCacheKey(
        lat: 22.57,
        lon: 88.36,
        mapType: 'satellite',
      );
      expect(key, equals(expectedHash));
    });

    test('5. AppMapType.fromString returns satellite for null, empty, or unknown strings', () {
      expect(AppMapType.fromString(null), equals(AppMapType.satellite));
      expect(AppMapType.fromString(''), equals(AppMapType.satellite));
      expect(AppMapType.fromString('unknown_type'), equals(AppMapType.satellite));
      expect(AppMapType.fromString('normal'), equals(AppMapType.normal));
      expect(AppMapType.fromString('roadmap'), equals(AppMapType.normal));
      expect(AppMapType.fromString('satellite'), equals(AppMapType.satellite));
    });
  });

  group('JpegMetadataExtractor Unit Tests', () {
    test('Extracts JPEG dimensions accurately without full bitmap decode', () {
      // Create a test synthetic JPEG image (1200x800)
      final testImage = img.Image(width: 1200, height: 800);
      final jpegBytes = Uint8List.fromList(img.encodeJpg(testImage));

      final extracted = JpegMetadataExtractor.extract(jpegBytes);
      expect(extracted.rawWidth, equals(1200));
      expect(extracted.rawHeight, equals(800));
      expect(extracted.orientedWidth, equals(1200));
      expect(extracted.orientedHeight, equals(800));

      final (crop43W, crop43H) = extracted.getTargetDimensions(CameraAspectRatio.ratio4_3);
      expect(crop43W, equals(1067)); // 800 * 4/3
      expect(crop43H, equals(800));

      final (crop11W, crop11H) = extracted.getTargetDimensions(CameraAspectRatio.ratio1_1);
      expect(crop11W, equals(800));
      expect(crop11H, equals(800));
    });
  });

  group('In-Flight Capture State & Async Processing Tests', () {
    final mockSnapshot = EvidenceMetadataSnapshot(
      mediaId: 'test_media_001',
      siteId: 'site_100',
      siteCode: 'SITE-100',
      siteName: 'Main Terminal',
      latitude: 22.5726,
      longitude: 88.3639,
      accuracyMeters: 3.2,
      altitudeMeters: 14.5,
      lowAccuracy: false,
      canonicalTimestampUtc: '2026-09-01T12:00:00Z',
      capturedAtUtc: DateTime.utc(2026, 9, 1, 12, 0, 0),
      creatorId: 'user_001',
      resolvedAddress: 'Park Street, Kolkata',
    );

    test('6. PendingCapturePayload holds in-flight processing future and provisional preview', () {
      final completer = Completer<ProcessedEvidencePayload>();
      final payload = PendingCapturePayload(
        mediaId: 'test_media_001',
        mediaType: MediaItemType.photo,
        originalFilePath: 'media/orig_test_media_001.jpg',
        evidenceFilePath: null,
        thumbnailFilePath: null,
        sha256Hash: 'original_sha256_hash',
        fileSizeBytes: 1024000,
        metadataSnapshot: mockSnapshot,
        previewBytes: Uint8List.fromList([1, 2, 3, 4]),
        processingFuture: completer.future,
      );

      expect(payload.isPhoto, isTrue);
      expect(payload.evidenceFilePath, isNull);
      expect(payload.previewBytes, isNotNull);
      expect(payload.isCancelled, isFalse);
    });

    test('7. Retake marks in-flight processing as cancelled', () {
      final completer = Completer<ProcessedEvidencePayload>();
      final payload = PendingCapturePayload(
        mediaId: 'test_media_002',
        mediaType: MediaItemType.photo,
        originalFilePath: 'media/orig_test_media_002.jpg',
        sha256Hash: 'hash',
        fileSizeBytes: 500,
        metadataSnapshot: mockSnapshot,
        processingFuture: completer.future,
      );

      payload.cancelProcessing();
      expect(payload.isCancelled, isTrue);
    });

    test('8. copyWith correctly updates payload when canonical evidence completes', () async {
      final payload = PendingCapturePayload(
        mediaId: 'test_media_003',
        mediaType: MediaItemType.photo,
        originalFilePath: 'media/orig_test_media_003.jpg',
        evidenceFilePath: null,
        thumbnailFilePath: null,
        sha256Hash: 'hash',
        fileSizeBytes: 500,
        metadataSnapshot: mockSnapshot,
      );

      final updated = payload.copyWith(
        evidenceFilePath: 'media/evid_test_media_003.jpg',
        thumbnailFilePath: 'media/thumb_test_media_003.jpg',
      );

      expect(updated.evidenceFilePath, equals('media/evid_test_media_003.jpg'));
      expect(updated.thumbnailFilePath, equals('media/thumb_test_media_003.jpg'));
    });
  });
}
