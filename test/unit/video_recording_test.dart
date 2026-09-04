import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitelens/features/camera/controllers/camera_hardware_controller.dart';
import 'package:sitelens/features/camera/models/camera_hardware_state.dart';
import 'package:sitelens/features/camera/services/camera_hardware_service.dart';

class MockVideoCameraService extends CameraHardwareService {
  bool isRecording = false;
  bool startCalled = false;
  bool stopCalled = false;

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
}
