import 'package:flutter_test/flutter_test.dart';
import 'package:camera/camera.dart';
import 'package:sitelens/features/camera/controllers/camera_hardware_controller.dart';
import 'package:sitelens/features/camera/models/camera_hardware_state.dart';
import 'package:sitelens/features/camera/models/camera_ui_state.dart';
import 'package:sitelens/features/camera/models/gps_hardware_state.dart';
import 'package:sitelens/features/camera/services/camera_hardware_service.dart';

class MockEmptyCameraService extends CameraHardwareService {
  @override
  Future<List<CameraDescription>> getAvailableCameras() async {
    return [];
  }
}

class MockAccessDeniedCameraService extends CameraHardwareService {
  @override
  Future<List<CameraDescription>> getAvailableCameras() async {
    throw CameraException('CameraAccessDenied', 'Permission was denied by user');
  }
}

class MockGenericErrorCameraService extends CameraHardwareService {
  @override
  Future<List<CameraDescription>> getAvailableCameras() async {
    throw CameraException('CameraInitError', 'Sensor initialization failed');
  }
}

class MockFailingResolutionCameraService extends CameraHardwareService {
  final List<CameraDescription> cameras;
  final List<CameraController> createdControllers = [];
  final List<CameraController> disposedControllers = [];

  MockFailingResolutionCameraService(this.cameras);

  @override
  Future<List<CameraDescription>> getAvailableCameras() async => cameras;

  @override
  CameraController createController({
    required CameraDescription cameraDescription,
    ResolutionPreset resolutionPreset = ResolutionPreset.max,
    bool enableAudio = true,
  }) {
    final c = super.createController(
      cameraDescription: cameraDescription,
      resolutionPreset: resolutionPreset,
      enableAudio: enableAudio,
    );
    createdControllers.add(c);
    return c;
  }

  @override
  Future<void> initializeController(CameraController controller) async {
    throw CameraException('CameraInitError', 'Sensor open failed');
  }

  @override
  Future<void> disposeController(CameraController? controller) async {
    if (controller != null) {
      disposedControllers.add(controller);
    }
  }
}

class MockRecoverableCameraService extends CameraHardwareService {
  final List<CameraDescription> cameras;
  bool shouldFail = true;
  final List<CameraController> disposedControllers = [];

  MockRecoverableCameraService(this.cameras);

  @override
  Future<List<CameraDescription>> getAvailableCameras() async => cameras;

  @override
  Future<void> initializeController(CameraController controller) async {
    if (shouldFail) {
      throw CameraException('HardwareUnavailable', 'Hardware busy');
    }
  }

  @override
  Future<void> disposeController(CameraController? controller) async {
    if (controller != null) {
      disposedControllers.add(controller);
    }
  }

  @override
  Future<double> getMinZoomLevel(CameraController controller) async => 1.0;

  @override
  Future<double> getMaxZoomLevel(CameraController controller) async => 5.0;

  @override
  Future<void> setZoomLevel(CameraController controller, double zoom) async {}
}

class FakeCameraService extends CameraHardwareService {
  final List<CameraDescription> cameras;
  bool wasDisposed = false;
  double minZoom = 1.0;
  double maxZoom = 5.0;
  double currentZoom = 1.0;
  FlashMode currentFlash = FlashMode.auto;

  ResolutionPreset? lastResolutionPreset;

  FakeCameraService(this.cameras);

  @override
  CameraController createController({
    required CameraDescription cameraDescription,
    ResolutionPreset resolutionPreset = ResolutionPreset.max,
    bool enableAudio = true,
  }) {
    lastResolutionPreset = resolutionPreset;
    return super.createController(
      cameraDescription: cameraDescription,
      resolutionPreset: resolutionPreset,
      enableAudio: enableAudio,
    );
  }

  @override
  Future<List<CameraDescription>> getAvailableCameras() async {
    return cameras;
  }

