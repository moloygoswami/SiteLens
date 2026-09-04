import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
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
  MediaItem? _suggestedBeforeCandidate;
  double? _suggestedDistance;
  bool _isSearchingCandidate = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _activityController = TextEditingController(text: widget.item.activityTag ?? '');
    _noteController = TextEditingController(text: widget.item.note ?? '');
    _selectedObservation = widget.item.observationType;
    _linkedMediaId = widget.item.linkedMediaId;

    if (_selectedObservation == ObservationType.closed && _linkedMediaId == null) {
      _searchCandidate();
    }
  }

  @override
  void dispose() {
    _activityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _searchCandidate() async {
    setState(() => _isSearchingCandidate = true);
    final repo = ref.read(mediaRepositoryProvider);
    final candidate = await repo.findSuggestedBeforeMatch(
      centerLat: widget.item.lat,
      centerLon: widget.item.lon,
      siteId: widget.item.siteId,
      activityTag: _activityController.text.trim(),
      radiusMeters: 10.0,
      currentMediaId: widget.item.id,
    );

    if (mounted) {
      setState(() {
        _suggestedBeforeCandidate = candidate;
        _isSearchingCandidate = false;
      });
    }
  }

  void _onObservationSelected(ObservationType type) {
    setState(() {
      _selectedObservation = type;
      if (type == ObservationType.closed && _linkedMediaId == null) {
        _searchCandidate();
      }
    });
  }

  Future<void> _handleSave() async {
    if (_selectedObservation == ObservationType.closed &&
        (_linkedMediaId == null || _linkedMediaId!.isEmpty)) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      final repo = ref.read(mediaRepositoryProvider);
      await repo.updateTags(
        mediaId: widget.item.id,
        activityTag: _activityController.text.trim(),
        observationType: _selectedObservation,
        note: _noteController.text.trim().isNotEmpty ? _noteController.text.trim() : null,
      );

      if (_selectedObservation == ObservationType.closed && _linkedMediaId != null) {
        await repo.linkMedia(
          mediaId: widget.item.id,
          linkedMediaId: _linkedMediaId!,
        );
      }

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
    final isClosedUnlinked = _selectedObservation == ObservationType.closed &&
        (_linkedMediaId == null || _linkedMediaId!.isEmpty);

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

            // 3. Smart-Link Validation for Closed Observation
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
                )
              else if (_suggestedBeforeCandidate != null)
                SmartLinkCard(
                  candidate: _suggestedBeforeCandidate!,
                  distanceMeters: _suggestedDistance ?? 0.0,
                  isLinked: _linkedMediaId == _suggestedBeforeCandidate!.id,
                  onLink: () {
                    setState(() => _linkedMediaId = _suggestedBeforeCandidate!.id);
                  },
                  onDismiss: () {
                    setState(() => _linkedMediaId = null);
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
