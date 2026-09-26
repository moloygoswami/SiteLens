import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/services/permission_service.dart';
import '../models/camera_hardware_state.dart';
import '../models/camera_ui_state.dart';
import '../models/gps_hardware_state.dart';
import '../services/camera_hardware_service.dart';

final cameraHardwareServiceProvider = Provider<CameraHardwareService>((ref) {
  return CameraHardwareService();
});

final cameraHardwareProvider =
    StateNotifierProvider.autoDispose<CameraHardwareNotifier, CameraHardwareState>((ref) {
  final service = ref.watch(cameraHardwareServiceProvider);
  final permissionService = ref.watch(permissionServiceProvider.notifier);
  return CameraHardwareNotifier(service, permissionService: permissionService);
});

class CameraHardwareNotifier extends StateNotifier<CameraHardwareState> {
  final CameraHardwareService _service;
  final PermissionService? _permissionService;
  CameraController? _controller;
  Timer? _recordingTimer;
  XFile? _inFlightVideoFile;
  bool _isSwitching = false;
  bool _isPaused = false;
  Future<void>? _transitionLock;

  CameraHardwareNotifier(
    this._service, {
    PermissionService? permissionService,
  })  : _permissionService = permissionService,
        super(const CameraHardwareState()) {
    initialize();
  }

  CameraController? get controller => _controller;
  XFile? get inFlightVideoFile => _inFlightVideoFile;
  bool get isSwitching => _isSwitching;

  Future<T> _synchronized<T>(Future<T> Function() action) async {
    final previous = _transitionLock;
    final completer = Completer<void>();
    _transitionLock = completer.future;
    if (previous != null) {
      try {
        await previous;
      } catch (_) {}
    }
    try {
      return await action();
    } finally {
      completer.complete();
      if (_transitionLock == completer.future) {
        _transitionLock = null;
      }
    }
  }

  Future<void> initialize() async {
    _isPaused = false;
    return _synchronized(() async {
      if (_isPaused || !mounted) return;
      state = state.copyWith(status: CameraStatus.initializing);

      // 1. Verify camera permission via PermissionService abstraction
      if (_permissionService != null) {
        final perm = await _permissionService.checkCameraPermission();
        if (perm.isPermanentlyDenied) {
          state = state.copyWith(
            status: CameraStatus.permissionPermanentlyDenied,
            errorMessage: 'Camera permission is permanently denied',
          );
          return;
        } else if (perm.isRestricted) {
          state = state.copyWith(
            status: CameraStatus.permissionRestricted,
            errorMessage: 'Camera access is restricted by device policy',
          );
          return;
        } else if (!perm.isGranted && !perm.isLimited) {
          state = state.copyWith(
            status: CameraStatus.permissionDenied,
            errorMessage: 'Camera permission is denied',
          );
          return;
        }
      }

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
        if (mounted && !_isPaused) {
          if (e is CameraException &&
              (e.code == 'CameraAccessDenied' ||
                  e.code == 'CameraAccessDeniedWithoutPrompt')) {
            if (_permissionService != null) {
              final perm = await _permissionService.checkCameraPermission();
              if (perm.isPermanentlyDenied) {
                state = state.copyWith(
                  status: CameraStatus.permissionPermanentlyDenied,
                  errorMessage: 'Camera permission is permanently denied',
                );
                return;
              } else if (perm.isRestricted) {
                state = state.copyWith(
                  status: CameraStatus.permissionRestricted,
                  errorMessage: 'Camera access is restricted by device policy',
                );
                return;
              }
            }
            state = state.copyWith(
              status: CameraStatus.permissionDenied,
              errorMessage: 'Camera permission is denied: ${e.description}',
            );
            return;
          }

          state = state.copyWith(
            status: CameraStatus.error,
            errorMessage: 'Camera initialization failed: $e',
          );
        }
      }
    });
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

    if (!mounted || _isPaused) return;

    final cameraDesc = state.availableCameras[index];
    final isFrontCamera = cameraDesc.lensDirection == CameraLensDirection.front;
    final resolvedFlashMode = isFrontCamera ? CameraFlashMode.off : state.flashMode;

    bool canEnableAudio = true;
    if (_permissionService != null) {
      final micPerm = await _permissionService.checkMicrophonePermission();
      if (!micPerm.isGranted && !micPerm.isLimited) {
        canEnableAudio = false;
      }
    }

    final presetsToTry = canEnableAudio
        ? [
            (ResolutionPreset.max, true),
            (ResolutionPreset.veryHigh, false),
            (ResolutionPreset.high, false),
          ]
        : [
            (ResolutionPreset.max, false),
            (ResolutionPreset.veryHigh, false),
            (ResolutionPreset.high, false),
          ];

    CameraController? initializedController;
    Object? lastError;
    // The audio setting of the preset that actually initialized — the init
    // retry loop can fall back to an audio-less preset, so the winning value is
    // the only truthful audio source (R09).
    bool? resolvedEnableAudio;

