import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/gps_utils.dart';

enum CameraCaptureMode {
  photo('PHOTO'),
  video('VIDEO');

  final String label;
  const CameraCaptureMode(this.label);
}

enum CameraFlashMode {
  auto,
  on,
  off,
  torch;

  String get label {
    switch (this) {
      case CameraFlashMode.auto:
        return 'Auto';
      case CameraFlashMode.on:
        return 'On';
      case CameraFlashMode.off:
        return 'Off';
      case CameraFlashMode.torch:
        return 'Torch';
    }
  }

  IconData get icon {
    switch (this) {
      case CameraFlashMode.auto:
        return Icons.flash_auto_rounded;
      case CameraFlashMode.on:
        return Icons.flash_on_rounded;
      case CameraFlashMode.off:
        return Icons.flash_off_rounded;
      case CameraFlashMode.torch:
        return Icons.highlight_rounded;
    }
  }

  CameraFlashMode get next {
    switch (this) {
      case CameraFlashMode.auto:
        return CameraFlashMode.on;
      case CameraFlashMode.on:
        return CameraFlashMode.off;
      case CameraFlashMode.off:
        return CameraFlashMode.torch;
      case CameraFlashMode.torch:
        return CameraFlashMode.auto;
    }
  }
}

enum CameraLensZoom {
  wide('0.5x'),
  standard('1x'),
  tele('2x');

  final String label;
  const CameraLensZoom(this.label);

  CameraLensZoom get next {
    switch (this) {
      case CameraLensZoom.standard:
        return CameraLensZoom.tele;
      case CameraLensZoom.tele:
        return CameraLensZoom.wide;
      case CameraLensZoom.wide:
        return CameraLensZoom.standard;
    }
  }
}

enum CameraAspectRatio {
  ratioFull('Full'),
  ratio4_3('4:3'),
  ratio16_9('16:9'),
  ratio1_1('1:1');

  final String label;
  const CameraAspectRatio(this.label);

  CameraAspectRatio get next {
    switch (this) {
      case CameraAspectRatio.ratioFull:
        return CameraAspectRatio.ratio4_3;
      case CameraAspectRatio.ratio4_3:
        return CameraAspectRatio.ratio16_9;
      case CameraAspectRatio.ratio16_9:
        return CameraAspectRatio.ratio1_1;
      case CameraAspectRatio.ratio1_1:
        return CameraAspectRatio.ratioFull;
    }
  }

  IconData get icon {
    switch (this) {
      case CameraAspectRatio.ratioFull:
        return Icons.aspect_ratio_rounded;
      case CameraAspectRatio.ratio4_3:
        return Icons.crop_3_2_rounded;
      case CameraAspectRatio.ratio16_9:
        return Icons.crop_16_9_rounded;
      case CameraAspectRatio.ratio1_1:
        return Icons.crop_square_rounded;
    }
  }
}

enum CameraCaptureTimer {
  off('Off', 0),
  seconds3('3s', 3),
  seconds5('5s', 5),
  seconds10('10s', 10);

  final String label;
  final int seconds;
  const CameraCaptureTimer(this.label, this.seconds);

  CameraCaptureTimer get next {
    switch (this) {
      case CameraCaptureTimer.off:
        return CameraCaptureTimer.seconds3;
      case CameraCaptureTimer.seconds3:
        return CameraCaptureTimer.seconds5;
      case CameraCaptureTimer.seconds5:
        return CameraCaptureTimer.seconds10;
      case CameraCaptureTimer.seconds10:
        return CameraCaptureTimer.off;
    }
  }

  IconData get icon {
    switch (this) {
      case CameraCaptureTimer.off:
        return Icons.timer_off_outlined;
      case CameraCaptureTimer.seconds3:
        return Icons.timer_3_rounded;
      case CameraCaptureTimer.seconds5:
        return Icons.timer_outlined;
      case CameraCaptureTimer.seconds10:
        return Icons.timer_10_rounded;
    }
  }
}

class GpsUiFixture {
  final GPSFixStatus status;
  final GpsBlockReason? blockReason;
  final double? accuracyMeters;
  // Coordinates use 0.0 as the established "no fix" sentinel; the HUD card
  // rejects a 0.0 pair as a fix. Altitude is genuinely nullable so an
  // unestablished altitude renders as "—" rather than a fabricated 0 m (R10).
  final double latitude;
  final double longitude;
  final double? altitudeMeters;
  final bool isAltitudeMsl;
  final double? headingDegrees;
  final String timestampUtc;
  final String sectorName;
  final String geofenceStatus;
  final double lowAccuracyThresholdMeters;

