import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/utils/gps_utils.dart';
import '../models/camera_ui_state.dart';

/// Bottom sheet explaining the current GPS state with cause-specific guidance.
/// The GPS pill on the capture screen opens this; it is the single source of
/// truth for why capture is or is not permitted.
class GpsStatusExplainerSheet extends StatelessWidget {
  final GpsUiFixture gps;

  const GpsStatusExplainerSheet({super.key, required this.gps});

  static Future<void> show(BuildContext context, GpsUiFixture gps) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => GpsStatusExplainerSheet(gps: gps),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String title;
    final String body;
    final IconData icon;
    final Color accent;
    final bool showRecovery;

    switch (gps.blockReason) {
      case GpsBlockReason.permissionDenied:
        title = 'Location permission denied';
        body = 'SiteLens cannot capture valid evidence without your location. '
            'Every capture must be geotagged and verified. Enable location access '
            'in device settings to continue.';
        icon = Icons.location_off_rounded;
        accent = AppColors.statusRed;
        showRecovery = true;
        break;
      case GpsBlockReason.permissionUnknown:
        title = 'Location permission unknown';
        body = 'SiteLens could not determine whether location access is granted. '
            'Check your device settings and grant location access to capture '
            'evidence. This is not a confirmed denial.';
        icon = Icons.help_outline_rounded;
        accent = AppColors.statusAmber;
        showRecovery = true;
        break;
      case GpsBlockReason.serviceDisabled:
        title = 'Location service is off';
        body = 'Turn on your device\'s location service to capture evidence. '
            'SiteLens needs a live GPS fix to stamp every capture with verified '
            'coordinates.';
        icon = Icons.location_disabled_rounded;
        accent = AppColors.statusRed;
        showRecovery = true;
        break;
      case GpsBlockReason.lastKnownOnly:
        title = 'Last known location only';
        body = 'SiteLens has a cached last-known location, but evidence capture '
            'requires a live GPS fix. Move to an open area with a clear view of '
            'the sky and wait for a live fix.';
        icon = Icons.location_history_rounded;
        accent = AppColors.statusAmber;
        showRecovery = false;
        break;
      case GpsBlockReason.searching:
      case null:
        title = gps.isDegraded ? 'Low GPS precision' : 'Waiting for GPS lock';
        body = gps.isDegraded
            ? 'Current GPS precision is below the accuracy threshold. Captures will be '
                'allowed but flagged as low accuracy in the evidence record. Move to an '
                'open area for a stronger satellite fix.'
            : 'SiteLens is searching for satellites. Move to an open area with a clear '
                'view of the sky. Captures are locked until a verified GPS fix is obtained.';
        icon = Icons.location_searching_rounded;
        accent = gps.isDegraded ? AppColors.statusAmber : AppColors.statusAmber;
        showRecovery = false;
        break;
    }

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
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accent.withAlpha(18),
                    shape: BoxShape.circle,
                    border: Border.all(color: accent.withAlpha(90), width: 1.2),
                  ),
                  child: Icon(icon, color: accent, size: 22),
                ),
                 SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  icon:  Icon(Icons.close_rounded, size: 20, color: AppColors.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: AppTypography.bodyMedium.copyWith(fontSize: 14, height: 1.4),
            ),
            if (showRecovery) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    openAppSettings();
                  },
                  icon: const Icon(Icons.settings_rounded, size: 18),
                  label: const Text('Open device settings'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textOnPrimary,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pushNamed(AppRoutes.recovery);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side:  BorderSide(color: AppColors.border),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                  ),
                  child: const Text('Permission recovery'),
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
