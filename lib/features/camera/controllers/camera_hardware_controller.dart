import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/camera_hardware_state.dart';
import '../models/camera_ui_state.dart';
import '../services/camera_hardware_service.dart';

final cameraHardwareServiceProvider = Provider<CameraHardwareService>((ref) {
  return CameraHardwareService();
});

final cameraHardwareProvider =
    StateNotifierProvider.autoDispose<CameraHardwareNotifier, CameraHardwareState>((ref) {
  final service = ref.watch(cameraHardwareServiceProvider);
  return CameraHardwareNotifier(service);
});

class CameraHardwareNotifier extends StateNotifier<CameraHardwareState> {
  final CameraHardwareService _service;
  CameraController? _controller;
  Timer? _recordingTimer;
  XFile? _inFlightVideoFile;
  bool _isSwitching = false;

  CameraHardwareNotifier(this._service) : super(const CameraHardwareState()) {
    initialize();
  }

  CameraController? get controller => _controller;
  XFile? get inFlightVideoFile => _inFlightVideoFile;
  bool get isSwitching => _isSwitching;

  Future<void> initialize() async {
    state = state.copyWith(status: CameraStatus.initializing);
    try {
      final cameras = await _service.getAvailableCameras();
      if (cameras.isEmpty) {
        state = state.copyWith(
          status: CameraStatus.unavailable,
          availableCameras: const [],
          errorMessage: 'No cameras found on device',
        );
        return;
      }

      state = state.copyWith(
        availableCameras: cameras,
        selectedCameraIndex: 0,
      );

      await _initControllerAtIndex(0);
    } catch (e) {
      state = state.copyWith(
        status: CameraStatus.error,
        errorMessage: 'Camera initialization failed: $e',
      );
    }
  }

  Future<void> _initControllerAtIndex(int index, {CameraCaptureMode captureMode = CameraCaptureMode.photo}) async {
    if (state.availableCameras.isEmpty || index >= state.availableCameras.length) {
      state = state.copyWith(status: CameraStatus.unavailable);
      return;
    }

    state = state.copyWith(status: CameraStatus.initializing);

    final oldController = _controller;
    _controller = null;
    if (oldController != null) {
      await _service.disposeController(oldController);
    }

    if (!mounted) return;

    final cameraDesc = state.availableCameras[index];
    final isFrontCamera = cameraDesc.lensDirection == CameraLensDirection.front;
    final resolvedFlashMode = isFrontCamera ? CameraFlashMode.off : state.flashMode;
    const preset = ResolutionPreset.max;
    const shouldEnableAudio = true;
    var newController = _service.createController(
      cameraDescription: cameraDesc,
      resolutionPreset: preset,
      enableAudio: shouldEnableAudio,
    );

    try {
      await _service.initializeController(newController);
    } catch (e) {
      // Fallback: If initializing with max/audio failed, try fallback with veryHigh / high
      try {
        await _service.disposeController(newController);
        newController = _service.createController(
          cameraDescription: cameraDesc,
          resolutionPreset: ResolutionPreset.veryHigh,
          enableAudio: false,
        );
        await _service.initializeController(newController);
      } catch (innerError) {
        try {
          await _service.disposeController(newController);
          newController = _service.createController(
            cameraDescription: cameraDesc,
            resolutionPreset: ResolutionPreset.high,
            enableAudio: false,
          );
          await _service.initializeController(newController);
        } catch (finalError) {
          if (mounted) {
            state = state.copyWith(
              status: CameraStatus.error,
              errorMessage: 'Failed to initialize camera: $finalError',
            );
          }
          return;
        }
      }
    }

    if (!mounted) {
      await _service.disposeController(newController);
      return;
    }

    try {
      final zoomBounds = await Future.wait([
        _service.getMinZoomLevel(newController),
        _service.getMaxZoomLevel(newController),
      ]);
      final minZoom = zoomBounds[0];
      final maxZoom = zoomBounds[1];

      // Default to 0.5x wide zoom for both rear and front cameras
      final targetInitialZoom = 0.5.clamp(minZoom, maxZoom).toDouble();

      await _service.setZoomLevel(newController, targetInitialZoom);

      if (!mounted) {
        await _service.disposeController(newController);
        return;
      }

      _controller = newController;

      state = state.copyWith(
        status: CameraStatus.ready,
        selectedCameraIndex: index,
        flashMode: resolvedFlashMode,
        minZoomLevel: minZoom,
        maxZoomLevel: maxZoom,
        currentZoomLevel: targetInitialZoom,
        lensZoom: CameraLensZoom.wide,
      );
    } catch (e) {
      if (!mounted) {
        await _service.disposeController(newController);
        return;
      }
      _controller = newController;
      state = state.copyWith(
        status: CameraStatus.ready,
        selectedCameraIndex: index,
        flashMode: resolvedFlashMode,
        currentZoomLevel: 0.5,
        lensZoom: CameraLensZoom.wide,
      );
    }
  }

