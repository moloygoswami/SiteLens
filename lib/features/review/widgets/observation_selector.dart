import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../domain/models/enums.dart';

class ObservationSelector extends StatelessWidget {
  final ObservationType selectedType;
  final ValueChanged<ObservationType> onSelected;
  final bool isClosedDisabled;
  final String? closedDisabledExplanation;

  const ObservationSelector({
    super.key,
    required this.selectedType,
    required this.onSelected,
    this.isClosedDisabled = false,
    this.closedDisabledExplanation,
  });

  Color _getBadgeColor(ObservationType type) {
    switch (type) {
      case ObservationType.progress:
        return const Color(0xFF0369A1); // Sky / Blue (5.6:1 on white)
      case ObservationType.nonConformity:
        return const Color(0xFFC2410C); // Dark Amber / Orange (5.1:1 on white)
      case ObservationType.closed:
        return AppColors.statusGreen; // Forest Green (5.2:1 on white)
      case ObservationType.material:
        return const Color(0xFF7E22CE); // Purple (6.1:1 on white)
      case ObservationType.general:
        return const Color(0xFF475569); // Slate (5.8:1 on white)
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.category_outlined, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              'OBSERVATION CLASSIFICATION',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: ObservationType.values.map((type) {
              final isSelected = type == selectedType;
              final isDisabled = type == ObservationType.closed && isClosedDisabled;
              final color = _getBadgeColor(type);

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Opacity(
                  opacity: isDisabled ? 0.5 : 1.0,
                  child: InkWell(
                    onTap: () => onSelected(type),
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      constraints: const BoxConstraints(minHeight: 44),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isDisabled
                            ? AppColors.surfaceContainerHigh
                            : (isSelected ? color : AppColors.surfaceContainer),
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                        border: Border.all(
                          color: isDisabled
                              ? AppColors.border
                              : (isSelected ? color : AppColors.border),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: isDisabled
                                  ? AppColors.textMuted
                                  : (isSelected ? Colors.white : color),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            type.label,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                              color: isDisabled
                                  ? AppColors.textMuted
                                  : (isSelected ? Colors.white : AppColors.textPrimary),
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        if (isClosedDisabled) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.statusAmber.withAlpha(20),
              borderRadius: BorderRadius.circular(AppRadii.sm),
              border: Border.all(color: AppColors.statusAmber.withAlpha(60), width: 1),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 14, color: AppColors.statusAmber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    closedDisabledExplanation ??
                        'No open Non-Conformity exists on this site yet — capture one first',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.statusAmber,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