  /// Physical address resolved from capture coordinates. Null while geocoding
  /// is in-flight; the live camera_screen.dart always passes the live value.
  final String? resolvedAddress;

  const GpsUiFixture({
    required this.status,
    this.blockReason,
    required this.accuracyMeters,
    required this.latitude,
    required this.longitude,
    this.altitudeMeters,
    this.isAltitudeMsl = true,
    this.headingDegrees,
    required this.timestampUtc,
    this.sectorName = '',
    this.geofenceStatus = '',
    this.lowAccuracyThresholdMeters = AppConstants.gpsDefaultLowAccuracyThresholdMeters,
    this.resolvedAddress,
  });

  bool get isLocked => status == GPSFixStatus.high || status == GPSFixStatus.weak;
  bool get isDegraded => (accuracyMeters == null && hasFix) || (accuracyMeters != null && accuracyMeters! > lowAccuracyThresholdMeters);
  bool get isSearching => status == GPSFixStatus.searching;
  bool get hasFix => status == GPSFixStatus.high || status == GPSFixStatus.weak || status == GPSFixStatus.poor;

  /// Single authoritative GPS status line for the capture screen. Cause-specific
  /// when no fix exists: the UI never claims "searching" for a permission or
  /// service problem.
  String get statusLabel {
    switch (blockReason) {
      case GpsBlockReason.permissionDenied:
        return 'Location permission denied — enable it to capture evidence';
      case GpsBlockReason.permissionUnknown:
        return 'Location permission unknown — check device settings to capture evidence';
      case GpsBlockReason.serviceDisabled:
        return 'Location service is off — enable it to capture evidence';
      case GpsBlockReason.lastKnownOnly:
        return 'Last known location only — waiting for a live GPS fix';
      case GpsBlockReason.searching:
      case null:
        break;
    }
    if (isSearching) return 'Waiting for GPS lock';
    if (isDegraded) return 'GPS degraded — evidence will be flagged low accuracy';
    return 'GPS locked — ready for evidence';
  }

  String get pillLabel {
    if (blockReason == GpsBlockReason.permissionDenied) return 'GPS: Denied';
    if (blockReason == GpsBlockReason.permissionUnknown) return 'GPS: Unknown';
    if (blockReason == GpsBlockReason.serviceDisabled) return 'GPS: Off';
    if (blockReason == GpsBlockReason.lastKnownOnly) return 'GPS: Last known';
    if (isSearching) return 'GPS: Searching…';
    final accStr = accuracyMeters != null
        ? '±${accuracyMeters! == accuracyMeters!.roundToDouble() ? accuracyMeters!.toInt() : accuracyMeters!.toStringAsFixed(1)}m'
        : '—';
    if (isDegraded) return 'GPS: Poor · $accStr';
    if (status == GPSFixStatus.weak) return 'GPS: Weak · $accStr';
    return 'GPS: High · $accStr';
  }

  String get coordinatesDisplay {
    final latDir = latitude >= 0 ? 'N' : 'S';
    final lonDir = longitude >= 0 ? 'E' : 'W';
    return '${latitude.abs().toStringAsFixed(5)}° $latDir, ${longitude.abs().toStringAsFixed(5)}° $lonDir';
  }

  String get altitudeDisplay => GPSUtils.formatAltitude(altitudeMeters, isMsl: isAltitudeMsl);
  String get accuracyDisplay => accuracyMeters != null ? '${accuracyMeters!.toStringAsFixed(1)} m' : '—';

  // --- Static design/test fixtures (sentinel values — never used in production) ---

  /// GPS locked fixture for widget tests and Stitch design preview only.
  static const GpsUiFixture defaultLocked = GpsUiFixture(
    status: GPSFixStatus.high,
    accuracyMeters: 3.8,
    latitude: 0.0,
    longitude: 0.0,
    altitudeMeters: 0.0,
    headingDegrees: 0.0,
    timestampUtc: 'YYYY-MM-DD HH:MM:SS UTC',
    sectorName: 'DESIGN PREVIEW ONLY',
    geofenceStatus: 'Inside Perimeter',
    resolvedAddress: 'DESIGN PREVIEW ONLY',
  );

