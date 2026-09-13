import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';
import 'package:get_thumbnail_video/index.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/utils/crypto_utils.dart';
import '../../../core/utils/gps_utils.dart';
import '../../../data/repositories/media_repository.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/media_item.dart';
import '../review/models/pending_capture_payload.dart';
import '../review/review_tag_screen.dart';
import '../settings/settings_screen.dart';
import '../sites/site_controller.dart';
import 'controllers/camera_hardware_controller.dart';
import 'controllers/gps_hardware_controller.dart';
import 'models/camera_hardware_state.dart';
import 'models/camera_ui_state.dart';
import 'models/evidence_metadata_snapshot.dart';
import 'models/gps_hardware_state.dart';
import 'services/evidence_processing_service.dart';
import 'services/evidence_storage_service.dart';
import 'services/media_persistence_coordinator.dart';
import 'widgets/camera_top_hud.dart';
import 'widgets/camera_viewfinder.dart';
import 'widgets/gps_status_explainer_sheet.dart';
import 'controllers/map_thumbnail_controller.dart';
import '../../../core/services/map_thumbnail_service.dart';
import 'package:flutter/services.dart';
import '../../../core/controllers/map_type_settings_controller.dart';
import '../../../core/controllers/timestamp_settings_controller.dart';
import 'widgets/camera_shutter_station.dart';

import 'widgets/timestamp_settings_modal.dart';
import '../../../core/controllers/gps_settings_controller.dart';
import '../../../core/controllers/watermark_settings_controller.dart';


