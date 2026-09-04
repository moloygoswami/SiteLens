import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
import '../../google_photos/controllers/google_photos_settings_controller.dart';
import '../../google_photos/models/google_photos_settings.dart';
import '../../google_photos/models/google_photos_sync_status.dart';
import '../../google_photos/services/google_photos_sync_coordinator.dart';
import 'settings_section_card.dart';

class GooglePhotosSettingsCard extends ConsumerWidget {
  const GooglePhotosSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gpSettings = ref.watch(googlePhotosSettingsProvider);
    final notifier = ref.read(googlePhotosSettingsProvider.notifier);

    return SettingsSectionCard(
      title: 'GOOGLE PHOTOS AUTO-SYNC',
      subtitle: 'Optional secondary cloud destination',
      icon: Icons.photo_library_rounded,
      children: [
        Text(
          'Automatically archive watermarked evidence artifacts to your Google Photos library.',
          style: AppTypography.bodyMedium.copyWith(fontSize: 12),
        ),
        const SizedBox(height: 14),

        // Connection State Row
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: gpSettings.isConnected
                ? AppColors.primaryContainer.withAlpha(50)
                : AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: Border.all(
              color: gpSettings.isConnected ? AppColors.primary.withAlpha(80) : AppColors.border,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                gpSettings.isConnected ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                size: 20,
                color: gpSettings.isConnected ? AppColors.primaryDark : AppColors.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gpSettings.isConnected ? 'Connected Google Account' : 'Google Photos Disconnected',
                      style:  TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                    if (gpSettings.accountEmail != null)
                      Text(
                        gpSettings.accountEmail!,
                        style: AppTypography.bodyMedium.copyWith(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {
                  if (gpSettings.isConnected) {
                    notifier.disconnect();
                  } else {
                    notifier.connect();
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: gpSettings.isConnected ? AppColors.statusRed : AppColors.primary,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(
                  gpSettings.isConnected ? 'Disconnect' : 'Connect',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            ],
          ),
        ),

        if (gpSettings.isConnected) ...[
          const SizedBox(height: 12),
           Divider(color: AppColors.borderLight, height: 1),
          const SizedBox(height: 10),

          // Auto-upload Toggle
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                     Text(
                      'Automatically upload captured evidence',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Target album: ${gpSettings.albumName}',
                      style: AppTypography.bodyMedium.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: gpSettings.autoUpload,
                activeTrackColor: AppColors.primary,
                onChanged: (val) {
                  notifier.setAutoUpload(val);
                },
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Status Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  _buildStatusDot(gpSettings.overallStatus),
                  const SizedBox(width: 6),
                  Text(
                    'Status: ${_formatStatus(gpSettings)}',
                    style:  TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                ],
              ),
              if (gpSettings.pendingCount > 0)
                TextButton.icon(
                  onPressed: () {
                    ref.read(googlePhotosSyncCoordinatorProvider).triggerSync();
                  },
                  icon: const Icon(Icons.sync_rounded, size: 14),
                  label: const Text('Sync Now', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),

          if (gpSettings.lastError != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.statusRed.withAlpha(20),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                   Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.statusRed),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      gpSettings.lastError!,
                      style:  TextStyle(fontSize: 11, color: AppColors.statusRed),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildStatusDot(GooglePhotosSyncStatus status) {
    Color color;
    switch (status) {
      case GooglePhotosSyncStatus.uploaded:
        color = AppColors.statusGreen;
        break;
      case GooglePhotosSyncStatus.uploading:
        color = AppColors.primary;
        break;
      case GooglePhotosSyncStatus.pending:
        color = const Color(0xFFF59E0B);
        break;
      case GooglePhotosSyncStatus.failed:
      case GooglePhotosSyncStatus.authRequired:
        color = AppColors.statusRed;
        break;
      case GooglePhotosSyncStatus.disabled:
        color = AppColors.textMuted;
        break;
    }

    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }

  String _formatStatus(GooglePhotosSettings settings) {
    if (!settings.isConnected) return 'Disconnected';
    if (!settings.autoUpload) return 'Auto-Sync Paused';

    if (settings.pendingCount > 0) {
      return 'Pending (${settings.pendingCount} queued)';
    }

    switch (settings.overallStatus) {
      case GooglePhotosSyncStatus.uploading:
        return 'Uploading...';
      case GooglePhotosSyncStatus.uploaded:
        return 'All evidence synced';
      case GooglePhotosSyncStatus.authRequired:
        return 'Auth Required';
      case GooglePhotosSyncStatus.failed:
        return 'Sync Error';
      default:
        return 'Connected';
    }
  }
}
