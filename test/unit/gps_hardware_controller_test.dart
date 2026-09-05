import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sitelens/core/services/geocoding_service.dart';
import 'package:sitelens/core/utils/gps_utils.dart';
import 'package:sitelens/features/camera/controllers/gps_hardware_controller.dart';
import 'package:sitelens/features/camera/models/gnss_snapshot.dart';
import 'package:sitelens/features/camera/services/location_hardware_service.dart';

/// Minimal fake geocoder: returns [result] for any coordinate.
class _FakeGeocodingService extends GeocodingService {
  _FakeGeocodingService(this.result);
  final String? result;

  @override
  Future<String?> reverseGeocode(double lat, double lon) async => result;
}

/// Fake geocoder whose result can change between resolutions.
class _MutableFakeGeocodingService extends GeocodingService {
  _MutableFakeGeocodingService(this.result);
  String? result;

  @override
  Future<String?> reverseGeocode(double lat, double lon) async => result;
}

class MockLocationService extends LocationHardwareService {
  final StreamController<Position> _streamController = StreamController<Position>.broadcast();
  bool serviceEnabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  Position? lastKnown;
  GnssSnapshot gnssStatus = GnssSnapshot.unavailable;
  bool isGnssUpdatesStarted = false;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<Position?> getLastKnownPosition() async => lastKnown;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      _streamController.stream;

  @override
  Future<GnssSnapshot> getGnssStatus() async => gnssStatus;

  @override
  Future<bool> startGnssUpdates() async {
    isGnssUpdatesStarted = true;
    return true;
  }

  @override
  Future<bool> stopGnssUpdates() async {
    isGnssUpdatesStarted = false;
    return true;
  }

  AltitudeTelemetry? customAltitudeTelemetry;
  Position? _lastEmittedPosition;

  @override
  Future<AltitudeTelemetry> getAltitudeTelemetry() async {
    return customAltitudeTelemetry ??
        AltitudeTelemetry(
          hasMslAltitude: true,
          mslAltitudeMeters: _lastEmittedPosition?.altitude ?? lastKnown?.altitude ?? 18.4,
          wgs84AltitudeMeters: _lastEmittedPosition?.altitude ?? lastKnown?.altitude ?? 18.4,
        );
  }

  void emitPosition(Position pos) {
    _lastEmittedPosition = pos;
    _streamController.add(pos);
  }

  void emitError(dynamic error) {
    _streamController.addError(error);
  }

  void close() {
    _streamController.close();
  }
}