final activeSiteMediaStreamProvider = StreamProvider.autoDispose<List<MediaItem>>((ref) {
  final activeSite = ref.watch(siteControllerProvider).activeSite;
  if (activeSite == null) return Stream.value([]);
  final mediaRepo = ref.watch(mediaRepositoryProvider);
  String? creatorId;
  try {
    final authUser = ref.watch(authStateProvider).value;
    creatorId = authUser?.uid;
  } catch (_) {
    creatorId = null;
  }
  return mediaRepo.watchAllMedia(
    siteId: activeSite.id,
    creatorId: creatorId,
  );
});

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen>
    with WidgetsBindingObserver, RouteAware {
  late CameraUiState _uiState;
  Timer? _countdownTimer;
  bool _isExecutingCapture = false;
  bool _isRecoveringInterruptedRecording = false;

  /// True while a covering [PageRoute] (gallery / video evidence / fullscreen /
  /// review / settings) is on top of this screen. While covered, CameraX is
  /// released so exactly one camera resource owner exists.
  bool _isCoveredByRoute = false;

  /// The route this screen subscribed to [appRouteObserver] with, so repeated
  /// dependency changes never double-subscribe.
  PageRoute<dynamic>? _subscribedRoute;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _uiState = const CameraUiState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gpsHardwareProvider.notifier).setActiveSiteCoordinates(null, null);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute && !identical(route, _subscribedRoute)) {
      _subscribedRoute = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    // Stop receiving route/lifecycle callbacks before tearing anything down so
    // no callback can touch the controller after disposal.
    appRouteObserver.unsubscribe(this);
    _subscribedRoute = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _isExecutingCapture = false;
    _isRecoveringInterruptedRecording = false;
    _isCoveredByRoute = false;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // --- A2: CameraX route coverage lifecycle ---------------------------------

  /// A [PageRoute] was pushed above this screen: release CameraX.
  @override
  void didPushNext() {
    _deactivateCameraWhileCovered();
  }

  /// The covering [PageRoute] was popped: this screen is visible again, so
  /// safely reacquire CameraX.
  @override
  void didPopNext() {
    _reactivateCameraWhenVisible();
  }

  /// Idempotent: repeated coverage notifications while already covered are
  /// ignored, so CameraX is deactivated at most once per coverage.
  void _deactivateCameraWhileCovered() {
    if (!mounted || _isCoveredByRoute) return;
    _isCoveredByRoute = true;
    ref.read(cameraHardwareProvider.notifier).pauseCamera();
  }

  /// Idempotent: only a real covered -> visible transition reactivates CameraX.
  void _reactivateCameraWhenVisible() {
    if (!mounted || !_isCoveredByRoute) return;
    _isCoveredByRoute = false;
    ref.read(cameraHardwareProvider.notifier).resumeCamera();
    _showInterruptedRecordingRecovery();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cameraNotifier = ref.read(cameraHardwareProvider.notifier);
    final gpsNotifier = ref.read(gpsHardwareProvider.notifier);

    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      cameraNotifier.pauseCamera();
      gpsNotifier.pauseLocationStream();
    } else if (state == AppLifecycleState.resumed) {
      // Reacquire the camera only when this screen is actually visible. While
      // covered by another route, reactivation waits for didPopNext so CameraX
      // is not re-initialized underneath the covering route.
      if (!_isCoveredByRoute) {
        cameraNotifier.resumeCamera();
        _showInterruptedRecordingRecovery();
      }
      // GPS lifecycle semantics are unchanged.
      gpsNotifier.resumeLocationStream();
    }
  }

  /// After a lifecycle interruption that stopped an in-flight recording, the
  /// captured video is preserved (never silently deleted) and the user is
  /// explicitly offered a recovery path: review it, keep it, or discard it.
  Future<void> _showInterruptedRecordingRecovery() async {
    final cameraState = ref.read(cameraHardwareProvider);
    if (!cameraState.hasInterruptedRecording || _isRecoveringInterruptedRecording) return;
    _isRecoveringInterruptedRecording = true;

    try {
      final videoFile = ref.read(cameraHardwareProvider.notifier).inFlightVideoFile;
      if (!mounted || videoFile == null) return;

      final activeSite = ref.read(siteControllerProvider).activeSite;
      final gpsHardware = ref.read(gpsHardwareProvider);
      final gpsSettings = ref.read(gpsSettingsProvider);
      final currentUserId = ref.read(authServiceProvider).currentUser?.uid;
      final storageService = ref.read(evidenceStorageServiceProvider);

      final recordingGps = (cameraState.recordingGpsState != null && cameraState.recordingGpsState!.hasValidFix)
          ? cameraState.recordingGpsState!
          : gpsHardware;

      // Preserve the interrupted recording into app storage immediately so a
      // subsequent backgrounding cannot lose it.
      final snapshot = EvidenceMetadataSnapshot.capture(
        gpsState: recordingGps,
        siteId: activeSite?.id ?? '',
        siteCode: activeSite?.siteCode ?? '',
        siteName: activeSite?.name ?? '',
        resolvedAddress: recordingGps.resolvedLocationName ?? gpsHardware.resolvedLocationName,
        creatorId: currentUserId,
        lowAccuracyThresholdMeters: gpsSettings.lowAccuracyThresholdMeters,
        customCaptureTimeUtc: cameraState.recordingStartedAtUtc ?? recordingGps.timestampUtc ?? DateTime.now().toUtc(),
      );

      final videoBytes = await videoFile.readAsBytes();
      if (!mounted) return;

      final mediaDir = await storageService.getMediaDirectory();
      final relVideoPath = 'media/orig_${snapshot.mediaId}.mp4';
      final absVideoPath = '${mediaDir.parent.path}/$relVideoPath';
      final savedFile = File(absVideoPath);
      await savedFile.writeAsBytes(videoBytes, flush: true);

      // Clean up temporary camera cache file only after destination write succeeds
      storageService.deleteTempCameraFile(videoFile.path);

      final sha256 = CryptoUtils.computeSha256(videoBytes);
      final duration = Duration(seconds: cameraState.recordingDurationSeconds);

      // Extract a first-frame thumbnail (best effort).
      String? relThumbPath;
      try {
        final data = await VideoThumbnail.thumbnailData(
          video: absVideoPath,
          imageFormat: ImageFormat.JPEG,
          maxHeight: 200,
          maxWidth: 200,
          quality: 75,
        );
        if (data.isNotEmpty) {
          final candidateThumbPath = 'media/thumb_${snapshot.mediaId}.jpg';
          final absThumbPath = '${mediaDir.parent.path}/$candidateThumbPath';
          await File(absThumbPath).writeAsBytes(data, flush: true);
          relThumbPath = candidateThumbPath;
        }
      } catch (_) {
        // Thumbnail is best-effort; the evidence file itself is preserved.
      }

      final pendingPayload = PendingCapturePayload(
        mediaId: snapshot.mediaId,
        mediaType: MediaItemType.video,
        originalFilePath: relVideoPath,
        evidenceFilePath: relVideoPath,
        thumbnailFilePath: relThumbPath,
        sha256Hash: sha256,
        fileSizeBytes: videoBytes.length,
        previewBytes: null,
        videoDuration: duration,
        metadataSnapshot: snapshot,
      );

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Recording interrupted'),
          content: const Text(
            'Your recording was interrupted before it could be reviewed. '
            'Keep it for later or discard it.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _discardInterruptedRecording(pendingPayload);
              },
              child: const Text('Discard'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _keepInterruptedRecording(pendingPayload);
              },
              child: const Text('Keep for later'),
            ),
          ],
        ),
      );
    } catch (_) {
      // If the preserved file cannot be read, there is nothing to recover.
      // The flag stays clear — no fabricated recovery.
      if (mounted) {
        ref.read(cameraHardwareProvider.notifier).clearInterruptedRecording();
      }
    } finally {
      _isRecoveringInterruptedRecording = false;
    }
  }

  Future<void> _keepInterruptedRecording(PendingCapturePayload payload) async {
    final coordinator = ref.read(mediaPersistenceCoordinatorProvider);
    try {
      final saved = await coordinator.keepForLater(payload);
      ref.read(cameraHardwareProvider.notifier).clearInterruptedRecording();
      if (!mounted) return;
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Video saved for later — review it in the gallery (${saved.id.substring(0, 8)}…)',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      ref.read(cameraHardwareProvider.notifier).clearInterruptedRecording();
      if (!mounted) return;
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save the interrupted recording. The file remains on this device.',
            style: TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          duration: Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _discardInterruptedRecording([PendingCapturePayload? payload]) {
    if (payload != null) {
      final storageService = ref.read(evidenceStorageServiceProvider);
      storageService.deleteLocalMediaFiles(
        mediaId: payload.mediaId,
        originalUri: payload.originalFilePath,
        uri: payload.evidenceFilePath,
        thumbUri: payload.thumbnailFilePath,
        type: 'video',
      );
    }
    ref.read(cameraHardwareProvider.notifier).clearInterruptedRecording();
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Interrupted recording discarded',
          style: TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleTapFocus(Offset localPosition) {
    setState(() {
      _uiState = _uiState.copyWith(
        focusPoint: localPosition,
        focusTimestamp: DateTime.now(),
      );
    });
    ref.read(cameraHardwareProvider.notifier).setFocusPoint(localPosition);
  }

  void _handleToggleFlash() {
    final nextFlash = CameraFlashMode.values[
        (_uiState.flashMode.index + 1) % CameraFlashMode.values.length];
    setState(() {
      _uiState = _uiState.copyWith(flashMode: nextFlash);
    });
    ref.read(cameraHardwareProvider.notifier).setFlashMode(nextFlash);
  }

  void _handleToggleGrid() {
    setState(() {
      _uiState = _uiState.copyWith(isGridVisible: !_uiState.isGridVisible);
    });
  }

  void _handleToggleHighContrast() {
    setState(() {
      _uiState = _uiState.copyWith(isHighContrastMode: !_uiState.isHighContrastMode);
    });
  }

  void _handleCycleAspectRatio() {
    setState(() {
      _uiState = _uiState.copyWith(aspectRatio: _uiState.aspectRatio.next);
    });
  }

  void _handleCycleTimer() {
    setState(() {
      _uiState = _uiState.copyWith(captureTimer: _uiState.captureTimer.next);
    });
  }

  void _handleCycleLens() {
    final cameraHardware = ref.read(cameraHardwareProvider);
    final available = cameraHardware.availableZoomPresets;
    if (available.isEmpty) return;

    final currentIndex = available.indexOf(cameraHardware.lensZoom);
    final nextLens = (currentIndex == -1 || currentIndex + 1 >= available.length)
        ? available.first
        : available[currentIndex + 1];

    setState(() {
      _uiState = _uiState.copyWith(lensZoom: nextLens);
    });
    ref.read(cameraHardwareProvider.notifier).setZoomPreset(nextLens);
  }

  void _handleModeChanged(CameraCaptureMode mode) {
    if (ref.read(cameraHardwareProvider).isRecordingVideo) return;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    setState(() {
      _uiState = _uiState.copyWith(
        captureMode: mode,
        isCountingDown: false,
        countdownRemaining: 0,
      );
    });
    ref.read(cameraHardwareProvider.notifier).setCaptureMode(mode);
  }

  void _handleFlipCamera() {
    if (ref.read(cameraHardwareProvider).isRecordingVideo) return;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    setState(() {
      _uiState = _uiState.copyWith(
        isCountingDown: false,
        countdownRemaining: 0,
      );
    });
    ref.read(cameraHardwareProvider.notifier).switchCamera();
  }

  Future<void> _handleShutterPressed({
    required GpsUiFixture currentGps,
    required GpsHardwareState gpsHardware,
    required String siteId,
    required String siteCode,
    required String siteName,
    required bool isCapturePermitted,
  }) async {
    if (_isExecutingCapture) return;

    final cameraState = ref.read(cameraHardwareProvider);
    final isVideo = _uiState.captureMode == CameraCaptureMode.video;

    // Video Recording Toggle Flow
    if (isVideo) {
      if (cameraState.isRecordingVideo) {
        if (_isExecutingCapture) return;
        _isExecutingCapture = true;
        if (mounted) setState(() {});
        try {
          // Stop recording
          final videoFile = await ref.read(cameraHardwareProvider.notifier).stopVideoRecording();
          if (!mounted) return;
          if (videoFile == null) {
            ScaffoldMessenger.of(context).removeCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Video Recording Warning: Could not retrieve recorded video file',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
                backgroundColor: AppColors.statusAmber,
                duration: Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
              ),
            );
            return;
          }

          final storageService = ref.read(evidenceStorageServiceProvider);
          final currentUserId = ref.read(authServiceProvider).currentUser?.uid;
          final gpsSettings = ref.read(gpsSettingsProvider);
          final bestPos = ref.read(gpsHardwareProvider.notifier).getBestRecentPosition();
          final GpsHardwareState candidateGps;
          if (bestPos != null && gpsHardware.hasValidFix) {
            candidateGps = gpsHardware.copyWith(
              latitude: bestPos.latitude,
              longitude: bestPos.longitude,
              altitudeMeters: (gpsHardware.isAltitudeMsl && gpsHardware.altitudeMeters != null)
                  ? gpsHardware.altitudeMeters
                  : bestPos.altitude,
              accuracyMeters: bestPos.accuracy,
              timestampUtc: bestPos.timestamp.toUtc(),
            );
          } else if (gpsHardware.hasValidFix) {
            candidateGps = gpsHardware;
          } else if (cameraState.recordingGpsState != null && cameraState.recordingGpsState!.hasValidFix) {
            candidateGps = cameraState.recordingGpsState!;
          } else {
            candidateGps = gpsHardware;
          }

          final snapshot = EvidenceMetadataSnapshot.capture(
            gpsState: candidateGps,
            siteId: siteId,
            siteCode: siteCode,
            siteName: siteName,
            resolvedAddress: candidateGps.resolvedLocationName ?? gpsHardware.resolvedLocationName,
            creatorId: currentUserId,
            lowAccuracyThresholdMeters: gpsSettings.lowAccuracyThresholdMeters,
            customCaptureTimeUtc: cameraState.recordingStartedAtUtc ?? candidateGps.timestampUtc ?? DateTime.now().toUtc(),
          );

          if (candidateGps.isLastKnownSeed || !snapshot.hasValidCoordinates) {
            storageService.deleteTempCameraFile(videoFile.path);
            ScaffoldMessenger.of(context).removeCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Video Capture Error: Valid GPS fix required to record evidence.',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
                backgroundColor: AppColors.statusAmber,
                duration: Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
              ),
            );
            return;
          }

          final videoBytes = await videoFile.readAsBytes();

          final mediaDir = await storageService.getMediaDirectory();
          final relVideoPath = 'media/orig_${snapshot.mediaId}.mp4';
          final absVideoPath = '${mediaDir.parent.path}/$relVideoPath';
          final savedFile = File(absVideoPath);
          await savedFile.writeAsBytes(videoBytes, flush: true);

          // Clean up temporary camera cache file only after destination write succeeds
          storageService.deleteTempCameraFile(videoFile.path);

          // Normal handoff complete: the storage copy owns the recording and
          // the camera temp file is gone, so the controller must not retain
          // the in-flight reference — a later pause would otherwise raise a
          // false interrupted-recording recovery (Cross-Cutting Audit C, C-1).
          ref.read(cameraHardwareProvider.notifier).clearInterruptedRecording();

          final sha256 = CryptoUtils.computeSha256(videoBytes);
          final duration = cameraState.recordingStoppedAtUtc != null && cameraState.recordingStartedAtUtc != null
              ? cameraState.recordingStoppedAtUtc!.difference(cameraState.recordingStartedAtUtc!)
              : Duration(seconds: cameraState.recordingDurationSeconds);

          // Extract video first-frame thumbnail (200px max)
          Uint8List? thumbBytes;
          String? relThumbPath;
          try {
            final data = await VideoThumbnail.thumbnailData(
              video: absVideoPath,
              imageFormat: ImageFormat.JPEG,
              maxHeight: 200,
              maxWidth: 200,
              quality: 75,
            );
            if (data.isNotEmpty) {
              final candidateThumbPath = 'media/thumb_${snapshot.mediaId}.jpg';
              final absThumbPath = '${mediaDir.parent.path}/$candidateThumbPath';
              await File(absThumbPath).writeAsBytes(data, flush: true);
              thumbBytes = data;
              relThumbPath = candidateThumbPath;
            }
          } catch (_) {
            // Fallback handled safely by ReviewMediaPreview errorBuilder
          }

          final pendingPayload = PendingCapturePayload(
            mediaId: snapshot.mediaId,
            mediaType: MediaItemType.video,
            originalFilePath: relVideoPath,
            evidenceFilePath: relVideoPath,
            thumbnailFilePath: relThumbPath,
            sha256Hash: sha256,
            fileSizeBytes: videoBytes.length,
            previewBytes: thumbBytes,
            videoDuration: duration,
            metadataSnapshot: snapshot,
          );

          if (!mounted) return;

          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ReviewTagScreen(payload: pendingPayload),
            ),
          );
          return;
        } catch (e, stack) {
          debugPrint('Video stop/persistence error: $e\n$stack');
          if (mounted) {
            ScaffoldMessenger.of(context).removeCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Video Save Error: Could not save video file ($e)',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
                backgroundColor: AppColors.statusRed,
                duration: const Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } finally {
          _isExecutingCapture = false;
          if (mounted) setState(() {});
        }
      } else {
        // Start recording
        if (!isCapturePermitted) return;
        // Simulation mode has no real camera — never start a "recording" that
        // cannot produce valid evidence.
        if (ref.read(cameraHardwareProvider).status == CameraStatus.unavailable) {
          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Camera access is required to record video evidence.',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
              duration: Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.surface,
            ),
          );
          return;
        }
        await ref.read(cameraHardwareProvider.notifier).startVideoRecording(
          recordingGpsState: gpsHardware,
        );
        return;
      }
    }

    if (!mounted || !isCapturePermitted) {
      return;
    }

    // Camera access check: block capture if camera is unavailable or permission denied
    final currentCameraStatus = ref.read(cameraHardwareProvider).status;
    if (currentCameraStatus == CameraStatus.unavailable ||
        currentCameraStatus == CameraStatus.permissionDenied ||
        currentCameraStatus == CameraStatus.permissionPermanentlyDenied ||
        currentCameraStatus == CameraStatus.permissionRestricted) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      final String message;
      if (currentCameraStatus == CameraStatus.permissionPermanentlyDenied) {
        message = 'Camera permission blocked. Enable in settings to capture evidence.';
      } else if (currentCameraStatus == CameraStatus.permissionRestricted) {
        message = 'Camera access restricted by device policy.';
      } else if (currentCameraStatus == CameraStatus.unavailable) {
        message = 'Optical sensor is unavailable on this device.';
      } else if (currentCameraStatus == CameraStatus.error) {
        message = 'Camera hardware error. Restore camera to capture evidence.';
      } else {
        message = 'Camera access is required to capture evidence.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppColors.statusAmber, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surface,
        ),
      );
      return;
    }

    // Timer countdown handling for photo mode
    if (_uiState.captureTimer != CameraCaptureTimer.off) {
      if (_uiState.isCountingDown) {
        // Cancel existing countdown if shutter tapped while active
        _countdownTimer?.cancel();
        _countdownTimer = null;
        setState(() {
          _uiState = _uiState.copyWith(isCountingDown: false, countdownRemaining: 0);
        });
        return;
      }

      int remaining = _uiState.captureTimer.seconds;
      setState(() {
        _uiState = _uiState.copyWith(isCountingDown: true, countdownRemaining: remaining);
      });

      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        remaining--;
        if (remaining <= 0) {
          timer.cancel();
          _countdownTimer = null;
          if (mounted) {
            setState(() {
              _uiState = _uiState.copyWith(isCountingDown: false, countdownRemaining: 0);
            });
            _executePhotoCapture(
              currentGps: currentGps,
              gpsHardware: gpsHardware,
              siteId: siteId,
              siteCode: siteCode,
              siteName: siteName,
            );
          }
        } else {
          if (mounted) {
            setState(() {
              _uiState = _uiState.copyWith(countdownRemaining: remaining);
            });
          }
        }
      });
      return;
    }

    // Immediate photo capture
    await _executePhotoCapture(
      currentGps: currentGps,
      gpsHardware: gpsHardware,
      siteId: siteId,
      siteCode: siteCode,
      siteName: siteName,
    );
  }

  Future<void> _executePhotoCapture({
    required GpsUiFixture currentGps,
    required GpsHardwareState gpsHardware,
    required String siteId,
    required String siteCode,
    required String siteName,
  }) async {
    if (_isExecutingCapture) return;
    _isExecutingCapture = true;
    if (mounted) {
      setState(() {});
    }

    try {
      // 0. Physical capture instant authority at exact shutter actuation
      final shutterInstantUtc = DateTime.now().toUtc();

      // 1. Synchronously snapshot metadata at exact shutter-accept time
      final currentUserId = ref.read(authServiceProvider).currentUser?.uid;
      final gpsSettings = ref.read(gpsSettingsProvider);
      final bestPos = ref.read(gpsHardwareProvider.notifier).getBestRecentPosition();
      final effectiveGps = (bestPos != null && gpsHardware.hasValidFix)
          ? gpsHardware.copyWith(
              latitude: bestPos.latitude,
              longitude: bestPos.longitude,
              altitudeMeters: (gpsHardware.isAltitudeMsl && gpsHardware.altitudeMeters != null)
                  ? gpsHardware.altitudeMeters
                  : bestPos.altitude,
              accuracyMeters: bestPos.accuracy,
              timestampUtc: bestPos.timestamp.toUtc(),
            )
          : gpsHardware;
      final snapshot = EvidenceMetadataSnapshot.capture(
        gpsState: effectiveGps,
        siteId: siteId,
        siteCode: siteCode,
        siteName: siteName,
        resolvedAddress: gpsHardware.resolvedLocationName,
        creatorId: currentUserId,
        lowAccuracyThresholdMeters: gpsSettings.lowAccuracyThresholdMeters,
        customCaptureTimeUtc: shutterInstantUtc,
      );

      // D-SPAT-001/D-SPAT-002: a last-known cached seed or a fix-less state
      // must never reach evidence — the photo shutter requires
      // live-provenance coordinates, mirroring the video path gate.
      if (!effectiveGps.hasLiveFix || !snapshot.hasValidCoordinates) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Photo Capture Error: Valid GPS fix required to record evidence.',
              style: TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
            backgroundColor: AppColors.statusAmber,
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final currentMapType = ref.read(mapTypeSettingsProvider);

      // 2. Trigger real hardware photo capture and initiate live map snapshot concurrently at T0
      final liveSnapshotFuture = ref
          .read(mapThumbnailControllerProvider.notifier)
          .takeLiveSnapshotForEvidence(
            lat: effectiveGps.latitude,
            lon: effectiveGps.longitude,
            mapType: currentMapType,
          );
      try {
        final capturedFile = await ref.read(cameraHardwareProvider.notifier).takePhoto();

        if (!mounted) return;

        if (capturedFile != null) {
          final rawBytes = await capturedFile.readAsBytes();
          final storageService = ref.read(evidenceStorageServiceProvider);
          final processingService = ref.read(evidenceProcessingServiceProvider);

          // Clean up temporary camera cache file in background
          storageService.deleteTempCameraFile(capturedFile.path);

          // Retrieve map tile bytes matching the user-selected map type (Normal or Satellite).
          // Prefer a fresh native GoogleMap snapshot captured concurrently at shutter time
          // (matches exactly what the user sees on screen, including the Satellite layer);
          // fall back to the type-matched cache only when the live map is unavailable and
          // the cache satisfies strict freshness guards (matching mapType, age <= 5 min,
          // distance <= 20m).
          final mapThumbnailState = ref.read(mapThumbnailControllerProvider);
          Uint8List? mapTileBytes;

          final liveSnapshot = await liveSnapshotFuture;
          if (liveSnapshot != null && liveSnapshot.isNotEmpty) {
            mapTileBytes = liveSnapshot;
          } else {
            final isTransitioning =
                ref.read(mapThumbnailControllerProvider.notifier).isMapTypeTransitioning;
            final validInMemory = (!isTransitioning &&
                    effectiveGps.latitude != null &&
                    effectiveGps.longitude != null)
                ? ref.read(mapThumbnailControllerProvider.notifier).getValidCachedSnapshotBytes(
                      lat: effectiveGps.latitude!,
                      lon: effectiveGps.longitude!,
                      mapType: currentMapType,
                    )
                : null;
            if (validInMemory != null && validInMemory.isNotEmpty) {
              mapTileBytes = validInMemory;
            } else {
              final hasValidCachedFile = !isTransitioning &&
                  mapThumbnailState.cachedTile != null &&
                  mapThumbnailState.cachedTile!.existsSync() &&
                  mapThumbnailState.mapType == currentMapType;

              bool isCacheFresh = false;
              if (hasValidCachedFile && mapThumbnailState.lastUpdate != null) {
                final age = DateTime.now().difference(mapThumbnailState.lastUpdate!);
                final isAgeFresh = age <= const Duration(minutes: 5);

                bool isDistanceFresh = true;
                if (gpsHardware.latitude != null && gpsHardware.longitude != null) {
                  final distance = MapThumbnailService.haversineDistanceMeters(
                    mapThumbnailState.lat,
                    mapThumbnailState.lon,
                    gpsHardware.latitude!,
                    gpsHardware.longitude!,
                  );
                  isDistanceFresh = distance <= MapThumbnailPolicy.movementThresholdMeters;
                }
                isCacheFresh = isAgeFresh && isDistanceFresh;
              }

              if (isCacheFresh) {
                mapTileBytes = await mapThumbnailState.cachedTile!.readAsBytes();
              } else if (!isTransitioning &&
                  gpsHardware.latitude != null &&
                  gpsHardware.longitude != null) {
                // Check local disk cache for existing imagery strictly matching the canonical state
                try {
                  final service = ref.read(mapThumbnailServiceProvider);
                  final cachedFile = await service.getCachedImage(
                    lat: gpsHardware.latitude!,
                    lon: gpsHardware.longitude!,
                    mapType: currentMapType.staticMapParam,
                  );
                  if (cachedFile != null && cachedFile.existsSync()) {
                    mapTileBytes = await cachedFile.readAsBytes();
                  }
                } catch (_) {
                  // Cache read error safely falls back to null (synthetic reticle is never used)
                }
              }
            }
          }

          final watermarkSettings = ref.read(watermarkSettingsProvider);

          // 3. Initiate asynchronous background evidence processing (bakes matching map/satellite tile into watermark)
          bool isCaptureCancelled = false;
          final processingFuture = processingService.processCapture(
            originalBytes: rawBytes,
            snapshot: snapshot,
            mapTileBytes: mapTileBytes,
            isGpsLocked: gpsHardware.hasValidFix,
            showAddress: watermarkSettings.showAddress,
            showMapTile: watermarkSettings.showMapTile,
            targetAspectRatio: _uiState.aspectRatio,
            isCancelled: () => isCaptureCancelled,
          );

          final originalSha256 = CryptoUtils.computeSha256(rawBytes);
          final pendingPayload = PendingCapturePayload(
            mediaId: snapshot.mediaId,
            mediaType: MediaItemType.photo,
            originalFilePath: storageService.getOriginalRelativePath(snapshot.mediaId),
            evidenceFilePath: null,
            thumbnailFilePath: null,
            sha256Hash: originalSha256,
            fileSizeBytes: rawBytes.length,
            metadataSnapshot: snapshot,
            previewBytes: rawBytes,
            processingFuture: processingFuture,
            onCancel: () => isCaptureCancelled = true,
          );

          if (!mounted) return;

          // 4. Open Review & Tag Screen immediately with in-flight pending capture
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ReviewTagScreen(payload: pendingPayload),
            ),
          );
        } else {
          // Fallback optical simulation capture
          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Optical Simulation Capture • ${snapshot.coordinatesDisplay}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
              duration: const Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Capture processing error: $e',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
            backgroundColor: AppColors.statusAmber,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      _isExecutingCapture = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _handlePinchZoom(double targetZoom) {
    ref.read(cameraHardwareProvider.notifier).setPinchZoom(targetZoom);
  }

  void _handleGalleryPressed() {
    Navigator.of(context).pushNamed(AppRoutes.gallery);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SiteState>(siteControllerProvider, (prev, next) {
      if (prev?.activeSite?.id != next.activeSite?.id) {
        ref.read(gpsHardwareProvider.notifier).setActiveSiteCoordinates(null, null);
      }
    });

    final activeSite = ref.watch(siteControllerProvider).activeSite;
    final siteId = activeSite?.id ?? '';
    final siteCode = activeSite?.siteCode ?? _uiState.siteCode;
    final siteName = activeSite?.name ?? _uiState.siteName;

    final cameraHardware = ref.watch(cameraHardwareProvider);
    final cameraNotifier = ref.read(cameraHardwareProvider.notifier);

    final gpsHardware = ref.watch(gpsHardwareProvider);
    final timestampSettings = ref.watch(timestampSettingsProvider);
    final displayTimestamp = timestampSettings.format(gpsHardware.timestampUtc);

    final mediaListAsync = ref.watch(activeSiteMediaStreamProvider);
    final liveGalleryCount = mediaListAsync.valueOrNull?.length ?? 0;
    final watermarkSettings = ref.watch(watermarkSettingsProvider);
    final gpsSettings = ref.watch(gpsSettingsProvider);

    // Map live GpsHardwareState to GpsUiFixture
    // The resolved address is only shown when it belongs to the current fix
    // coordinates; otherwise the HUD renders its honest "RESOLVING..." state
    // rather than a stale address from a previous location.
    final addressMatchesFix = gpsHardware.resolvedLocationLat != null &&
        gpsHardware.resolvedLocationLon != null &&
        (gpsHardware.resolvedLocationLat! - (gpsHardware.latitude ?? 0)).abs() < 0.0005 &&
        (gpsHardware.resolvedLocationLon! - (gpsHardware.longitude ?? 0)).abs() < 0.0005;
    final currentGps = GpsUiFixture(
      status: gpsHardware.fixStatus,
      blockReason: gpsHardware.blockReason,
      accuracyMeters: gpsHardware.hasValidFix ? gpsHardware.accuracyMeters : null,
      latitude: gpsHardware.hasValidFix ? (gpsHardware.latitude ?? 0.0) : 0.0,
      longitude: gpsHardware.hasValidFix ? (gpsHardware.longitude ?? 0.0) : 0.0,
      altitudeMeters: gpsHardware.hasValidFix ? (gpsHardware.altitudeMeters ?? 0.0) : 0.0,
      isAltitudeMsl: gpsHardware.isAltitudeMsl,
      headingDegrees: gpsHardware.hasValidFix ? gpsHardware.headingDegrees : null,
      timestampUtc: gpsHardware.timestampUtcDisplay,
      sectorName: gpsHardware.resolvedLocationName ??
          (gpsHardware.distanceToSiteMeters != null
              ? 'Dist: ${gpsHardware.distanceToSiteMeters!.toStringAsFixed(0)}m'
              : siteName),
      // Site coordinates are not part of the current product model, so a
      // perimeter relationship is never established. The truthful labels are
      // fix-status only: "GPS Fixed" for a live fix, "Last Known" for a cached
      // seed (never presented as a live fix), "Acquiring Fix" without either.
      geofenceStatus: gpsHardware.hasLiveFix
          ? 'GPS Fixed'
          : (gpsHardware.hasValidFix ? 'Last Known' : 'Acquiring Fix'),
      lowAccuracyThresholdMeters: gpsSettings.lowAccuracyThresholdMeters,
      resolvedAddress: addressMatchesFix ? gpsHardware.resolvedLocationName : null,
    );

    // Combined Capture Readiness Decision:
    // (Camera ready OR fallback mode) AND a LIVE GPS fix AND GPS != searching.
    // Readiness uses live-fix provenance, not merely a latched fix: a
    // cached/last-known seed is display-only and MUST NOT unlock capture.
    final isCameraFunctional = cameraHardware.isReady || cameraHardware.isUnavailable;
    final isCapturePermitted = isCameraFunctional &&
        gpsHardware.hasLiveFix &&
        gpsHardware.fixStatus != GPSFixStatus.searching;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // 1. Top Status & Sensor HUD
            CameraTopHud(
              siteCode: siteCode,
              siteName: siteName,
              gps: currentGps,
              displayTimestamp: displayTimestamp,
              onBack: () => Navigator.of(context).pop(),
              onCycleGpsState: () => GpsStatusExplainerSheet.show(context, currentGps),
              onOpenSettings: () => TimestampSettingsModal.show(
                context,
                currentTimestamp: gpsHardware.timestampUtc,
              ),
              onOpenAppSettings: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),

            // 2. Main Viewfinder with overlays & live/fallback optical feed
            Expanded(
              child: CameraViewfinder(
                state: _uiState.copyWith(
                  siteCode: siteCode,
                  siteName: siteName,
                  gps: currentGps,
                  flashMode: cameraHardware.flashMode,
                  lensZoom: cameraHardware.lensZoom,
                  isFrontCamera: cameraHardware.isFrontCamera,
                ),
                showMinimap: watermarkSettings.showMapTile,
                cameraController: cameraNotifier.controller,
                cameraStatus: cameraHardware.status,
                currentZoomLevel: cameraHardware.currentZoomLevel,
                zoomDisplayLabel: cameraHardware.zoomDisplayLabel,
                onTapFocus: _handleTapFocus,
                onPinchZoom: _handlePinchZoom,
                onToggleFlash: _handleToggleFlash,
                onToggleGrid: _handleToggleGrid,
                onCycleLens: _handleCycleLens,
                onCycleAspectRatio: _handleCycleAspectRatio,
                onCycleTimer: _handleCycleTimer,
                onToggleHighContrast: _handleToggleHighContrast,
                onRetryCamera: () => ref.read(cameraHardwareProvider.notifier).retry(),
                onRequestPermission: () =>
                    ref.read(cameraHardwareProvider.notifier).requestPermissionAndRetry(),
                onOpenRecovery: () =>
                    Navigator.of(context).pushNamed(AppRoutes.recovery),
              ),
            ),

            // 3. Bottom Shutter Station with combined shutter lock & video recording state
            CameraShutterStation(
              state: _uiState.copyWith(
                gps: currentGps,
                isFrontCamera: cameraHardware.isFrontCamera,
                cachedGalleryCount: liveGalleryCount,
              ),
              cameraStatus: cameraHardware.status,
              isCapturePermitted: isCapturePermitted,
              isRecordingVideo: cameraHardware.isRecordingVideo,
              recordingDurationFormatted: cameraHardware.recordingDurationFormatted,
              isExecutingCapture: _isExecutingCapture,
              onShutterPressed: () => _handleShutterPressed(
                currentGps: currentGps,
                gpsHardware: gpsHardware,
                siteId: siteId,
                siteCode: siteCode,
                siteName: siteName,
                isCapturePermitted: isCapturePermitted,
              ),
              onGalleryPressed: _handleGalleryPressed,
              onModeChanged: _handleModeChanged,
              onFlipCameraPressed: _handleFlipCamera,
            ),
          ],
        ),
      ),
    );
  }
}
