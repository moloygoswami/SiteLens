import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:sitelens/core/services/permission_service.dart';
import 'package:sitelens/core/utils/gps_utils.dart';
import 'package:sitelens/features/camera/controllers/camera_hardware_controller.dart';
import 'package:sitelens/features/camera/controllers/gps_hardware_controller.dart';
import 'package:sitelens/features/camera/models/camera_hardware_state.dart';
import 'package:sitelens/features/camera/models/gnss_snapshot.dart';
import 'package:sitelens/features/camera/models/gps_hardware_state.dart';
import 'package:sitelens/features/camera/services/camera_hardware_service.dart';
import 'package:sitelens/features/camera/services/location_hardware_service.dart';

// -----------------------------------------------------------------------------
// Test Doubles & Mocks
// -----------------------------------------------------------------------------

class _MockCameraService extends CameraHardwareService {
  final List<CameraDescription> cameras;
  bool isRecording = false;
  double minZoom = 1.0;
  double maxZoom = 4.0;
  ResolutionPreset? lastPreset;
  bool? lastAudio;

  _MockCameraService([this.cameras = const []]);

  @override
  Future<List<CameraDescription>> getAvailableCameras() async => cameras;

  @override
  CameraController createController({
    required CameraDescription cameraDescription,
    ResolutionPreset resolutionPreset = ResolutionPreset.max,
    bool enableAudio = true,
  }) {
    lastPreset = resolutionPreset;
    lastAudio = enableAudio;
    return super.createController(
      cameraDescription: cameraDescription,
      resolutionPreset: resolutionPreset,
      enableAudio: enableAudio,
    );
  }

  @override
  Future<void> initializeController(CameraController controller) async {}

  @override
  Future<double> getMinZoomLevel(CameraController controller) async => minZoom;

  @override
  Future<double> getMaxZoomLevel(CameraController controller) async => maxZoom;

  @override
  Future<void> setZoomLevel(CameraController controller, double zoom) async {}

  @override
  Future<void> startVideoRecording(CameraController controller) async {
    isRecording = true;
  }

  @override
  Future<XFile> stopVideoRecording(CameraController controller) async {
    isRecording = false;
    return XFile('/tmp/test_video.mp4');
  }

  @override
  bool isRecordingVideo(CameraController? controller) => isRecording;

  @override
  Future<void> disposeController(CameraController? controller) async {}
}

class _MockPermissionService extends PermissionService {
  PermissionStatus cameraPerm;
  PermissionStatus micPerm;

  _MockPermissionService({
    this.cameraPerm = PermissionStatus.granted,
    this.micPerm = PermissionStatus.granted,
  });

  @override
  Future<PermissionStatus> checkCameraPermission() async => cameraPerm;

  @override
  Future<PermissionStatus> checkMicrophonePermission() async => micPerm;

  @override
  Future<SiteLensPermissionStatus> checkAllPermissions() async {
    final s = SiteLensPermissionStatus(
      camera: cameraPerm,
      location: PermissionStatus.granted,
      microphone: micPerm,
    );
    state = s;
    return s;
  }
}

class _MockLocationService extends LocationHardwareService {
  bool serviceEnabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  Position? lastKnown;
  AltitudeTelemetry altitudeTelemetry = const AltitudeTelemetry(hasMslAltitude: false);
  final StreamController<Position> streamCtrl = StreamController<Position>.broadcast();
  GnssSnapshot gnssSnapshot = GnssSnapshot.unavailable;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<Position?> getLastKnownPosition() async => lastKnown;

  @override
  Future<AltitudeTelemetry> getAltitudeTelemetry() async => altitudeTelemetry;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings, bool highAccuracy = true}) => streamCtrl.stream;

  @override
  Future<GnssSnapshot> getGnssStatus() async => gnssSnapshot;

  @override
  Future<bool> startGnssUpdates() async => true;

  @override
  Future<bool> stopGnssUpdates() async => true;
}

final _dummyCamera = const CameraDescription(
  name: '0',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);

