import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
import '../../../core/controllers/gps_settings_controller.dart';

class GpsSettingsModal extends ConsumerWidget {
  const GpsSettingsModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const GpsSettingsModal(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(gpsSettingsProvider);
    final notifier = ref.read(gpsSettingsProvider.notifier);

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
                    Icon(Icons.gps_fixed_rounded, color: AppColors.primary, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'GPS Accuracy Threshold',
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
             SizedBox(height: 8),

            Text(
              'Captures with horizontal accuracy worse than this threshold will be flagged as degraded/low accuracy. (Default: 20.0 m).',
              style: AppTypography.bodyMedium.copyWith(fontSize: 13),
            ),
             SizedBox(height: 16),

            // Active Threshold Indicator Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                       Text(
                        'ACTIVE THRESHOLD',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                       SizedBox(height: 4),
                      Text(
                        '±${settings.lowAccuracyThresholdMeters.toStringAsFixed(1)} m',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  if (settings.lowAccuracyThresholdMeters != GpsSettingsNotifier.defaultThreshold)
                    TextButton.icon(
                      onPressed: () => notifier.resetToDefault(),
                      icon:  Icon(Icons.restart_alt_rounded, size: 16, color: AppColors.textSecondary),
                      label: const Text(
                        'Reset (20m)',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

             Text(
              'SELECT THRESHOLD (METERS)',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: GpsSettingsNotifier.presetThresholds.map((preset) {
                final isSelected = settings.lowAccuracyThresholdMeters == preset;
                final isDefault = preset == GpsSettingsNotifier.defaultThreshold;
                final label = '${preset.toStringAsFixed(0)} m${isDefault ? " (Default)" : ""}';

                return ChoiceChip(
                  label: Text(label),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      notifier.setLowAccuracyThreshold(preset);
                    }
                  },
                  selectedColor: AppColors.primaryContainer,
                  backgroundColor: AppColors.surface,
                  labelStyle: TextStyle(
                    color: isSelected ? AppColors.primaryDark : AppColors.textPrimary,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13,
                  ),
                  side: BorderSide(
                    color: isSelected ? AppColors.primary : AppColors.border,
                    width: isSelected ? 1.5 : 1.0,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            const Divider(height: 1),
            const SizedBox(height: 16),

            // High Accuracy Mode toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'High Accuracy Mode',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        settings.highAccuracyMode
                            ? 'Uses GPS + sensors for best precision (uses more battery)'
                            : 'Uses cell/Wi-Fi for a coarser but faster fix',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Switch(
                  value: settings.highAccuracyMode,
                  onChanged: (enabled) => notifier.setHighAccuracyMode(enabled),
                  activeThumbColor: AppColors.primary,
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