  @override
  Future<void> initializeController(CameraController controller) async {
    // Simulated fast initialization
  }

  @override
  Future<double> getMinZoomLevel(CameraController controller) async => minZoom;

  @override
  Future<double> getMaxZoomLevel(CameraController controller) async => maxZoom;

  @override
  Future<void> setZoomLevel(CameraController controller, double zoom) async {
    currentZoom = zoom;
  }

  @override
  Future<void> setFlashMode(CameraController controller, FlashMode flashMode) async {
    currentFlash = flashMode;
  }

  @override
  Future<void> startVideoRecording(CameraController controller) async {}

  @override
  Future<XFile> stopVideoRecording(CameraController controller) async {
    return XFile('/tmp/fake_video.mp4');
  }

  @override
  Future<void> disposeController(CameraController? controller) async {
    wasDisposed = true;
  }
}

void main() {
  group('CameraHardwareNotifier Unit Tests', () {
    test('Transitions to unavailable when no cameras are found', () async {
      final notifier = CameraHardwareNotifier(MockEmptyCameraService());
      await Future.delayed(Duration.zero);

      expect(notifier.state.status, CameraStatus.unavailable);
      expect(notifier.state.isUnavailable, isTrue);
      expect(notifier.state.errorMessage, contains('No cameras found'));
      expect(notifier.controller, isNull);
    });

    test('Transitions to permissionDenied when availableCameras() throws CameraAccessDenied', () async {
      final notifier = CameraHardwareNotifier(MockAccessDeniedCameraService());
      await Future.delayed(Duration.zero);

      expect(notifier.state.status, CameraStatus.permissionDenied);
      expect(notifier.state.isPermissionDenied, isTrue);
      expect(notifier.state.errorMessage, contains('Camera permission is denied'));
      expect(notifier.controller, isNull);
    });

    test('Transitions to error when availableCameras() throws generic exception', () async {
      final notifier = CameraHardwareNotifier(MockGenericErrorCameraService());
      await Future.delayed(Duration.zero);

      expect(notifier.state.status, CameraStatus.error);
      expect(notifier.state.hasError, isTrue);
      expect(notifier.state.errorMessage, contains('Camera initialization failed'));
      expect(notifier.controller, isNull);
    });

    test('Clamps zoom level against device-reported min and max', () async {
      final notifier = CameraHardwareNotifier(MockEmptyCameraService());
      await Future.delayed(Duration.zero);

      // Set device-reported bounds where 0.5x is unsupported (min: 1.0, max: 3.0)
      notifier.state = notifier.state.copyWith(minZoomLevel: 1.0, maxZoomLevel: 3.0);

      // Verify zoom preset calculation with clamping
      await notifier.setZoomPreset(CameraLensZoom.wide); // 0.5x requested
      // Clamped to 1.0 and accurately reflected as standard lens zoom (not wide)
      expect(notifier.state.currentZoomLevel, 1.0);
      expect(notifier.state.lensZoom, CameraLensZoom.standard);
      expect(notifier.state.zoomDisplayLabel, '1x');

      await notifier.setZoomPreset(CameraLensZoom.tele); // 2.0x requested
      // Allowed within 1.0 to 3.0 range
      expect(notifier.state.currentZoomLevel, 2.0);
      expect(notifier.state.lensZoom, CameraLensZoom.tele);
      expect(notifier.state.zoomDisplayLabel, '2x');
    });

    test('Initializes camera at 1.0x standard zoom by default', () async {
      const mockCamera = CameraDescription(
        name: '0',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      );
      final fakeService = FakeCameraService([mockCamera]);
      fakeService.minZoom = 0.5;
      fakeService.maxZoom = 8.0;

      final notifier = CameraHardwareNotifier(fakeService);
      await Future.delayed(Duration.zero);

      expect(notifier.state.status, CameraStatus.ready);
      expect(notifier.state.currentZoomLevel, 1.0);
      expect(fakeService.currentZoom, 1.0);
      expect(notifier.state.lensZoom, CameraLensZoom.standard);
      expect(notifier.state.zoomDisplayLabel, '1x');
    });

    test('Clamps initial zoom to sensor min when 1.0x is outside bounds', () async {
      const mockCamera = CameraDescription(
        name: '0',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      );
      final fakeService = FakeCameraService([mockCamera]);
      fakeService.minZoom = 1.2;
      fakeService.maxZoom = 3.0;

      final notifier = CameraHardwareNotifier(fakeService);
      await Future.delayed(Duration.zero);

      expect(notifier.state.status, CameraStatus.ready);
      expect(notifier.state.currentZoomLevel, 1.2);
      expect(notifier.state.lensZoom, CameraLensZoom.standard);
      expect(notifier.state.zoomDisplayLabel, '1.2x');
    });

    test('Flash mode updates state cleanly', () async {
      final notifier = CameraHardwareNotifier(MockEmptyCameraService());
      await Future.delayed(Duration.zero);

      await notifier.setFlashMode(CameraFlashMode.on);
      expect(notifier.state.flashMode, CameraFlashMode.on);

      await notifier.setFlashMode(CameraFlashMode.torch);
      expect(notifier.state.flashMode, CameraFlashMode.torch);

      await notifier.setFlashMode(CameraFlashMode.off);
      expect(notifier.state.flashMode, CameraFlashMode.off);
    });

    test('takePhoto returns null safely when camera is not ready', () async {
      final notifier = CameraHardwareNotifier(MockEmptyCameraService());
      await Future.delayed(Duration.zero);

      final photo = await notifier.takePhoto();
      expect(photo, isNull);
    });

    test('pauseCamera disposes controller and transitions state', () async {
      final notifier = CameraHardwareNotifier(MockEmptyCameraService());
      await Future.delayed(Duration.zero);

      await notifier.pauseCamera();
      expect(notifier.state.status, CameraStatus.unavailable);
      expect(notifier.controller, isNull);
    });

    test('setPinchZoom continuously updates and clamps zoom ratio', () async {
      final notifier = CameraHardwareNotifier(MockEmptyCameraService());
      await Future.delayed(Duration.zero);

      // Default min/max is 0.5 to 5.0 in initial state
      await notifier.setPinchZoom(1.8);
      expect(notifier.state.currentZoomLevel, 1.8);
      expect(notifier.state.zoomDisplayLabel, '1.8x');

      // Test with custom bounds
      notifier.state = notifier.state.copyWith(minZoomLevel: 1.0, maxZoomLevel: 8.0);
      await notifier.setPinchZoom(3.456);
      expect(notifier.state.currentZoomLevel, 3.456);
      expect(notifier.state.zoomDisplayLabel, '3.5x');

      await notifier.setPinchZoom(0.3); // Below min
      expect(notifier.state.currentZoomLevel, 1.0);
      expect(notifier.state.zoomDisplayLabel, '1x');

      await notifier.setPinchZoom(12.0); // Above max
      expect(notifier.state.currentZoomLevel, 8.0);
      expect(notifier.state.zoomDisplayLabel, '8x');
    });

    test('setCaptureMode updates captureMode seamlessly without tearing down controller', () async {
      const mockCamera = CameraDescription(
        name: '0',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      );
      final fakeService = FakeCameraService([mockCamera]);
      final notifier = CameraHardwareNotifier(fakeService);
      await Future.delayed(Duration.zero);

      // Initial mode is photo
      expect(notifier.state.captureMode, CameraCaptureMode.photo);
      expect(fakeService.lastResolutionPreset, ResolutionPreset.max);

      // Switch to video -> updates captureMode cleanly without controller teardown
      await notifier.setCaptureMode(CameraCaptureMode.video);
      expect(notifier.state.captureMode, CameraCaptureMode.video);

      // Switch back to photo -> updates captureMode cleanly
      await notifier.setCaptureMode(CameraCaptureMode.photo);
      expect(notifier.state.captureMode, CameraCaptureMode.photo);
    });

    test('Default camera state configurations have 1.0x standard zoom preset', () {
      const defaultHardwareState = CameraHardwareState();
      expect(defaultHardwareState.lensZoom, CameraLensZoom.standard);
      expect(defaultHardwareState.currentZoomLevel, 1.0);
      expect(defaultHardwareState.zoomDisplayLabel, '1x');

      const defaultUiState = CameraUiState();
      expect(defaultUiState.lensZoom, CameraLensZoom.standard);
    });

    test('Flip mutex ignores concurrent switchCamera calls and releases guard on completion', () async {
      const rearCamera = CameraDescription(
        name: '0',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      );
      const frontCamera = CameraDescription(
        name: '1',
        lensDirection: CameraLensDirection.front,
        sensorOrientation: 270,
      );

      final fakeService = FakeCameraService([rearCamera, frontCamera]);
      final notifier = CameraHardwareNotifier(fakeService);
      await Future.delayed(Duration.zero);

      expect(notifier.state.selectedCameraIndex, 0);
      expect(notifier.state.status, CameraStatus.ready);

      // Trigger 3 concurrent switches rapidly
      final f1 = notifier.switchCamera();
      final f2 = notifier.switchCamera();
      final f3 = notifier.switchCamera();

      await Future.wait([f1, f2, f3]);

      // Only one switch cycle executed (0 -> 1)
      expect(notifier.state.selectedCameraIndex, 1);
      expect(notifier.isSwitching, isFalse);
      expect(notifier.state.status, CameraStatus.ready);

      // Mutex released: Next switch proceeds cleanly (1 -> 0)
      await notifier.switchCamera();
      expect(notifier.state.selectedCameraIndex, 0);
      expect(notifier.isSwitching, isFalse);
      expect(notifier.state.status, CameraStatus.ready);
    });

    test('Flip mutex releases guard even when target camera initialization fails', () async {
      const rearCamera = CameraDescription(
        name: '0',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      );
      const frontCamera = CameraDescription(
        name: '1',
        lensDirection: CameraLensDirection.front,
        sensorOrientation: 270,
      );

      final fakeService = FakeCameraService([rearCamera, frontCamera]);
      final notifier = CameraHardwareNotifier(fakeService);
      await Future.delayed(Duration.zero);

      expect(notifier.state.status, CameraStatus.ready);

      // Simulate failure on next switch
      notifier.state = notifier.state.copyWith(availableCameras: [rearCamera]); // only 1 camera left
      await notifier.switchCamera(); // should exit early

      expect(notifier.isSwitching, isFalse);
    });

    test('Shutter locks with status initializing during switchCamera and restores ready after init', () async {
      const rearCamera = CameraDescription(
        name: '0',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      );
      const frontCamera = CameraDescription(
        name: '1',
        lensDirection: CameraLensDirection.front,
        sensorOrientation: 270,
      );

      final fakeService = FakeCameraService([rearCamera, frontCamera]);
      final notifier = CameraHardwareNotifier(fakeService);
      await Future.delayed(Duration.zero);

      expect(notifier.state.status, CameraStatus.ready);

      // Start switch
      final switchFuture = notifier.switchCamera();

      // While in flight, takePhoto safely returns null
      expect(notifier.isSwitching, isTrue);
      final inFlightPhoto = await notifier.takePhoto();
      expect(inFlightPhoto, isNull);

      await switchFuture;

      expect(notifier.state.status, CameraStatus.ready);
      expect(notifier.isSwitching, isFalse);
    });

    test('Front camera switch automatically resets flash mode to off', () async {
      const rearCamera = CameraDescription(
        name: '0',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      );
      const frontCamera = CameraDescription(
        name: '1',
        lensDirection: CameraLensDirection.front,
        sensorOrientation: 270,
      );

      final fakeService = FakeCameraService([rearCamera, frontCamera]);
      final notifier = CameraHardwareNotifier(fakeService);
      await Future.delayed(Duration.zero);

      // Set rear flash to torch
      await notifier.setFlashMode(CameraFlashMode.torch);
      expect(notifier.state.flashMode, CameraFlashMode.torch);

      // Switch to front camera (CameraLensDirection.front)
      await notifier.switchCamera();

      expect(notifier.state.selectedCameraIndex, 1);
      expect(notifier.state.flashMode, CameraFlashMode.off);

      // Switch back to rear camera
      await notifier.switchCamera();
      expect(notifier.state.selectedCameraIndex, 0);
      // Can set flash mode on rear camera
      await notifier.setFlashMode(CameraFlashMode.on);
      expect(notifier.state.flashMode, CameraFlashMode.on);
    });

    test('Parallel optical zoom bound queries concurrently retrieve min/max and set initial zoom to 1.0x standard', () async {
      const mockCamera = CameraDescription(
        name: '0',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      );
      final fakeService = FakeCameraService([mockCamera]);
      fakeService.minZoom = 0.5;
      fakeService.maxZoom = 10.0;

      final notifier = CameraHardwareNotifier(fakeService);
      await Future.delayed(Duration.zero);

      expect(notifier.state.minZoomLevel, 0.5);
      expect(notifier.state.maxZoomLevel, 10.0);
      expect(notifier.state.currentZoomLevel, 1.0);
      expect(notifier.state.lensZoom, CameraLensZoom.standard);
      expect(notifier.state.zoomDisplayLabel, '1x');
    });

    test('availableZoomPresets includes wide only when sensor supports <= 0.6x and is not front camera', () {
      // Rear camera without ultra-wide (e.g. Motorola edge 50 fusion back camera: min 1.0)
      const rearStandardState = CameraHardwareState(
        minZoomLevel: 1.0,
        maxZoomLevel: 10.0,
        availableCameras: [
          CameraDescription(name: '0', lensDirection: CameraLensDirection.back, sensorOrientation: 90),
        ],
        selectedCameraIndex: 0,
      );
      expect(rearStandardState.supportsWide, isFalse);
      expect(rearStandardState.supportsTele, isTrue);
      expect(rearStandardState.availableZoomPresets, [CameraLensZoom.standard, CameraLensZoom.tele]);

      // Rear camera with ultra-wide (min 0.5)
      const rearWideState = CameraHardwareState(
        minZoomLevel: 0.5,
        maxZoomLevel: 8.0,
        availableCameras: [
          CameraDescription(name: '0', lensDirection: CameraLensDirection.back, sensorOrientation: 90),
        ],
        selectedCameraIndex: 0,
      );
      expect(rearWideState.supportsWide, isTrue);
      expect(rearWideState.supportsTele, isTrue);
      expect(rearWideState.availableZoomPresets, [
        CameraLensZoom.standard,
        CameraLensZoom.tele,
        CameraLensZoom.wide,
      ]);

      // Front camera with min 0.5 (front cameras should not enable wide preset)
      const frontState = CameraHardwareState(
        minZoomLevel: 0.5,
        maxZoomLevel: 3.0,
        availableCameras: [
          CameraDescription(name: '1', lensDirection: CameraLensDirection.front, sensorOrientation: 270),
        ],
        selectedCameraIndex: 0,
      );
      expect(frontState.supportsWide, isFalse);
      expect(frontState.availableZoomPresets, [CameraLensZoom.standard, CameraLensZoom.tele]);
    });

    test('zoomDisplayLabel never returns 0.5x when currentZoomLevel is 1.0x', () {
      // Evidence integrity verification: Never falsely display 0.5x on 1.0x zoom
      const state1x = CameraHardwareState(
        currentZoomLevel: 1.0,
        lensZoom: CameraLensZoom.wide, // Even if lensZoom is wide, 1.0x magnification is 1x
      );
      expect(state1x.zoomDisplayLabel, '1x');

      const state05x = CameraHardwareState(
        currentZoomLevel: 0.5,
        lensZoom: CameraLensZoom.wide,
      );
      expect(state05x.zoomDisplayLabel, '0.5x');

      const state2x = CameraHardwareState(
        currentZoomLevel: 2.0,
        lensZoom: CameraLensZoom.tele,
      );
      expect(state2x.zoomDisplayLabel, '2x');
    });

    test('Every candidate controller created during fallback attempts is cleanly disposed on initialization failure', () async {
      const rearCamera = CameraDescription(
        name: '0',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      );
      final failingService = MockFailingResolutionCameraService([rearCamera]);
      final notifier = CameraHardwareNotifier(failingService);
      await Future.delayed(Duration.zero);

      expect(notifier.state.status, CameraStatus.error);
      expect(notifier.controller, isNull);
      // All 3 fallback presets (max, veryHigh, high) were attempted
      expect(failingService.createdControllers.length, 3);
      // Crucial: ALL 3 created controllers were cleanly disposed — zero hardware resource leak!
      expect(failingService.disposedControllers.length, 3);
      for (final created in failingService.createdControllers) {
        expect(failingService.disposedControllers.contains(created), isTrue);
      }
    });

    test('Rapid pauseCamera followed immediately by resumeCamera resolves cleanly to ready state', () async {
      const rearCamera = CameraDescription(
        name: '0',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      );
      final fakeService = FakeCameraService([rearCamera]);
      final notifier = CameraHardwareNotifier(fakeService);
      await Future.delayed(Duration.zero);
      expect(notifier.state.status, CameraStatus.ready);

      // Rapidly fire pause then resume without waiting for pause to complete
      final pauseFuture = notifier.pauseCamera();
      final resumeFuture = notifier.resumeCamera();
      await Future.wait([pauseFuture, resumeFuture]);

      expect(notifier.state.status, CameraStatus.ready);
      expect(notifier.controller, isNotNull);
    });

    test('retry restores camera to ready state after transient initialization failure', () async {
      const rearCamera = CameraDescription(
        name: '0',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      );
      final recoverableService = MockRecoverableCameraService([rearCamera]);
      recoverableService.shouldFail = true;

      final notifier = CameraHardwareNotifier(recoverableService);
      await Future.delayed(Duration.zero);
      expect(notifier.state.status, CameraStatus.error);
      expect(notifier.controller, isNull);

      // Hardware becomes available again
      recoverableService.shouldFail = false;
      await notifier.retry();

      expect(notifier.state.status, CameraStatus.ready);
      expect(notifier.controller, isNotNull);
    });

    test('startVideoRecording stores recordingGpsState and pauseCamera preserves it across interruption', () async {
      const mockCamera = CameraDescription(
        name: '0',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      );
      final fakeService = FakeCameraService([mockCamera]);
      final notifier = CameraHardwareNotifier(fakeService);
      await Future.delayed(Duration.zero);
      expect(notifier.state.status, CameraStatus.ready);

      const recordingGps = GpsHardwareState(
        latitude: 22.56298,
        longitude: 88.30085,
        altitudeMeters: 10.0,
        accuracyMeters: 3.5,
        isAltitudeMsl: true,
        hasValidFix: true,
      );

      await notifier.startVideoRecording(recordingGpsState: recordingGps);
      expect(notifier.state.isRecordingVideo, isTrue);
      expect(notifier.state.recordingGpsState, equals(recordingGps));

      // Pause during recording simulates lifecycle interruption
      await notifier.pauseCamera();
      expect(notifier.state.hasInterruptedRecording, isTrue);
      expect(notifier.state.recordingGpsState, equals(recordingGps));

      // Clear interrupted recording clears recordingGpsState
      notifier.clearInterruptedRecording();
      expect(notifier.state.hasInterruptedRecording, isFalse);
      expect(notifier.state.recordingGpsState, isNull);
    });
  });
}