  Future<void> switchCamera() async {
    if (!mounted || state.availableCameras.length < 2 || _isSwitching) return;
    _isSwitching = true;
    try {
      final nextIndex = (state.selectedCameraIndex + 1) % state.availableCameras.length;
      await _initControllerAtIndex(nextIndex, captureMode: state.captureMode);
    } finally {
      _isSwitching = false;
    }
  }

  Future<void> setCaptureMode(CameraCaptureMode mode) async {
    if (state.captureMode == mode || state.isRecordingVideo) return;
    state = state.copyWith(captureMode: mode);
  }

  Future<void> setFlashMode(CameraFlashMode mode) async {
    if (_controller != null && _controller!.value.isInitialized) {
      FlashMode targetMode;
      switch (mode) {
        case CameraFlashMode.off:
          targetMode = FlashMode.off;
          break;
        case CameraFlashMode.auto:
          targetMode = FlashMode.auto;
          break;
        case CameraFlashMode.on:
          targetMode = FlashMode.always;
          break;
        case CameraFlashMode.torch:
          targetMode = FlashMode.torch;
          break;
      }
      await _service.setFlashMode(_controller!, targetMode);
    }
    state = state.copyWith(flashMode: mode);
  }

  Future<void> setZoomPreset(CameraLensZoom preset) async {
    double requested;
    switch (preset) {
      case CameraLensZoom.wide:
        requested = 0.5;
        break;
      case CameraLensZoom.standard:
        requested = 1.0;
        break;
      case CameraLensZoom.tele:
        requested = 2.0;
        break;
    }

    final clampedZoom = requested.clamp(state.minZoomLevel, state.maxZoomLevel);

    if (_controller != null && _controller!.value.isInitialized) {
      await _service.setZoomLevel(_controller!, clampedZoom);
    }

    if (mounted) {
      state = state.copyWith(
        lensZoom: preset,
        currentZoomLevel: clampedZoom,
      );
    }
  }

  Future<void> setPinchZoom(double targetZoom) async {
    if (!mounted) return;
    final clampedZoom = targetZoom.clamp(state.minZoomLevel, state.maxZoomLevel);

    if (_controller != null && _controller!.value.isInitialized) {
      await _service.setZoomLevel(_controller!, clampedZoom);
    }

    if (mounted) {
      final lensPreset = clampedZoom <= 0.6
          ? CameraLensZoom.wide
          : (clampedZoom >= 1.8 ? CameraLensZoom.tele : CameraLensZoom.standard);
      state = state.copyWith(
        currentZoomLevel: clampedZoom,
        lensZoom: lensPreset,
      );
    }
  }

  Future<void> setFocusPoint(Offset point) async {
    if (_controller != null && _controller!.value.isInitialized) {
      final clampedPoint = Offset(
        point.dx.clamp(0.0, 1.0),
        point.dy.clamp(0.0, 1.0),
      );
      await _service.setFocusPoint(_controller!, clampedPoint);
    }
  }

