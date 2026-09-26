import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../core/utils/gps_utils.dart';
import '../../domain/models/enums.dart';
import '../../shared/utils/responsive_layout.dart';
import '../camera/services/evidence_storage_service.dart';
import '../gallery/controllers/evidence_video_playback.dart';
import 'controllers/review_tag_controller.dart';
import 'models/pending_capture_payload.dart';
import 'models/review_tag_state.dart';
import 'widgets/observation_selector.dart';
import 'widgets/review_media_preview.dart';
import 'widgets/smart_link_card.dart';
import '../../domain/models/media_item.dart';
import '../nearby/nearby_search_screen.dart';

class ReviewTagScreen extends ConsumerStatefulWidget {
  final PendingCapturePayload payload;

  const ReviewTagScreen({
    super.key,
    required this.payload,
  });

  @override
  ConsumerState<ReviewTagScreen> createState() => _ReviewTagScreenState();
}

class _ReviewTagScreenState extends ConsumerState<ReviewTagScreen> {
  late final TextEditingController _activityController;
  late final TextEditingController _noteController;
  late PendingCapturePayload _currentPayload;
  String? _resolvedEvidencePath;
  String? _processingError;
  bool _isPopping = false;
  bool _isDiscardDialogOpen = false;

  /// Single-owner playback for a just-captured video, so Review & Tag can play
  /// the evidence immediately and hand the same owner to the gallery. Null for
  /// photos (R13).
  EvidenceVideoPlayback? _videoPlayback;

