import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
import '../../../core/utils/closed_evidence_integrity.dart';
import '../../../core/utils/haversine.dart';
import '../../../data/repositories/media_repository.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/media_item.dart';
import '../../review/widgets/observation_selector.dart';
import '../../review/widgets/smart_link_card.dart';

class MediaTagEditModal extends ConsumerStatefulWidget {
  final MediaItem item;

  const MediaTagEditModal({
    super.key,
    required this.item,
  });

  static Future<bool?> show(BuildContext context, MediaItem item) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surfaceContainerHigh,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => MediaTagEditModal(item: item),
    );
  }

  @override
  ConsumerState<MediaTagEditModal> createState() => _MediaTagEditModalState();
}

class _MediaTagEditModalState extends ConsumerState<MediaTagEditModal> {
  late TextEditingController _activityController;
  late TextEditingController _noteController;
  late ObservationType _selectedObservation;
  String? _linkedMediaId;

  /// The explicitly linked BEFORE evidence (authoritative). Loaded from the
  /// persisted `linkedMediaId` and never displaced by a Smart-Link suggestion.
  MediaItem? _linkedCandidate;
  double? _linkedDistance;

  /// The current Smart-Link SUGGESTION (alternative candidate). Distinct from
  /// [_linkedCandidate]; presenting it never changes the existing relationship.
  MediaItem? _suggestedBeforeCandidate;
  double? _suggestedDistance;
  bool _isSearchingCandidate = false;
  bool _isSaving = false;
  int _candidateSearchRequestId = 0;

  /// Mirrors [ReviewTagState.isLinked]: true only when the linked media ID and the
  /// loaded linked candidate agree, so the UI always represents the relationship
  /// that will actually be persisted.
  bool get _isLinked =>
      _linkedMediaId != null &&
      _linkedCandidate != null &&
      _linkedMediaId == _linkedCandidate!.id;

  @override
  void initState() {
    super.initState();
    _activityController = TextEditingController(text: widget.item.activityTag ?? '');
    _noteController = TextEditingController(text: widget.item.note ?? '');
    _selectedObservation = widget.item.observationType;
    _linkedMediaId = widget.item.linkedMediaId;

    if (_selectedObservation == ObservationType.closed) {
      if (_linkedMediaId != null) {
        _loadLinkedCandidate();
      } else {
        _searchCandidate();
      }
    }
  }

  Future<void> _loadLinkedCandidate() async {
    setState(() => _isSearchingCandidate = true);
    final repo = ref.read(mediaRepositoryProvider);
    final candidate = await repo.getMediaById(_linkedMediaId!);
    if (!mounted) return;
    final dist = candidate != null
        ? SpatialMathUtils.haversineDistanceMeters(
            widget.item.lat,
            widget.item.lon,
            candidate.lat,
            candidate.lon,
          )
        : null;
    setState(() {
      _isSearchingCandidate = false;
      // The existing relationship is authoritative: load it for display, never
      // clear or replace it here.
      _linkedCandidate = candidate;
      _linkedDistance = dist;
    });
  }

