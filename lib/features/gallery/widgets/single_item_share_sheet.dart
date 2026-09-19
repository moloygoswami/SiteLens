import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
import '../../../core/services/auth_service.dart';
import '../../../data/repositories/site_repository.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/media_item.dart';
import '../../camera/hud/hud_formatter.dart';
import '../../camera/services/evidence_storage_service.dart';
import '../../sites/site_controller.dart';
import '../services/evidence_export_service.dart';

class SingleItemShareSheet extends ConsumerWidget {
  final MediaItem item;
  final String? siteCode;
  final String? siteName;

  const SingleItemShareSheet({
    super.key,
    required this.item,
    this.siteCode,
    this.siteName,
  });

  static Future<void> show(
    BuildContext context,
    MediaItem item, {
    String? siteCode,
    String? siteName,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceContainerHigh,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SingleItemShareSheet(
        item: item,
        siteCode: siteCode,
        siteName: siteName,
      ),
    );
  }

  Future<({String? siteCode, String? siteName})> _resolveSiteContext(
    WidgetRef ref,
  ) async {
    if (siteCode != null && siteCode!.isNotEmpty) {
      return (siteCode: siteCode, siteName: siteName);
    }

    final targetSiteId = item.siteId.trim();
    if (targetSiteId.isEmpty) {
      return (siteCode: null, siteName: null);
    }

    // 1. Check in-memory availableSites
    final availableSites = ref.read(siteControllerProvider).availableSites;
    for (final s in availableSites) {
      if (s.id == targetSiteId) {
        return (siteCode: s.siteCode, siteName: s.name);
      }
    }

    // 2. Query SiteRepository by item.siteId
    AuthUser? currentUser;
    try {
      currentUser = ref.read(authServiceProvider).currentUser;
    } catch (_) {}
    final effectiveCreatorId = item.creatorId ?? currentUser?.uid;

    try {
      final siteRepo = ref.read(siteRepositoryProvider);
      final site =
          await siteRepo.getSiteById(targetSiteId, creatorId: effectiveCreatorId);
      if (site != null) {
        return (siteCode: site.siteCode, siteName: site.name);
      }
    } catch (_) {}

    return (siteCode: null, siteName: null);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AuthUser? currentUser;
    try {
      currentUser = ref.watch(authServiceProvider).currentUser;
    } catch (_) {}
    final exportService = ref.read(evidenceExportServiceProvider);
    final storageService = ref.read(evidenceStorageServiceProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.ios_share_rounded,
                    color: AppColors.primaryLight,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SHARE & EXPORT EVIDENCE',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        'ID: ${item.id.length > 16 ? "${item.id.substring(0, 16)}..." : item.id}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 8),

            // Option 1: Share Raw Evidence File
            _ShareOptionTile(
              icon: Icons.share_rounded,
              iconColor: AppColors.primaryLight,
              title: item.type == MediaItemType.video
                  ? 'Share Video File (MP4)'
                  : 'Share Evidence Photo (JPEG)',
              subtitle: 'Export watermarked evidence file to external apps',
              onTap: () async {
                Navigator.of(context).pop();
                try {
                  final targetUri = item.uri;
                  final absPath = await storageService.resolveAbsolutePath(targetUri);
                  final (:siteCode, :siteName) = await _resolveSiteContext(ref);
                  await exportService.shareSingleFile(
                    absPath,
                    text:
                        'SiteLens Evidence: ${HudFormatter.resolveSiteIdentifier(siteCode)} • ${item.capturedAddress ?? ""}',
                  );
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to share file: $e'),
                        backgroundColor: AppColors.statusRed,
                      ),
                    );
                  }
                }
              },
            ),

            // Option 2: Export PDF Inspection Note
            _ShareOptionTile(
              icon: Icons.picture_as_pdf_rounded,
              iconColor: AppColors.statusAmber,
              title: 'Export PDF Inspection Note',
              subtitle: 'Generate client-facing PDF inspection note',
              onTap: () async {
                Navigator.of(context).pop();
                try {
                  final (:siteCode, :siteName) = await _resolveSiteContext(ref);
                  await exportService.exportSingleInspectionNotePdf(
                    item: item,
                    siteCode: siteCode,
                    siteName: siteName,
                    exporterEmail: currentUser?.email,
                    exporterUid: currentUser?.uid,
                  );
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to generate PDF: $e'),
                        backgroundColor: AppColors.statusRed,
                      ),
                    );
                  }
                }
              },
            ),

            // Option 3: Copy Full SHA-256 Checksum
            _ShareOptionTile(
              icon: Icons.fingerprint_rounded,
              iconColor: AppColors.statusGreen,
              title: 'Copy SHA-256 Checksum',
              subtitle: 'Copy full 64-character forensic hash to clipboard',
              onTap: () async {
                Navigator.of(context).pop();
                final hash = item.sha256Hash ?? item.evidenceSha256Hash ?? 'UNKNOWN';
                await Clipboard.setData(ClipboardData(text: hash));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).removeCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.check_circle_outline_rounded, color: AppColors.statusGreenLight, size: 16),
                          SizedBox(width: 8),
                          Text(
                            'SHA-256 copied to clipboard',
                            style: TextStyle(fontFamily: 'monospace', fontSize: 11),
                          ),
                        ],
                      ),
                      duration: Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ShareOptionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ShareOptionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: iconColor.withAlpha(20),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: iconColor.withAlpha(50), width: 1),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          fontSize: 11,
          color: AppColors.textSecondary,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.textMuted,
        size: 18,
      ),
      onTap: onTap,
    );
  }
}
