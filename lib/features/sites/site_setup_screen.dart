import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../app/router.dart';
import '../../core/services/auth_service.dart';
import '../../domain/models/site_model.dart';
import '../../shared/utils/responsive_layout.dart';
import '../../shared/widgets/primary_button.dart';
import 'site_controller.dart';

class SiteSetupScreen extends ConsumerStatefulWidget {
  const SiteSetupScreen({super.key});

  @override
  ConsumerState<SiteSetupScreen> createState() => _SiteSetupScreenState();
}

class _SiteSetupScreenState extends ConsumerState<SiteSetupScreen> {
  void _showAddCustomSiteDialog() {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final addressCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Offline Site / Address', style: AppTypography.titleMedium),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeCtrl,
                decoration: const InputDecoration(labelText: 'Site Code / ID (e.g. 5012)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Site / Structure Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressCtrl,
                decoration: const InputDecoration(labelText: 'Street Address / Location Ref'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (codeCtrl.text.isNotEmpty && nameCtrl.text.isNotEmpty) {
                ref.read(siteControllerProvider.notifier).addCustomOfflineSite(
                      siteCode: codeCtrl.text.trim(),
                      name: nameCtrl.text.trim(),
                      address: addressCtrl.text.trim(),
                    );
                Navigator.of(ctx).pop();
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Add & Select'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSite(SiteModel site) {
    showDialog(
      context: context,
      barrierColor: const Color.fromRGBO(0, 0, 0, 0.6),
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: AppColors.surfaceContainerHigh,
        title: const Text('Delete Site', style: AppTypography.titleMedium),
        content: Text('Are you sure you want to remove "${site.name}" from local cached sites?'),
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                    ),
                    side: const BorderSide(color: AppColors.border, width: 1.0),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    ref.read(siteControllerProvider.notifier).deleteSite(site.id);
                    Navigator.of(ctx).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.statusRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                    ),
                  ),
                  child: const Text(
                    'Delete',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final siteState = ref.watch(siteControllerProvider);
    final activeSite = siteState.activeSite;
    final availableSites = siteState.availableSites;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Project & Site Context'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reload Sites',
            onPressed: () {
              ref.read(siteControllerProvider.notifier).loadSitesAndActiveContext();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign Out',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                barrierColor: const Color.fromRGBO(0, 0, 0, 0.6),
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                  backgroundColor: AppColors.surface,
                  title: const Text('Sign Out', style: AppTypography.titleMedium),
                  content: const Text('Are you sure you want to sign out from SiteLens?'),
                  actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  actions: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppRadii.sm),
                              ),
                              side: const BorderSide(color: AppColors.border, width: 1.0),
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.statusRed,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppRadii.sm),
                              ),
                            ),
                            child: const Text(
                              'Sign Out',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await ref.read(authServiceProvider).signOut();
                if (context.mounted) {
                  Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.root, (route) => false);
                }
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= ResponsiveBreakpoints.expandedMin;

            if (isWide) {
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 20.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left Pane: Active Project Context, Actions & Offline Status
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Active Project Card
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(AppRadii.card),
                                  border: Border.all(color: AppColors.border, width: 1),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withAlpha(6),
                                      blurRadius: 12,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: AppColors.primaryContainer,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Icon(Icons.apartment_rounded, color: AppColors.primaryDark, size: 22),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'ACTIVE PROJECT / SITE',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.textSecondary,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                siteState.activeSite != null
                                                    ? '${siteState.activeSite!.siteCode} • ${siteState.activeSite!.name}'
                                                    : 'No Site Selected',
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.textPrimary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    const Divider(color: AppColors.borderLight),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        const Icon(Icons.check_circle_outline_rounded, size: 16, color: AppColors.statusGreen),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '${availableSites.length} Sites cached for 100% offline capture',
                                            style: AppTypography.bodyMedium.copyWith(fontSize: 12),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              OutlinedButton.icon(
                                onPressed: _showAddCustomSiteDialog,
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: const Text('Add New Custom Site', style: TextStyle(fontWeight: FontWeight.w700)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  side: const BorderSide(color: AppColors.primary, width: 1.5),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                                ),
                              ),
                              const Spacer(),
                              PrimaryButton(
                                label: 'Confirm Site & Open Camera',
                                icon: Icons.camera_alt_rounded,
                                onPressed: activeSite != null
                                    ? () {
                                        Navigator.of(context).pushNamed(AppRoutes.camera);
                                      }
                                    : null,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 32),

                        // Right Pane: Selectable Sites List
                        Expanded(
                          flex: 6,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Available Inspection Sites',
                                      style: AppTypography.titleMedium,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${availableSites.length} total',
                                    style: AppTypography.labelSmall.copyWith(color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: siteState.isLoading
                                    ? const Center(child: CircularProgressIndicator())
                                    : availableSites.isEmpty
                                        ? Center(
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                const Icon(Icons.location_off_rounded, size: 48, color: AppColors.textMuted),
                                                const SizedBox(height: 12),
                                                const Text('No cached sites found'),
                                                const SizedBox(height: 12),
                                                ElevatedButton(
                                                  onPressed: _showAddCustomSiteDialog,
                                                  child: const Text('Add Offline Site'),
                                                ),
                                              ],
                                            ),
                                          )
                                        : ListView.separated(
                                            itemCount: availableSites.length,
                                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                                            itemBuilder: (context, index) {
                                              final site = availableSites[index];
                                              final isSelected = activeSite?.id == site.id;

                                              return _buildSiteCard(
                                                site: site,
                                                isSelected: isSelected,
                                                onSelect: () {
                                                  ref.read(siteControllerProvider.notifier).setActiveSite(site);
                                                },
                                                onDelete: () => _confirmDeleteSite(site),
                                              );
                                            },
                                          ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            // Compact Mobile Stack
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Project Selection Card
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadii.card),
                          border: Border.all(color: AppColors.border, width: 1),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.primaryContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.apartment_rounded, color: AppColors.primaryDark, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'ACTIVE PROJECT / SITE',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    siteState.activeSite != null
                                        ? '${siteState.activeSite!.siteCode} • ${siteState.activeSite!.name}'
                                        : 'No Site Selected',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Section Title & Add Site button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Text(
                              'Select Active Site',
                              style: AppTypography.titleMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _showAddCustomSiteDialog,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('+ Add Site', style: TextStyle(fontWeight: FontWeight.w700)),
                            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Sites List
                      Expanded(
                        child: siteState.isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : availableSites.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.location_off_rounded, size: 48, color: AppColors.textMuted),
                                        const SizedBox(height: 12),
                                        const Text('No cached sites found'),
                                        const SizedBox(height: 12),
                                        ElevatedButton(
                                          onPressed: _showAddCustomSiteDialog,
                                          child: const Text('Add Offline Site'),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: availableSites.length,
                                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                                    itemBuilder: (context, index) {
                                      final site = availableSites[index];
                                      final isSelected = activeSite?.id == site.id;

                                      return _buildSiteCard(
                                        site: site,
                                        isSelected: isSelected,
                                        onSelect: () {
                                          ref.read(siteControllerProvider.notifier).setActiveSite(site);
                                        },
                                        onDelete: () => _confirmDeleteSite(site),
                                      );
                                    },
                                  ),
                      ),

                      const SizedBox(height: 12),
                      // Offline Status Indicator
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle_outline_rounded, size: 15, color: AppColors.statusGreen),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '${availableSites.length} Sites cached locally for 100% offline capture',
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Primary Action: Confirm Site
                      PrimaryButton(
                        label: 'Confirm Site & Open Camera',
                        icon: Icons.camera_alt_rounded,
                        onPressed: activeSite != null
                            ? () {
                                Navigator.of(context).pushNamed(AppRoutes.camera);
                              }
                            : null,
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSiteCard({
    required SiteModel site,
    required bool isSelected,
    required VoidCallback onSelect,
    required VoidCallback onDelete,
  }) {
    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryContainer.withAlpha(80) : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withAlpha(20),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '#${site.siteCode}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    site.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.place_outlined, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          site.address,
                          style: AppTypography.bodyMedium.copyWith(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.textMuted),
              tooltip: 'Remove Site',
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Icon(
                isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                color: isSelected ? AppColors.primary : AppColors.border,
                size: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