Position _createPosition({
  double lat = 22.5726,
  double lon = 88.3639,
  double accuracy = 4.2,
  double altitude = 15.0,
  double heading = 120.0,
  DateTime? timestamp,
}) {
  return Position(
    latitude: lat,
    longitude: lon,
    accuracy: accuracy,
    altitude: altitude,
    altitudeAccuracy: 1.0,
    heading: heading,
    headingAccuracy: 1.0,
    speed: 0.0,
    speedAccuracy: 1.0,
    timestamp: timestamp ?? DateTime.now(),
  );
}

// -----------------------------------------------------------------------------
// Slice 3 Normative Conformance Test Suite
// -----------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Slice 3 — Capture Context & Gating Unit Tests', () {
    // -------------------------------------------------------------------------
    // 1. Camera Readiness & Lifecycle
    // -------------------------------------------------------------------------
    group('1. Camera readiness and lifecycle handling', () {
      test('Initializes camera successfully to ready status', () async {
        final camService = _MockCameraService([_dummyCamera]);
        final permService = _MockPermissionService();
        final notifier = CameraHardwareNotifier(camService, permissionService: permService);
        await Future.delayed(Duration.zero);

        expect(notifier.state.status, CameraStatus.ready);
        expect(notifier.state.isReady, isTrue);
        expect(notifier.state.isUnavailable, isFalse);
      });

      test('Fails closed to unavailable when no hardware sensors exist', () async {
        final camService = _MockCameraService([]);
        final notifier = CameraHardwareNotifier(camService, permissionService: _MockPermissionService());
        await Future.delayed(Duration.zero);

        expect(notifier.state.status, CameraStatus.unavailable);
        expect(notifier.state.isReady, isFalse);
      });

      test('Transitions to permissionDenied when camera permission is denied', () async {
        final camService = _MockCameraService([_dummyCamera]);
        final permService = _MockPermissionService(cameraPerm: PermissionStatus.denied);
        final notifier = CameraHardwareNotifier(camService, permissionService: permService);
        await Future.delayed(Duration.zero);

        expect(notifier.state.status, CameraStatus.permissionDenied);
        expect(notifier.state.isReady, isFalse);
      });

      test('Transitions to permissionPermanentlyDenied when permanently denied', () async {
        final camService = _MockCameraService([_dummyCamera]);
        final permService = _MockPermissionService(cameraPerm: PermissionStatus.permanentlyDenied);
        final notifier = CameraHardwareNotifier(camService, permissionService: permService);
        await Future.delayed(Duration.zero);

        expect(notifier.state.status, CameraStatus.permissionPermanentlyDenied);
        expect(notifier.state.isReady, isFalse);
      });
    });

    // -------------------------------------------------------------------------
    // 2. All Seven Normative GPS States
    // -------------------------------------------------------------------------
    group('2. All seven normative GPS states remain distinct', () {
      test('State 1: permission undetermined', () {
        const state = GpsHardwareState(
          permissionStatus: LocationPermission.unableToDetermine,
          isLocationServiceEnabled: true,
        );
        expect(state.blockReason, GpsBlockReason.permissionUnknown);
        expect(state.hasLiveFix, isFalse);
      });

      test('State 2: permission denied', () {
        const state = GpsHardwareState(
          permissionStatus: LocationPermission.denied,
          isLocationServiceEnabled: true,
        );
        expect(state.blockReason, GpsBlockReason.permissionDenied);
        expect(state.hasLiveFix, isFalse);
      });

      test('State 3: location services off', () {
        const state = GpsHardwareState(
          permissionStatus: LocationPermission.whileInUse,
          isLocationServiceEnabled: false,
        );
        expect(state.blockReason, GpsBlockReason.serviceDisabled);
        expect(state.hasLiveFix, isFalse);
      });

      test('State 4: acquiring (searching, never had fix)', () {
        const state = GpsHardwareState(
          permissionStatus: LocationPermission.whileInUse,
          isLocationServiceEnabled: true,
          fixStatus: GPSFixStatus.searching,
          hasValidFix: false,
          isLiveFixStale: false,
          isLastKnownSeed: false,
        );
        expect(state.blockReason, GpsBlockReason.searching);
        expect(state.hasLiveFix, isFalse);
      });

      test('State 5: stale-only (last-known seed, never upgraded to live)', () {
        const state = GpsHardwareState(
          permissionStatus: LocationPermission.whileInUse,
          isLocationServiceEnabled: true,
          fixStatus: GPSFixStatus.high,
          hasValidFix: true,
          isLastKnownSeed: true,
          isLiveFixStale: false,
        );
        expect(state.blockReason, GpsBlockReason.lastKnownOnly);
        expect(state.hasLiveFix, isFalse);
        expect(state.statusBadgeLabel, 'GPS: Last known');
      });

      test('State 6: live-gone-stale (had live fix, stream timed out)', () {
        const state = GpsHardwareState(
          permissionStatus: LocationPermission.whileInUse,
          isLocationServiceEnabled: true,
          fixStatus: GPSFixStatus.searching,
          hasValidFix: false,
          isLiveFixStale: true,
          isLastKnownSeed: false,
        );
        expect(state.blockReason, GpsBlockReason.liveGoneStale);
        expect(state.hasLiveFix, isFalse);
        expect(state.statusBadgeLabel, 'GPS: Fix lost');
      });

      test('State 7: live-current (active and fresh live fix)', () {
        const state = GpsHardwareState(
          permissionStatus: LocationPermission.whileInUse,
          isLocationServiceEnabled: true,
          fixStatus: GPSFixStatus.high,
          hasValidFix: true,
          isLastKnownSeed: false,
          isLiveFixStale: false,
          latitude: 22.57,
          longitude: 88.36,
          accuracyMeters: 4.5,
        );
        expect(state.blockReason, isNull);
        expect(state.hasLiveFix, isTrue);
      });
    });

    // -------------------------------------------------------------------------
    // 3. Live vs Cached/Stale GPS & Degraded Behavior
    // -------------------------------------------------------------------------
    group('3. Live vs cached/stale GPS and degraded live behavior', () {
      test('Cached last-known seed NEVER provides hasLiveFix', () {
        final state = const GpsHardwareState().copyWith(
          hasValidFix: true,
          isLastKnownSeed: true,
          isLiveFixStale: false,
          latitude: 22.5,
          longitude: 88.3,
        );
        expect(state.hasLiveFix, isFalse);
      });

      test('Stale live fix NEVER provides hasLiveFix', () {
        final state = const GpsHardwareState().copyWith(
          hasValidFix: true,
          isLastKnownSeed: false,
          isLiveFixStale: true,
          latitude: 22.5,
          longitude: 88.3,
        );
        expect(state.hasLiveFix, isFalse);
      });

      test('Live fix evaluates accuracy using single configurable threshold', () {
        const threshold = 15.0;
        expect(
          GPSUtils.evaluateAccuracy(5.0, hasFix: true, lowAccuracyThresholdMeters: threshold),
          GPSFixStatus.high,
        );
        expect(
          GPSUtils.evaluateAccuracy(15.1, hasFix: true, lowAccuracyThresholdMeters: threshold),
          GPSFixStatus.poor,
        );
      });

      test('Degraded live GPS allows capture but marks fixStatus as poor', () {
        final state = const GpsHardwareState().copyWith(
          hasValidFix: true,
          fixStatus: GPSFixStatus.poor,
          isLastKnownSeed: false,
          isLiveFixStale: false,
          accuracyMeters: 35.0,
        );
        expect(state.hasLiveFix, isTrue);
        expect(state.isDegraded, isTrue);
      });
    });

    // -------------------------------------------------------------------------
    // 4. Capture-Readiness Gating & Below UI Boundary Enforcement
    // -------------------------------------------------------------------------
    group('4. Capture-readiness gating below UI boundary', () {
      test('startVideoRecording fails closed when creatorId is null or empty', () async {
        final camService = _MockCameraService([_dummyCamera]);
        final notifier = CameraHardwareNotifier(camService, permissionService: _MockPermissionService());
        await Future.delayed(Duration.zero);

        const liveGps = GpsHardwareState(
          hasValidFix: true,
          fixStatus: GPSFixStatus.high,
          isLastKnownSeed: false,
          isLiveFixStale: false,
        );

        final result = await notifier.startVideoRecording(
          recordingCreatorId: null,
          recordingSiteId: 'site-123',
          recordingGpsState: liveGps,
        );
        expect(result, isFalse);
        expect(notifier.state.isRecordingVideo, isFalse);
      });

      test('startVideoRecording fails closed when siteId is null or empty', () async {
        final camService = _MockCameraService([_dummyCamera]);
        final notifier = CameraHardwareNotifier(camService, permissionService: _MockPermissionService());
        await Future.delayed(Duration.zero);

        const liveGps = GpsHardwareState(
          hasValidFix: true,
          fixStatus: GPSFixStatus.high,
          isLastKnownSeed: false,
          isLiveFixStale: false,
        );

        final result = await notifier.startVideoRecording(
          recordingCreatorId: 'user-123',
          recordingSiteId: '',
          recordingGpsState: liveGps,
        );
        expect(result, isFalse);
        expect(notifier.state.isRecordingVideo, isFalse);
      });

      test('startVideoRecording fails closed when GPS is not live (cached seed)', () async {
        final camService = _MockCameraService([_dummyCamera]);
        final notifier = CameraHardwareNotifier(camService, permissionService: _MockPermissionService());
        await Future.delayed(Duration.zero);

        const seedGps = GpsHardwareState(
          hasValidFix: true,
          fixStatus: GPSFixStatus.high,
          isLastKnownSeed: true,
          isLiveFixStale: false,
        );

        final result = await notifier.startVideoRecording(
          recordingCreatorId: 'user-123',
          recordingSiteId: 'site-123',
          recordingGpsState: seedGps,
        );
        expect(result, isFalse);
        expect(notifier.state.isRecordingVideo, isFalse);
      });

      test('startVideoRecording fails closed when camera is not ready', () async {
        final camService = _MockCameraService([]);
        final notifier = CameraHardwareNotifier(camService, permissionService: _MockPermissionService());
        await Future.delayed(Duration.zero);

        const liveGps = GpsHardwareState(
          hasValidFix: true,
          fixStatus: GPSFixStatus.high,
          isLastKnownSeed: false,
          isLiveFixStale: false,
        );

        final result = await notifier.startVideoRecording(
          recordingCreatorId: 'user-123',
          recordingSiteId: 'site-123',
          recordingGpsState: liveGps,
        );
        expect(result, isFalse);
      });
    });

    // -------------------------------------------------------------------------
    // 5. Atomic Video T0 Context Freeze & Immutability
    // -------------------------------------------------------------------------
    group('5. Atomic video T0 context freeze and immutability', () {
      test('startVideoRecording atomically freezes timestamp, site, creator, GPS, and audio', () async {
        final camService = _MockCameraService([_dummyCamera]);
        final notifier = CameraHardwareNotifier(camService, permissionService: _MockPermissionService());
        await Future.delayed(Duration.zero);

        final t0Gps = const GpsHardwareState().copyWith(
          hasValidFix: true,
          fixStatus: GPSFixStatus.high,
          isLastKnownSeed: false,
          isLiveFixStale: false,
          latitude: 22.5726,
          longitude: 88.3639,
          altitudeMeters: 25.0,
          accuracyMeters: 3.2,
        );

        final success = await notifier.startVideoRecording(
          recordingCreatorId: 'creator-alpha',
          recordingSiteId: 'site-001',
          recordingSiteCode: 'SITE-A',
          recordingSiteName: 'Site Alpha',
          recordingGpsState: t0Gps,
        );

        expect(success, isTrue);
        expect(notifier.state.isRecordingVideo, isTrue);
        expect(notifier.state.recordingStartedAtUtc, isNotNull);
        expect(notifier.state.recordingCreatorId, 'creator-alpha');
        expect(notifier.state.recordingSiteId, 'site-001');
        expect(notifier.state.recordingSiteCode, 'SITE-A');
        expect(notifier.state.recordingSiteName, 'Site Alpha');
        expect(notifier.state.recordingGpsState?.latitude, 22.5726);
        expect(notifier.state.recordingGpsState?.longitude, 88.3639);
        expect(notifier.state.recordingHasAudioTrack, notifier.state.isAudioEnabled);
      });

      test('Later GPS stream emissions do not mutate frozen recording context', () async {
        final camService = _MockCameraService([_dummyCamera]);
        final notifier = CameraHardwareNotifier(camService, permissionService: _MockPermissionService());
        await Future.delayed(Duration.zero);

        final t0Gps = const GpsHardwareState().copyWith(
          hasValidFix: true,
          latitude: 10.0,
          longitude: 20.0,
        );

        await notifier.startVideoRecording(
          recordingCreatorId: 'creator-alpha',
          recordingSiteId: 'site-001',
          recordingSiteCode: 'SITE-A',
          recordingSiteName: 'Site Alpha',
          recordingGpsState: t0Gps,
        );

        // The recording state remains frozen at T0 values
        expect(notifier.state.recordingGpsState?.latitude, 10.0);
        expect(notifier.state.recordingGpsState?.longitude, 20.0);
        expect(notifier.state.recordingSiteId, 'site-001');
      });
    });

    // -------------------------------------------------------------------------
    // 6. Truthful Audio Disclosure
    // -------------------------------------------------------------------------
    group('6. Audio permission and recording disclosure', () {
      test('Microphone permission denied disables audio track truthfully', () async {
        final camService = _MockCameraService([_dummyCamera]);
        final permService = _MockPermissionService(micPerm: PermissionStatus.denied);
        final notifier = CameraHardwareNotifier(camService, permissionService: permService);
        await Future.delayed(Duration.zero);

        expect(notifier.state.isAudioEnabled, isFalse);

        const liveGps = GpsHardwareState(
          hasValidFix: true,
          fixStatus: GPSFixStatus.high,
          isLastKnownSeed: false,
          isLiveFixStale: false,
        );

        await notifier.startVideoRecording(
          recordingCreatorId: 'user-1',
          recordingSiteId: 'site-1',
          recordingGpsState: liveGps,
        );

        expect(notifier.state.recordingHasAudioTrack, isFalse);
      });

      test('Microphone permission granted enables audio track', () async {
        final camService = _MockCameraService([_dummyCamera]);
        final permService = _MockPermissionService(micPerm: PermissionStatus.granted);
        final notifier = CameraHardwareNotifier(camService, permissionService: permService);
        await Future.delayed(Duration.zero);

        expect(notifier.state.isAudioEnabled, isTrue);

        const liveGps = GpsHardwareState(
          hasValidFix: true,
          fixStatus: GPSFixStatus.high,
          isLastKnownSeed: false,
          isLiveFixStale: false,
        );

        await notifier.startVideoRecording(
          recordingCreatorId: 'user-1',
          recordingSiteId: 'site-1',
          recordingGpsState: liveGps,
        );

        expect(notifier.state.recordingHasAudioTrack, isTrue);
      });
    });

    // -------------------------------------------------------------------------
    // 7. Null Unavailable Telemetry (No Synthetic Values)
    // -------------------------------------------------------------------------
    group('7. Unavailable telemetry remains explicitly null', () {
      test('Bearing 0.0 is treated as unavailable (null), never synthesized to North 0°', () async {
        final locService = _MockLocationService();
        final notifier = GpsHardwareNotifier(locService);
        await Future.delayed(Duration.zero);

        // Stream a position with heading: 0.0 (plugin's unavailable sentinel)
        locService.streamCtrl.add(_createPosition(heading: 0.0));
        await Future.delayed(const Duration(milliseconds: 50));

        expect(notifier.state.headingDegrees, isNull);
      });

      test('Unavailable altitude remains null, never synthesized to 0.0', () async {
        final locService = _MockLocationService();
        locService.altitudeTelemetry = const AltitudeTelemetry(
          hasMslAltitude: false,
          mslAltitudeMeters: null,
          wgs84AltitudeMeters: null,
        );
        final notifier = GpsHardwareNotifier(locService);
        await Future.delayed(Duration.zero);

        locService.streamCtrl.add(_createPosition());
        await Future.delayed(const Duration(milliseconds: 50));

        expect(notifier.state.altitudeMeters, isNull);
        expect(notifier.state.isAltitudeMsl, isFalse);
      });
    });

    // -------------------------------------------------------------------------
    // 8. Shutter Re-entrancy
    // -------------------------------------------------------------------------
    group('8. Shutter non-reentrancy', () {
      test('ShutterReentrancyGuard prevents re-entrant execution', () {
        final guard = ShutterReentrancyGuard();

        expect(guard.isExecuting, isFalse);
        expect(guard.tryAcquire(), isTrue);
        expect(guard.isExecuting, isTrue);

        // Second acquire while busy must fail
        expect(guard.tryAcquire(), isFalse);
        expect(guard.isExecuting, isTrue);

        guard.release();
        expect(guard.isExecuting, isFalse);

        // Next acquire succeeds
        expect(guard.tryAcquire(), isTrue);
        guard.release();
        expect(guard.isExecuting, isFalse);
      });
    });

    // -------------------------------------------------------------------------
    // 9. App-Resume Resynchronization
    // -------------------------------------------------------------------------
    group('9. App-resume resynchronization', () {
      test('Resuming location stream when permission revoked drops fix to searching', () async {
        final locService = _MockLocationService();
        final notifier = GpsHardwareNotifier(locService);
        await Future.delayed(Duration.zero);

        // Simulate active live fix
        locService.streamCtrl.add(_createPosition());
        await Future.delayed(const Duration(milliseconds: 50));
        expect(notifier.state.hasLiveFix, isTrue);

        // Pause for backgrounding
        notifier.pauseLocationStream();

        // While backgrounded, OS permission is revoked
        locService.permission = LocationPermission.denied;

        // App resumes
        await notifier.resumeLocationStream();

        expect(notifier.state.hasValidFix, isFalse);
        expect(notifier.state.hasLiveFix, isFalse);
        expect(notifier.state.blockReason, GpsBlockReason.permissionDenied);
      });

      test('Resuming location stream when service disabled drops fix', () async {
        final locService = _MockLocationService();
        final notifier = GpsHardwareNotifier(locService);
        await Future.delayed(Duration.zero);

        locService.streamCtrl.add(_createPosition());
        await Future.delayed(const Duration(milliseconds: 50));
        expect(notifier.state.hasLiveFix, isTrue);

        notifier.pauseLocationStream();
        locService.serviceEnabled = false;

        await notifier.resumeLocationStream();

        expect(notifier.state.hasValidFix, isFalse);
        expect(notifier.state.blockReason, GpsBlockReason.serviceDisabled);
      });
    });

    // -------------------------------------------------------------------------
    // 10. Zero Network Requirement (Offline Capture)
    // -------------------------------------------------------------------------
    group('10. Offline capture independence', () {
      test('Capture context is valid and functional with no network connectivity', () async {
        final camService = _MockCameraService([_dummyCamera]);
        final notifier = CameraHardwareNotifier(camService, permissionService: _MockPermissionService());
        await Future.delayed(Duration.zero);

        const offlineLiveGps = GpsHardwareState(
          hasValidFix: true,
          fixStatus: GPSFixStatus.high,
          isLastKnownSeed: false,
          isLiveFixStale: false,
          latitude: 22.57,
          longitude: 88.36,
          accuracyMeters: 5.0,
        );

        // Zero network checks: capture initiates purely on camera + GPS + site + creator
        final success = await notifier.startVideoRecording(
          recordingCreatorId: 'offline-creator',
          recordingSiteId: 'offline-site-01',
          recordingGpsState: offlineLiveGps,
        );

        expect(success, isTrue);
        expect(notifier.state.isRecordingVideo, isTrue);
      });
    });
  });
}
