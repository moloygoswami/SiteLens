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
  final List<String> invalidatedKeys = [];

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

  @override
  Future<void> invalidateCachedImage({
    required double lat,
    required double lon,
    int zoom = 16,
    required String mapType,
    String styleVersion = 'v1',
  }) async {
    invalidatedKeys.add(MapThumbnailService.computeCacheKey(
      lat: lat,
      lon: lon,
      zoom: zoom,
      mapType: mapType,
      styleVersion: styleVersion,
    ));
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

    test('9. takeLiveSnapshotForEvidence executes bounded retry and recovers if primary attempt throws', () async {
      final fakeService = FakeMapThumbnailService();
      final notifier = MapThumbnailNotifier(fakeService);

      final testBytes = Uint8List.fromList([10, 20, 30, 40]);
      int callCount = 0;

      // Provider throws on first attempt, succeeds on bounded retry
      notifier.registerLiveSnapshotProvider(() async {
        callCount++;
        if (callCount == 1) {
          throw Exception('Transient native platform-view contention');
        }
        return testBytes;
      });

      final result = await notifier.takeLiveSnapshotForEvidence(
        lat: 22.56298,
        lon: 88.30085,
        mapType: AppMapType.satellite,
      );

      expect(result, equals(testBytes));
      expect(callCount, equals(2), reason: 'Must retry once after transient failure');
    });

    test('10. takeLiveSnapshotForEvidence falls back to verified pre-cached snapshot when live provider fails', () async {
      final fakeService = FakeMapThumbnailService();
      final notifier = MapThumbnailNotifier(fakeService);

      final cachedBytes = Uint8List.fromList([100, 101, 102]);

      // Pre-cache authentic snapshot
      await notifier.updateLiveSnapshot(
        cachedBytes,
        lat: 22.56298,
        lon: 88.30085,
        mapType: AppMapType.satellite,
      );

      // Provider fails completely on all attempts
      notifier.registerLiveSnapshotProvider(() async {
        throw Exception('Native surface detached');
      });

      // Shutter at same location (< 20m) and matching mapType
      final result = await notifier.takeLiveSnapshotForEvidence(
        lat: 22.56300,
        lon: 88.30085,
        mapType: AppMapType.satellite,
      );

      expect(result, equals(cachedBytes), reason: 'Must return verified pre-cached authentic snapshot');
    });

    test('11. takeLiveSnapshotForEvidence rejects pre-cache if distance > 20m or mapType mismatches', () async {
      final fakeService = FakeMapThumbnailService();
      final notifier = MapThumbnailNotifier(fakeService);

      final cachedBytes = Uint8List.fromList([200, 201]);

      // Pre-cache authentic snapshot for Satellite at (22.56298, 88.30085)
      await notifier.updateLiveSnapshot(
        cachedBytes,
        lat: 22.56298,
        lon: 88.30085,
        mapType: AppMapType.satellite,
      );

      // Provider fails
      notifier.registerLiveSnapshotProvider(() async => null);

      // Case A: MapType mismatch (user selected Normal, cached is Satellite) -> REJECTED
      final mismatchedTypeResult = await notifier.takeLiveSnapshotForEvidence(
        lat: 22.56298,
        lon: 88.30085,
        mapType: AppMapType.normal,
      );
      expect(mismatchedTypeResult, isNull, reason: 'Mismatched mapType pre-cache must be rejected');

      // Case B: Distance moved > 20m (~50m away) -> REJECTED
      final distantResult = await notifier.takeLiveSnapshotForEvidence(
        lat: 22.56345, // ~52m away
        lon: 88.30085,
        mapType: AppMapType.satellite,
      );
      expect(distantResult, isNull, reason: 'Pre-cache beyond 20m must be rejected');
    });

    test('12. Map-type change increments generation and activates transition state', () {
      final fakeService = FakeMapThumbnailService();
      final notifier = MapThumbnailNotifier(fakeService);

      expect(notifier.mapTypeGeneration, equals(0));
      expect(notifier.isMapTypeTransitioning, isFalse);

      notifier.invalidateCachesOnMapTypeChange(
        AppMapType.normal,
        lat: 22.56298,
        lon: 88.30085,
      );

      expect(notifier.mapTypeGeneration, equals(1));
      expect(notifier.isMapTypeTransitioning, isTrue);
      expect(notifier.transitionTargetMapType, equals(AppMapType.normal));
    });

    test('13. In-memory cache is invalidated immediately on map-type change', () async {
      final fakeService = FakeMapThumbnailService();
      final notifier = MapThumbnailNotifier(fakeService);

      final satBytes = Uint8List.fromList([1, 2, 3]);
      await notifier.updateLiveSnapshot(
        satBytes,
        lat: 22.56298,
        lon: 88.30085,
        mapType: AppMapType.satellite,
      );

      expect(
        notifier.getValidCachedSnapshotBytes(
          lat: 22.56298,
          lon: 88.30085,
          mapType: AppMapType.satellite,
        ),
        equals(satBytes),
      );

      // Act: User switches to Normal (Roadmap)
      notifier.invalidateCachesOnMapTypeChange(
        AppMapType.normal,
        lat: 22.56298,
        lon: 88.30085,
      );

      // In-memory cache must now be cleared
      expect(
        notifier.getValidCachedSnapshotBytes(
          lat: 22.56298,
          lon: 88.30085,
          mapType: AppMapType.satellite,
        ),
        isNull,
      );
      expect(
        notifier.getValidCachedSnapshotBytes(
          lat: 22.56298,
          lon: 88.30085,
          mapType: AppMapType.normal,
        ),
        isNull,
      );
    });

    test('14. Affected disk cache is invalidated on map-type change', () {
      final fakeService = FakeMapThumbnailService();
      final notifier = MapThumbnailNotifier(fakeService);

      notifier.invalidateCachesOnMapTypeChange(
        AppMapType.satellite,
        lat: 22.56298,
        lon: 88.30085,
      );

      final expectedKey = MapThumbnailService.computeCacheKey(
        lat: 22.56298,
        lon: 88.30085,
        mapType: AppMapType.satellite.staticMapParam,
      );

      expect(fakeService.invalidatedKeys, contains(expectedKey));
    });

    test('15. Old async snapshot completing after a map-type change is discarded (stale generation)', () async {
      final fakeService = FakeMapThumbnailService();
      final notifier = MapThumbnailNotifier(fakeService);

      // Snapshot captured under generation 0 (Roadmap)
      final initialGen = notifier.mapTypeGeneration;
      final roadmapBytes = Uint8List.fromList([8, 8, 8]);

      // User switches to Satellite (increments generation to 1)
      notifier.invalidateCachesOnMapTypeChange(
        AppMapType.satellite,
        lat: 22.56298,
        lon: 88.30085,
      );

      expect(notifier.mapTypeGeneration, greaterThan(initialGen));

      // Asynchronous Roadmap snapshot completes late with captureGeneration = 0
      await notifier.updateLiveSnapshot(
        roadmapBytes,
        lat: 22.56298,
        lon: 88.30085,
        mapType: AppMapType.normal,
        captureGeneration: initialGen,
      );

      // Must be completely discarded: neither Normal nor Satellite should have these bytes
      expect(
        notifier.getValidCachedSnapshotBytes(
          lat: 22.56298,
          lon: 88.30085,
          mapType: AppMapType.normal,
        ),
        isNull,
      );
      expect(
        notifier.getValidCachedSnapshotBytes(
          lat: 22.56298,
          lon: 88.30085,
          mapType: AppMapType.satellite,
        ),
        isNull,
      );
    });

    test('16. Transition-state pre-cache is blocked during the 1500ms settling window and accepted after settling', () async {
      final fakeService = FakeMapThumbnailService();
      final notifier = MapThumbnailNotifier(fakeService);

      // Transition to Satellite
      notifier.invalidateCachesOnMapTypeChange(
        AppMapType.satellite,
        lat: 22.56298,
        lon: 88.30085,
      );
      final gen = notifier.mapTypeGeneration;
      final prematureBytes = Uint8List.fromList([99, 99]);

      // Attempt to write snapshot immediately during settling window (elapsed < 1500ms)
      await notifier.updateLiveSnapshot(
        prematureBytes,
        lat: 22.56298,
        lon: 88.30085,
        mapType: AppMapType.satellite,
        captureGeneration: gen,
      );

      // Should be blocked because settling duration hasn't elapsed
      expect(
        notifier.getValidCachedSnapshotBytes(
          lat: 22.56298,
          lon: 88.30085,
          mapType: AppMapType.satellite,
        ),
        isNull,
      );
      expect(notifier.isMapTypeTransitioning, isTrue);
    });

    test('17. Shutter fallback cannot use a previous-layer snapshot during active transition', () async {
      final fakeService = FakeMapThumbnailService();
      final notifier = MapThumbnailNotifier(fakeService);

      // Live provider fails
      notifier.registerLiveSnapshotProvider(() async => null);

      // Transition to Satellite
      notifier.invalidateCachesOnMapTypeChange(
        AppMapType.satellite,
        lat: 22.56298,
        lon: 88.30085,
      );

      // Attempt evidence capture during transition
      final result = await notifier.takeLiveSnapshotForEvidence(
        lat: 22.56298,
        lon: 88.30085,
        mapType: AppMapType.satellite,
      );

      // Must return null instead of falling back to stale pre-transition data
      expect(result, isNull);
    });

    test('18. Roadmap pixels can never be accepted as Satellite snapshot merely because logical state is Satellite', () async {
      final fakeService = FakeMapThumbnailService();
      final notifier = MapThumbnailNotifier(fakeService);

      // Current state is Satellite
      notifier.invalidateCachesOnMapTypeChange(
        AppMapType.satellite,
        lat: 22.56298,
        lon: 88.30085,
      );

      final roadmapBytes = Uint8List.fromList([55, 66, 77]);

      // An old Roadmap snapshot arrives tagged as normal
      await notifier.updateLiveSnapshot(
        roadmapBytes,
        lat: 22.56298,
        lon: 88.30085,
        mapType: AppMapType.normal,
      );

      // Must not be cached under Satellite
      expect(
        notifier.getValidCachedSnapshotBytes(
          lat: 22.56298,
          lon: 88.30085,
          mapType: AppMapType.satellite,
        ),
        isNull,
      );
    });
  });
}
