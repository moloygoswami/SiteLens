import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sitelens/core/utils/gps_utils.dart';
import 'package:sitelens/features/camera/models/evidence_metadata_snapshot.dart';
import 'package:sitelens/features/camera/models/gnss_snapshot.dart';
import 'package:sitelens/features/camera/models/gps_hardware_state.dart';
import 'package:sitelens/features/camera/hud/hud_formatter.dart';

void main() {
  group('EvidenceMetadataSnapshot Unit Tests', () {
    test('Synchronously captures immutable snapshot from GPS state, active site, and resolved address', () {
      final gpsState = GpsHardwareState(
        fixStatus: GPSFixStatus.high,
        hasValidFix: true,
        latitude: 22.57264,
        longitude: 88.36391,
        altitudeMeters: 18.4,
        accuracyMeters: 3.2,
        timestampUtc: DateTime.utc(2026, 8, 15, 14, 30, 0),
        permissionStatus: LocationPermission.whileInUse,
        resolvedLocationLat: 22.57264,
        resolvedLocationLon: 88.36391,
      );

      final snapshot = EvidenceMetadataSnapshot.capture(
        gpsState: gpsState,
        siteId: 'SITE_101',
        siteCode: 'HOME',
        siteName: 'Sonar Kella Apartment',
        customMediaId: 'fixed-uuid-1234',
        resolvedAddress: '42 Construction Way • New Town',
        customCaptureTimeUtc: DateTime.utc(2026, 8, 15, 14, 30, 0),
      );

      expect(snapshot.mediaId, 'fixed-uuid-1234');
      expect(snapshot.siteId, 'SITE_101');
      expect(snapshot.siteCode, 'HOME');
      expect(snapshot.siteName, 'Sonar Kella Apartment');
      expect(snapshot.latitude, 22.57264);
      expect(snapshot.longitude, 88.36391);
      expect(snapshot.altitudeMeters, 18.4);
      expect(snapshot.accuracyMeters, 3.2);
      expect(snapshot.lowAccuracy, isFalse);
      expect(snapshot.capturedAtUtc, DateTime.utc(2026, 8, 15, 14, 30, 0));
      expect(snapshot.canonicalTimestampUtc, '2026-08-15 14:30:00 UTC');
      expect(snapshot.gnssFixTimestampUtc, DateTime.utc(2026, 8, 15, 14, 30, 0));
      expect(snapshot.altitudeDisplay, '+18.4 m ASL');
      expect(snapshot.accuracyDisplay, '±3.2m');
      expect(snapshot.resolvedAddress, '42 Construction Way • New Town');
    });

    test('Rejects a stale resolved address not associated with the current fix coordinates', () {
      // Fix at A; the resolved name was produced for coordinates at B (moved since).
      final gpsState = GpsHardwareState(
        fixStatus: GPSFixStatus.high,
        hasValidFix: true,
        latitude: 22.57264,
        longitude: 88.36391,
        accuracyMeters: 3.2,
        resolvedLocationLat: 22.58264, // ~1.1 km away
        resolvedLocationLon: 88.36391,
      );

      final snapshot = EvidenceMetadataSnapshot.capture(
        gpsState: gpsState,
        siteId: 'SITE_101',
        siteCode: 'HOME',
        siteName: 'Sonar Kella Apartment',
        resolvedAddress: 'OLD STREET, PREVIOUS LOCATION',
      );

      // The stale name must never be baked into evidence.
      expect(snapshot.resolvedAddress, 'HOME VICINITY');
    });

    test('Rejects a resolved address when no coordinate association exists', () {
      final gpsState = GpsHardwareState(
        fixStatus: GPSFixStatus.high,
        hasValidFix: true,
        latitude: 22.57264,
        longitude: 88.36391,
        accuracyMeters: 3.2,
      );

      final snapshot = EvidenceMetadataSnapshot.capture(
        gpsState: gpsState,
        siteId: 'SITE_101',
        siteCode: 'HOME',
        siteName: 'Sonar Kella Apartment',
        resolvedAddress: 'UNVERIFIED NAME',
      );

      expect(snapshot.resolvedAddress, 'HOME VICINITY');
    });

    test('Applies fallback address chain when geocoding is null or GPS has no fix', () {
      final gpsWithFix = const GpsHardwareState(
        fixStatus: GPSFixStatus.high,
        hasValidFix: true,
        latitude: 22.57264,
        longitude: 88.36391,
      );

      // 1. Offline with GPS fix -> SITE_CODE VICINITY
      final offlineSnapshot = EvidenceMetadataSnapshot.capture(
        gpsState: gpsWithFix,
        siteId: 'SITE_101',
        siteCode: 'HOME',
        siteName: 'Sonar Kella Apartment',
        resolvedAddress: null,
      );
      expect(offlineSnapshot.resolvedAddress, 'HOME VICINITY');

      // 2. No GPS fix -> NO FIX — LOCATION UNAVAILABLE
      final noFixGps = const GpsHardwareState(
        fixStatus: GPSFixStatus.searching,
        hasValidFix: false,
      );
      final noFixSnapshot = EvidenceMetadataSnapshot.capture(
        gpsState: noFixGps,
        siteId: 'SITE_101',
        siteCode: 'HOME',
        siteName: 'Sonar Kella Apartment',
        resolvedAddress: null,
      );
      expect(noFixSnapshot.resolvedAddress, 'NO FIX — LOCATION UNAVAILABLE');
    });

    test('Flags lowAccuracy when accuracy exceeds 20 meters', () {
      final gpsState = const GpsHardwareState(
        fixStatus: GPSFixStatus.poor,
        hasValidFix: true,
        latitude: 22.57264,
        longitude: 88.36391,
        accuracyMeters: 28.5,
      );

      final snapshot = EvidenceMetadataSnapshot.capture(
        gpsState: gpsState,
        siteId: 'SITE_101',
        siteCode: 'HOME',
        siteName: 'Sonar Kella Apartment',
      );

      expect(snapshot.lowAccuracy, isTrue);
      expect(snapshot.accuracyDisplay, '±28.5m');
    });

    test('Captures GNSS satellite count, used in fix, and constellations when available', () {
      final gnss = GnssSnapshot(
        isSupported: true,
        isAvailable: true,
        satelliteCount: 16,
        satellitesUsedInFix: 10,
        constellations: {
          'gps': const GnssConstellationSummary(constellation: 'gps', trackedCount: 8, usedInFixCount: 6),
          'glonass': const GnssConstellationSummary(constellation: 'glonass', trackedCount: 8, usedInFixCount: 4),
        },
      );

      final gpsState = GpsHardwareState(
        fixStatus: GPSFixStatus.high,
        hasValidFix: true,
        latitude: 22.57264,
        longitude: 88.36391,
        accuracyMeters: 3.2,
        gnssSnapshot: gnss,
      );

      final snapshot = EvidenceMetadataSnapshot.capture(
        gpsState: gpsState,
        siteId: 'SITE_101',
        siteCode: 'HOME',
        siteName: 'Sonar Kella Apartment',
      );

      expect(snapshot.gnssSatelliteCount, 16);
      expect(snapshot.gnssSatellitesUsedInFix, 10);
      expect(snapshot.gnssConstellations?['gps']?.trackedCount, 8);
      expect(snapshot.gnssConstellations?['gps']?.usedInFixCount, 6);
      expect(snapshot.gnssSnapshot, gnss);
    });

    test('R10: an available-but-unreported satellite count stays null on evidence', () {
      const gnss = GnssSnapshot(isSupported: true, isAvailable: true);

      final gpsState = GpsHardwareState(
        fixStatus: GPSFixStatus.high,
        hasValidFix: true,
        latitude: 22.57264,
        longitude: 88.36391,
        accuracyMeters: 3.2,
        gnssSnapshot: gnss,
      );

      final snapshot = EvidenceMetadataSnapshot.capture(
        gpsState: gpsState,
        siteId: 'SITE_101',
        siteCode: 'HOME',
        siteName: 'Sonar Kella Apartment',
      );

      // GNSS availability does not imply an established count: an unreported
      // count must never be disclosed as a fabricated 0 (R10).
      expect(snapshot.gnssSatelliteCount, isNull);
      expect(snapshot.gnssSatellitesUsedInFix, isNull);
    });

    test('Negative and null altitude representations are clean', () {
      final negSnapshot = EvidenceMetadataSnapshot(
        mediaId: 'id1',
        siteId: 's1',
        siteCode: 'sc1',
        siteName: 'sn1',
        latitude: 22.0,
        longitude: 88.0,
        altitudeMeters: -43.4,
        accuracyMeters: 5.0,
        lowAccuracy: false,
        capturedAtUtc: DateTime.utc(2026, 8, 15, 12, 0, 0),
        canonicalTimestampUtc: '2026-08-15 12:00:00 UTC',
        resolvedAddress: '10 Industrial Area',
      );
      expect(negSnapshot.altitudeDisplay, '-43.4 m ASL');

      final nullSnapshot = EvidenceMetadataSnapshot(
        mediaId: 'id2',
        siteId: 's1',
        siteCode: 'sc1',
        siteName: 'sn1',
        latitude: 22.0,
        longitude: 88.0,
        altitudeMeters: null,
        accuracyMeters: 5.0,
        lowAccuracy: false,
        capturedAtUtc: DateTime.utc(2026, 8, 15, 12, 0, 0),
        canonicalTimestampUtc: '2026-08-15 12:00:00 UTC',
        resolvedAddress: '10 Industrial Area',
      );
      expect(nullSnapshot.altitudeDisplay, '—');
    });

    test('EvidenceMetadataSnapshot formats WGS84 truthfully when isAltitudeMsl is false', () {
      final wgsSnapshot = EvidenceMetadataSnapshot(
        mediaId: 'id-wgs',
        siteId: 's1',
        siteCode: 'sc1',
        siteName: 'sn1',
        latitude: 22.5629,
        longitude: 88.3009,
        altitudeMeters: -42.4,
        isAltitudeMsl: false,
        accuracyMeters: 3.0,
        lowAccuracy: false,
        capturedAtUtc: DateTime.utc(2026, 9, 4, 15, 0, 0),
        canonicalTimestampUtc: '2026-09-04 15:00:00 UTC',
        resolvedAddress: 'Kolkata, WB',
      );
      expect(wgsSnapshot.isAltitudeMsl, isFalse);
      expect(wgsSnapshot.altitudeDisplay, '-42.4 m (WGS84)');
    });

    group('F1: Capture Timestamp Authority Tests', () {
      test('1. Single capture timestamp authority: capturedAtUtc reflects shutter instant, not stale GNSS fix time', () {
        final staleGpsFixTime = DateTime.utc(2026, 8, 15, 14, 29, 55); // 5 seconds in past
        final shutterTime = DateTime.utc(2026, 8, 15, 14, 30, 0);

        final gpsState = GpsHardwareState(
          fixStatus: GPSFixStatus.high,
          hasValidFix: true,
          latitude: 22.57264,
          longitude: 88.36391,
          accuracyMeters: 2.1,
          timestampUtc: staleGpsFixTime,
        );

        final snapshot = EvidenceMetadataSnapshot.capture(
          gpsState: gpsState,
          siteId: 'SITE_101',
          siteCode: 'HOME',
          siteName: 'Test Site',
          customCaptureTimeUtc: shutterTime,
        );

        // Captured time MUST equal the shutter instant
        expect(snapshot.capturedAtUtc, shutterTime);
        expect(snapshot.canonicalTimestampUtc, '2026-08-15 14:30:00 UTC');
        // GNSS fix time is preserved strictly as GNSS telemetry metadata
        expect(snapshot.gnssFixTimestampUtc, staleGpsFixTime);
        expect(snapshot.capturedAtUtc, isNot(equals(staleGpsFixTime)));
      });

      test('2. Rapid 3x capture produces distinct, correctly ordered timestamps under identical static GNSS fix', () {
        final staticGpsFixTime = DateTime.utc(2026, 8, 15, 14, 30, 0);
        final gpsState = GpsHardwareState(
          fixStatus: GPSFixStatus.high,
          hasValidFix: true,
          latitude: 22.57264,
          longitude: 88.36391,
          accuracyMeters: 2.1,
          timestampUtc: staticGpsFixTime,
        );

        final t1 = DateTime.utc(2026, 8, 15, 14, 30, 1, 100);
        final t2 = DateTime.utc(2026, 8, 15, 14, 30, 1, 850);
        final t3 = DateTime.utc(2026, 8, 15, 14, 30, 2, 400);

        final s1 = EvidenceMetadataSnapshot.capture(gpsState: gpsState, siteId: 'S1', siteCode: 'SC', siteName: 'SN', customCaptureTimeUtc: t1);
        final s2 = EvidenceMetadataSnapshot.capture(gpsState: gpsState, siteId: 'S1', siteCode: 'SC', siteName: 'SN', customCaptureTimeUtc: t2);
        final s3 = EvidenceMetadataSnapshot.capture(gpsState: gpsState, siteId: 'S1', siteCode: 'SC', siteName: 'SN', customCaptureTimeUtc: t3);

        // All 3 share the static GNSS fix metadata
        expect(s1.gnssFixTimestampUtc, staticGpsFixTime);
        expect(s2.gnssFixTimestampUtc, staticGpsFixTime);
        expect(s3.gnssFixTimestampUtc, staticGpsFixTime);

        // But all 3 have distinct, monotonic physical capture times
        expect(s1.capturedAtUtc, t1);
        expect(s2.capturedAtUtc, t2);
        expect(s3.capturedAtUtc, t3);
        expect(s1.capturedAtUtc.isBefore(s2.capturedAtUtc), isTrue);
        expect(s2.capturedAtUtc.isBefore(s3.capturedAtUtc), isTrue);
        expect(s1.canonicalTimestampUtc, '2026-08-15 14:30:01 UTC');
        expect(s2.canonicalTimestampUtc, '2026-08-15 14:30:01 UTC');
        expect(s3.canonicalTimestampUtc, '2026-08-15 14:30:02 UTC');
        expect(s1.capturedAtUtc != s2.capturedAtUtc, isTrue);
        expect(s2.capturedAtUtc != s3.capturedAtUtc, isTrue);
      });

      test('3. Rapid 5x capture produces distinct, correctly ordered timestamps across burst', () {
        final staticGpsFixTime = DateTime.utc(2026, 8, 15, 14, 30, 0);
        final gpsState = GpsHardwareState(
          fixStatus: GPSFixStatus.high,
          hasValidFix: true,
          latitude: 22.57264,
          longitude: 88.36391,
          accuracyMeters: 2.1,
          timestampUtc: staticGpsFixTime,
        );

        final times = List.generate(5, (i) => DateTime.utc(2026, 8, 15, 14, 30, 1 + i, i * 200));
        final snapshots = times.map((t) => EvidenceMetadataSnapshot.capture(
          gpsState: gpsState,
          siteId: 'S1',
          siteCode: 'SC',
          siteName: 'SN',
          customCaptureTimeUtc: t,
        )).toList();

        for (int i = 0; i < 4; i++) {
          expect(snapshots[i].capturedAtUtc.isBefore(snapshots[i + 1].capturedAtUtc), isTrue);
          expect(snapshots[i].gnssFixTimestampUtc, staticGpsFixTime);
        }
        final uniqueCapturedTimes = snapshots.map((s) => s.capturedAtUtc).toSet();
        expect(uniqueCapturedTimes.length, 5);
      });

      test('4. Confirm persisted timestamps correspond to capture-time authority rather than GNSS fix time', () {
        final oldFixTime = DateTime.utc(2026, 8, 15, 14, 25, 0); // 5 minutes old
        final shutterTime = DateTime.utc(2026, 8, 15, 14, 30, 0);
        final gpsState = GpsHardwareState(
          fixStatus: GPSFixStatus.high,
          hasValidFix: true,
          latitude: 22.57264,
          longitude: 88.36391,
          accuracyMeters: 2.1,
          timestampUtc: oldFixTime,
        );

        final snapshot = EvidenceMetadataSnapshot.capture(
          gpsState: gpsState,
          siteId: 'S1',
          siteCode: 'SC',
          siteName: 'SN',
          customCaptureTimeUtc: shutterTime,
        );

        // Simulation of database persistence mapping (LocalMediaRepository / MediaPersistenceCoordinator)
        final persistedIso = snapshot.capturedAtUtc.toUtc().toIso8601String();
        expect(persistedIso, '2026-08-15T14:30:00.000Z');
        expect(persistedIso, isNot(equals(oldFixTime.toIso8601String())));
      });

      test('5. Confirm watermark HUD text and persisted timestamp agree', () {
        final shutterTime = DateTime.utc(2026, 8, 15, 14, 30, 45);
        final gpsState = GpsHardwareState(
          fixStatus: GPSFixStatus.high,
          hasValidFix: true,
          latitude: 22.57264,
          longitude: 88.36391,
          accuracyMeters: 2.1,
          timestampUtc: DateTime.utc(2026, 8, 15, 14, 30, 40),
        );

        final snapshot = EvidenceMetadataSnapshot.capture(
          gpsState: gpsState,
          siteId: 'S1',
          siteCode: 'SC',
          siteName: 'SN',
          customCaptureTimeUtc: shutterTime,
        );

        final hud = HudFormatter.fromSnapshot(
          snapshot: snapshot,
          originalSha256: 'sha-dummy',
          isGpsLocked: true,
        );

        final persistedIso = snapshot.capturedAtUtc.toUtc().toIso8601String();
        // Watermark HUD formats 'yyyy-MM-dd HH:mm:ss'
        expect(hud.utcTimestampText, '2026-08-15 14:30:45');
        expect(snapshot.canonicalTimestampUtc, '2026-08-15 14:30:45 UTC');
        expect(persistedIso, startsWith('2026-08-15T14:30:45'));
      });

      test('6. Default capture path (omitted customCaptureTimeUtc) uses current execution instant, preserves gnssFixTimestampUtc, and is not overwritten by stale GNSS fix time', () {
        final staleGpsFixTime = DateTime.utc(2026, 8, 15, 14, 20, 0); // 10 minutes in past
        final gpsState = GpsHardwareState(
          fixStatus: GPSFixStatus.high,
          hasValidFix: true,
          latitude: 22.57264,
          longitude: 88.36391,
          accuracyMeters: 2.1,
          timestampUtc: staleGpsFixTime,
        );

        final beforeCapture = DateTime.now().toUtc();
        final snapshot = EvidenceMetadataSnapshot.capture(
          gpsState: gpsState,
          siteId: 'S1',
          siteCode: 'SC',
          siteName: 'SN',
        );
        final afterCapture = DateTime.now().toUtc();

        expect(snapshot.gnssFixTimestampUtc, staleGpsFixTime);
        expect(snapshot.capturedAtUtc, isNot(equals(staleGpsFixTime)));
        expect(
          snapshot.capturedAtUtc.isAfter(beforeCapture.subtract(const Duration(seconds: 1))) &&
              snapshot.capturedAtUtc.isBefore(afterCapture.add(const Duration(seconds: 1))),
          isTrue,
        );
      });
    });
  });
}
