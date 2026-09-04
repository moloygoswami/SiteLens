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

class _CameraScreenState extends ConsumerState<CameraScreen> with WidgetsBindingObserver {
  late CameraUiState _uiState;
  Timer? _countdownTimer;

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
  void dispose() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cameraNotifier = ref.read(cameraHardwareProvider.notifier);
    final gpsNotifier = ref.read(gpsHardwareProvider.notifier);

    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      cameraNotifier.pauseCamera();
      gpsNotifier.pauseLocationStream();
    } else if (state == AppLifecycleState.resumed) {
      final currentStatus = ref.read(cameraHardwareProvider).status;
      if (currentStatus == CameraStatus.unavailable || currentStatus == CameraStatus.error) {
        cameraNotifier.resumeCamera();
      }
      gpsNotifier.resumeLocationStream();
      _showInterruptedRecordingRecovery();
    }
  }

  /// After a lifecycle interruption that stopped an in-flight recording, the
  /// captured video is preserved (never silently deleted) and the user is
  /// explicitly offered a recovery path: review it, keep it, or discard it.
  Future<void> _showInterruptedRecordingRecovery() async {
    final cameraState = ref.read(cameraHardwareProvider);
    if (!cameraState.hasInterruptedRecording) return;

    final videoFile = ref.read(cameraHardwareProvider.notifier).inFlightVideoFile;
    if (!mounted || videoFile == null) return;

    final activeSite = ref.read(siteControllerProvider).activeSite;
    final gpsHardware = ref.read(gpsHardwareProvider);
    final gpsSettings = ref.read(gpsSettingsProvider);
    final currentUserId = ref.read(authServiceProvider).currentUser?.uid;
    final storageService = ref.read(evidenceStorageServiceProvider);

    // Preserve the interrupted recording into app storage immediately so a
    // subsequent backgrounding cannot lose it.
    final snapshot = EvidenceMetadataSnapshot.capture(
      gpsState: gpsHardware,
      siteId: activeSite?.id ?? '',
      siteCode: activeSite?.siteCode ?? '',
      siteName: activeSite?.name ?? '',
      resolvedAddress: gpsHardware.resolvedLocationName,
      creatorId: currentUserId,
      lowAccuracyThresholdMeters: gpsSettings.lowAccuracyThresholdMeters,
    );

    try {
      final videoBytes = await videoFile.readAsBytes();
      if (!mounted) return;

      final mediaDir = await storageService.getMediaDirectory();
      final relVideoPath = 'media/orig_${snapshot.mediaId}.mp4';
      final absVideoPath = '${mediaDir.parent.path}/$relVideoPath';
      final savedFile = File(absVideoPath);
      await savedFile.writeAsBytes(videoBytes, flush: true);

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
          relThumbPath = 'media/thumb_${snapshot.mediaId}.jpg';
          final absThumbPath = '${mediaDir.parent.path}/$relThumbPath';
          await File(absThumbPath).writeAsBytes(data, flush: true);
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
    final nextLens = CameraLensZoom.values[
        (_uiState.lensZoom.index + 1) % CameraLensZoom.values.length];
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
    final cameraState = ref.read(cameraHardwareProvider);
    final isVideo = _uiState.captureMode == CameraCaptureMode.video;

    // Video Recording Toggle Flow
    if (isVideo) {
      if (cameraState.isRecordingVideo) {
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
        final effectiveGps = (bestPos != null && gpsHardware.hasValidFix)
            ? gpsHardware.copyWith(
                latitude: bestPos.latitude,
                longitude: bestPos.longitude,
                altitudeMeters: bestPos.altitude,
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
        );

        final videoBytes = await videoFile.readAsBytes();
        storageService.deleteTempCameraFile(videoFile.path);

        final mediaDir = await storageService.getMediaDirectory();
        final relVideoPath = 'media/orig_${snapshot.mediaId}.mp4';
        final absVideoPath = '${mediaDir.parent.path}/$relVideoPath';
        final savedFile = File(absVideoPath);
        await savedFile.writeAsBytes(videoBytes, flush: true);

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
            thumbBytes = data;
            relThumbPath = 'media/thumb_${snapshot.mediaId}.jpg';
            final absThumbPath = '${mediaDir.parent.path}/$relThumbPath';
            await File(absThumbPath).writeAsBytes(thumbBytes, flush: true);
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

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ReviewTagScreen(payload: pendingPayload),
          ),
        );
        return;
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
        await ref.read(cameraHardwareProvider.notifier).startVideoRecording();
        return;
      }
    }

    if (!isCapturePermitted) {
      return;
    }

    // Camera access check: block capture if camera is unavailable
    if (ref.read(cameraHardwareProvider).status == CameraStatus.unavailable) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.statusAmber, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Camera access is required to capture evidence.',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          duration: Duration(seconds: 4),
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

    // 1. Synchronously snapshot metadata at exact shutter-accept time
    final currentUserId = ref.read(authServiceProvider).currentUser?.uid;
    final gpsSettings = ref.read(gpsSettingsProvider);
    final bestPos = ref.read(gpsHardwareProvider.notifier).getBestRecentPosition();
    final effectiveGps = (bestPos != null && gpsHardware.hasValidFix)
        ? gpsHardware.copyWith(
            latitude: bestPos.latitude,
            longitude: bestPos.longitude,
            altitudeMeters: bestPos.altitude,
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
    );

    // 2. Trigger real hardware photo capture and initiate live map snapshot concurrently at T0
    final liveSnapshotFuture = ref
        .read(mapThumbnailControllerProvider.notifier)
        .takeLiveSnapshotForEvidence();
    final capturedFile = await ref.read(cameraHardwareProvider.notifier).takePhoto();

    if (!mounted) return;

    if (capturedFile != null) {
      try {
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
        final currentMapType = ref.read(mapTypeSettingsProvider);
        Uint8List? mapTileBytes;

        final liveSnapshot = await liveSnapshotFuture;
        if (liveSnapshot != null && liveSnapshot.isNotEmpty) {
          mapTileBytes = liveSnapshot;
        } else {
          final hasValidCachedFile = mapThumbnailState.cachedTile != null &&
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
          } else if (gpsHardware.latitude != null && gpsHardware.longitude != null) {
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

        final watermarkSettings = ref.read(watermarkSettingsProvider);

        // 3. Initiate asynchronous background evidence processing (bakes matching map/satellite tile into watermark)
        final processingFuture = processingService.processCapture(
          originalBytes: rawBytes,
          snapshot: snapshot,
          mapTileBytes: mapTileBytes,
          isGpsLocked: gpsHardware.hasValidFix,
          showAddress: watermarkSettings.showAddress,
          showMapTile: watermarkSettings.showMapTile,
          targetAspectRatio: _uiState.aspectRatio,
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
        );

        if (!mounted) return;

        // 4. Open Review & Tag Screen immediately with in-flight pending capture
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ReviewTagScreen(payload: pendingPayload),
          ),
        );
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
      headingDegrees: gpsHardware.hasValidFix ? gpsHardware.headingDegrees : null,
      timestampUtc: gpsHardware.timestampUtcDisplay,
      sectorName: gpsHardware.resolvedLocationName ??
          (gpsHardware.distanceToSiteMeters != null
              ? 'Dist: ${gpsHardware.distanceToSiteMeters!.toStringAsFixed(0)}m'
              : siteName),
      // Site coordinates are not part of the current product model, so a
      // perimeter relationship is never established. The truthful labels are
      // fix-status only: "GPS Fixed" with a valid fix, "Acquiring Fix" without.
      geofenceStatus: gpsHardware.hasValidFix ? 'GPS Fixed' : 'Acquiring Fix',
      resolvedAddress: addressMatchesFix ? gpsHardware.resolvedLocationName : null,
    );

    // Combined Capture Readiness Decision:
    // (Camera ready OR fallback mode) AND Valid GPS Fix AND GPS != searching
    final isCameraFunctional = cameraHardware.isReady || cameraHardware.isUnavailable;
    final isCapturePermitted = isCameraFunctional &&
        gpsHardware.hasValidFix &&
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
