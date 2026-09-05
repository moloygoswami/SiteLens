import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sitelens/core/utils/gps_utils.dart';
import 'package:sitelens/features/camera/models/evidence_metadata_snapshot.dart';
import 'package:sitelens/features/camera/models/gnss_snapshot.dart';
import 'package:sitelens/features/camera/models/gps_hardware_state.dart';

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
      expect(snapshot.canonicalTimestampUtc, '2026-08-15 14:30:00 UTC');
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
  });
}
