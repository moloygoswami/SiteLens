// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sitelens/core/utils/gnss_quality_assessor.dart';
import 'package:sitelens/features/camera/models/evidence_metadata_snapshot.dart';
import 'package:sitelens/features/camera/models/gps_hardware_state.dart';
import 'package:sitelens/features/camera/services/location_hardware_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Physical Device GNSS & Location Verification', (tester) async {
    final locationService = LocationHardwareService();

    // 1. Check permission & location service
    final isEnabled = await locationService.isLocationServiceEnabled();
    var permission = await locationService.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    print('--- GNSS PHYSICAL DEVICE VERIFICATION ---');
    print('Location service enabled: $isEnabled');
    print('Location permission: $permission');

    // 2. Start GNSS updates on native Android layer and start location stream to activate GNSS hardware
    final started = await locationService.startGnssUpdates();
    print('startGnssUpdates returned: $started');

    // Subscribe to position stream so Android powers on GNSS chipset
    final posSub = locationService.getPositionStream().listen((pos) {
      print('Streamed Position: (${pos.latitude}, ${pos.longitude}), acc: ±${pos.accuracy}m');
    });

    // Wait a brief window for satellite updates to stream in from hardware
    await Future.delayed(const Duration(seconds: 6));

    // 3. Query native GnssStatus
    final gnssSnapshot = await locationService.getGnssStatus();
    print('GNSS Snapshot: $gnssSnapshot');
    print('isSupported: ${gnssSnapshot.isSupported}');
    print('isAvailable: ${gnssSnapshot.isAvailable}');
    print('Total Satellites: ${gnssSnapshot.satelliteCount}');
    print('Satellites Used in Fix: ${gnssSnapshot.satellitesUsedInFix}');
    print('Has NavIC (IRNSS): ${gnssSnapshot.hasNavIC}');

    for (final entry in gnssSnapshot.constellations.entries) {
      print('Constellation: ${entry.value.displayName} (${entry.key}) -> Tracked: ${entry.value.trackedCount}, Used: ${entry.value.usedInFixCount}');
    }

    await posSub.cancel();

    // 4. Verify NavIC integrity
    if (gnssSnapshot.constellations.containsKey('irnss')) {
      expect(gnssSnapshot.hasNavIC, isTrue);
      print('Device natively reports CONSTELLATION_IRNSS (NavIC)');
    } else {
      expect(gnssSnapshot.hasNavIC, isFalse);
      print('Device does not report CONSTELLATION_IRNSS; NavIC correctly reported as false (no false claim)');
    }

    // 5. Query OS Location Provider
    Position? osPosition;
    try {
      osPosition = await locationService.getCurrentPosition();
    } catch (e) {
      print('getCurrentPosition note: $e');
    }

    if (osPosition != null) {
      print('OS Provider Position: Lat ${osPosition.latitude}, Lon ${osPosition.longitude}');
      print('OS Provider Accuracy: ±${osPosition.accuracy}m');
      print('OS Provider Altitude: ${osPosition.altitude}m');

      final gpsState = GpsHardwareState(
        hasValidFix: true,
        latitude: osPosition.latitude,
        longitude: osPosition.longitude,
        accuracyMeters: osPosition.accuracy,
        altitudeMeters: osPosition.altitude,
        timestampUtc: osPosition.timestamp.toUtc(),
        gnssSnapshot: gnssSnapshot,
      );

      final assessment = GnssQualityAssessment.evaluate(
        hasValidFix: true,
        accuracyMeters: osPosition.accuracy,
        gnssSnapshot: gnssSnapshot,
      );
      print('Deterministic Quality Assessment: FixStatus=${assessment.fixStatus.name}, Confidence=${assessment.confidence.name}, SatellitesUsed=${assessment.satellitesUsedInFix}');

      final snapshot = EvidenceMetadataSnapshot.capture(
        gpsState: gpsState,
        siteId: 'PHYSICAL_TEST_SITE',
        siteCode: 'TEST',
        siteName: 'Hardware Test Site',
      );

      print('EvidenceMetadataSnapshot captured at shutter time:');
      print(' - Latitude: ${snapshot.latitude}');
      print(' - Longitude: ${snapshot.longitude}');
      print(' - Accuracy: ${snapshot.accuracyDisplay}');
      print(' - Altitude: ${snapshot.altitudeDisplay}');
      print(' - GNSS Satellite Count: ${snapshot.gnssSatelliteCount}');
      print(' - GNSS Used in Fix: ${snapshot.gnssSatellitesUsedInFix}');

      expect(snapshot.latitude, osPosition.latitude);
      expect(snapshot.longitude, osPosition.longitude);
      expect(snapshot.accuracyMeters, osPosition.accuracy);
    } else {
      print('OS Location Position not currently locked or permission required in test runner environment.');
    }

    await locationService.stopGnssUpdates();
    print('--- GNSS VERIFICATION COMPLETE ---');
  });
}
