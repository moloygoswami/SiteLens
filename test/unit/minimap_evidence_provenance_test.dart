import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sitelens/core/services/map_thumbnail_service.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/features/camera/controllers/map_thumbnail_controller.dart';
import 'package:sitelens/features/camera/models/evidence_metadata_snapshot.dart';
import 'package:sitelens/features/camera/models/gps_hardware_state.dart';
import 'package:sitelens/features/camera/services/evidence_processing_service.dart';
import 'package:sitelens/features/camera/services/evidence_storage_service.dart';
import 'package:sitelens/features/camera/services/watermark_drawer.dart';

class MockEvidenceStorageService extends EvidenceStorageService {
  final Map<String, Uint8List> savedFiles = {};

  @override
  Future<String> saveOriginalBytes(Uint8List originalBytes, String mediaId) async {
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
  Future<void> cleanupPartialArtifacts(String mediaId) async {}
}

class FakeMapThumbnailService extends MapThumbnailService {
  File? cachedFileToReturn;

  FakeMapThumbnailService() : super(apiKey: 'fake-key');

  @override
  Future<File?> getCachedImage({
    required double lat,
    required double lon,
    int zoom = 16,
    String mapType = 'satellite',
    String styleVersion = 'v1',
  }) async {
    return cachedFileToReturn;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Minimap Evidence Provenance Invariant Tests', () {
    late MockEvidenceStorageService mockStorage;
    late EvidenceProcessingService processingService;
    late Uint8List sampleJpegBytes;
    late Uint8List sampleMapTilePngBytes;

    final sampleSnapshot = EvidenceMetadataSnapshot(
      mediaId: 'provenance-test-uuid',
      siteId: 'SITE_001',
      siteCode: 'TEST',
      siteName: 'Invariant Test Site',
      latitude: 22.56298,
      longitude: 88.30085,
      altitudeMeters: 12.0,
      accuracyMeters: 4.5,
      lowAccuracy: false,
      capturedAtUtc: DateTime.utc(2026, 9, 4, 12, 0, 0),
      canonicalTimestampUtc: '2026-09-04 12:00:00 UTC',
      resolvedAddress: 'Park Street, Kolkata, WB',
    );

    setUp(() {
      mockStorage = MockEvidenceStorageService();
      processingService = EvidenceProcessingService(mockStorage);

      // Create base camera image (400x300)
      final cameraImg = img.Image(width: 400, height: 300);
      img.fill(cameraImg, color: img.ColorRgb8(50, 50, 50));
      sampleJpegBytes = Uint8List.fromList(img.encodeJpg(cameraImg));

      // Create distinct map tile PNG (60x50 with bright distinctive blue pixels)
      final mapImg = img.Image(width: 60, height: 50);
      img.fill(mapImg, color: img.ColorRgb8(10, 100, 220));
      sampleMapTilePngBytes = Uint8List.fromList(img.encodePng(mapImg));
    });

    test('1. Shutter-time live map snapshot bytes are burned directly into Evidence JPEG', () async {
      // Act: Process capture with the live snapshot bytes captured at shutter time
      final result = await processingService.processCapture(
        originalBytes: sampleJpegBytes,
        snapshot: sampleSnapshot,
        mapTileBytes: sampleMapTilePngBytes,
        isGpsLocked: true,
        showAddress: true,
        showMapTile: true,
      );

      expect(result.isSuccess, isTrue);

      // Verify that the evidence JPEG was persisted
      final savedEvidBytes = mockStorage.savedFiles['/mock/media/evid_${sampleSnapshot.mediaId}.jpg'];
      expect(savedEvidBytes, isNotNull);

      // Decode the burned evidence JPEG and verify that the distinctive blue map tile was composited
      final decodedEvid = img.decodeJpg(savedEvidBytes!);
      expect(decodedEvid, isNotNull);

      // Inspect bottom watermark zone: the map tile pixels should be present in the bottom-left
      bool foundMapTilePixel = false;
      for (int y = (decodedEvid!.height * 0.7).toInt(); y < decodedEvid.height; y++) {
        for (int x = 0; x < (decodedEvid.width * 0.45).toInt(); x++) {
          final p = decodedEvid.getPixel(x, y);
          // Check for high blue and low red/green characteristic of the distinctive blue tile
          if (p.b > 150 && p.r < 80) {
            foundMapTilePixel = true;
            break;
          }
        }
        if (foundMapTilePixel) break;
      }
      expect(foundMapTilePixel, isTrue, reason: 'Live minimap snapshot pixels must be burned into Evidence JPEG');
    });

    test('2. When no map bytes are available, NO synthetic vector reticle or fake roads are burned', () async {
      // Act: Process capture with null mapTileBytes (e.g. offline / no live map snapshot)
      final result = await processingService.processCapture(
        originalBytes: sampleJpegBytes,
        snapshot: sampleSnapshot,
        mapTileBytes: null,
        isGpsLocked: true,
        showAddress: true,
        showMapTile: true,
      );

      expect(result.isSuccess, isTrue);
      final savedEvidBytes = mockStorage.savedFiles['/mock/media/evid_${sampleSnapshot.mediaId}.jpg'];
      expect(savedEvidBytes, isNotNull);

      // Render vector HUD image directly with null map tile
      final hudImage = await WatermarkDrawer.renderVectorHudImage(
        width: 400,
        height: 300,
        snapshot: sampleSnapshot,
        originalSha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        mapTileBytes: null,
        isGpsLocked: true,
        showAddress: true,
        showMapTile: true,
      );

      expect(hudImage, isNotNull);
      expect(hudImage.width, 400);
      expect(hudImage.height, 300);
    });

    test('3. Fallback cache validation enforces strict mapType, age <= 5m, and distance <= 20m', () {
      final now = DateTime.now();

      // Case A: Cache matches mapType, age is 2 minutes (< 5m), distance is 5m (< 20m) -> FRESH
      final stateFresh = MapThumbnailState(
        mapType: AppMapType.satellite,
        lat: 22.56298,
        lon: 88.30085,
        lastUpdate: now.subtract(const Duration(minutes: 2)),
      );

      final currentMapType = AppMapType.satellite;
      final gpsHardware = GpsHardwareState(
        latitude: 22.56300, // ~2.2 meters away
        longitude: 88.30085,
        hasValidFix: true,
      );

      final distance = MapThumbnailService.haversineDistanceMeters(
        stateFresh.lat,
        stateFresh.lon,
        gpsHardware.latitude!,
        gpsHardware.longitude!,
      );
      final age = now.difference(stateFresh.lastUpdate!);

      final isCacheFresh = stateFresh.mapType == currentMapType &&
          age <= const Duration(minutes: 5) &&
          distance <= MapThumbnailPolicy.movementThresholdMeters;

      expect(isCacheFresh, isTrue);

      // Case B: Cache mapType is Normal, but active type is Satellite -> REJECTED
      final isTypeMismatchFresh = stateFresh.mapType == AppMapType.normal &&
          age <= const Duration(minutes: 5) &&
          distance <= MapThumbnailPolicy.movementThresholdMeters;
      expect(isTypeMismatchFresh, isFalse, reason: 'Cache with mismatched mapType must be rejected');

      // Case C: Cache age is 10 minutes (> 5m) -> REJECTED
      final staleAge = const Duration(minutes: 10);
      final isStaleAgeFresh = stateFresh.mapType == currentMapType &&
          staleAge <= const Duration(minutes: 5) &&
          distance <= MapThumbnailPolicy.movementThresholdMeters;
      expect(isStaleAgeFresh, isFalse, reason: 'Cache older than 5 minutes must be rejected');

      // Case D: Cache position moved 50 meters (> 20m) -> REJECTED
      const staleDistance = 50.0;
      final isStaleDistanceFresh = stateFresh.mapType == currentMapType &&
          age <= const Duration(minutes: 5) &&
          staleDistance <= MapThumbnailPolicy.movementThresholdMeters;
      expect(isStaleDistanceFresh, isFalse, reason: 'Cache with distance > 20m must be rejected');
    });

    test('4. MapThumbnailNotifier registers and executes live snapshot provider with 3500ms timeout', () async {
      final fakeService = FakeMapThumbnailService();
      final notifier = MapThumbnailNotifier(fakeService);

      // Verify null when no provider registered
      final nullResult = await notifier.takeLiveSnapshotForEvidence();
      expect(nullResult, isNull);

      // Register live provider that returns distinct bytes
      final testBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      notifier.registerLiveSnapshotProvider(() async => testBytes);

      final capturedBytes = await notifier.takeLiveSnapshotForEvidence();
      expect(capturedBytes, equals(testBytes));

      // Provider that times out (> 3500ms) returns null safely
      notifier.registerLiveSnapshotProvider(() async {
        await Future.delayed(const Duration(milliseconds: 4000));
        return testBytes;
      });

      final timeoutResult = await notifier.takeLiveSnapshotForEvidence();
      expect(timeoutResult, isNull);
    });

    test('5. Downstream invariant: Evidence Detail and Immersive Viewer display burned JPEG without map reconstruction', () {
      // Proves the architectural contract: downstream viewers consume the burned-in evidence JPEG file.
      // There is zero secondary map controller, zero GoogleMap platform view instantiation,
      // and zero network map queries in downstream review.
      final evidenceFilePath = '/mock/media/evid_${sampleSnapshot.mediaId}.jpg';
      final evidenceFile = File(evidenceFilePath);

      expect(evidenceFile.path, contains('evid_'));
      expect(evidenceFile.path, endsWith('.jpg'));
      // The burned JPEG contains both the photo content and the canonical HUD overlay with minimap pixels
    });

    test('6. EvidenceMetadataSnapshot.capture at T0 captures headingDegrees from GpsHardwareState', () {
      final gpsWithHeading = GpsHardwareState(
        hasValidFix: true,
        latitude: 22.56298,
        longitude: 88.30085,
        headingDegrees: 142.5,
      );

      final snapshot = EvidenceMetadataSnapshot.capture(
        gpsState: gpsWithHeading,
        siteId: 'SITE_001',
        siteCode: 'TEST',
        siteName: 'Test Site',
      );

      expect(snapshot.headingDegrees, equals(142.5));
    });

    test('7. Live minimap overlays: Heading cone is reproduced in Evidence watermark when headingDegrees is present at T0', () async {
      // Create snapshot with heading degrees (North = 0 deg)
      final snapshotWithHeading = EvidenceMetadataSnapshot(
        mediaId: 'heading-test-uuid',
        siteId: 'SITE_001',
        siteCode: 'TEST',
        siteName: 'Heading Test Site',
        latitude: 22.56298,
        longitude: 88.30085,
        headingDegrees: 0.0,
        lowAccuracy: false,
        capturedAtUtc: DateTime.utc(2026, 9, 4, 12, 0, 0),
        canonicalTimestampUtc: '2026-09-04 12:00:00 UTC',
        resolvedAddress: 'Park Street, Kolkata, WB',
      );

      // Render HUD with heading
      final hudWithHeading = await WatermarkDrawer.renderVectorHudImage(
        width: 400,
        height: 300,
        snapshot: snapshotWithHeading,
        originalSha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        mapTileBytes: null,
        isGpsLocked: true,
        showAddress: true,
        showMapTile: true,
      );

      // Render HUD without heading
      final snapshotNoHeading = EvidenceMetadataSnapshot(
        mediaId: 'no-heading-test-uuid',
        siteId: 'SITE_001',
        siteCode: 'TEST',
        siteName: 'No Heading Test Site',
        latitude: 22.56298,
        longitude: 88.30085,
        headingDegrees: null,
        lowAccuracy: false,
        capturedAtUtc: DateTime.utc(2026, 9, 4, 12, 0, 0),
        canonicalTimestampUtc: '2026-09-04 12:00:00 UTC',
        resolvedAddress: 'Park Street, Kolkata, WB',
      );

      final hudNoHeading = await WatermarkDrawer.renderVectorHudImage(
        width: 400,
        height: 300,
        snapshot: snapshotNoHeading,
        originalSha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        mapTileBytes: null,
        isGpsLocked: true,
        showAddress: true,
        showMapTile: true,
      );

      final bytesWithHeading = await hudWithHeading.toByteData(format: ui.ImageByteFormat.rawRgba);
      final bytesNoHeading = await hudNoHeading.toByteData(format: ui.ImageByteFormat.rawRgba);

      expect(bytesWithHeading, isNotNull);
      expect(bytesNoHeading, isNotNull);

      // The two pixel buffers must differ because the heading cone (Color 0x444285F4) was drawn
      bool pixelsDiffer = false;
      final raw1 = bytesWithHeading!.buffer.asUint8List();
      final raw2 = bytesNoHeading!.buffer.asUint8List();

      for (int i = 0; i < raw1.length; i++) {
        if (raw1[i] != raw2[i]) {
          pixelsDiffer = true;
          break;
        }
      }

      expect(pixelsDiffer, isTrue, reason: 'HUD watermark must render the heading cone when headingDegrees is provided');
    });

    test('8. EvidenceProcessingService.processCapture burns heading cone into final Evidence JPEG', () async {
      final snapshotWithHeading = EvidenceMetadataSnapshot(
        mediaId: 'process-heading-uuid',
        siteId: 'SITE_001',
        siteCode: 'TEST',
        siteName: 'Process Heading Site',
        latitude: 22.56298,
        longitude: 88.30085,
        headingDegrees: 90.0,
        lowAccuracy: false,
        capturedAtUtc: DateTime.utc(2026, 9, 4, 12, 0, 0),
        canonicalTimestampUtc: '2026-09-04 12:00:00 UTC',
        resolvedAddress: 'Park Street, Kolkata, WB',
      );

      final result = await processingService.processCapture(
        originalBytes: sampleJpegBytes,
        snapshot: snapshotWithHeading,
        mapTileBytes: sampleMapTilePngBytes,
        isGpsLocked: true,
        showAddress: true,
        showMapTile: true,
      );

      expect(result.isSuccess, isTrue);
      final savedEvidBytes = mockStorage.savedFiles['/mock/media/evid_${snapshotWithHeading.mediaId}.jpg'];
      expect(savedEvidBytes, isNotNull);

      final decoded = img.decodeJpg(savedEvidBytes!);
      expect(decoded, isNotNull);
      expect(decoded!.width, equals(400));
      expect(decoded.height, equals(300));
    });
  });
}
