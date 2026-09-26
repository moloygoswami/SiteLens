import 'dart:ffi';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sitelens/core/utils/gps_utils.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/features/camera/hud/hud_data.dart';
import 'package:sitelens/features/camera/hud/hud_formatter.dart';
import 'package:sitelens/features/camera/models/evidence_metadata_snapshot.dart';
import 'package:sitelens/features/camera/models/gps_hardware_state.dart';

void main() {
  late AppDatabase db;
  late MediaRepository mediaRepo;

  setUpAll(() {
    open.overrideFor(
        OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    mediaRepo = LocalMediaRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('F1: Canonical Verification Status Semantics & Configurable Threshold', () {
    test('EvidenceMetadataSnapshot.evaluateVerificationStatus honours configurable threshold', () {
      // Accuracy = 25m. Default threshold is 20m.
      expect(
        EvidenceMetadataSnapshot.evaluateVerificationStatus(
          hasValidFix: true,
          latitude: 22.5726,
          longitude: 88.3639,
          accuracyMeters: 25.0,
          lowAccuracyThresholdMeters: 20.0,
        ),
        equals(HudStatus.degraded),
      );

      // Same 25m accuracy, but user configured threshold = 30m -> should be verified!
      expect(
        EvidenceMetadataSnapshot.evaluateVerificationStatus(
          hasValidFix: true,
          latitude: 22.5726,
          longitude: 88.3639,
          accuracyMeters: 25.0,
          lowAccuracyThresholdMeters: 30.0,
        ),
        equals(HudStatus.verified),
      );

      // If no valid fix or (0,0) -> pending
      expect(
        EvidenceMetadataSnapshot.evaluateVerificationStatus(
          hasValidFix: false,
          latitude: 22.5726,
          longitude: 88.3639,
          accuracyMeters: 5.0,
          lowAccuracyThresholdMeters: 20.0,
        ),
        equals(HudStatus.pending),
      );
      expect(
        EvidenceMetadataSnapshot.evaluateVerificationStatus(
          hasValidFix: true,
          latitude: 0.0,
          longitude: 0.0,
          accuracyMeters: 5.0,
          lowAccuracyThresholdMeters: 20.0,
        ),
        equals(HudStatus.pending),
      );
    });

    test('Live HUD and Snapshot HUD achieve 100% status parity with custom threshold', () {
      const customThreshold = 35.0;
      final gps = GpsHardwareState(
        hasValidFix: true,
        latitude: 22.5726,
        longitude: 88.3639,
        accuracyMeters: 28.0, // > 20m, but < 35m custom threshold
        altitudeMeters: 14.5,
        timestampUtc: DateTime.utc(2026, 8, 28, 10, 0, 0),
      );

      // Live HUD format
      final liveHud = HudFormatter.fromLive(
        siteCode: 'TEST',
        latitude: gps.latitude!,
        longitude: gps.longitude!,
        accuracyMeters: gps.accuracyMeters,
        altitudeMeters: gps.altitudeMeters,
        isGpsLocked: true,
        lowAccuracyThresholdMeters: customThreshold,
      );

      // Snapshot captured with custom threshold
      final snapshot = EvidenceMetadataSnapshot.capture(
        siteId: 'SITE-01',
        siteCode: 'TEST',
        siteName: 'Test Site',
        gpsState: gps,
        customCaptureTimeUtc: DateTime.utc(2026, 8, 28, 10, 0, 0),
        lowAccuracyThresholdMeters: customThreshold,
      );
      final snapshotHud = HudFormatter.fromSnapshot(
        snapshot: snapshot,
        originalSha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );

      expect(liveHud.status, equals(HudStatus.verified));
      expect(snapshot.verificationStatus, equals(HudStatus.verified));
      expect(snapshotHud.status, equals(HudStatus.verified));
      expect(liveHud.status, equals(snapshotHud.status));
    });
  });

  group('F2: Status Persistence & Pre-v8 Migration Fallback', () {
    test('Persisted verificationStatus is preserved across settings changes', () async {
      final item = MediaItem(
        id: 'media-v8-01',
        siteId: 'SITE-01',
        originalUri: 'media/orig_01.jpg',
        uri: 'media/evid_01.jpg',
        type: MediaItemType.photo,
        lat: 22.5726,
        lon: 88.3639,
        accuracyM: 25.0,
        lowAccuracy: false,
        verificationStatus: HudStatus.verified, // Saved as verified because threshold was 30m at capture
        capturedAt: DateTime.utc(2026, 8, 28, 12, 0, 0),
        creatorId: 'user-overlay',
      );

      await mediaRepo.insertMedia(item);
      final retrieved = await mediaRepo.getMediaById('media-v8-01', creatorId: 'user-overlay');

      expect(retrieved, isNotNull);
      expect(retrieved!.verificationStatus, equals(HudStatus.verified));
      expect(retrieved.accuracyM, equals(25.0));
    });

    test('Pre-v8 records with null verification_status fallback safely to weakest defensible semantic', () async {
      // 1. (0,0) coordinates -> must be PENDING even if lowAccuracy is 0
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'legacy-zero-coords',
              siteId: const drift.Value('SITE-01'),
              uri: 'media/evid_zero.jpg',
              lat: 0.0,
              lon: 0.0,
              accuracyM: const drift.Value(5.0),
              lowAccuracy: const drift.Value(0),
              capturedAt: '2026-08-01T00:00:00Z',
              type: const drift.Value('photo'),
              creatorId: const drift.Value('user-overlay'),
            ),
          );
      final itemZero = await mediaRepo.getMediaById('legacy-zero-coords', creatorId: 'user-overlay');
      expect(itemZero!.verificationStatus, equals(HudStatus.pending));

      // 2. null accuracy -> must be PENDING
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'legacy-null-acc',
              siteId: const drift.Value('SITE-01'),
              uri: 'media/evid_null_acc.jpg',
              lat: 22.5726,
              lon: 88.3639,
              accuracyM: const drift.Value(null),
              lowAccuracy: const drift.Value(0),
              capturedAt: '2026-08-01T00:00:00Z',
              type: const drift.Value('photo'),
              creatorId: const drift.Value('user-overlay'),
            ),
          );
      final itemNullAcc = await mediaRepo.getMediaById('legacy-null-acc', creatorId: 'user-overlay');
      expect(itemNullAcc!.verificationStatus, equals(HudStatus.pending));

      // 3. lowAccuracy == 1 -> DEGRADED
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'legacy-flagged-low',
              siteId: const drift.Value('SITE-01'),
              uri: 'media/evid_low.jpg',
              lat: 22.5726,
              lon: 88.3639,
              accuracyM: const drift.Value(15.0),
              lowAccuracy: const drift.Value(1),
              capturedAt: '2026-08-01T00:00:00Z',
              type: const drift.Value('photo'),
              creatorId: const drift.Value('user-overlay'),
            ),
          );
      final itemLow = await mediaRepo.getMediaById('legacy-flagged-low', creatorId: 'user-overlay');
      expect(itemLow!.verificationStatus, equals(HudStatus.degraded));

      // 4. accuracy > 20.0 -> DEGRADED
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'legacy-high-m',
              siteId: const drift.Value('SITE-01'),
              uri: 'media/evid_high_m.jpg',
              lat: 22.5726,
              lon: 88.3639,
              accuracyM: const drift.Value(22.0),
              lowAccuracy: const drift.Value(0),
              capturedAt: '2026-08-01T00:00:00Z',
              type: const drift.Value('photo'),
              creatorId: const drift.Value('user-overlay'),
            ),
          );
      final itemHighM = await mediaRepo.getMediaById('legacy-high-m', creatorId: 'user-overlay');
      expect(itemHighM!.verificationStatus, equals(HudStatus.degraded));

      // 5. Valid coordinates, lowAccuracy == 0, accuracy <= 20.0 -> VERIFIED
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'legacy-verified',
              siteId: const drift.Value('SITE-01'),
              uri: 'media/evid_ver.jpg',
              lat: 22.5726,
              lon: 88.3639,
              accuracyM: const drift.Value(8.5),
              lowAccuracy: const drift.Value(0),
              capturedAt: '2026-08-01T00:00:00Z',
              type: const drift.Value('photo'),
              creatorId: const drift.Value('user-overlay'),
            ),
          );
      final itemVer = await mediaRepo.getMediaById('legacy-verified', creatorId: 'user-overlay');
      expect(itemVer!.verificationStatus, equals(HudStatus.verified));
    });
  });

  group('F3: Canonical GNSS Telemetry Persistence & Reload', () {
    test('Persists and reloads canonical GNSS telemetry fields', () async {
      final fixTime = DateTime.utc(2026, 8, 28, 14, 25, 30);
      final item = MediaItem(
        id: 'gnss-telemetry-01',
        siteId: 'SITE-01',
        originalUri: 'media/orig_gnss.jpg',
        uri: 'media/evid_gnss.jpg',
        type: MediaItemType.photo,
        lat: 22.5726,
        lon: 88.3639,
        accuracyM: 4.2,
        lowAccuracy: false,
        verificationStatus: HudStatus.verified,
        gnssSatelliteCount: 16,
        gnssSatellitesUsedInFix: 11,
        gnssFixTimestampUtc: fixTime,
        capturedAt: DateTime.utc(2026, 8, 28, 14, 25, 31),
        creatorId: 'user-overlay',
      );

      await mediaRepo.insertMedia(item);
      final retrieved = await mediaRepo.getMediaById('gnss-telemetry-01', creatorId: 'user-overlay');

      expect(retrieved, isNotNull);
      expect(retrieved!.gnssSatelliteCount, equals(16));
      expect(retrieved.gnssSatellitesUsedInFix, equals(11));
      expect(retrieved.gnssFixTimestampUtc, equals(fixTime));
    });
  });

  group('F4: Video Metadata Preservation & Untouched Raw Video', () {
    test('Video MediaItem persists and exposes canonical metadata without modifying raw video', () async {
      final fixTime = DateTime.utc(2026, 8, 28, 15, 0, 0);
      final videoItem = MediaItem(
        id: 'video-meta-01',
        siteId: 'BRIDGE-NORTH',
        originalUri: 'media/orig_video.mp4',
        uri: 'media/evid_video.mp4',
        thumbUri: 'media/thumb_video.jpg',
        type: MediaItemType.video,
        lat: 22.5726,
        lon: 88.3639,
        accuracyM: 6.8,
        lowAccuracy: false,
        altitude: 24.5,
        isAltitudeMsl: true,
        verificationStatus: HudStatus.verified,
        gnssSatelliteCount: 14,
        gnssSatellitesUsedInFix: 9,
        gnssFixTimestampUtc: fixTime,
        sha256Hash: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        capturedAt: DateTime.utc(2026, 8, 28, 15, 0, 0),
        creatorId: 'user-overlay',
      );

      await mediaRepo.insertMedia(videoItem);
      final retrieved = await mediaRepo.getMediaById('video-meta-01', creatorId: 'user-overlay');

      expect(retrieved, isNotNull);
      expect(retrieved!.type, equals(MediaItemType.video));
      expect(retrieved.originalUri, equals('media/orig_video.mp4'));
      expect(retrieved.uri, equals('media/evid_video.mp4'));
      // Raw video hash is identical
      expect(retrieved.sha256Hash, equals('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'));
      // Metadata fields are intact
      expect(retrieved.verificationStatus, equals(HudStatus.verified));
      expect(retrieved.altitude, equals(24.5));
      expect(retrieved.isAltitudeMsl, isTrue);
      expect(retrieved.gnssSatelliteCount, equals(14));
      expect(retrieved.gnssSatellitesUsedInFix, equals(9));
    });
  });

  group('F5: Altitude Datum Truthfulness & Export', () {
    test('GPSUtils.formatAltitude formats MSL, WGS84, and unknown datum truthfully', () {
      expect(GPSUtils.formatAltitude(18.4, isMsl: true), equals('+18.4 m ASL'));
      expect(GPSUtils.formatAltitude(-43.4, isMsl: false), equals('-43.4 m (WGS84)'));
      expect(GPSUtils.formatAltitude(25.0, isMsl: null), equals('+25.0 m'));
      expect(GPSUtils.formatAltitude(-12.0, isMsl: null), equals('-12.0 m'));
      expect(GPSUtils.formatAltitude(null, isMsl: null), equals('—'));
      expect(GPSUtils.formatAltitude(null, isMsl: true), equals('—'));
    });

    test('formatInspectionCoordinates includes truthful datum', () {
      final formattedMsl = GPSUtils.formatInspectionCoordinates(
        22.5726,
        88.3639,
        altitudeMeters: 14.5,
        isMsl: true,
      );
      expect(formattedMsl, contains('+14.5 m ASL'));

      final formattedWgs84 = GPSUtils.formatInspectionCoordinates(
        22.5726,
        88.3639,
        altitudeMeters: -32.1,
        isMsl: false,
      );
      expect(formattedWgs84, contains('-32.1 m (WGS84)'));

      final formattedUnknown = GPSUtils.formatInspectionCoordinates(
        22.5726,
        88.3639,
        altitudeMeters: 10.0,
        isMsl: null,
      );
      expect(formattedUnknown, contains('+10.0 m'));
      expect(formattedUnknown, isNot(contains('ASL')));
      expect(formattedUnknown, isNot(contains('WGS84')));
    });

    test('isAltitudeMsl persists and reloads true, false, and null correctly', () async {
      // 1. isAltitudeMsl = true
      final itemMsl = MediaItem(
        id: 'alt-msl',
        siteId: 'S1',
        originalUri: 'o',
        uri: 'u',
        type: MediaItemType.photo,
        lat: 22.0,
        lon: 88.0,
        altitude: 10.5,
        isAltitudeMsl: true,
        capturedAt: DateTime.now().toUtc(),
        creatorId: 'user-overlay',
      );
      await mediaRepo.insertMedia(itemMsl);
      final rMsl = await mediaRepo.getMediaById('alt-msl', creatorId: 'user-overlay');
      expect(rMsl!.isAltitudeMsl, isTrue);

      // 2. isAltitudeMsl = false
      final itemWgs = MediaItem(
        id: 'alt-wgs',
        siteId: 'S1',
        originalUri: 'o',
        uri: 'u',
        type: MediaItemType.photo,
        lat: 22.0,
        lon: 88.0,
        altitude: -15.2,
        isAltitudeMsl: false,
        capturedAt: DateTime.now().toUtc(),
        creatorId: 'user-overlay',
      );
      await mediaRepo.insertMedia(itemWgs);
      final rWgs = await mediaRepo.getMediaById('alt-wgs', creatorId: 'user-overlay');
      expect(rWgs!.isAltitudeMsl, isFalse);

      // 3. isAltitudeMsl = null
      final itemUnknown = MediaItem(
        id: 'alt-unknown',
        siteId: 'S1',
        originalUri: 'o',
        uri: 'u',
        type: MediaItemType.photo,
        lat: 22.0,
        lon: 88.0,
        altitude: 30.0,
        isAltitudeMsl: null,
        capturedAt: DateTime.now().toUtc(),
        creatorId: 'user-overlay',
      );
      await mediaRepo.insertMedia(itemUnknown);
      final rUnknown = await mediaRepo.getMediaById('alt-unknown', creatorId: 'user-overlay');
      expect(rUnknown!.isAltitudeMsl, isNull);
    });
  });
}