  /// Degraded GPS fixture for widget tests (>20m accuracy).
  static const GpsUiFixture degraded = GpsUiFixture(
    status: GPSFixStatus.poor,
    accuracyMeters: 24.5,
    latitude: 0.0,
    longitude: 0.0,
    altitudeMeters: 0.0,
    headingDegrees: 0.0,
    timestampUtc: 'YYYY-MM-DD HH:MM:SS UTC',
    sectorName: 'DESIGN PREVIEW ONLY',
    geofenceStatus: 'Inside Perimeter',
    resolvedAddress: 'DESIGN PREVIEW ONLY',
  );

  /// Searching GPS fixture for widget tests (no lock).
  static const GpsUiFixture searching = GpsUiFixture(
    status: GPSFixStatus.searching,
    blockReason: GpsBlockReason.searching,
    accuracyMeters: null,
    latitude: 0.0,
    longitude: 0.0,
    altitudeMeters: 0.0,
    headingDegrees: null,
    timestampUtc: 'YYYY-MM-DD HH:MM:SS UTC',
    sectorName: 'Locating...',
    geofenceStatus: 'Perimeter Unknown',
    resolvedAddress: null,
  );
}

class CameraUiState {
  final String siteCode;
  final String siteName;
  final GpsUiFixture gps;
  final CameraCaptureMode captureMode;
  final CameraFlashMode flashMode;
  final CameraLensZoom lensZoom;
  final CameraAspectRatio aspectRatio;
  final CameraCaptureTimer captureTimer;
  final bool isCountingDown;
  final int countdownRemaining;
  final bool isGridVisible;
  final bool isHighContrastMode;
  final Offset? focusPoint;
  final DateTime? focusTimestamp;
  final int cachedGalleryCount;
  final bool isCameraInitialized;
  final bool isCameraActive;
  final bool isFrontCamera;

  const CameraUiState({
    this.siteCode = '',
    this.siteName = '',
    this.gps = GpsUiFixture.defaultLocked,
    this.captureMode = CameraCaptureMode.photo,
    this.flashMode = CameraFlashMode.auto,
    this.lensZoom = CameraLensZoom.standard,
    this.aspectRatio = CameraAspectRatio.ratio4_3,
    this.captureTimer = CameraCaptureTimer.off,
    this.isCountingDown = false,
    this.countdownRemaining = 0,
    this.isGridVisible = true,
    this.isHighContrastMode = false,
    this.focusPoint,
    this.focusTimestamp,
    this.cachedGalleryCount = 0,
    this.isCameraInitialized = false,
    this.isCameraActive = false,
    this.isFrontCamera = false,
  });

  CameraUiState copyWith({
    String? siteCode,
    String? siteName,
    GpsUiFixture? gps,
    CameraCaptureMode? captureMode,
    CameraFlashMode? flashMode,
    CameraLensZoom? lensZoom,
    CameraAspectRatio? aspectRatio,
    CameraCaptureTimer? captureTimer,
    bool? isCountingDown,
    int? countdownRemaining,
    bool? isGridVisible,
    bool? isHighContrastMode,
    Offset? focusPoint,
    bool clearFocus = false,
    DateTime? focusTimestamp,
    int? cachedGalleryCount,
    bool? isCameraInitialized,
    bool? isCameraActive,
    bool? isFrontCamera,
  }) {
    return CameraUiState(
      siteCode: siteCode ?? this.siteCode,
      siteName: siteName ?? this.siteName,
      gps: gps ?? this.gps,
      captureMode: captureMode ?? this.captureMode,
      flashMode: flashMode ?? this.flashMode,
      lensZoom: lensZoom ?? this.lensZoom,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      captureTimer: captureTimer ?? this.captureTimer,
      isCountingDown: isCountingDown ?? this.isCountingDown,
      countdownRemaining: countdownRemaining ?? this.countdownRemaining,
      isGridVisible: isGridVisible ?? this.isGridVisible,
      isHighContrastMode: isHighContrastMode ?? this.isHighContrastMode,
      focusPoint: clearFocus ? null : (focusPoint ?? this.focusPoint),
      focusTimestamp: clearFocus ? null : (focusTimestamp ?? this.focusTimestamp),
      cachedGalleryCount: cachedGalleryCount ?? this.cachedGalleryCount,
      isCameraInitialized: isCameraInitialized ?? this.isCameraInitialized,
      isCameraActive: isCameraActive ?? this.isCameraActive,
      isFrontCamera: isFrontCamera ?? this.isFrontCamera,
    );
  }
}
