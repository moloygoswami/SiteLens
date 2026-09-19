import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../app/theme.dart';
import '../../core/services/session_service.dart';
import '../../core/utils/gps_utils.dart';
import '../../core/utils/haversine.dart';
import '../../data/repositories/media_repository.dart';
import '../../data/repositories/site_repository.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/media_item.dart';
import '../../shared/utils/responsive_layout.dart';
import '../../shared/widgets/confirmation_dialog.dart';
import '../../shared/widgets/evidence_metadata_hud_card.dart';
import '../camera/hud/hud_data.dart';
import '../camera/hud/hud_formatter.dart';
import '../camera/services/evidence_storage_service.dart';
import '../nearby/nearby_search_screen.dart';
import '../sync/services/cloud_media_recovery_service.dart';
import 'controllers/evidence_video_playback.dart';
import 'widgets/local_video_player_widget.dart';
import 'widgets/media_tag_edit_modal.dart';
import 'widgets/single_item_share_sheet.dart';

class MediaDetailScreen extends ConsumerStatefulWidget {
  final MediaItem mediaItem;

  const MediaDetailScreen({
    super.key,
    required this.mediaItem,
  });

  @override
  ConsumerState<MediaDetailScreen> createState() => _MediaDetailScreenState();
}

class _MediaDetailScreenState extends ConsumerState<MediaDetailScreen> {
  late MediaItem _item;
  MediaItem? _linkedItem;
  String? _resolvedEvidencePath;
  String? _resolvedOriginalPath;
  bool _isShaExpanded = false;
  bool _isRecovering = false;

  /// Canonical persisted site code for [_item]'s site, resolved from the site
  /// repository by [MediaItem.siteId]. Used only for the user-facing metadata
  /// card; the internal Firestore-style site document id is never presented.
  String? _siteCode;

  /// Persisted site name for [_item]'s site, resolved alongside [_siteCode].
  String? _siteName;

  /// Single owner of the video player for this evidence item. Shared by the
  /// inline surface and the fullscreen surface so exactly one ExoPlayer exists.
  EvidenceVideoPlayback? _videoPlayback;

  /// True while the fullscreen route is on top; the inline video surface is
  /// parked so only one video surface renders for the shared player.
  bool _isFullscreenOpen = false;

  @override
  void initState() {
    super.initState();
    _item = widget.mediaItem;
    _loadContextualData();
  }

  @override
  void dispose() {
    // The single owned player dies with this screen.
    _videoPlayback?.dispose();
    _videoPlayback = null;
    super.dispose();
  }

  Future<void> _loadContextualData() async {
    final storage = ref.read(evidenceStorageServiceProvider);
    final mediaRepo = ref.read(mediaRepositoryProvider);
    final siteRepo = ref.read(siteRepositoryProvider);

    final evidAbs = await storage.resolveAbsolutePath(_item.uri);
    final origAbs = await storage.resolveAbsolutePath(_item.originalUri);

    final session = ref.read(sessionServiceProvider);
    final currentUserId = session.user?.uid;
    final site = _item.siteId.isEmpty
        ? null
        : await siteRepo.getSiteById(_item.siteId, creatorId: currentUserId);

    MediaItem? linked;
    if (_item.observationType == ObservationType.closed && _item.linkedMediaId != null) {
      linked = await mediaRepo.getMediaById(_item.linkedMediaId!);
    }

    if (mounted) {
      _syncVideoPlayback(_item.type == MediaItemType.video ? origAbs : null);
      setState(() {
        _resolvedEvidencePath = evidAbs;
        _resolvedOriginalPath = origAbs;
        _linkedItem = linked;
        _siteCode = site?.siteCode;
        _siteName = site?.name;
      });
    }
  }

