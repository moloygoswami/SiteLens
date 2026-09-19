import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitelens/features/camera/controllers/camera_hardware_controller.dart';
import 'package:sitelens/features/camera/models/camera_hardware_state.dart';
import 'package:sitelens/features/camera/models/camera_ui_state.dart';
import 'package:sitelens/features/camera/models/gps_hardware_state.dart';
import 'package:sitelens/features/camera/services/camera_hardware_service.dart';

class MockVideoCameraService extends CameraHardwareService {
  bool isRecording = false;
  bool startCalled = false;
  bool stopCalled = false;

  @override
  Future<double> getMinZoomLevel(CameraController controller) async => 0.5;

  @override
  Future<double> getMaxZoomLevel(CameraController controller) async => 5.0;

  @override
  Future<List<CameraDescription>> getAvailableCameras() async {
    return [
      const CameraDescription(
        name: '0',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      ),
    ];
  }

  @override
  CameraController createController({
    required CameraDescription cameraDescription,
    ResolutionPreset resolutionPreset = ResolutionPreset.high,
    bool enableAudio = true,
  }) {
    return CameraController(
      cameraDescription,
      resolutionPreset,
      enableAudio: enableAudio,
    );
  }

  @override
  Future<void> initializeController(CameraController controller) async {}

  @override
  Future<void> startVideoRecording(CameraController controller) async {
    startCalled = true;
    isRecording = true;
  }

  @override
  Future<XFile> stopVideoRecording(CameraController controller) async {
    stopCalled = true;
    isRecording = false;
    return XFile('temp/video_capture.mp4');
  }

  @override
  bool isRecordingVideo(CameraController? controller) => isRecording;

  @override
  Future<void> disposeController(CameraController? controller) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockVideoCameraService service;
  late CameraHardwareNotifier notifier;

  setUp(() async {
    service = MockVideoCameraService();
    notifier = CameraHardwareNotifier(service);
    await notifier.initialize();
  });

  tearDown(() {
    notifier.dispose();
  });

  group('Video Recording Controller Tests', () {
    test('startVideoRecording transitions to recordingVideo state and tracks timestamp', () async {
      final success = await notifier.startVideoRecording();

      expect(success, isTrue);
      expect(notifier.state.status, CameraStatus.recordingVideo);
      expect(notifier.state.isRecordingVideo, isTrue);
      expect(notifier.state.recordingStartedAtUtc, isNotNull);
      expect(service.startCalled, isTrue);
    });

    test('stopVideoRecording finalizes recording and calculates duration', () async {
      await notifier.startVideoRecording();
      final startTime = notifier.state.recordingStartedAtUtc;

      await Future<void>.delayed(const Duration(milliseconds: 50));
      final videoFile = await notifier.stopVideoRecording();

      expect(videoFile, isNotNull);
      expect(videoFile!.path, 'temp/video_capture.mp4');
      expect(notifier.state.status, CameraStatus.ready);
      expect(notifier.state.isRecordingVideo, isFalse);
      expect(notifier.state.recordingStoppedAtUtc, isNotNull);
      expect(notifier.state.recordingStoppedAtUtc!.isAfter(startTime!), isTrue);
      expect(service.stopCalled, isTrue);
    });

    test('Double startVideoRecording does not trigger secondary recording', () async {
      await notifier.startVideoRecording();
      final secondStart = await notifier.startVideoRecording();

      expect(secondStart, isFalse);
    });

    test('Double stopVideoRecording does not fail or duplicate finalization', () async {
      await notifier.startVideoRecording();
      await notifier.stopVideoRecording();

      final secondStop = await notifier.stopVideoRecording();
      expect(secondStop, isNull);
    });

    test('pauseCamera safely stops active video recording to prevent data loss', () async {
      await notifier.startVideoRecording();
      expect(notifier.state.isRecordingVideo, isTrue);

      await notifier.pauseCamera();

      expect(service.stopCalled, isTrue);
      expect(notifier.state.status, CameraStatus.unavailable);
    });
  });

  group('Wave B — R07/R08/R09 video authority, recording locks, audio disclosure', () {
    const t0Gps = GpsHardwareState(
      hasValidFix: true,
      latitude: 22.5001,
      longitude: 88.3001,
      accuracyMeters: 3.0,
      isLastKnownSeed: false,
    );

    test('R07: the T0 timestamp and the T0 GPS snapshot survive the stop unchanged', () async {
      await notifier.startVideoRecording(recordingGpsState: t0Gps);
      final t0 = notifier.state.recordingStartedAtUtc;
      expect(t0, isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await notifier.stopVideoRecording();

      // T0 (and the GPS snapshot frozen at T0) remain the authority — a stop
      // timestamp never usurps them.
      expect(notifier.state.recordingStartedAtUtc, t0);
      expect(notifier.state.recordingGpsState, same(t0Gps));
      expect(notifier.state.recordingGpsState!.latitude, 22.5001);
      expect(notifier.state.recordingGpsState!.longitude, 88.3001);
    });

    test('R08: lens switching and zoom are locked while recording and apply otherwise', () async {
      // Not recording: the control applies.
      await notifier.setZoomPreset(CameraLensZoom.tele);
      expect(notifier.state.lensZoom, CameraLensZoom.tele);
      expect(notifier.state.currentZoomLevel, 2.0);

      await notifier.startVideoRecording();
      expect(notifier.state.isRecordingVideo, isTrue);

      // Recording: lens switching and digital zoom are inert.
      await notifier.setZoomPreset(CameraLensZoom.wide);
      await notifier.setPinchZoom(4.5);
      expect(notifier.state.lensZoom, CameraLensZoom.tele);
      expect(notifier.state.currentZoomLevel, 2.0);
    });

    test('R09: audio presence is established at init and frozen at T0', () async {
      // The initializing preset (max, audio enabled) established audio.
      expect(notifier.state.isAudioEnabled, isTrue);

      await notifier.startVideoRecording(recordingGpsState: t0Gps);
      expect(notifier.state.recordingHasAudioTrack, isTrue);

      await notifier.stopVideoRecording();
      // The T0 audio snapshot is not re-derived or lost on stop.
      expect(notifier.state.recordingHasAudioTrack, isTrue);
    });
  });
}