    for (final (preset, enableAudio) in presetsToTry) {
      if (!mounted || _isPaused) {
        return;
      }

      final candidate = _service.createController(
        cameraDescription: cameraDesc,
        resolutionPreset: preset,
        enableAudio: enableAudio,
      );

      try {
        await _service.initializeController(candidate);
        initializedController = candidate;
        resolvedEnableAudio = enableAudio;
        lastError = null;
        break;
      } catch (err) {
        lastError = err;
        await _service.disposeController(candidate);
      }
    }

    if (initializedController == null) {
      if (mounted && !_isPaused) {
        if (lastError is CameraException &&
            (lastError.code == 'CameraAccessDenied' ||
                lastError.code == 'CameraAccessDeniedWithoutPrompt')) {
          if (_permissionService != null) {
            final perm = await _permissionService.checkCameraPermission();
            if (perm.isPermanentlyDenied) {
              state = state.copyWith(
                status: CameraStatus.permissionPermanentlyDenied,
                errorMessage: 'Camera permission is permanently denied',
              );
              return;
            } else if (perm.isRestricted) {
              state = state.copyWith(
                status: CameraStatus.permissionRestricted,
                errorMessage: 'Camera access is restricted by device policy',
              );
              return;
            }
          }
          state = state.copyWith(
            status: CameraStatus.permissionDenied,
            errorMessage: 'Camera permission is denied',
          );
          return;
        }

        state = state.copyWith(
          status: CameraStatus.error,
          errorMessage: 'Failed to initialize camera: $lastError',
        );
      }
      return;
    }

    if (!mounted || _isPaused) {
      await _service.disposeController(initializedController);
      return;
    }