  @override
  void dispose() {
    _activityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _searchCandidate() async {
    final requestId = ++_candidateSearchRequestId;
    setState(() => _isSearchingCandidate = true);
    final repo = ref.read(mediaRepositoryProvider);
    final candidate = await repo.findSuggestedBeforeMatch(
      centerLat: widget.item.lat,
      centerLon: widget.item.lon,
      siteId: widget.item.siteId,
      activityTag: _activityController.text.trim(),
      radiusMeters: 10.0,
      currentMediaId: widget.item.id,
      creatorId: widget.item.creatorId,
    );

    // Discard stale responses so an older search can never replace a newer candidate.
    if (!mounted || requestId != _candidateSearchRequestId) return;

    final dist = candidate != null
        ? SpatialMathUtils.haversineDistanceMeters(
            widget.item.lat,
            widget.item.lon,
            candidate.lat,
            candidate.lon,
          )
        : null;
    setState(() {
      _isSearchingCandidate = false;
      // Search results are only SUGGESTIONS; an existing B -> A link is untouched.
      _suggestedBeforeCandidate = candidate;
      _suggestedDistance = dist;
    });
  }

  /// Explicit user action: replace the existing link with the suggested candidate.
  void _handleLinkSuggestion() {
    final candidate = _suggestedBeforeCandidate;
    if (candidate == null) return;
    setState(() {
      final updatedNote = ClosedEvidenceIntegrity.updateNoteWithEvidId(
        currentNote: _noteController.text,
        newId: candidate.id,
        previousId: _linkedMediaId,
      );
      _noteController.text = updatedNote;
      _linkedMediaId = candidate.id;
      _linkedCandidate = candidate;
      _linkedDistance = _suggestedDistance;
      _suggestedBeforeCandidate = null;
      _suggestedDistance = null;
    });
  }

  /// Explicit user action: remove the existing B -> A relationship.
  void _handleUnlink() {
    setState(() {
      if (_linkedMediaId != null) {
        _noteController.text = ClosedEvidenceIntegrity.removeEvidIdFromNote(
          currentNote: _noteController.text,
          linkedId: _linkedMediaId!,
        );
      }
      _linkedMediaId = null;
      _linkedCandidate = null;
      _linkedDistance = null;
      // A discovered suggestion, if any, remains available as an alternative.
    });
  }

  /// Dismisses the SUGGESTION only; an existing link is never affected.
  void _handleDismissSuggestion() {
    setState(() {
      _suggestedBeforeCandidate = null;
      _suggestedDistance = null;
    });
  }

  void _onObservationSelected(ObservationType type) {
    setState(() {
      _selectedObservation = type;
      if (type == ObservationType.closed) {
        if (_linkedMediaId == null) {
          _searchCandidate();
        }
      } else {
        // Changing a Closed observation to another type is an explicit user action:
        // it must clear linkedMediaId and remove any system-owned Evid_ID reference.
        if (_linkedMediaId != null) {
          _noteController.text = ClosedEvidenceIntegrity.removeEvidIdFromNote(
            currentNote: _noteController.text,
            linkedId: _linkedMediaId!,
          );
        }
        _noteController.text = ClosedEvidenceIntegrity.removeAllEvidIdsFromNote(_noteController.text);
        _linkedMediaId = null;
        _linkedCandidate = null;
        _linkedDistance = null;
        _suggestedBeforeCandidate = null;
        _suggestedDistance = null;
      }
    });
  }

  Future<void> _handleSave() async {
    // Closed evidence must retain a represented B -> A link. This guard protects
    // the existing relationship: it never clears or rewrites the link implicitly.
    if (_selectedObservation == ObservationType.closed && !_isLinked) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      final repo = ref.read(mediaRepositoryProvider);
      final effectiveLinkedId = (_selectedObservation == ObservationType.closed)
          ? _linkedMediaId
          : null;

      final validated = ClosedEvidenceIntegrity.enforceIntegrity(
        observationType: _selectedObservation,
        linkedMediaId: effectiveLinkedId,
        note: _noteController.text,
      );

      await repo.updateTags(
        mediaId: widget.item.id,
        activityTag: _activityController.text.trim(),
        observationType: _selectedObservation,
        note: validated.note,
        linkedMediaId: validated.linkedMediaId,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isClosedUnlinked = _selectedObservation == ObservationType.closed && !_isLinked;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'EDIT EVIDENCE TAGS',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: 0.8,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
            const Divider(color: AppColors.border),
            const SizedBox(height: 12),

            // 1. Activity / Work Stage Input
            const Text(
              'ACTIVITY / WORK STAGE',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _activityController,
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'e.g. Excavation, PCC, Rebar...',
                hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.surfaceContainer,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
              onChanged: (_) {
                if (_selectedObservation == ObservationType.closed) {
                  _searchCandidate();
                }
              },
            ),
            const SizedBox(height: 16),

            // 2. Observation Type Selector
            ObservationSelector(
              selectedType: _selectedObservation,
              onSelected: _onObservationSelected,
            ),

            // 3. Smart-Link Section for Closed Observation:
            //    - The existing linked BEFORE evidence is authoritative and always
            //      shown as the selected relationship.
            //    - A discovered candidate is presented separately as a NEW suggestion
            //      and never silently replaces the existing link.
            if (_selectedObservation == ObservationType.closed) ...[
              if (_isSearchingCandidate)
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
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Scanning for eligible open Non-Conformity captures within 10m...',
                          style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_isLinked)
                SmartLinkCard(
                  candidate: _linkedCandidate!,
                  distanceMeters: _linkedDistance ?? 0.0,
                  isLinked: true,
                  onLink: () {},
                  onDismiss: _handleUnlink,
                ),
              if (_suggestedBeforeCandidate != null &&
                  _suggestedBeforeCandidate!.id != _linkedMediaId)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SmartLinkCard(
                    candidate: _suggestedBeforeCandidate!,
                    distanceMeters: _suggestedDistance ?? 0.0,
                    isLinked: false,
                    onLink: _handleLinkSuggestion,
                    onDismiss: _handleDismissSuggestion,
                  ),
                ),
              if (!_isLinked &&
                  !_isSearchingCandidate &&
                  _suggestedBeforeCandidate == null)
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
                          Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.statusRed),
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
                        'No open Non-Conformity found within 10m. Closed observations cannot be saved without an eligible BEFORE photo. Please select another observation type.',
                        style: TextStyle(fontSize: 12, color: AppColors.textPrimary, height: 1.3),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 16),

            // 4. Notes Input
            const Text(
              'INSPECTION NOTES / REMARKS',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _noteController,
              maxLines: 2,
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Enter remarks or reference...',
                hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.surfaceContainer,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Bottom Actions (Cancel / Save in two-pill layout)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      side: const BorderSide(color: AppColors.border, width: 1.5),
                    ),
                    child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: (_isSaving || isClosedUnlinked) ? null : _handleSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isClosedUnlinked ? AppColors.surfaceContainerHigh : AppColors.primary,
                      foregroundColor: isClosedUnlinked ? AppColors.textMuted : Colors.white,
                      disabledBackgroundColor: isClosedUnlinked
                          ? AppColors.surfaceContainerHigh
                          : AppColors.primary.withAlpha(120),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                    ),
                    child: Text(
                      _isSaving
                          ? 'Saving...'
                          : (isClosedUnlinked ? 'Link BEFORE to Save' : 'Save Changes'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
