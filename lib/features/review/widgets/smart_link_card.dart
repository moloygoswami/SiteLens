import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../domain/models/media_item.dart';

class SmartLinkCard extends StatelessWidget {
  final MediaItem candidate;
  final double distanceMeters;
  final bool isLinked;
  final VoidCallback onLink;
  final VoidCallback onDismiss;

  const SmartLinkCard({
    super.key,
    required this.candidate,
    required this.distanceMeters,
    required this.isLinked,
    required this.onLink,
    required this.onDismiss,
  });

  String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.isNegative) return 'just now';
    if (diff.inDays > 0) {
      return '${diff.inDays}d ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m ago';
    }
    return 'just now';
  }

  @override
  Widget build(BuildContext context) {
    final distanceStr = '${distanceMeters.toStringAsFixed(1)}m';
    final timeStr = _formatTimeAgo(candidate.capturedAt);
    final activityStr = candidate.activityTag != null && candidate.activityTag!.isNotEmpty
        ? ' • ${candidate.activityTag}'
        : '';

    if (isLinked) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.statusGreen.withAlpha(25),
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: AppColors.statusGreen.withAlpha(100), width: 1),
        ),
        child: Row(
          children: [
            const Icon(Icons.link_rounded, color: AppColors.statusGreenLight, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SELECTED BEFORE EVIDENCE',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.statusGreenLight,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Matched Non-Conformity ($distanceStr away, $timeStr$activityStr)',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onDismiss,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text(
                'Unlink',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onLink,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primary.withAlpha(20),
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: AppColors.primary.withAlpha(80), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, color: AppColors.primaryLight, size: 16),
                const SizedBox(width: 6),
                const Text(
                  'SMART-LINK SUGGESTION',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryLight,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Nearby Non-Conformity photo, $distanceStr away, taken $timeStr$activityStr — select as BEFORE reference?',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: onDismiss,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text(
                    'Not now',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: onLink,
                  icon: const Icon(Icons.link_rounded, size: 14),
                  label: const Text('Select as BEFORE', style: TextStyle(fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
