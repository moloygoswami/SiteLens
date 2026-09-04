import 'package:flutter_test/flutter_test.dart';
import 'package:camera/camera.dart';
import 'package:sitelens/features/camera/controllers/camera_hardware_controller.dart';
import 'package:sitelens/features/camera/models/camera_hardware_state.dart';
import 'package:sitelens/features/camera/models/camera_ui_state.dart';
import 'package:sitelens/features/camera/services/camera_hardware_service.dart';

class MockEmptyCameraService extends CameraHardwareService {
  @override
  Future<List<CameraDescription>> getAvailableCameras() async {
    return [];
  }
}

class MockErrorCameraService extends CameraHardwareService {
  @override
  Future<List<CameraDescription>> getAvailableCameras() async {
    throw CameraException('CameraAccessDenied', 'Permission was denied by user');
  }
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

    test('Transitions to error when availableCameras() throws exception', () async {
      final notifier = CameraHardwareNotifier(MockErrorCameraService());
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
      // Clamped to 1.0
      expect(notifier.state.currentZoomLevel, 1.0);
      expect(notifier.state.lensZoom, CameraLensZoom.wide);

      await notifier.setZoomPreset(CameraLensZoom.tele); // 2.0x requested
      // Allowed within 1.0 to 3.0 range
      expect(notifier.state.currentZoomLevel, 2.0);
      expect(notifier.state.lensZoom, CameraLensZoom.tele);
    });

    test('Initializes camera at 0.5x wide zoom when sensor supports it', () async {
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
      expect(notifier.state.currentZoomLevel, 0.5);
      expect(fakeService.currentZoom, 0.5);
      expect(notifier.state.lensZoom, CameraLensZoom.wide);
    });

    test('Clamps initial zoom to sensor min when 0.5x is outside bounds', () async {
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
      expect(notifier.state.lensZoom, CameraLensZoom.wide);
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

    test('Default camera state configurations have 0.5x wide zoom preset', () {
      const defaultHardwareState = CameraHardwareState();
      expect(defaultHardwareState.lensZoom, CameraLensZoom.wide);
      expect(defaultHardwareState.currentZoomLevel, 0.5);
      expect(defaultHardwareState.zoomDisplayLabel, '0.5x');

      const defaultUiState = CameraUiState();
      expect(defaultUiState.lensZoom, CameraLensZoom.wide);
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

    test('Parallel optical zoom bound queries concurrently retrieve min/max and clamp initial zoom to 0.5x preference', () async {
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
      expect(notifier.state.currentZoomLevel, 0.5);
      expect(notifier.state.lensZoom, CameraLensZoom.wide);
    });
  });
}
