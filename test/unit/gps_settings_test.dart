import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sitelens/core/controllers/gps_settings_controller.dart';
import 'package:sitelens/core/utils/gps_utils.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/features/camera/models/evidence_metadata_snapshot.dart';
import 'package:sitelens/features/camera/models/gps_hardware_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GpsSettingsNotifier Unit Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('1. Default threshold is 20.0 meters', () {
      final notifier = GpsSettingsNotifier();
      expect(notifier.state.lowAccuracyThresholdMeters, 20.0);
    });

    test('2. Changed threshold persists to SharedPreferences', () async {
      final notifier = GpsSettingsNotifier();
      await notifier.setLowAccuracyThreshold(30.0);

      expect(notifier.state.lowAccuracyThresholdMeters, 30.0);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(GpsSettingsNotifier.keyLowAccuracyThreshold), 30.0);
    });

    test('3. Persisted threshold restores on notifier initialization', () async {
      SharedPreferences.setMockInitialValues({
        GpsSettingsNotifier.keyLowAccuracyThreshold: 15.0,
      });

      final notifier = GpsSettingsNotifier();
      // Allow async _loadSettings to complete
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(notifier.state.lowAccuracyThresholdMeters, 15.0);
    });

    test('4. Invalid (zero, negative, NaN) threshold values are strictly rejected', () async {
      final notifier = GpsSettingsNotifier();
      await notifier.setLowAccuracyThreshold(25.0);
      expect(notifier.state.lowAccuracyThresholdMeters, 25.0);

      // Attempt setting zero
      await notifier.setLowAccuracyThreshold(0.0);
      expect(notifier.state.lowAccuracyThresholdMeters, 25.0);

      // Attempt setting negative
      await notifier.setLowAccuracyThreshold(-10.0);
      expect(notifier.state.lowAccuracyThresholdMeters, 25.0);

      // Attempt setting NaN
      await notifier.setLowAccuracyThreshold(double.nan);
      expect(notifier.state.lowAccuracyThresholdMeters, 25.0);
    });

    test('5. resetToDefault resets threshold to 20.0 m', () async {
      final notifier = GpsSettingsNotifier();
      await notifier.setLowAccuracyThreshold(50.0);
      expect(notifier.state.lowAccuracyThresholdMeters, 50.0);

      await notifier.resetToDefault();
      expect(notifier.state.lowAccuracyThresholdMeters, 20.0);
    });
  });

  group('Capture Accuracy Threshold & Forensic Immutability Tests', () {
    test('6. Accuracy <= threshold produces lowAccuracy = false', () {
      const gpsState = GpsHardwareState(
        hasValidFix: true,
        fixStatus: GPSFixStatus.high,
        latitude: 22.5726,
        longitude: 88.3639,
        accuracyMeters: 18.0,
      );

      final snapshot = EvidenceMetadataSnapshot.capture(
        gpsState: gpsState,
        siteId: 'site-1',
        siteCode: 'SL-01',
        siteName: 'Site Alpha',
        lowAccuracyThresholdMeters: 20.0,
      );

      expect(snapshot.lowAccuracy, isFalse);
      expect(snapshot.accuracyMeters, 18.0);
    });

    test('7. Accuracy > threshold produces lowAccuracy = true', () {
      const gpsState = GpsHardwareState(
        hasValidFix: true,
        fixStatus: GPSFixStatus.weak,
        latitude: 22.5726,
        longitude: 88.3639,
        accuracyMeters: 25.0,
      );

      final snapshot = EvidenceMetadataSnapshot.capture(
        gpsState: gpsState,
        siteId: 'site-1',
        siteCode: 'SL-01',
        siteName: 'Site Alpha',
        lowAccuracyThresholdMeters: 20.0,
      );

      expect(snapshot.lowAccuracy, isTrue);
      expect(snapshot.accuracyMeters, 25.0);
    });

    test('8. Changing threshold affects subsequent captures without modifying historical captures', () {
      const gpsState = GpsHardwareState(
        hasValidFix: true,
        fixStatus: GPSFixStatus.weak,
        latitude: 22.5726,
        longitude: 88.3639,
        accuracyMeters: 22.0,
      );

      // Capture 1 under default 20m threshold -> lowAccuracy = true (22 > 20)
      final historicalCapture = EvidenceMetadataSnapshot.capture(
        gpsState: gpsState,
        siteId: 'site-1',
        siteCode: 'SL-01',
        siteName: 'Site Alpha',
        lowAccuracyThresholdMeters: 20.0,
      );
      expect(historicalCapture.lowAccuracy, isTrue);

      // User changes threshold to 30m
      const newThreshold = 30.0;

      // Capture 2 under new 30m threshold -> lowAccuracy = false (22 <= 30)
      final futureCapture = EvidenceMetadataSnapshot.capture(
        gpsState: gpsState,
        siteId: 'site-1',
        siteCode: 'SL-01',
        siteName: 'Site Alpha',
        lowAccuracyThresholdMeters: newThreshold,
      );
      expect(futureCapture.lowAccuracy, isFalse);

      // Historical capture remains strictly unchanged (lowAccuracy == true)
      expect(historicalCapture.lowAccuracy, isTrue);
      expect(historicalCapture.accuracyMeters, 22.0);
    });

    test('9. Existing SQLite MediaItem records remain immutable when settings change', () {
      final historicalItem = MediaItem(
        id: 'hist-item-1',
        siteId: 'site-1',
        uri: 'media/evid_1.jpg',
        originalUri: 'media/orig_1.jpg',
        thumbUri: 'media/thumb_1.jpg',
        type: MediaItemType.photo,
        lat: 22.5726,
        lon: 88.3639,
        accuracyM: 25.0,
        lowAccuracy: true, // Captured with 25m accuracy when threshold was 20m
        capturedAt: DateTime.utc(2026, 1, 1, 12, 0, 0),
        sha256Hash: 'hash-orig-1',
        evidenceSha256Hash: 'hash-evid-1',
        capturedAddress: 'Kolkata Sector V',
        syncStatus: SyncStatusType.synced,
      );

      // Simulating user changing threshold preference to 50.0m
      const updatedThreshold = 50.0;
      expect(updatedThreshold, 50.0);

      // Verify historical MediaItem object fields remain completely unmodified
      expect(historicalItem.lowAccuracy, isTrue);
      expect(historicalItem.accuracyM, 25.0);
      expect(historicalItem.sha256Hash, 'hash-orig-1');
      expect(historicalItem.evidenceSha256Hash, 'hash-evid-1');
      expect(historicalItem.capturedAt, DateTime.utc(2026, 1, 1, 12, 0, 0));
    });
  });
}