  @override
  void initState() {
    super.initState();
    _activityController = TextEditingController();
    _noteController = TextEditingController(
      text: ref.read(reviewTagControllerProvider).note,
    );
    _currentPayload = widget.payload;

    _listenToProcessingFuture();
    _resolvePath();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(reviewTagControllerProvider.notifier)
          .initializeSiteCandidates(_currentPayload);
    });
  }

  void _listenToProcessingFuture() {
    final future = widget.payload.processingFuture;
    if (future != null) {
      future.then((result) async {
        if (!mounted || widget.payload.isCancelled) return;
        if (result.isSuccess && result.evidenceFilePath != null) {
          final storage = ref.read(evidenceStorageServiceProvider);
          final abs = await storage.resolveAbsolutePath(result.evidenceFilePath!);
          if (mounted && !widget.payload.isCancelled) {
            setState(() {
              _resolvedEvidencePath = abs;
              _currentPayload = _currentPayload.copyWith(
                evidenceFilePath: result.evidenceFilePath,
                thumbnailFilePath: result.thumbnailFilePath,
                photoPayload: result,
              );
            });
          }
        } else if (!result.isSuccess) {
          if (mounted && !widget.payload.isCancelled) {
            setState(() {
              _processingError = result.errorMessage ?? 'Evidence processing failed';
            });
          }
        }
      }).catchError((e) {
        if (mounted && !widget.payload.isCancelled) {
          setState(() {
            _processingError = 'Evidence processing failed: $e';
          });
        }
      });
    }
  }

  Future<void> _resolvePath() async {
    final path = _currentPayload.evidenceFilePath;
    if (path == null || path.isEmpty) return;
    final storage = ref.read(evidenceStorageServiceProvider);
    final abs = await storage.resolveAbsolutePath(path);
    if (!mounted) return;
    _syncVideoPlayback(abs);
    setState(() => _resolvedEvidencePath = abs);
  }

  /// Establishes the single video playback owner for the just-captured video.
  /// Reuses the existing owner when the resolved path is unchanged so a rebuild
  /// never creates a second decoder for the same recording (R13).
  void _syncVideoPlayback(String? absPath) {
    if (!_currentPayload.isVideo || absPath == null || absPath.isEmpty) return;
    final existing = _videoPlayback;
    if (existing != null &&
        !existing.isDisposed &&
        existing.videoFile.path == absPath) {
      return;
    }
    existing?.dispose();
    final playback =
        ref.read(evidenceVideoPlaybackFactoryProvider)(File(absPath));
    _videoPlayback = playback;
    unawaited(playback.initialize());
  }

  @override
  void dispose() {
    _videoPlayback?.dispose();
    _videoPlayback = null;
    _activityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _handleRetake() async {
    // R14: back/dismiss must never discard an uncommitted capture while its
    // save is in flight — the persistence pipeline is committing those files.
    if (ref.read(reviewTagControllerProvider).isSaving) return;
    // Re-entrancy guard: a double back gesture must not stack discard dialogs.
    if (_isDiscardDialogOpen) return;
    _isDiscardDialogOpen = true;

    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: const Color.fromRGBO(0, 0, 0, 0.6),
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md)),
        backgroundColor: AppColors.surface,
        title: const Text('Discard Capture?',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 18)),
        content: const Text(
          'Discard this capture? Unsaved evidence will be permanently lost.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                    ),
                    side: const BorderSide(color: AppColors.border, width: 1.0),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.statusRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                    ),
                  ),
                  child: const Text(
                    'Discard & Retake',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    _isDiscardDialogOpen = false;

    if (confirm == true && mounted) {
      await ref
          .read(reviewTagControllerProvider.notifier)
          .retake(_currentPayload);
      if (mounted) {
        setState(() => _isPopping = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context).pop(false);
          }
        });
      }
    }
  }

  Future<void> _openNearbyPicker() async {
    final selected = await Navigator.of(context).push<MediaItem>(
      MaterialPageRoute(
        builder: (_) => NearbySearchScreen(
          initialLat: _currentPayload.metadataSnapshot.latitude,
          initialLon: _currentPayload.metadataSnapshot.longitude,
          initialSiteId: _currentPayload.metadataSnapshot.siteId,
          initialSiteCode: _currentPayload.metadataSnapshot.siteCode,
          isPicker: true,
        ),
      ),
    );
    if (selected != null && mounted) {
      ref.read(reviewTagControllerProvider.notifier).linkBeforeItem(selected);
    }
  }

  Future<void> _handleSave() async {
    if (_processingError != null) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_processingError!),
          backgroundColor: AppColors.statusRed,
        ),
      );
      return;
    }

    final mediaItem = await ref
        .read(reviewTagControllerProvider.notifier)
        .saveEvidence(_currentPayload);

    if (mounted && mediaItem != null) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: AppColors.statusGreenLight, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Evidence Saved • ${_currentPayload.metadataSnapshot.siteCode} • ${mediaItem.observationType.label}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.textPrimary,
        ),
      );
      setState(() => _isPopping = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ReviewTagState>(reviewTagControllerProvider, (previous, next) {
      if (_noteController.text != next.note) {
        _noteController.text = next.note;
        _noteController.selection = TextSelection.collapsed(
          offset: next.note.length,
        );
      }
    });

    final reviewState = ref.watch(reviewTagControllerProvider);

    return PopScope(
      canPop: _isPopping,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleRetake();
      },
      child: Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary),
          onPressed: _handleRetake,
        ),
        title: const Text(
          'REVIEW & TAG EVIDENCE',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            letterSpacing: 0.8,
          ),
        ),
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

            if (isWide) {
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left Pane: Media Preview (Canonical Burned Evidence JPEG)
                        Expanded(
                          flex: 5,
                          child: SingleChildScrollView(
                            child: ReviewMediaPreview(
                              payload: _currentPayload,
                              absoluteEvidencePath: _resolvedEvidencePath,
                              videoPlayback: _videoPlayback,
                            ),
                          ),
                        ),

                        const SizedBox(width: 24),

                        // Right Pane: Observation & Tagging Controls + Action Station
                        Expanded(
                          flex: 6,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius:
                                  BorderRadius.circular(AppRadii.card),
                              border:
                                  Border.all(color: AppColors.border, width: 1),
                            ),
                            child: Column(
                              children: [
                                Expanded(
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.all(20),
                                    child: _buildFormFields(reviewState),
                                  ),
                                ),
                                const Divider(
                                    height: 1, color: AppColors.border),
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: _buildBottomActions(reviewState),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            // Compact Mobile View
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ReviewMediaPreview(
                              payload: _currentPayload,
                              absoluteEvidencePath: _resolvedEvidencePath,
                              videoPlayback: _videoPlayback,
                            ),
                            const SizedBox(height: 18),
                            _buildFormFields(reviewState),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        border: Border(
                            top: BorderSide(color: AppColors.border, width: 1)),
                      ),
                      child: _buildBottomActions(reviewState),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}


  Widget _buildFormFields(ReviewTagState reviewState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.construction_rounded,
                size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            const Text(
              'ACTIVITY / WORK STAGE',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _activityController,
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'e.g. Excavation, PCC, Rebar, Finishing...',
            hintStyle:
                const TextStyle(fontSize: 13, color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.surfaceContainer,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
          onChanged: (val) {
            ref
                .read(reviewTagControllerProvider.notifier)
                .setActivityTag(val, _currentPayload);
          },
        ),
        const SizedBox(height: 18),
        ObservationSelector(
          selectedType: reviewState.observationType,
          isClosedDisabled: !reviewState.hasSiteOpenNonConformities,
          onSelected: (type) {
            ref
                .read(reviewTagControllerProvider.notifier)
                .setObservationType(type, _currentPayload);
          },
        ),
        if (reviewState.observationType == ObservationType.closed) ...[
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: reviewState.isLinked
                    ? AppColors.primary.withAlpha(80)
                    : AppColors.border,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.travel_explore_rounded,
                              size: 16, color: AppColors.primaryLight),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'BEFORE REFERENCE REQUIRED',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primaryLight,
                                letterSpacing: 0.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _openNearbyPicker,
                      icon: const Icon(Icons.travel_explore_rounded, size: 14),
                      label: const Text(
                        'Find Nearby Evidence',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryLight,
                        side: const BorderSide(color: AppColors.primaryLight, width: 1.2),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Existing linked BEFORE evidence remains authoritative; a Smart-Link
                // suggestion is presented separately and never displaces the link.
                if (reviewState.isLinked) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.statusGreen.withAlpha(20),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.statusGreen.withAlpha(80)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded,
                            color: AppColors.statusGreenLight, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'SELECTED BEFORE EVIDENCE',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.statusGreenLight,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                reviewState.linkedCandidate?.activityTag != null
                                    ? 'Non-Conformity • ${reviewState.linkedCandidate!.activityTag}'
                                    : 'Non-Conformity Reference',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            final notifier = ref
                                .read(reviewTagControllerProvider.notifier);
                            // Discard the pending closure selection, then
                            // immediately re-surface eligible BEFORE
                            // candidates so the correct one can be selected
                            // without losing the Smart-Link flow.
                            notifier.unlinkBeforeItem();
                            notifier.searchSmartLink(_currentPayload);
                          },
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                          ),
                          child: const Text(
                            'Unlink',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (reviewState.isSearchingSmartLink) ...[
                  const Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Scanning for eligible open Non-Conformity captures within 10m...',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (reviewState.suggestedBeforeMatch != null &&
                    reviewState.suggestedBeforeMatch!.id !=
                        reviewState.linkedMediaId) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SmartLinkCard(
                      candidate: reviewState.suggestedBeforeMatch!,
                      distanceMeters: reviewState.suggestedDistanceMeters,
                      isLinked: false,
                      onLink: () {
                        ref
                            .read(reviewTagControllerProvider.notifier)
                            .linkSuggestedMatch();
                      },
                      onDismiss: () {
                        ref
                            .read(reviewTagControllerProvider.notifier)
                            .dismissSuggestedMatch();
                      },
                    ),
                  ),
                ],
                if (!reviewState.isLinked &&
                    !reviewState.isSearchingSmartLink &&
                    reviewState.suggestedBeforeMatch == null) ...[
                  const Text(
                    'No 10m auto-match found. Tap "Find Nearby Evidence" to search and select the corresponding open Non-Conformity.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.3,
                    ),
                  ),
                  if (reviewState.siteWideCandidates.isNotEmpty) ...[
                    if (reviewState.isSiteWideSearchExpanded)
                      _buildSiteWideCandidatesSection(reviewState)
                    else
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: OutlinedButton.icon(
                          onPressed: () {
                            ref
                                .read(reviewTagControllerProvider.notifier)
                                .toggleSiteWideSearchExpanded();
                          },
                          icon: const Icon(Icons.travel_explore_rounded,
                              size: 14),
                          label: const Text(
                            'Search all open Non-Conformities on this site',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(
                                color: AppColors.primary, width: 1.2),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                          ),
                        ),
                      ),
                  ],
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            const Icon(Icons.notes_rounded,
                size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            const Text(
              'INSPECTION NOTES / REFERENCE (OPTIONAL)',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _noteController,
          maxLines: 2,
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText:
                'Enter specification clause, drawing number, or remarks...',
            hintStyle:
                const TextStyle(fontSize: 12, color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.surfaceContainer,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
          onChanged: (val) {
            ref.read(reviewTagControllerProvider.notifier).setNote(val);
          },
        ),
        if (reviewState.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              reviewState.errorMessage!,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: AppColors.statusAmber,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBottomActions(ReviewTagState reviewState) {
    return Row(
      children: [
        Expanded(
          flex: 1,
          child: OutlinedButton.icon(
            onPressed: reviewState.isSaving ? null : _handleRetake,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retake'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Builder(
            builder: (context) {
              final isClosedUnlinked =
                  reviewState.observationType == ObservationType.closed &&
                      !reviewState.isLinked;
              final isSaveDisabled = reviewState.isSaving || isClosedUnlinked;

              return ElevatedButton.icon(
                onPressed: isSaveDisabled ? null : _handleSave,
                icon: reviewState.isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(
                        isClosedUnlinked
                            ? Icons.lock_outline_rounded
                            : Icons.check_rounded,
                        size: 18,
                      ),
                label: Text(
                  reviewState.isSaving
                      ? 'Saving...'
                      : (isClosedUnlinked
                          ? 'Link BEFORE to Save'
                          : 'Save Evidence'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isClosedUnlinked
                      ? AppColors.surfaceContainerHigh
                      : AppColors.primary,
                  foregroundColor:
                      isClosedUnlinked ? AppColors.textMuted : Colors.white,
                  disabledBackgroundColor: isClosedUnlinked
                      ? AppColors.surfaceContainerHigh
                      : AppColors.primary.withAlpha(120),
                  disabledForegroundColor: isClosedUnlinked
                      ? AppColors.textMuted
                      : Colors.white.withAlpha(150),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSiteWideCandidatesSection(ReviewTagState reviewState) {
    final siteLabel = _currentPayload.metadataSnapshot.siteCode;
    final candidates = reviewState.siteWideCandidates;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh.withAlpha(120),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.travel_explore_rounded,
                  size: 15, color: AppColors.primary),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Search all open Non-Conformities on this site',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (siteLabel.isNotEmpty)
                Text(
                  siteLabel,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'No 10m match. Select an open defect from this site to link as BEFORE reference:',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          for (final candidate in candidates) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainer,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      size: 20,
                      color: AppColors.statusRed,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          candidate.item.activityTag != null &&
                                  candidate.item.activityTag!.isNotEmpty
                              ? candidate.item.activityTag!
                              : 'Non-Conformity',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${GPSUtils.formatDistanceWithUncertainty(candidate.distanceMeters, accuracyMeters: candidate.item.accuracyM)} • ${candidate.item.capturedAt.toIso8601String().substring(0, 10)}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      ref
                          .read(reviewTagControllerProvider.notifier)
                          .linkBeforeItem(candidate.item);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Link', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                ref
                    .read(reviewTagControllerProvider.notifier)
                    .dismissSiteWideSearch();
              },
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: AppColors.textSecondary,
              ),
              child: const Text(
                'None of these',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
