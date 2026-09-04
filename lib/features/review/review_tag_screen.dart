import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../domain/models/enums.dart';
import '../../shared/utils/responsive_layout.dart';
import '../camera/services/evidence_storage_service.dart';
import 'controllers/review_tag_controller.dart';
import 'models/pending_capture_payload.dart';
import 'models/review_tag_state.dart';
import 'widgets/observation_selector.dart';
import 'widgets/review_media_preview.dart';
import 'widgets/smart_link_card.dart';

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

  @override
  void initState() {
    super.initState();
    _activityController = TextEditingController();
    _noteController = TextEditingController();
    _currentPayload = widget.payload;

    _listenToProcessingFuture();
    _resolvePath();
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
    if (mounted) {
      setState(() => _resolvedEvidencePath = abs);
    }
  }

  @override
  void dispose() {
    _activityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _handleRetake() async {
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
          'This will delete the uncommitted capture files and return to the camera.',
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

    if (confirm == true && mounted) {
      await ref
          .read(reviewTagControllerProvider.notifier)
          .retake(_currentPayload);
      if (mounted) {
        Navigator.of(context).pop(false);
      }
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
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reviewState = ref.watch(reviewTagControllerProvider);

    return Scaffold(
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
          onSelected: (type) {
            ref
                .read(reviewTagControllerProvider.notifier)
                .setObservationType(type, _currentPayload);
          },
        ),
        if (reviewState.observationType == ObservationType.closed) ...[
          if (reviewState.isSearchingSmartLink)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
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
            )
          else if (reviewState.suggestedBeforeMatch != null)
            SmartLinkCard(
              candidate: reviewState.suggestedBeforeMatch!,
              distanceMeters: reviewState.suggestedDistanceMeters ?? 0.0,
              isLinked: reviewState.isLinked,
              onLink: () {
                ref
                    .read(reviewTagControllerProvider.notifier)
                    .linkSuggestedMatch();
              },
              onDismiss: () {
                ref
                    .read(reviewTagControllerProvider.notifier)
                    .unlinkSuggestedMatch();
              },
            )
          else
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.statusRed.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.statusRed.withAlpha(80)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 16, color: AppColors.statusRed),
                      SizedBox(width: 6),
                      Text(
                        'NO OPEN NON-CONFORMITY WITHIN 10M',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.statusRed,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 6),
                  Text(
                    'No open Non-Conformity found within 10m. Closed observations cannot be saved without an eligible BEFORE photo. Please select another observation type or discard this capture.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textPrimary,
                      height: 1.3,
                    ),
                  ),
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
}
