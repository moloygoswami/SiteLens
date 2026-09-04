import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

class CameraHardwareService {
  Future<List<CameraDescription>> getAvailableCameras() async {
    return await availableCameras();
  }

  CameraController createController({
    required CameraDescription cameraDescription,
    ResolutionPreset resolutionPreset = ResolutionPreset.max,
    bool enableAudio = true,
  }) {
    return CameraController(
      cameraDescription,
      resolutionPreset,
      enableAudio: enableAudio,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
  }

  Future<void> initializeController(CameraController controller) async {
    await controller.initialize();
  }

  Future<double> getMinZoomLevel(CameraController controller) async {
    try {
      return await controller.getMinZoomLevel();
    } catch (_) {
      return 1.0;
    }
  }

  Future<double> getMaxZoomLevel(CameraController controller) async {
    try {
      return await controller.getMaxZoomLevel();
    } catch (_) {
      return 1.0;
    }
  }

  Future<void> setZoomLevel(CameraController controller, double zoom) async {
    try {
      await controller.setZoomLevel(zoom);
    } catch (e) {
      debugPrint('CameraHardwareService.setZoomLevel error: $e');
    }
  }

  Future<void> setFlashMode(CameraController controller, FlashMode flashMode) async {
    try {
      await controller.setFlashMode(flashMode);
    } catch (e) {
      debugPrint('CameraHardwareService.setFlashMode error: $e');
    }
  }

  Future<void> setFocusPoint(CameraController controller, Offset point) async {
    try {
      await controller.setFocusPoint(point);
      await controller.setFocusMode(FocusMode.auto);
    } catch (e) {
      debugPrint('CameraHardwareService.setFocusPoint error: $e');
    }
  }

  Future<XFile> takePicture(CameraController controller) async {
    return await controller.takePicture();
  }

  Future<void> startVideoRecording(CameraController controller) async {
    await controller.startVideoRecording();
  }

  Future<XFile> stopVideoRecording(CameraController controller) async {
    return await controller.stopVideoRecording();
  }

  bool isRecordingVideo(CameraController? controller) {
    if (controller == null) return false;
    return controller.value.isRecordingVideo;
  }

  Future<void> disposeController(CameraController? controller) async {
    if (controller != null) {
      try {
        await controller.dispose();
      } catch (e) {
        debugPrint('CameraHardwareService.disposeController error: $e');
      }
    }
  }
}