  Future<XFile?> takePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      return null;
    }
    if (_controller!.value.isTakingPicture || state.status == CameraStatus.capturing) {
      return null;
    }

    state = state.copyWith(status: CameraStatus.capturing);
    try {
      final file = await _service.takePicture(_controller!);
      return file;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
          errorMessage: 'Capture failed: $e',
        );
      }
      return null;
    } finally {
      if (mounted) {
        state = state.copyWith(status: CameraStatus.ready);
      }
    }
  }

  Future<bool> startVideoRecording() async {
    if (_controller == null) return false;
    if (_service.isRecordingVideo(_controller) || state.isRecordingVideo) return false;

    try {
      await _service.startVideoRecording(_controller!);
      final startTime = DateTime.now().toUtc();

      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && state.isRecordingVideo) {
          state = state.copyWith(
            recordingDurationSeconds: state.recordingDurationSeconds + 1,
          );
        }
      });

      state = state.copyWith(
        status: CameraStatus.recordingVideo,
        recordingStartedAtUtc: startTime,
        recordingDurationSeconds: 0,
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Failed to start video recording: $e',
      );
      return false;
    }
  }

  Future<XFile?> stopVideoRecording() async {
    if (_controller == null) return null;
    if (!_service.isRecordingVideo(_controller) && !state.isRecordingVideo) return null;

    _recordingTimer?.cancel();
    _recordingTimer = null;

    final stopTime = DateTime.now().toUtc();

    try {
      final videoFile = await _service.stopVideoRecording(_controller!);
      _inFlightVideoFile = videoFile;

      state = state.copyWith(
        status: CameraStatus.ready,
        recordingStoppedAtUtc: stopTime,
      );
      return videoFile;
    } catch (e) {
      state = state.copyWith(
        status: CameraStatus.ready,
        errorMessage: 'Failed to stop video recording: $e',
      );
      return null;
    }
  }

  Future<void> pauseCamera() async {
    if (!mounted) return;

    // An in-flight recording must NEVER be silently discarded: evidence loss
    // on a phone call or lifecycle interruption is a P1 failure. Stop it
    // cleanly, keep the file, and flag it for recovery on resume.
    if (state.isRecordingVideo) {
      _recordingTimer?.cancel();
      _recordingTimer = null;
      try {
        if (_controller != null && _service.isRecordingVideo(_controller)) {
          _inFlightVideoFile = await _service.stopVideoRecording(_controller!);
        }
      } catch (_) {}
    }

    final oldController = _controller;
    _controller = null;
    await _service.disposeController(oldController);

    if (mounted) {
      state = state.copyWith(
        status: CameraStatus.unavailable,
        hasInterruptedRecording: state.isRecordingVideo || _inFlightVideoFile != null,
        recordingStoppedAtUtc: DateTime.now().toUtc(),
      );
    }
  }

  Future<void> resumeCamera() async {
    if (!mounted) return;
    state = state.copyWith(status: CameraStatus.initializing);
    try {
      final cameras = await _service.getAvailableCameras();
      if (cameras.isEmpty) {
        state = state.copyWith(
          status: CameraStatus.unavailable,
          availableCameras: const [],
          errorMessage: 'No cameras found on device',
        );
        return;
      }
      state = state.copyWith(availableCameras: cameras);
      final targetIndex = state.selectedCameraIndex < cameras.length ? state.selectedCameraIndex : 0;
      await _initControllerAtIndex(targetIndex);
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
          status: CameraStatus.error,
          errorMessage: 'Failed to resume camera: $e',
        );
      }
    }
  }

  /// Retries initializing the camera hardware and available optical lenses.
  Future<void> retry() async {
    await initialize();
  }

  /// Clears the interrupted-recording flag after the user has resolved it
  /// (reviewed, kept, or explicitly discarded).
  void clearInterruptedRecording() {
    if (!mounted) return;
    state = state.copyWith(hasInterruptedRecording: false);
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    final oldController = _controller;
    _controller = null;
    _service.disposeController(oldController);
    super.dispose();
  }
}