  /// Establishes the single video playback owner for [displayPath].
  ///
  /// Reuses the existing owner when the resolved path is unchanged so reloading
  /// contextual data (tag edits, cloud recovery) never creates a second player
  /// for the same video.
  void _syncVideoPlayback(String? displayPath) {
    if (displayPath == null) return;

    final existing = _videoPlayback;
    if (existing != null &&
        !existing.isDisposed &&
        existing.videoFile.path == displayPath) {
      return;
    }

    existing?.dispose();
    final playback =
        ref.read(evidenceVideoPlaybackFactoryProvider)(File(displayPath));
    _videoPlayback = playback;
    unawaited(playback.initialize());
  }

  /// [FROZEN CONTRACT - DO NOT ALTER HEIGHT OR LAYOUT]
  /// The Immersive Evidence Viewer layout is permanently frozen to ensure edge-to-edge
  /// evidence inspection without black letterboxing or unwanted blank gaps.
  /// 1. Top: Floating translucent header bar (`SafeArea` top-aligned).
  /// 2. Body: Photo occupies full expanded height from the header bottom edge
  ///    directly down to the screen bottom (`BoxFit.contain` with `InteractiveViewer`).
  void _openFullScreenViewer() {
    final isVideo = _item.type == MediaItemType.video;
    final videoPlayback = _videoPlayback;
    final displayPath = isVideo
        ? videoPlayback?.videoFile.path
        : (_resolvedEvidencePath ?? _resolvedOriginalPath);

    if (displayPath == null) {
      return;
    }
    if (isVideo && (videoPlayback == null || videoPlayback.isDisposed)) {
      return;
    }

    // Park the inline video surface while the fullscreen surface is on top so
    // exactly one video surface renders for the single shared player.
    setState(() => _isFullscreenOpen = true);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) {
          bool showHud = true;
          return StatefulBuilder(
            builder: (ctx, setViewerState) => Scaffold(
              backgroundColor: Colors.black,
              body: SafeArea(
                child: Stack(
                  children: [
                    // 1. Media viewport
                    Positioned.fill(
                      child: isVideo
                          ? Center(
                              child: videoPlayback == null
                                  ? _buildMediaFallback(true)
                                  : LocalVideoPlayerWidget(
                                      playback: videoPlayback,
                                    ),
                            )
                          : GestureDetector(
                              onTap: () =>
                                  setViewerState(() => showHud = !showHud),
                              child: InteractiveViewer(
                                minScale: 0.8,
                                maxScale: 6.0,
                                child: Center(
                                  child: (!File(displayPath).existsSync())
                                      ? _buildMediaFallback(false)
                                      : Image.file(
                                          File(displayPath),
                                          fit: BoxFit.contain,
                                          errorBuilder: (ctx, err, stack) =>
                                              _buildMediaFallback(false),
                                        ),
                                ),
                              ),
                            ),
                    ),

                    // 2. Floating Translucent Header Bar
                    if (showHud)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          child: Row(
                            children: [
                              IconButton(
                                icon: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(
                                    color: Color(0x99000000),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close_rounded,
                                      color: Colors.white, size: 20),
                                ),
                                onPressed: () => Navigator.of(ctx).pop(),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0x99000000),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: Colors.white24, width: 0.8),
                                ),
                                child: Text(
                                  isVideo
                                      ? 'FULLSCREEN VIDEO EVIDENCE'
                                      : 'IMMERSIVE EVIDENCE VIEWER',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                              if (isVideo) ...[
                                const Spacer(),
                                IconButton(
                                  icon: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: const BoxDecoration(
                                      color: Color(0x99000000),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      showHud
                                          ? Icons.layers_outlined
                                          : Icons.layers_clear_outlined,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                  tooltip: 'Toggle Metadata Overlay',
                                  onPressed: () => setViewerState(
                                      () => showHud = !showHud),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                    // 3. Bottom canonical metadata card — VIDEO ONLY (does not
                    //    intercept touches). Video evidence has no burned-in HUD, so
                    //    the card is rendered at runtime from persisted capture-time
                    //    metadata via HudFormatter.fromMediaItem. Photo evidence
                    //    already carries the authoritative burned HUD (minimap +
                    //    metadata card) inside the persisted JPEG, so drawing a
                    //    runtime card here would duplicate it over the artifact.
                    if (showHud && isVideo)
                      Positioned(
                        bottom: 24,
                        left: 12,
                        right: 12,
                        child: IgnorePointer(
                          child: StandaloneMetadataWidget(
                            hudData: HudFormatter.fromMediaItem(
                              _item,
                              siteCode: _siteCode,
                              siteName: _siteName,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      if (mounted) {
        setState(() => _isFullscreenOpen = false);
      }
    });
  }

  Future<void> _handleEditTags() async {
    final updated = await MediaTagEditModal.show(context, _item);
    if (updated == true && mounted) {
      final mediaRepo = ref.read(mediaRepositoryProvider);
      final refreshed = await mediaRepo.getMediaById(_item.id);
      if (refreshed != null && mounted) {
        setState(() {
          _item = refreshed;
        });
        _loadContextualData();
      }
    }
  }

  Future<void> _handleDelete() async {
    final confirm = await ConfirmationDialog.show(
      context,
      title: 'Delete Media',
      message: 'Are you sure you want to delete this media?',
      confirmLabel: 'Delete',
    );

    if (confirm == true && mounted) {
      final repo = ref.read(mediaRepositoryProvider);
      if (_item.syncStatus == SyncStatusType.synced) {
        // Synced: remove from local gallery/device, cloud copy remains safely stored
        await repo.removeFromGallery(_item.id);
      } else {
        // Unsynced: permanently delete from device and SQLite
        await repo.deletePermanently(_item.id);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Media deleted'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _copyShaToClipboard() {
    final hash = _item.sha256Hash ?? _item.evidenceSha256Hash ?? 'UNKNOWN';
    Clipboard.setData(ClipboardData(text: hash));
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_outline_rounded,
                color: AppColors.statusGreenLight, size: 16),
            SizedBox(width: 8),
            Text(
              'Full SHA-256 Checksum copied to clipboard',
              style: TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ],
        ),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleRecoverMedia() async {
    setState(() {
      _isRecovering = true;
    });

    try {
      final recoveryService = ref.read(cloudMediaRecoveryServiceProvider);
      await recoveryService.recoverOriginal(item: _item);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Original recovered from cloud successfully'),
            backgroundColor: AppColors.statusGreen,
          ),
        );
        _loadContextualData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Recovery failed: $e'),
            backgroundColor: AppColors.statusRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRecovering = false;
        });
      }
    }
  }

  Widget _buildCloudRecoveryBanner() {
    final isVideo = _item.type == MediaItemType.video;
    final title =
        isVideo ? 'VIDEO STORED IN CLOUD' : 'ORIGINAL STORED IN CLOUD';
    final buttonLabel = isVideo ? 'DOWNLOAD & PLAY VIDEO' : 'DOWNLOAD ORIGINAL';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer.withAlpha(50),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primaryLight.withAlpha(100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_download_outlined,
                  color: AppColors.primaryLight, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isVideo
                ? 'The video original has been safely stored in cloud storage and cleared locally.'
                : 'The high-resolution original has been safely stored in cloud storage and cleared locally.',
            style:
                const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _isRecovering
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.download_rounded, size: 16),
              label: Text(
                buttonLabel,
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _isRecovering ? null : _handleRecoverMedia,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = _item.type == MediaItemType.video;
    final videoPlayback = _videoPlayback;
    final isDegradedStatus = _item.verificationStatus == HudStatus.degraded;
    final isVerifiedStatus = _item.verificationStatus == HudStatus.verified;
    final isPendingStatus = _item.verificationStatus == HudStatus.pending;
    final fullSha = _item.sha256Hash ?? 'UNKNOWN';
    final hashPrefix = fullSha.length > 16 ? fullSha.substring(0, 16) : fullSha;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          isVideo ? 'VIDEO EVIDENCE DETAIL' : 'PHOTO EVIDENCE DETAIL',
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            letterSpacing: 0.8,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_rounded,
                color: AppColors.primaryLight),
            tooltip: 'Share & Export Evidence',
            onPressed: () => SingleItemShareSheet.show(
              context,
              _item,
              siteCode: _siteCode,
              siteName: _siteName,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_note_rounded,
                color: AppColors.textPrimary),
            tooltip: 'Edit Tags & Notes',
            onPressed: _handleEditTags,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: AppColors.statusRed),
            tooltip: 'Delete Evidence',
            onPressed: _handleDelete,
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide =
                constraints.maxWidth >= ResponsiveBreakpoints.expandedMin;

            // The photo viewport is measured by its own LayoutBuilder so the
            // Minimap + Metadata Card overlay (burned into the evidence file) is
            // sized/positioned against the actual viewport constraints (a wide
            // split row, or a fixed-height portrait photo band).
            final displayPath = _resolvedEvidencePath ?? _resolvedOriginalPath;

            final photoViewportHeight =
                isWide ? double.infinity : screenHeight * 0.54;

            final mediaViewer = Container(
              width: double.infinity,
              height: photoViewportHeight,
              color: Colors.black,
              child: isVideo
                  ? (videoPlayback != null
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            LocalVideoPlayerWidget(
                              playback: videoPlayback,
                              isActive: !_isFullscreenOpen,
                            ),
                            Positioned(
                              top: 12,
                              right: 12,
                              child: Material(
                                color: Colors.black.withAlpha(180),
                                borderRadius: BorderRadius.circular(20),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: _openFullScreenViewer,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.fullscreen_rounded,
                                            color: Colors.white, size: 16),
                                        SizedBox(width: 4),
                                        Text(
                                          'Fullscreen Zoom',
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : const Center(
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.primary)))
                  : (displayPath != null
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            InteractiveViewer(
                              minScale: 1.0,
                              maxScale: 4.0,
                              child: Center(
                                child: Image.file(
                                  File(displayPath),
                                  fit: BoxFit.contain,
                                  errorBuilder: (ctx, err, stack) =>
                                      _buildMediaFallback(isVideo),
                                ),
                              ),
                            ),

                            // Fullscreen Expand Button Overlay (Top-Right inside photo frame)
                            Positioned(
                              top: 12,
                              right: 12,
                              child: Material(
                                color: Colors.black.withAlpha(180),
                                borderRadius: BorderRadius.circular(20),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: _openFullScreenViewer,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.fullscreen_rounded,
                                            color: Colors.white, size: 16),
                                        SizedBox(width: 4),
                                        Text(
                                          'Fullscreen Zoom',
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : _buildMediaFallback(isVideo)),
            );

            final metadataContent = Container(
              color: AppColors.background,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // CLOUD MEDIA RECOVERY BANNER (When synced original is cleared locally)
                  if (_item.syncStatus == SyncStatusType.synced &&
                      _resolvedOriginalPath != null &&
                      !File(_resolvedOriginalPath!).existsSync())
                    _buildCloudRecoveryBanner(),


                  // GROUP 1: OBSERVATION & TAGS (Consolidated, non-duplicative)
                  _buildSectionHeader('OBSERVATION & TAGS'),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainer,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color:
                                    _getObservationColor(_item.observationType),
                                borderRadius:
                                    BorderRadius.circular(AppRadii.pill),
                              ),
                              child: Text(
                                _item.observationType.label.toUpperCase(),
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _item.syncStatus == SyncStatusType.synced
                                    ? AppColors.statusGreen.withAlpha(20)
                                    : AppColors.statusAmber.withAlpha(20),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _item.syncStatus == SyncStatusType.synced
                                        ? Icons.cloud_done_rounded
                                        : Icons.cloud_upload_outlined,
                                    size: 14,
                                    color: _item.syncStatus ==
                                            SyncStatusType.synced
                                        ? AppColors.statusGreen
                                        : AppColors.statusAmber,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _item.syncStatus.name.toUpperCase(),
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: _item.syncStatus ==
                                              SyncStatusType.synced
                                          ? AppColors.statusGreen
                                          : AppColors.statusAmber,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (_item.activityTag != null &&
                            _item.activityTag!.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(Icons.construction_rounded,
                                  size: 14, color: AppColors.textSecondary),
                              const SizedBox(width: 6),
                              Text(
                                _item.activityTag!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (_item.note != null && _item.note!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            _item.note!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: isDegradedStatus
                                ? AppColors.statusAmber.withAlpha(25)
                                : (isVerifiedStatus
                                    ? AppColors.statusGreen.withAlpha(25)
                                    : AppColors.statusRed.withAlpha(25)),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isDegradedStatus
                                  ? AppColors.statusAmber.withAlpha(100)
                                  : (isVerifiedStatus
                                      ? AppColors.statusGreen.withAlpha(100)
                                      : AppColors.statusRed.withAlpha(100)),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isDegradedStatus
                                    ? Icons.warning_amber_rounded
                                    : (isVerifiedStatus
                                        ? Icons.verified_rounded
                                        : Icons.location_off_rounded),
                                size: 14,
                                color: isDegradedStatus
                                    ? AppColors.statusAmber
                                    : (isVerifiedStatus
                                        ? AppColors.statusGreen
                                        : AppColors.statusRed),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  isPendingStatus
                                      ? 'GPS STATUS: PENDING / NO FIX'
                                      : 'GPS STATUS: ${_item.verificationStatus?.name.toUpperCase() ?? (_item.lowAccuracy ? "DEGRADED" : "VERIFIED")} (±${_item.accuracyM?.toStringAsFixed(1) ?? 'N/A'}m)',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: isDegradedStatus
                                        ? AppColors.statusAmber
                                        : (isVerifiedStatus
                                            ? AppColors.statusGreen
                                            : AppColors.statusRed),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // GROUP: CAPTURE & GEOSPATIAL TELEMETRY
                  _buildSectionHeader('CAPTURE & GEOSPATIAL TELEMETRY'),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainer,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTelemetryRow(
                          'TIMESTAMP',
                          GPSUtils.formatInspectionTimestamp(_item.capturedAt),
                        ),
                        const SizedBox(height: 6),
                        _buildTelemetryRow(
                          'COORDINATES',
                          GPSUtils.formatLabeledCoordinates(_item.lat, _item.lon),
                        ),
                        const SizedBox(height: 6),
                        _buildTelemetryRow(
                          'ALTITUDE',
                          GPSUtils.formatAltitude(_item.altitude, isMsl: _item.isAltitudeMsl),
                        ),
                        const SizedBox(height: 6),
                        // R10: an uncalibrated compass heading stays explicitly
                        // unknown rather than being rendered as 0°.
                        _buildTelemetryRow(
                          'HEADING',
                          _item.headingDegrees != null
                              ? '${_item.headingDegrees!.toStringAsFixed(1)}°'
                              : '—',
                        ),
                        if (_item.capturedAddress != null &&
                            _item.capturedAddress!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          _buildTelemetryRow('LOCATION', _item.capturedAddress!),
                        ],
                        const SizedBox(height: 6),
                        _buildTelemetryRow(
                          'VERIFICATION',
                          '${_item.verificationStatus?.name.toUpperCase() ?? (_item.lowAccuracy ? "DEGRADED" : "VERIFIED")} (±${_item.accuracyM?.toStringAsFixed(1) ?? "N/A"}m)',
                        ),
                        // R09: audio-track disclosure for video evidence only.
                        // Unknown (historical rows) renders as "—", never assumed.
                        if (_item.type == MediaItemType.video) ...[
                          const SizedBox(height: 6),
                          _buildTelemetryRow('AUDIO', _audioDisclosure),
                        ],
                        if (_item.gnssSatelliteCount != null) ...[
                          const SizedBox(height: 6),
                          _buildTelemetryRow(
                            'SATELLITES',
                            '${_item.gnssSatellitesUsedInFix ?? _item.gnssSatelliteCount} used / ${_item.gnssSatelliteCount} visible',
                          ),
                        ],
                        if (_item.gnssFixTimestampUtc != null) ...[
                          const SizedBox(height: 6),
                          _buildTelemetryRow(
                            'GNSS FIX TIME',
                            '${_item.gnssFixTimestampUtc!.toUtc().toIso8601String()} (UTC)',
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // GROUP 2: FORENSIC INTEGRITY
                  _buildSectionHeader('FORENSIC INTEGRITY'),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainer,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ORIGINAL: ${_item.originalUri}',
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'EVIDENCE: ${_item.uri}',
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: AppColors.textSecondary),
                        ),
                        if (_item.thumbUri != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'THUMBNAIL: ${_item.thumbUri}',
                            style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10,
                                color: AppColors.textSecondary),
                          ),
                        ],
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () =>
                              setState(() => _isShaExpanded = !_isShaExpanded),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _isShaExpanded
                                        ? 'SHA256:\n$fullSha'
                                        : 'SHA256: $hashPrefix...',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primaryLight,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy_rounded,
                                      size: 16, color: AppColors.textSecondary),
                                  tooltip: 'Copy SHA-256 Hash',
                                  onPressed: _copyShaToClipboard,
                                  constraints: const BoxConstraints(
                                      minWidth: 48, minHeight: 48),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // SECTION 5: SMART-LINK BEFORE / AFTER EVIDENCE LINKAGE
                  if (_item.observationType == ObservationType.closed && _linkedItem != null) ...[
                    _buildLinkedEvidenceCard(_linkedItem!),
                    const SizedBox(height: 16),
                  ],

                  // PRIMARY ACTION: FIND NEARBY EVIDENCE (M5)
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              NearbySearchScreen(sourceMedia: _item),
                        ),
                      );
                    },
                    icon: const Icon(Icons.near_me_rounded, size: 18),
                    label: const Text('Find Nearby Evidence',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );

            if (isWide) {
              return Row(
                children: [
                  Expanded(
                    flex: 6,
                    child: mediaViewer,
                  ),
                  Expanded(
                    flex: 5,
                    child: SingleChildScrollView(
                      child: metadataContent,
                    ),
                  ),
                ],
              );
            }

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  mediaViewer,
                  metadataContent,
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }


  /// Truthful audio-track disclosure for a video record (R09): captured,
  /// muted, or explicitly unknown — never an assumption.
  String get _audioDisclosure {
    final hasAudio = _item.hasAudioTrack;
    if (hasAudio == null) return '—';
    return hasAudio ? 'CAPTURED' : 'MUTED';
  }

  Widget _buildTelemetryRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 95,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLinkedEvidenceCard(MediaItem linked) {
    final distance = SpatialMathUtils.haversineDistanceMeters(
      _item.lat,
      _item.lon,
      linked.lat,
      linked.lon,
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.statusGreen.withAlpha(25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.statusGreen.withAlpha(100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.link_rounded,
                  color: AppColors.statusGreen, size: 18),
              const SizedBox(width: 6),
              Text(
                _item.observationType == ObservationType.closed
                    ? 'LINKED BEFORE EVIDENCE (NON-CONFORMITY)'
                    : 'LINKED AFTER RESOLUTION (CLOSED)',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.statusGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Distance: ${distance.toStringAsFixed(1)}m away • Tag: ${linked.activityTag ?? 'General'}',
            style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            'Captured: ${DateFormat('yyyy-MM-dd HH:mm').format(linked.capturedAt.toLocal())}',
            style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaFallback(bool isVideo) {
    return Container(
      color: AppColors.surfaceContainerHigh,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isVideo ? Icons.videocam_off_rounded : Icons.broken_image_rounded,
              size: 48,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 8),
            Text(
              isVideo
                  ? 'VIDEO FILE NOT ACCESSIBLE'
                  : 'PHOTO FILE NOT ACCESSIBLE',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getObservationColor(ObservationType type) {
    switch (type) {
      case ObservationType.nonConformity:
        return AppColors.statusRed;
      case ObservationType.closed:
        return AppColors.statusGreen;
      case ObservationType.progress:
        return AppColors.primary;
      case ObservationType.material:
        return const Color(0xFF0288D1);
      case ObservationType.general:
        return AppColors.textSecondary;
    }
  }
}
