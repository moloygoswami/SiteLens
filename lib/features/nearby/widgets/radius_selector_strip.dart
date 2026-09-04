import 'package:flutter/material.dart';
import '../../../app/theme.dart';

class RadiusSelectorStrip extends StatelessWidget {
  final double selectedRadius;
  final ValueChanged<double> onRadiusSelected;

  static const List<double> defaultPresets = [2.0, 5.0, 10.0, 25.0, 50.0];

  const RadiusSelectorStrip({
    super.key,
    required this.selectedRadius,
    required this.onRadiusSelected,
  });

  bool get isCustom => !defaultPresets.contains(selectedRadius);

  void _showCustomRadiusDialog(BuildContext context) {
    double tempRadius = selectedRadius.clamp(1.0, 200.0);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
          backgroundColor: AppColors.surface,
          title: const Row(
            children: [
              Icon(Icons.radar_rounded, color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Text(
                'Custom Search Radius',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${tempRadius.toStringAsFixed(0)} meters',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Set spatial distance boundary for nearby inspection evidence.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              Slider(
                value: tempRadius,
                min: 1.0,
                max: 200.0,
                divisions: 199,
                activeColor: AppColors.primary,
                inactiveColor: AppColors.surfaceContainerHigh,
                onChanged: (val) {
                  setDialogState(() => tempRadius = val);
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('1m', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  Text('100m', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  Text('200m', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                onRadiusSelected(tempRadius.roundToDouble());
                Navigator.of(ctx).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
              ),
              child: const Text('Apply Radius', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          for (final preset in defaultPresets) ...[
            _buildRadiusChip(
              label: '${preset.toInt()}m',
              isSelected: selectedRadius == preset,
              onTap: () => onRadiusSelected(preset),
            ),
            const SizedBox(width: 8),
          ],
          _buildRadiusChip(
            label: isCustom ? 'Custom (${selectedRadius.toInt()}m)' : 'Custom...',
            isSelected: isCustom,
            onTap: () => _showCustomRadiusDialog(context),
            isCustomPill: true,
          ),
        ],
      ),
    );
  }

  Widget _buildRadiusChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    bool isCustomPill = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: Border.all(
              color: isSelected ? AppColors.primaryDark : AppColors.border,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isCustomPill) ...[
                Icon(
                  Icons.tune_rounded,
                  size: 13,
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
