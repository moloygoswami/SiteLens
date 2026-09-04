import 'package:flutter_test/flutter_test.dart';
import 'package:sitelens/core/utils/gnss_quality_assessor.dart';
import 'package:sitelens/core/utils/gps_utils.dart';
import 'package:sitelens/features/camera/models/gnss_snapshot.dart';

void main() {
  group('GnssSnapshot & Constellation Mapping Tests', () {
    test('Correctly maps all supported GNSS constellations and displays', () {
      final data = {
        'isSupported': true,
        'isAvailable': true,
        'satelliteCount': 24,
        'satellitesUsedInFix': 18,
        'timestampMillis': 1755255600000,
        'constellations': {
          'gps': {'tracked': 8, 'usedInFix': 6},
          'glonass': {'tracked': 6, 'usedInFix': 5},
          'galileo': {'tracked': 4, 'usedInFix': 3},
          'beidou': {'tracked': 4, 'usedInFix': 3},
          'qzss': {'tracked': 1, 'usedInFix': 1},
          'sbas': {'tracked': 1, 'usedInFix': 0},
        },
      };

      final snapshot = GnssSnapshot.fromMap(data);

      expect(snapshot.isSupported, isTrue);
      expect(snapshot.isAvailable, isTrue);
      expect(snapshot.satelliteCount, 24);
      expect(snapshot.satellitesUsedInFix, 18);
      expect(snapshot.hasNavIC, isFalse);

      expect(snapshot.constellations['gps']?.displayName, 'GPS');
      expect(snapshot.constellations['gps']?.trackedCount, 8);
      expect(snapshot.constellations['gps']?.usedInFixCount, 6);

      expect(snapshot.constellations['glonass']?.displayName, 'GLONASS');
      expect(snapshot.constellations['galileo']?.displayName, 'Galileo');
      expect(snapshot.constellations['beidou']?.displayName, 'BeiDou');
      expect(snapshot.constellations['qzss']?.displayName, 'QZSS');
      expect(snapshot.constellations['sbas']?.displayName, 'SBAS');
    });

    test('Detects IRNSS/NavIC strictly when Android reports CONSTELLATION_IRNSS', () {
      final dataWithNavIC = {
        'isSupported': true,
        'isAvailable': true,
        'satelliteCount': 12,
        'satellitesUsedInFix': 8,
        'timestampMillis': 1755255600000,
        'constellations': {
          'gps': {'tracked': 6, 'usedInFix': 4},
          'irnss': {'tracked': 3, 'usedInFix': 2},
          'glonass': {'tracked': 3, 'usedInFix': 2},
        },
      };

      final snapshot = GnssSnapshot.fromMap(dataWithNavIC);
      expect(snapshot.hasNavIC, isTrue);
      expect(snapshot.constellations['irnss']?.displayName, 'NavIC (IRNSS)');
      expect(snapshot.constellations['irnss']?.trackedCount, 3);
      expect(snapshot.constellations['irnss']?.usedInFixCount, 2);
    });

    test('Never reports NavIC when IRNSS is absent from telemetry', () {
      final dataWithoutNavIC = {
        'isSupported': true,
        'isAvailable': true,
        'satelliteCount': 15,
        'satellitesUsedInFix': 10,
        'timestampMillis': 1755255600000,
        'constellations': {
          'gps': {'tracked': 8, 'usedInFix': 6},
          'glonass': {'tracked': 7, 'usedInFix': 4},
        },
      };

      final snapshot = GnssSnapshot.fromMap(dataWithoutNavIC);
      expect(snapshot.hasNavIC, isFalse);
      expect(snapshot.constellations.containsKey('irnss'), isFalse);
    });

    test('Handles unavailable GNSS gracefully', () {
      final dataUnavailable = {
        'isSupported': true,
        'isAvailable': false,
        'satelliteCount': 0,
        'satellitesUsedInFix': 0,
        'timestampMillis': null,
        'constellations': {},
      };

      final snapshot = GnssSnapshot.fromMap(dataUnavailable);
      expect(snapshot.isSupported, isTrue);
      expect(snapshot.isAvailable, isFalse);
      expect(snapshot.satelliteCount, 0);
      expect(snapshot.satellitesUsedInFix, 0);
      expect(snapshot.constellations, isEmpty);
      expect(snapshot.timestampUtc, isNull);

      final defaultUnavailable = GnssSnapshot.unavailable;
      expect(defaultUnavailable.isAvailable, isFalse);
      expect(defaultUnavailable.isSupported, isTrue);
    });

    test('Handles unsupported Android API (API < 24) gracefully', () {
      final dataUnsupported = {
        'isSupported': false,
        'isAvailable': false,
        'satelliteCount': 0,
        'satellitesUsedInFix': 0,
        'timestampMillis': null,
        'constellations': {},
      };

      final snapshot = GnssSnapshot.fromMap(dataUnsupported);
      expect(snapshot.isSupported, isFalse);
      expect(snapshot.isAvailable, isFalse);

      final defaultUnsupported = GnssSnapshot.unsupported;
      expect(defaultUnsupported.isSupported, isFalse);
      expect(defaultUnsupported.isAvailable, isFalse);
    });
  });

  group('GnssQualityAssessment Unit Tests', () {
    test('Fix with <=5m accuracy and >=4 satellites is High accuracy & multiSatelliteVerified', () {
      const gnss = GnssSnapshot(
        isSupported: true,
        isAvailable: true,
        satelliteCount: 14,
        satellitesUsedInFix: 8,
      );

      final assessment = GnssQualityAssessment.evaluate(
        hasValidFix: true,
        accuracyMeters: 3.2,
        gnssSnapshot: gnss,
      );

      expect(assessment.hasValidFix, isTrue);
      expect(assessment.accuracyMeters, 3.2);
      expect(assessment.fixStatus, GPSFixStatus.high);
      expect(assessment.confidence, GnssFixConfidence.multiSatelliteVerified);
      expect(assessment.satellitesUsedInFix, 8);
      expect(assessment.totalSatellitesTracked, 14);
      expect(assessment.isGnssAvailable, isTrue);
    });

    test('Fix with high accuracy but <4 satellites gets basic confidence without modifying accuracy', () {
      const gnss = GnssSnapshot(
        isSupported: true,
        isAvailable: true,
        satelliteCount: 4,
        satellitesUsedInFix: 2,
      );

      final assessment = GnssQualityAssessment.evaluate(
        hasValidFix: true,
        accuracyMeters: 4.5,
        gnssSnapshot: gnss,
      );

      expect(assessment.hasValidFix, isTrue);
      expect(assessment.accuracyMeters, 4.5);
      expect(assessment.fixStatus, GPSFixStatus.high);
      expect(assessment.confidence, GnssFixConfidence.basic);
      expect(assessment.satellitesUsedInFix, 2);
    });

    test('Fix with poor accuracy (>20m) remains poor fixStatus regardless of satellite count', () {
      const gnss = GnssSnapshot(
        isSupported: true,
        isAvailable: true,
        satelliteCount: 20,
        satellitesUsedInFix: 15,
      );

      final assessment = GnssQualityAssessment.evaluate(
        hasValidFix: true,
        accuracyMeters: 28.0,
        gnssSnapshot: gnss,
      );

      expect(assessment.hasValidFix, isTrue);
      expect(assessment.accuracyMeters, 28.0);
      expect(assessment.fixStatus, GPSFixStatus.poor);
      expect(assessment.confidence, GnssFixConfidence.multiSatelliteVerified);
    });

    test('No valid fix returns searching status and none confidence', () {
      final assessment = GnssQualityAssessment.evaluate(
        hasValidFix: false,
        accuracyMeters: null,
      );

      expect(assessment.hasValidFix, isFalse);
      expect(assessment.accuracyMeters, isNull);
      expect(assessment.fixStatus, GPSFixStatus.searching);
      expect(assessment.confidence, GnssFixConfidence.none);
    });
  });
}