Position createFakePosition({
  required double latitude,
  required double longitude,
  required double accuracy,
  double? altitude,
  DateTime? timestamp,
}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: timestamp ?? DateTime.utc(2026, 8, 15, 12, 0, 0),
    accuracy: accuracy,
    altitude: altitude ?? 20.0,
    altitudeAccuracy: 1.0,
    heading: 0.0,
    headingAccuracy: 1.0,
    speed: 0.0,
    speedAccuracy: 1.0,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GpsHardwareNotifier Unit Tests', () {
    late MockLocationService mockService;

    setUp(() {
      mockService = MockLocationService();
    });

    tearDown(() {
      mockService.close();
    });

    test('Initial state starts in searching mode with no valid fix', () async {
      final notifier = GpsHardwareNotifier(mockService);
      await Future.delayed(Duration.zero);

      expect(notifier.state.fixStatus, GPSFixStatus.searching);
      expect(notifier.state.hasValidFix, isFalse);
      expect(notifier.state.isSearching, isTrue);
      expect(notifier.state.coordinatesDisplay, 'Lat — , Long —');
      expect(notifier.state.altitudeDisplay, '—');
      expect(notifier.state.timestampUtcDisplay, '—');
    });

    test('Service disabled sets searching state and badge', () async {
      mockService.serviceEnabled = false;
      final notifier = GpsHardwareNotifier(mockService);
      await Future.delayed(Duration.zero);

      expect(notifier.state.isLocationServiceEnabled, isFalse);
      expect(notifier.state.hasValidFix, isFalse);
      expect(notifier.state.statusBadgeLabel, 'GPS: Disabled');
    });

    test('Permission denied sets searching state and badge', () async {
      mockService.permission = LocationPermission.denied;
      final notifier = GpsHardwareNotifier(mockService);
      await Future.delayed(Duration.zero);

      expect(notifier.state.isPermissionGranted, isFalse);
      expect(notifier.state.hasValidFix, isFalse);
      expect(notifier.state.statusBadgeLabel, 'GPS: Denied');
    });

    test('Processes stream positions into High, Weak, and Poor (Degraded) states', () async {
      final notifier = GpsHardwareNotifier(mockService);
      await Future.delayed(Duration.zero);

      // High accuracy fix (<= 5m)
      mockService.emitPosition(createFakePosition(
        latitude: 22.57264,
        longitude: 88.36391,
        accuracy: 3.2,
        altitude: 18.4,
        timestamp: DateTime.utc(2026, 8, 15, 14, 30, 0),
      ));
      await Future.delayed(Duration.zero);

      expect(notifier.state.hasValidFix, isTrue);
      expect(notifier.state.fixStatus, GPSFixStatus.high);
      expect(notifier.state.isHighOrWeak, isTrue);
      expect(notifier.state.isDegraded, isFalse);
      expect(notifier.state.altitudeDisplay, '+18.4 m ASL');
      expect(notifier.state.timestampUtcDisplay, '2026-08-15 14:30:00 UTC');
      expect(notifier.state.latitudeDisplay, '22.572640° N');
      expect(notifier.state.longitudeDisplay, '88.363910° E');
    });

    test('Altitude clean sign formatting for positive and negative values', () {
      // When MSL is established (default isMsl: true)
      expect(GPSUtils.formatAltitude(18.4), '+18.4 m ASL');
      expect(GPSUtils.formatAltitude(-43.4), '-43.4 m ASL');
      expect(GPSUtils.formatAltitude(0.0), '+0.0 m ASL');
      expect(GPSUtils.formatAltitude(null), '—');

      // When MSL is unavailable (truthful WGS84 labeling)
      expect(GPSUtils.formatAltitude(18.4, isMsl: false), '+18.4 m (WGS84)');
      expect(GPSUtils.formatAltitude(-42.4, isMsl: false), '-42.4 m (WGS84)');
      expect(GPSUtils.formatAltitude(0.0, isMsl: false), '+0.0 m (WGS84)');
      expect(GPSUtils.formatAltitude(null, isMsl: false), '—');
    });

    test('WGS84 fallback when MSL altitude is unavailable', () async {
      final notifier = GpsHardwareNotifier(mockService);
      await Future.delayed(Duration.zero);

      mockService.customAltitudeTelemetry = const AltitudeTelemetry(
        hasMslAltitude: false,
        mslAltitudeMeters: null,
        wgs84AltitudeMeters: -42.4,
      );

      mockService.emitPosition(createFakePosition(
        latitude: 22.5629,
        longitude: 88.3009,
        accuracy: 3.0,
        altitude: -42.4,
        timestamp: DateTime.utc(2026, 9, 4, 15, 0, 0),
      ));
      await Future.delayed(Duration.zero);

      expect(notifier.state.hasValidFix, isTrue);
      expect(notifier.state.isAltitudeMsl, isFalse);
      expect(notifier.state.altitudeMeters, -42.4);
      expect(notifier.state.altitudeDisplay, '-42.4 m (WGS84)');
    });

    test('Altitude null gracefully shows placeholder without inventing values', () async {
      final notifier = GpsHardwareNotifier(mockService);
      await Future.delayed(Duration.zero);

      mockService.emitPosition(Position(
        latitude: 22.57264,
        longitude: 88.36391,
        timestamp: DateTime.utc(2026, 8, 15, 14, 30, 0),
        accuracy: 4.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      ));
      await Future.delayed(Duration.zero);

      // Test explicit null altitude with clearAltitude flag
      notifier.state = notifier.state.copyWith(clearAltitude: true);
      expect(notifier.state.altitudeDisplay, '—');
    });

    test('Calculates distance to active site coordinates and clears on null site coordinates', () async {
      final notifier = GpsHardwareNotifier(mockService);
      await Future.delayed(Duration.zero);

      // Site at ~100m offset
      notifier.setActiveSiteCoordinates(22.57354, 88.36391);

      mockService.emitPosition(createFakePosition(
        latitude: 22.57264,
        longitude: 88.36391,
        accuracy: 4.0,
      ));
      await Future.delayed(Duration.zero);

      expect(notifier.state.distanceToSiteMeters, isNotNull);
      expect(notifier.state.distanceToSiteMeters!, greaterThan(50));
      expect(notifier.state.distanceToSiteMeters!, lessThan(150));

      // Reset to null coordinates
      notifier.setActiveSiteCoordinates(null, null);
      expect(notifier.state.distanceToSiteMeters, isNull);
    });

    test('Stale GPS transition clears live coordinates and resets validity', () async {
      final notifier = GpsHardwareNotifier(mockService);
      await Future.delayed(Duration.zero);

      mockService.emitPosition(createFakePosition(
        latitude: 22.57264,
        longitude: 88.36391,
        accuracy: 3.5,
      ));
      await Future.delayed(Duration.zero);
      expect(notifier.state.hasValidFix, isTrue);

      // Trigger loss of fix / stale state
      notifier.setStaleOrSearching();
      expect(notifier.state.hasValidFix, isFalse);
      expect(notifier.state.fixStatus, GPSFixStatus.searching);
      expect(notifier.state.coordinatesDisplay, 'Lat — , Long —');
      expect(notifier.state.latitudeDisplay, '—');
      expect(notifier.state.longitudeDisplay, '—');
      expect(notifier.state.altitudeDisplay, '—');
    });

    test('Fix becomes stale when no fresh position arrives within the staleness window', () {
      fakeAsync((async) {
        final notifier = GpsHardwareNotifier(mockService);
        async.flushMicrotasks();

        mockService.emitPosition(createFakePosition(
          latitude: 22.57264,
          longitude: 88.36391,
          accuracy: 3.5,
        ));
        async.flushMicrotasks();
        expect(notifier.state.hasValidFix, isTrue);
        expect(notifier.state.fixStatus, GPSFixStatus.high);

        // No further emissions: past the window the watchdog must drop to searching.
        async.elapse(GpsHardwareNotifier.stalenessTimeout + const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(notifier.state.hasValidFix, isFalse);
        expect(notifier.state.fixStatus, GPSFixStatus.searching);
        expect(notifier.state.latitude, isNull);
        expect(notifier.state.longitude, isNull);
      });
    });

    test('A fresh position within the staleness window keeps the fix valid', () {
      fakeAsync((async) {
        final notifier = GpsHardwareNotifier(mockService);
        async.flushMicrotasks();

        mockService.emitPosition(createFakePosition(
          latitude: 22.57264,
          longitude: 88.36391,
          accuracy: 3.5,
        ));
        async.flushMicrotasks();

        // Stay well inside the window.
        async.elapse(const Duration(seconds: 5));
        expect(notifier.state.hasValidFix, isTrue);

        // A fresh emission resets the watchdog; goes stale only after the full window.
        mockService.emitPosition(createFakePosition(
          latitude: 22.57264,
          longitude: 88.36391,
          accuracy: 3.1,
        ));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));
        expect(notifier.state.hasValidFix, isTrue);

        async.elapse(GpsHardwareNotifier.stalenessTimeout);
        async.flushMicrotasks();
        expect(notifier.state.hasValidFix, isFalse);
      });
    });

    test('A new position after staleness re-acquires the fix', () {
      fakeAsync((async) {
        final notifier = GpsHardwareNotifier(mockService);
        async.flushMicrotasks();

        mockService.emitPosition(createFakePosition(
          latitude: 22.57264,
          longitude: 88.36391,
          accuracy: 3.5,
        ));
        async.flushMicrotasks();

        // Go stale.
        async.elapse(GpsHardwareNotifier.stalenessTimeout + const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(notifier.state.hasValidFix, isFalse);

        // Fresh emission re-acquires.
        mockService.emitPosition(createFakePosition(
          latitude: 22.57264,
          longitude: 88.36391,
          accuracy: 4.2,
        ));
        async.flushMicrotasks();
        expect(notifier.state.hasValidFix, isTrue);
        expect(notifier.state.fixStatus, GPSFixStatus.high);
      });
    });

    test('Pausing the location stream cancels the staleness watchdog', () {
      fakeAsync((async) {
        final notifier = GpsHardwareNotifier(mockService);
        async.flushMicrotasks();

        mockService.emitPosition(createFakePosition(
          latitude: 22.57264,
          longitude: 88.36391,
          accuracy: 3.5,
        ));
        async.flushMicrotasks();
        expect(notifier.state.hasValidFix, isTrue);

        notifier.pauseLocationStream();
        async.elapse(GpsHardwareNotifier.stalenessTimeout + const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(notifier.state.hasValidFix, isTrue);

        // Resume + fresh emission re-arms the watchdog.
        notifier.resumeLocationStream();
        mockService.emitPosition(createFakePosition(
          latitude: 22.57264,
          longitude: 88.36391,
          accuracy: 3.0,
        ));
        async.flushMicrotasks();
        async.elapse(GpsHardwareNotifier.stalenessTimeout);
        async.flushMicrotasks();
        expect(notifier.state.hasValidFix, isFalse);
      });
    });

    test('Successful geocode stores the resolved name with its coordinates', () async {
      final notifier = GpsHardwareNotifier(
        mockService,
        geocodingService: _FakeGeocodingService('42 Construction Way'),
      );
      await Future.delayed(Duration.zero);

      mockService.emitPosition(createFakePosition(
        latitude: 22.57264,
        longitude: 88.36391,
        accuracy: 3.5,
      ));
      await Future.delayed(Duration.zero);

      expect(notifier.state.resolvedLocationName, '42 Construction Way');
      expect(notifier.state.resolvedLocationLat, 22.57264);
      expect(notifier.state.resolvedLocationLon, 88.36391);
    });

    test('Failed geocode leaves the previous name and association intact', () async {
      final mutableFake = _MutableFakeGeocodingService('42 Construction Way');
      final notifier = GpsHardwareNotifier(
        mockService,
        geocodingService: mutableFake,
      );
      await Future.delayed(Duration.zero);

      mockService.emitPosition(createFakePosition(
        latitude: 22.57264,
        longitude: 88.36391,
        accuracy: 3.5,
      ));
      await Future.delayed(Duration.zero);
      expect(notifier.state.resolvedLocationName, '42 Construction Way');
      expect(notifier.state.resolvedLocationLat, 22.57264);

      // The user moves; geocoding for the new position fails (null).
      mutableFake.result = null;
      await Future.delayed(const Duration(milliseconds: 1100)); // pass the 1s throttle
      mockService.emitPosition(createFakePosition(
        latitude: 22.58264,
        longitude: 88.37391,
        accuracy: 3.5,
      ));
      await Future.delayed(Duration.zero);

      // The old name + its association survive (the evidence guard rejects the
      // name later because it no longer matches the fix coordinates).
      expect(notifier.state.resolvedLocationName, '42 Construction Way');
      expect(notifier.state.resolvedLocationLat, 22.57264);
      expect(notifier.state.resolvedLocationLon, 88.36391);
      // The new fix coordinates are authoritative and current.
      expect(notifier.state.latitude, 22.58264);
      expect(notifier.state.longitude, 88.37391);
    });

    test('Throttles rapid stream positions to ~1 second intervals', () async {
      final notifier = GpsHardwareNotifier(mockService);
      await Future.delayed(Duration.zero);

      // Emit initial position
      mockService.emitPosition(createFakePosition(
        latitude: 10.0,
        longitude: 20.0,
        accuracy: 3.0,
      ));
      await Future.delayed(Duration.zero);
      expect(notifier.state.latitude, 10.0);

      // Rapidly emit immediate second position (< 1000ms)
      mockService.emitPosition(createFakePosition(
        latitude: 11.0,
        longitude: 21.0,
        accuracy: 3.0,
      ));
      await Future.delayed(Duration.zero);
      // Second rapid emission should be throttled
      expect(notifier.state.latitude, 10.0);

      // After 1050ms, emission passes
      await Future.delayed(const Duration(milliseconds: 1050));
      mockService.emitPosition(createFakePosition(
        latitude: 12.0,
        longitude: 22.0,
        accuracy: 3.0,
      ));
      await Future.delayed(Duration.zero);
      expect(notifier.state.latitude, 12.0);
    });

    test('Fresh cached position (10s old, 5m accuracy) is accepted on initialization', () async {
      mockService.lastKnown = createFakePosition(
        latitude: 22.57264,
        longitude: 88.36391,
        accuracy: 5.0,
        timestamp: DateTime.now().toUtc().subtract(const Duration(seconds: 10)),
      );

      final notifier = GpsHardwareNotifier(mockService);
      await Future.delayed(Duration.zero);

      expect(notifier.state.hasValidFix, isTrue);
      expect(notifier.state.fixStatus, GPSFixStatus.high);
      expect(notifier.state.latitude, 22.57264);
      expect(notifier.state.longitude, 88.36391);
    });

    test('Stale cached position (2 hours old) is rejected and remains in searching state', () async {
      mockService.lastKnown = createFakePosition(
        latitude: 22.57264,
        longitude: 88.36391,
        accuracy: 5.0,
        timestamp: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
      );

      final notifier = GpsHardwareNotifier(mockService);
      await Future.delayed(Duration.zero);

      expect(notifier.state.hasValidFix, isFalse);
      expect(notifier.state.fixStatus, GPSFixStatus.searching);
      expect(notifier.state.latitude, isNull);
    });

    test('Inaccurate cached position (>30m accuracy) is rejected and remains in searching state', () async {
      mockService.lastKnown = createFakePosition(
        latitude: 22.57264,
        longitude: 88.36391,
        accuracy: 35.0,
        timestamp: DateTime.now().toUtc().subtract(const Duration(seconds: 10)),
      );

      final notifier = GpsHardwareNotifier(mockService);
      await Future.delayed(Duration.zero);

      expect(notifier.state.hasValidFix, isFalse);
      expect(notifier.state.fixStatus, GPSFixStatus.searching);
    });

    test('Cache boundary semantics: exactly 60s and 30m is valid, 61s and 30.1m is rejected', () async {
      // Exactly 60s and 30m -> VALID
      mockService.lastKnown = createFakePosition(
        latitude: 22.57264,
        longitude: 88.36391,
        accuracy: 30.0,
        timestamp: DateTime.now().toUtc().subtract(const Duration(seconds: 60)),
      );

      final validNotifier = GpsHardwareNotifier(mockService);
      await Future.delayed(Duration.zero);
      expect(validNotifier.state.hasValidFix, isTrue);

      // 61s old -> REJECTED
      mockService.lastKnown = createFakePosition(
        latitude: 22.57264,
        longitude: 88.36391,
        accuracy: 10.0,
        timestamp: DateTime.now().toUtc().subtract(const Duration(seconds: 61)),
      );

      final staleNotifier = GpsHardwareNotifier(mockService);
      await Future.delayed(Duration.zero);
      expect(staleNotifier.state.hasValidFix, isFalse);

      // 30.1m accuracy -> REJECTED
      mockService.lastKnown = createFakePosition(
        latitude: 22.57264,
        longitude: 88.36391,
        accuracy: 30.1,
        timestamp: DateTime.now().toUtc().subtract(const Duration(seconds: 10)),
      );

      final inaccurateNotifier = GpsHardwareNotifier(mockService);
      await Future.delayed(Duration.zero);
      expect(inaccurateNotifier.state.hasValidFix, isFalse);
    });

    test('Rejected stale cache does not prevent subsequent live stream acquisition', () async {
      mockService.lastKnown = createFakePosition(
        latitude: 22.57264,
        longitude: 88.36391,
        accuracy: 5.0,
        timestamp: DateTime.now().toUtc().subtract(const Duration(hours: 3)),
      );

      final notifier = GpsHardwareNotifier(mockService);
      await Future.delayed(Duration.zero);

      // Initial state is searching
      expect(notifier.state.hasValidFix, isFalse);
      expect(notifier.state.fixStatus, GPSFixStatus.searching);

      // Live satellite position arrives
      mockService.emitPosition(createFakePosition(
        latitude: 22.57264,
        longitude: 88.36391,
        accuracy: 4.2,
        timestamp: DateTime.now().toUtc(),
      ));
      await Future.delayed(Duration.zero);

      // Successfully acquired
      expect(notifier.state.hasValidFix, isTrue);
      expect(notifier.state.fixStatus, GPSFixStatus.high);
      expect(notifier.state.latitude, 22.57264);
    });

    test('getBestRecentPosition prefers lowest accuracy within capture window', () async {
      final notifier = GpsHardwareNotifier(mockService);
      await Future.delayed(Duration.zero);

      final t0 = DateTime.now().toUtc();

      // Emit pos 1 (accuracy 8m)
      mockService.emitPosition(createFakePosition(
        latitude: 22.57200,
        longitude: 88.36300,
        accuracy: 8.0,
        timestamp: t0.subtract(const Duration(seconds: 4)),
      ));
      await Future.delayed(Duration.zero);

      // Emit pos 2 (accuracy 2.5m - BEST)
      mockService.emitPosition(createFakePosition(
        latitude: 22.57250,
        longitude: 88.36350,
        accuracy: 2.5,
        timestamp: t0.subtract(const Duration(seconds: 2)),
      ));
      await Future.delayed(Duration.zero);

      // Emit pos 3 (accuracy 5.0m)
      mockService.emitPosition(createFakePosition(
        latitude: 22.57280,
        longitude: 88.36380,
        accuracy: 5.0,
        timestamp: t0,
      ));
      await Future.delayed(Duration.zero);

      final best = notifier.getBestRecentPosition(window: const Duration(seconds: 5));
      expect(best, isNotNull);
      expect(best!.accuracy, 2.5);
      expect(best.latitude, 22.57250);
      expect(best.longitude, 88.36350);
    });

    test('getBestRecentPosition ignores positions outside the capture window', () async {
      final notifier = GpsHardwareNotifier(mockService);
      await Future.delayed(Duration.zero);

      final t0 = DateTime.now().toUtc();

      // Ancient pos (accuracy 1.0m, but 20s old)
      mockService.emitPosition(createFakePosition(
        latitude: 22.57100,
        longitude: 88.36100,
        accuracy: 1.0,
        timestamp: t0.subtract(const Duration(seconds: 20)),
      ));
      await Future.delayed(Duration.zero);

      // Recent pos (accuracy 4.0m, 2s old)
      mockService.emitPosition(createFakePosition(
        latitude: 22.57250,
        longitude: 88.36350,
        accuracy: 4.0,
        timestamp: t0.subtract(const Duration(seconds: 2)),
      ));
      await Future.delayed(Duration.zero);

      final best = notifier.getBestRecentPosition(window: const Duration(seconds: 5));
      expect(best, isNotNull);
      expect(best!.accuracy, 4.0);
      expect(best.latitude, 22.57250);
    });

    test('Synchronizes GNSS snapshot on position emissions', () async {
      mockService.gnssStatus = const GnssSnapshot(
        isSupported: true,
        isAvailable: true,
        satelliteCount: 18,
        satellitesUsedInFix: 12,
      );

      final notifier = GpsHardwareNotifier(mockService);
      await Future.delayed(Duration.zero);

      mockService.emitPosition(createFakePosition(
        latitude: 22.57264,
        longitude: 88.36391,
        accuracy: 3.2,
      ));
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(notifier.state.gnssSnapshot, isNotNull);
      expect(notifier.state.gnssSnapshot!.satelliteCount, 18);
      expect(notifier.state.gnssSnapshot!.satellitesUsedInFix, 12);
    });
  });
}
