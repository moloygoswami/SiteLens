import 'package:flutter/material.dart';
import '../../../app/theme.dart';

class GalleryEmptyView extends StatelessWidget {
  final bool hasActiveFilters;
  final VoidCallback? onResetFilters;
  final VoidCallback onOpenCamera;

  const GalleryEmptyView({
    super.key,
    required this.hasActiveFilters,
    this.onResetFilters,
    required this.onOpenCamera,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(
                hasActiveFilters
                    ? Icons.filter_list_off_rounded
                    : Icons.photo_camera_back_outlined,
                size: 48,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              hasActiveFilters
                  ? 'NO MATCHING EVIDENCE'
                  : 'NO CAPTURED EVIDENCE YET',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasActiveFilters
                  ? 'No inspection evidence records match the selected filters or search terms.'
                  : 'Capture geotagged photos or inspection videos for this site context.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            if (hasActiveFilters && onResetFilters != null) ...[
              OutlinedButton.icon(
                onPressed: onResetFilters,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Reset All Filters'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            ElevatedButton.icon(
              onPressed: onOpenCamera,
              icon: const Icon(Icons.photo_camera_rounded, size: 18),
              label: const Text('Open Inspection Camera', style: TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
