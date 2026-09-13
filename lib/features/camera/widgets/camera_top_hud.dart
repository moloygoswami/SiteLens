import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../core/utils/gps_utils.dart';
import '../models/camera_ui_state.dart';

class CameraTopHud extends StatelessWidget {
  final String siteCode;
  final String siteName;
  final GpsUiFixture gps;
  final String? displayTimestamp;
  final VoidCallback onBack;
  final VoidCallback? onCycleGpsState;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenAppSettings;

  const CameraTopHud({
    super.key,
    required this.siteCode,
    required this.siteName,
    required this.gps,
    this.displayTimestamp,
    required this.onBack,
    this.onCycleGpsState,
    this.onOpenSettings,
    this.onOpenAppSettings,
  });

  @override
  Widget build(BuildContext context) {
    final timestampText = displayTimestamp ?? gps.timestampUtc;

    return Container(
      color: AppColors.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Main Top Bar: Back button, Site Code & Site Name (wrapping cleanly), and GPS Status Pill
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Back button to Site Setup / Dashboard
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                  onPressed: onBack,
                  tooltip: 'Back to Site Setup',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                ),
                const SizedBox(width: 4),
                // Site icon & Project Name
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    border: Border.all(color: AppColors.primary.withAlpha(60), width: 1),
                  ),
                  child: const Icon(
                    Icons.location_city_rounded,
                    size: 16,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            siteCode.toUpperCase(),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primaryDark,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              color: AppColors.textMuted,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              gps.geofenceStatus,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: gps.isLocked
                                    ? AppColors.statusGreen
                                    : AppColors.statusAmber,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        siteName,
                        style: AppTypography.bodyMedium.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                // GPS Status Pill
                GpsStatusPill(
                  gps: gps,
                  onTap: onCycleGpsState,
                ),
                if (onOpenAppSettings != null) ...[
                  const SizedBox(width: 2),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined,
                        size: 20, color: AppColors.textSecondary),
                    onPressed: onOpenAppSettings,
                    tooltip: 'Settings & Sync',
                    constraints:
                        const BoxConstraints(minWidth: 44, minHeight: 44),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          // Precision Timestamp Strip (Configurable Display Time & Satellite Accuracy - Secondary Tier)
          Semantics(
            button: onOpenSettings != null,
            label:
                'Timestamp: $timestampText. GPS Accuracy: ${gps.accuracyMeters != null ? "±${gps.accuracyMeters!.toStringAsFixed(1)} meters" : "acquiring fix"}.',
            hint: onOpenSettings != null
                ? 'Double tap to open timestamp overlay settings'
                : null,
            child: InkWell(
              onTap: onOpenSettings,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4.5),
                color: AppColors.surfaceContainer,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.schedule_rounded,
                            size: 11, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text(
                          timestampText,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (onOpenSettings != null) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.tune_rounded,
                              size: 10, color: AppColors.textMuted),
                        ],
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(Icons.satellite_alt_rounded,
                            size: 11, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text(
                          gps.accuracyMeters != null
                              ? 'ACC: ±${gps.accuracyMeters!.toStringAsFixed(1)}m'
                              : 'ACC: ACQUIRING',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
        ],
      ),
    );
  }
}

class GpsStatusPill extends StatelessWidget {
  final GpsUiFixture gps;
  final VoidCallback? onTap;

  const GpsStatusPill({
    super.key,
    required this.gps,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    Color borderCol;
    String semanticLabel;
    const semanticHint = 'Double tap to open GPS satellite diagnostic details';

    if (gps.blockReason == GpsBlockReason.permissionDenied) {
      bg = AppColors.statusRedLight;
      fg = AppColors.statusRed;
      borderCol = AppColors.statusRed.withAlpha(80);
      semanticLabel = 'GPS location permission denied. Evidence capture locked.';
    } else if (gps.blockReason == GpsBlockReason.permissionUnknown) {
      // Unknown is not a denial: amber, and say so truthfully.
      bg = AppColors.statusAmberLight;
      fg = AppColors.statusAmber;
      borderCol = AppColors.statusAmber.withAlpha(80);
      semanticLabel =
          'GPS location permission could not be determined. Evidence capture locked.';
    } else if (gps.blockReason == GpsBlockReason.serviceDisabled) {
      bg = AppColors.statusRedLight;
      fg = AppColors.statusRed;
      borderCol = AppColors.statusRed.withAlpha(80);
      semanticLabel = 'GPS location service disabled. Evidence capture locked.';
    } else if (gps.blockReason == GpsBlockReason.lastKnownOnly) {
      bg = AppColors.statusAmberLight;
      fg = AppColors.statusAmber;
      borderCol = AppColors.statusAmber.withAlpha(80);
      semanticLabel =
          'GPS has only a last-known location. Waiting for a live fix. Evidence capture locked.';
    } else if (gps.isSearching) {
      bg = AppColors.statusAmberLight;
      fg = AppColors.statusAmber;
      borderCol = AppColors.statusAmber.withAlpha(80);
      semanticLabel = 'GPS searching for satellite lock. Precision acquiring. Capture locked.';
    } else if (gps.isDegraded) {
      bg = AppColors.statusAmberLight;
      fg = const Color(0xFFD97706);
      borderCol = const Color(0xFFD97706).withAlpha(100);
      semanticLabel = 'GPS fix locked with degraded precision: ${gps.pillLabel}.';
    } else {
      bg = AppColors.statusGreenLight;
      fg = AppColors.statusGreen;
      borderCol = AppColors.statusGreen.withAlpha(80);
      semanticLabel = 'GPS fix locked with high precision: ${gps.pillLabel}.';
    }

    return Semantics(
      button: true,
      label: semanticLabel,
      hint: semanticHint,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: Border.all(color: borderCol, width: 1.0),
          ),
          child: Text(
            gps.pillLabel,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}
