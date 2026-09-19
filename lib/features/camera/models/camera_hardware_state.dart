import 'package:camera/camera.dart';
import 'camera_ui_state.dart';
import 'gps_hardware_state.dart';

enum CameraStatus {
  initializing,
  ready,
  unavailable,
  error,
  capturing,
  recordingVideo,
  permissionDenied,
  permissionPermanentlyDenied,
  permissionRestricted,
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
  final GpsHardwareState? recordingGpsState;

  /// Whether AUDIO is enabled on the active camera controller. This is the
  /// effective value of the preset that actually initialized (the init retry
  /// loop can silently fall back to an audio-less preset), so it is the
  /// truthful disclosure source for R09. Conservative default: audio is never
  /// claimed unless the active controller established it.
  final bool isAudioEnabled;

  /// Audio-track presence frozen at recording start (T0), or null when no
  /// recording has established it. Null means unknown — never an assumption.
  final bool? recordingHasAudioTrack;


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
    this.recordingGpsState,
    this.isAudioEnabled = false,
    this.recordingHasAudioTrack,
  });

  bool get isReady =>
      status == CameraStatus.ready ||
      status == CameraStatus.capturing ||
      status == CameraStatus.recordingVideo;
  bool get isCapturing => status == CameraStatus.capturing;
  bool get isRecordingVideo => status == CameraStatus.recordingVideo;
  bool get isUnavailable => status == CameraStatus.unavailable;
  bool get hasError => status == CameraStatus.error;
  bool get isPermissionDenied =>
      status == CameraStatus.permissionDenied ||
      status == CameraStatus.permissionPermanentlyDenied ||
      status == CameraStatus.permissionRestricted;
  bool get isPermissionPermanentlyDenied =>
      status == CameraStatus.permissionPermanentlyDenied;
  bool get isPermissionRestricted =>
      status == CameraStatus.permissionRestricted;

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
    GpsHardwareState? recordingGpsState,
    bool clearRecordingGpsState = false,
    bool? isAudioEnabled,
    bool? recordingHasAudioTrack,
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
      recordingGpsState: clearRecordingGpsState ? null : (recordingGpsState ?? this.recordingGpsState),
      isAudioEnabled: isAudioEnabled ?? this.isAudioEnabled,
      recordingHasAudioTrack: recordingHasAudioTrack ?? this.recordingHasAudioTrack,
    );
  }
}
