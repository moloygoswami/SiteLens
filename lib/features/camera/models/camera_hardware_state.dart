import 'package:camera/camera.dart';
import 'camera_ui_state.dart';

enum CameraStatus {
  initializing,
  ready,
  unavailable,
  error,
  capturing,
  recordingVideo,
}

class CameraHardwareState {
  final CameraStatus status;
  final List<CameraDescription> availableCameras;
  final int selectedCameraIndex;
  final CameraCaptureMode captureMode;
  final CameraFlashMode flashMode;
  final CameraLensZoom lensZoom;
  final double currentZoomLevel;
  final double minZoomLevel;
  final double maxZoomLevel;
  final String? errorMessage;
  final int recordingDurationSeconds;
  final DateTime? recordingStartedAtUtc;
  final DateTime? recordingStoppedAtUtc;
  final bool hasInterruptedRecording;

  const CameraHardwareState({
    this.status = CameraStatus.initializing,
    this.availableCameras = const [],
    this.selectedCameraIndex = 0,
    this.captureMode = CameraCaptureMode.photo,
    this.flashMode = CameraFlashMode.auto,
    this.lensZoom = CameraLensZoom.standard,
    this.currentZoomLevel = 1.0,
    this.minZoomLevel = 1.0,
    this.maxZoomLevel = 5.0,
    this.errorMessage,
    this.recordingDurationSeconds = 0,
    this.recordingStartedAtUtc,
    this.recordingStoppedAtUtc,
    this.hasInterruptedRecording = false,
  });

  bool get isReady =>
      status == CameraStatus.ready ||
      status == CameraStatus.capturing ||
      status == CameraStatus.recordingVideo;
  bool get isCapturing => status == CameraStatus.capturing;
  bool get isRecordingVideo => status == CameraStatus.recordingVideo;
  bool get isUnavailable => status == CameraStatus.unavailable;
  bool get hasError => status == CameraStatus.error;

  CameraDescription? get currentCameraDescription {
    if (availableCameras.isEmpty || selectedCameraIndex >= availableCameras.length) {
      return null;
    }
    return availableCameras[selectedCameraIndex];
  }

  bool get isFrontCamera =>
      currentCameraDescription?.lensDirection == CameraLensDirection.front;

  bool get hasMultipleCameras => availableCameras.length > 1;

  bool get supportsWide => minZoomLevel <= 0.6 && !isFrontCamera;
  bool get supportsTele => maxZoomLevel >= 1.8;

  List<CameraLensZoom> get availableZoomPresets {
    final presets = <CameraLensZoom>[CameraLensZoom.standard];
    if (supportsTele) {
      presets.add(CameraLensZoom.tele);
    }
    if (supportsWide) {
      presets.add(CameraLensZoom.wide);
    }
    return presets;
  }

  String get zoomDisplayLabel {
    if (currentZoomLevel <= 0.6) {
      return '0.5x';
    }
    if (currentZoomLevel == currentZoomLevel.roundToDouble()) {
      return '${currentZoomLevel.toInt()}x';
    }
    return '${currentZoomLevel.toStringAsFixed(1)}x';
  }

  String get recordingDurationFormatted {
    final minutes = (recordingDurationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (recordingDurationSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  CameraHardwareState copyWith({
    CameraStatus? status,
    List<CameraDescription>? availableCameras,
    int? selectedCameraIndex,
    CameraCaptureMode? captureMode,
    CameraFlashMode? flashMode,
    CameraLensZoom? lensZoom,
    double? currentZoomLevel,
    double? minZoomLevel,
    double? maxZoomLevel,
    String? errorMessage,
    int? recordingDurationSeconds,
    DateTime? recordingStartedAtUtc,
    DateTime? recordingStoppedAtUtc,
    bool? hasInterruptedRecording,
  }) {
    return CameraHardwareState(
      status: status ?? this.status,
      availableCameras: availableCameras ?? this.availableCameras,
      selectedCameraIndex: selectedCameraIndex ?? this.selectedCameraIndex,
      captureMode: captureMode ?? this.captureMode,
      flashMode: flashMode ?? this.flashMode,
      lensZoom: lensZoom ?? this.lensZoom,
      currentZoomLevel: currentZoomLevel ?? this.currentZoomLevel,
      minZoomLevel: minZoomLevel ?? this.minZoomLevel,
      maxZoomLevel: maxZoomLevel ?? this.maxZoomLevel,
      errorMessage: errorMessage ?? this.errorMessage,
      recordingDurationSeconds: recordingDurationSeconds ?? this.recordingDurationSeconds,
      recordingStartedAtUtc: recordingStartedAtUtc ?? this.recordingStartedAtUtc,
      recordingStoppedAtUtc: recordingStoppedAtUtc ?? this.recordingStoppedAtUtc,
      hasInterruptedRecording: hasInterruptedRecording ?? this.hasInterruptedRecording,
    );
  }
}