    try {
      final zoomBounds = await Future.wait([
        _service.getMinZoomLevel(initializedController),
        _service.getMaxZoomLevel(initializedController),
      ]);
      final minZoom = zoomBounds[0];
      final maxZoom = zoomBounds[1];

      // Default to 1.0x standard zoom
      final targetInitialZoom = 1.0.clamp(minZoom, maxZoom).toDouble();

      await _service.setZoomLevel(initializedController, targetInitialZoom);

      if (!mounted || _isPaused) {
        await _service.disposeController(initializedController);
        return;
      }

      _controller = initializedController;

      final initialLens = targetInitialZoom <= 0.6
          ? CameraLensZoom.wide
          : (targetInitialZoom >= 1.8 ? CameraLensZoom.tele : CameraLensZoom.standard);

      state = state.copyWith(
        status: CameraStatus.ready,
        selectedCameraIndex: index,
        flashMode: resolvedFlashMode,
        minZoomLevel: minZoom,
        maxZoomLevel: maxZoom,
        currentZoomLevel: targetInitialZoom,
        lensZoom: initialLens,
        isAudioEnabled: resolvedEnableAudio ?? false,
      );
    } catch (e) {
      if (!mounted || _isPaused) {
        await _service.disposeController(initializedController);
        return;
      }
      _controller = initializedController;
      state = state.copyWith(
        status: CameraStatus.ready,
        selectedCameraIndex: index,
        flashMode: resolvedFlashMode,
        currentZoomLevel: 1.0,
        lensZoom: CameraLensZoom.standard,
        isAudioEnabled: resolvedEnableAudio ?? false,
      );
    }
  }

  Future<void> switchCamera() async {
    if (!mounted || state.availableCameras.length < 2 || _isSwitching || _isPaused) return;
    _isSwitching = true;
    try {
      await _synchronized(() async {
        if (!mounted || _isPaused) return;
        final nextIndex = (state.selectedCameraIndex + 1) % state.availableCameras.length;
        await _initControllerAtIndex(nextIndex, captureMode: state.captureMode);
      });
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
    // R08: lens/zoom is locked while recording to protect the video stream.
    if (state.isRecordingVideo) return;
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
      final actualLens = clampedZoom <= 0.6
          ? CameraLensZoom.wide
          : (clampedZoom >= 1.8 ? CameraLensZoom.tele : CameraLensZoom.standard);
      state = state.copyWith(
        lensZoom: actualLens,
        currentZoomLevel: clampedZoom,
      );
    }
  }

  Future<void> setPinchZoom(double targetZoom) async {
    if (!mounted) return;
    // R08: digital zoom gestures are locked while recording.
    if (state.isRecordingVideo) return;
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
      if (mounted && !_isPaused) {
        state = state.copyWith(status: CameraStatus.ready);
      }
    }
  }

  Future<bool> startVideoRecording({
    GpsHardwareState? recordingGpsState,
    String? recordingSiteId,
    String? recordingSiteCode,
    String? recordingSiteName,
    String? recordingCreatorId,
  }) async {
    if (_controller == null) return false;
    if (_service.isRecordingVideo(_controller) || state.isRecordingVideo) return false;
    if (state.status != CameraStatus.ready) return false;

    // Enforce critical capture invariants below UI boundary
    if (recordingCreatorId == null || recordingCreatorId.isEmpty) return false;
    if (recordingSiteId == null || recordingSiteId.isEmpty) return false;
    if (recordingGpsState == null || !recordingGpsState.hasLiveFix) return false;

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
        recordingGpsState: recordingGpsState,
        recordingSiteId: recordingSiteId,
        recordingSiteCode: recordingSiteCode,
        recordingSiteName: recordingSiteName,
        recordingCreatorId: recordingCreatorId,
        // Freeze audio-track presence at T0 so it cannot be re-derived from a
        // later state and so it discloses truthfully (R09).
        recordingHasAudioTrack: state.isAudioEnabled,
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
    _isPaused = true;
    if (!mounted) return;

    return _synchronized(() async {
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
      if (oldController != null) {
        await _service.disposeController(oldController);
      }

      if (mounted) {
        state = state.copyWith(
          status: CameraStatus.unavailable,
          hasInterruptedRecording: state.isRecordingVideo || _inFlightVideoFile != null,
          recordingStoppedAtUtc: DateTime.now().toUtc(),
          recordingGpsState: state.recordingGpsState,
          recordingSiteId: state.recordingSiteId,
          recordingSiteCode: state.recordingSiteCode,
          recordingSiteName: state.recordingSiteName,
          recordingCreatorId: state.recordingCreatorId,
        );
      }
    });
  }

  Future<void> resumeCamera() async {
    _isPaused = false;
    if (!mounted) return;

    return _synchronized(() async {
      if (_isPaused || !mounted) return;

      // 1. Check camera permission via PermissionService abstraction
      if (_permissionService != null) {
        final perm = await _permissionService.checkCameraPermission();
        if (perm.isPermanentlyDenied) {
          state = state.copyWith(
            status: CameraStatus.permissionPermanentlyDenied,
            errorMessage: 'Camera permission is permanently denied',
          );
          return;
        } else if (perm.isRestricted) {
          state = state.copyWith(
            status: CameraStatus.permissionRestricted,
            errorMessage: 'Camera access is restricted by device policy',
          );
          return;
        } else if (!perm.isGranted && !perm.isLimited) {
          state = state.copyWith(
            status: CameraStatus.permissionDenied,
            errorMessage: 'Camera permission is denied',
          );
          return;
        }
      }

      if (_controller != null && _controller!.value.isInitialized && state.status == CameraStatus.ready) {
        return;
      }

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
        if (mounted && !_isPaused) {
          if (e is CameraException &&
              (e.code == 'CameraAccessDenied' ||
                  e.code == 'CameraAccessDeniedWithoutPrompt')) {
            if (_permissionService != null) {
              final perm = await _permissionService.checkCameraPermission();
              if (perm.isPermanentlyDenied) {
                state = state.copyWith(
                  status: CameraStatus.permissionPermanentlyDenied,
                  errorMessage: 'Camera permission is permanently denied',
                );
                return;
              } else if (perm.isRestricted) {
                state = state.copyWith(
                  status: CameraStatus.permissionRestricted,
                  errorMessage: 'Camera access is restricted by device policy',
                );
                return;
              }
            }
            state = state.copyWith(
              status: CameraStatus.permissionDenied,
              errorMessage: 'Camera permission is denied: ${e.description}',
            );
            return;
          }

          state = state.copyWith(
            status: CameraStatus.error,
            errorMessage: 'Failed to resume camera: $e',
          );
        }
      }
    });
  }

  /// Requests camera permission via PermissionService and automatically reinitializes if granted.
  Future<void> requestPermissionAndRetry() async {
    if (_permissionService == null) {
      await initialize();
      return;
    }
    final status = await _permissionService.requestCameraPermission();
    if (status.isGranted || status.isLimited) {
      await initialize();
    } else if (status.isPermanentlyDenied) {
      state = state.copyWith(
        status: CameraStatus.permissionPermanentlyDenied,
        errorMessage: 'Camera permission is permanently denied',
      );
    } else if (status.isRestricted) {
      state = state.copyWith(
        status: CameraStatus.permissionRestricted,
        errorMessage: 'Camera access is restricted by device policy',
      );
    } else {
      state = state.copyWith(
        status: CameraStatus.permissionDenied,
        errorMessage: 'Camera permission is denied',
      );
    }
  }

  /// Retries initializing the camera hardware and available optical lenses.
  Future<void> retry() async {
    _isPaused = false;
    if (state.status == CameraStatus.permissionDenied) {
      await requestPermissionAndRetry();
    } else {
      await initialize();
    }
  }

  /// Clears the in-flight video reference once it no longer requires
  /// interrupted-recording recovery: after the user resolved an interruption
  /// (reviewed, kept, or explicitly discarded) or after a normal stop handed
  /// the recording to the review flow (Cross-Cutting Audit C, C-1).
  void clearInterruptedRecording() {
    if (!mounted) return;
    _inFlightVideoFile = null;
    state = state.copyWith(
      hasInterruptedRecording: false,
      clearRecordingGpsState: true,
      clearRecordingSiteIdentity: true,
    );
  }

  @override
  void dispose() {
    _isPaused = true;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    final oldController = _controller;
    _controller = null;
    _service.disposeController(oldController);
    super.dispose();
  }
}
