import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
import '../../../domain/models/enums.dart';
import '../controllers/gallery_controller.dart';

class GalleryFilterBar extends ConsumerWidget {
  const GalleryFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterState = ref.watch(galleryFilterProvider);
    final notifier = ref.read(galleryFilterProvider.notifier);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // 'All' Chip
          _buildChip(
            label: 'All',
            isSelected: filterState.observationType == null && !filterState.lowAccuracyOnly,
            onSelected: () {
              notifier.setObservationType(null);
              if (filterState.lowAccuracyOnly) {
                notifier.toggleLowAccuracyOnly();
              }
            },
          ),
          const SizedBox(width: 8),

          // Observation Type Chips
          ...ObservationType.values.map((type) {
            final isSelected = filterState.observationType == type;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildChip(
                label: type.label,
                isSelected: isSelected,
                leadingColor: _getObservationColor(type),
                onSelected: () => notifier.setObservationType(type),
              ),
            );
          }),

          // Low GPS Accuracy Filter Chip
          _buildChip(
            label: 'Low GPS (>20m)',
            isSelected: filterState.lowAccuracyOnly,
            leadingIcon: Icons.warning_amber_rounded,
            leadingColor: AppColors.statusAmber,
            onSelected: () => notifier.toggleLowAccuracyOnly(),
          ),
        ],
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required bool isSelected,
    Color? leadingColor,
    IconData? leadingIcon,
    required VoidCallback onSelected,
  }) {
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leadingIcon != null) ...[
            Icon(leadingIcon, size: 13, color: isSelected ? Colors.white : leadingColor),
            const SizedBox(width: 4),
          ] else if (leadingColor != null) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : leadingColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ],
      ),
      selected: isSelected,
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surfaceContainer,
      checkmarkColor: Colors.white,
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        side: BorderSide(
          color: isSelected ? AppColors.primary : AppColors.border,
          width: 1,
        ),
      ),
      onSelected: (_) => onSelected(),
    );
  }

  Color _getObservationColor(ObservationType type) {
    switch (type) {
      case ObservationType.nonConformity:
        return AppColors.statusRed;
      case ObservationType.closed:
        return AppColors.statusGreenLight;
      case ObservationType.progress:
        return AppColors.primary;
      case ObservationType.material:
        return const Color(0xFF0288D1);
      case ObservationType.general:
        return AppColors.textSecondary;
    }
  }
}
