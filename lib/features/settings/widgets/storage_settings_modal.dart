import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
import '../../../core/controllers/storage_settings_controller.dart';
import '../../../shared/widgets/confirmation_dialog.dart';

class StorageSettingsModal extends ConsumerWidget {
  const StorageSettingsModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const StorageSettingsModal(),
    );
  }

  void _showConfirmationDialog(BuildContext context, WidgetRef ref, int count, String size) {
    ConfirmationDialog.show(
      context,
      title: 'Clear Synced Originals',
      message: 'This will locally delete $count synced raw camera original files to reclaim approximately $size of storage.',
      confirmLabel: 'Clear Originals',
      icon: Icons.cleaning_services_rounded,
      destructive: false,
      extraContent: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSafetyBullet('Watermarked evidence (evid_*.jpg) is retained.'),
            _buildSafetyBullet('Thumbnails (thumb_*.jpg) are retained.'),
            _buildSafetyBullet('Videos (orig_*.mp4) are NOT deleted.'),
            _buildSafetyBullet('Cloud copies in Firebase remain permanent.'),
          ],
        ),
      ),
    ).then((confirmed) async {
      if (confirmed == true && context.mounted) {
        final result = await ref
            .read(storageSettingsProvider.notifier)
            .clearSyncedPhotoOriginals();
        if (result != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Reclaimed ${result.formattedReclaimedSize} across ${result.successfullyDeletedCount} photo originals.',
              ),
              backgroundColor: AppColors.statusGreen,
            ),
          );
        }
      }
    });
  }

  static Widget _buildSafetyBullet(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           Text('• ', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(
              text,
              style:  TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(storageSettingsProvider);
    final summary = state.summary;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
             SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                 Row(
                  children: [
                    Icon(Icons.storage_rounded, color: AppColors.primary, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Storage Management',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
             SizedBox(height: 12),

            // Storage Overview Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text(
                    'SYNCED PHOTO ORIGINALS',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                      letterSpacing: 0.5,
                    ),
                  ),
                   SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${summary.eligiblePhotosCount} Photos Eligible',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        summary.formattedReclaimableSize,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Raw camera originals backed up to Firebase Cloud Storage can be safely cleared from local storage to free space. Watermarked evidence images remain available on device.',
                    style: AppTypography.bodyMedium.copyWith(fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  // Video retention badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                         Icon(Icons.videocam_rounded, size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '${summary.totalVideosCount} Videos retained locally (offline playback preserved)',
                            style:  TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Action Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: (summary.eligiblePhotosCount > 0 && !state.isCleaning)
                    ? () => _showConfirmationDialog(
                          context,
                          ref,
                          summary.eligiblePhotosCount,
                          summary.formattedReclaimableSize,
                        )
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.statusAmber,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: AppColors.surfaceContainerHigh,
                  disabledForegroundColor: AppColors.textMuted,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                ),
                icon: state.isCleaning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.delete_sweep_rounded, size: 20),
                label: Text(
                  state.isCleaning
                      ? 'Clearing Originals…'
                      : (summary.eligiblePhotosCount > 0
                          ? 'Clear Synced Photo Originals (${summary.formattedReclaimableSize})'
                          : 'No Synced Originals to Clear'),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
