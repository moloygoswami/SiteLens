import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
import '../services/sync_coordinator.dart';

class SyncStatusBadge extends ConsumerWidget {
  final bool compact;

  const SyncStatusBadge({
    super.key,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncCoordinatorProvider);

    Color badgeColor;
    IconData badgeIcon;
    String badgeText;
    bool isInteractive = false;

    if (!syncState.isOnline) {
      badgeColor = const Color(0xFFC2410C); // Deep Orange / Offline (5.1:1 on white)
      badgeIcon = Icons.cloud_off_rounded;
      badgeText = syncState.pendingCount > 0
          ? 'Offline (${syncState.pendingCount})'
          : 'Offline';
    } else if (syncState.isSyncing) {
      badgeColor = AppColors.primaryDark; // 0xFFE65100 (5.0:1 on white)
      badgeIcon = Icons.sync_rounded;
      badgeText = syncState.pendingCount > 0
          ? 'Syncing (${syncState.pendingCount})...'
          : 'Syncing...';
    } else if (syncState.failedCount > 0) {
      badgeColor = AppColors.statusRed; // 0xFFD32F2F (5.0:1 on white)
      badgeIcon = Icons.error_outline_rounded;
      badgeText = '${syncState.failedCount} failed — Retry';
      isInteractive = true;
    } else if (syncState.pendingCount > 0) {
      badgeColor = const Color(0xFF0369A1); // Deep Blue / Pending (5.6:1 on white)
      badgeIcon = Icons.cloud_upload_outlined;
      badgeText = '${syncState.pendingCount} pending';
      isInteractive = true;
    } else {
      badgeColor = AppColors.statusGreen; // 0xFF2E7D32 / Synced (5.2:1 on white)
      badgeIcon = Icons.cloud_done_rounded;
      badgeText = 'All synced';
      isInteractive = true; // Can tap to force refresh
    }

    final content = Semantics(
      button: isInteractive,
      label: 'Cloud synchronization: $badgeText',
      hint: isInteractive
          ? (syncState.failedCount > 0
              ? 'Double tap to retry synchronization'
              : 'Double tap to check cloud synchronization')
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8.0 : 10.0,
          vertical: compact ? 4.0 : 6.0,
        ),
        decoration: BoxDecoration(
          color: badgeColor.withAlpha(25),
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(
            color: badgeColor.withAlpha(80),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (syncState.isSyncing)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2.0,
                  valueColor: AlwaysStoppedAnimation<Color>(badgeColor),
                ),
              )
            else
              Icon(badgeIcon, size: 14, color: badgeColor),
            if (!compact) ...[
              const SizedBox(width: 6),
              Text(
                badgeText,
                style: TextStyle(
                  color: badgeColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (!isInteractive) return content;

    return GestureDetector(
      onTap: () {
        ref.read(syncCoordinatorProvider.notifier).triggerSync(isManual: true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              syncState.failedCount > 0
                  ? 'Retrying synchronization...'
                  : 'Checking cloud synchronization...',
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: content,
    );
  }
}
