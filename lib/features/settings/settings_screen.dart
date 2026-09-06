import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/controllers/gps_settings_controller.dart';
import '../../core/controllers/map_type_settings_controller.dart';
import '../../core/controllers/nearby_settings_controller.dart';
import '../../core/controllers/timestamp_settings_controller.dart';
import '../../core/controllers/watermark_settings_controller.dart';
import '../../core/models/timestamp_settings.dart';
import '../../core/services/auth_service.dart';
import '../../domain/models/enums.dart';
import '../../shared/utils/responsive_layout.dart';
import '../../shared/widgets/confirmation_dialog.dart';
import '../camera/widgets/gps_settings_modal.dart';
import '../camera/widgets/timestamp_settings_modal.dart';
import '../sites/site_controller.dart';
import '../sites/site_setup_screen.dart';
import '../support/widgets/user_enquiry_modal.dart';
import '../../data/local/database/database_provider.dart';
import 'widgets/account_deletion_dialog.dart';
import 'widgets/google_photos_settings_card.dart';
import 'widgets/legal_doc_modal.dart';
import 'widgets/settings_section_card.dart';
import 'widgets/storage_settings_modal.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gpsThreshold = ref.watch(gpsSettingsProvider);
    final timestampFormat = ref.watch(timestampSettingsProvider);
    final mapType = ref.watch(mapTypeSettingsProvider);
    final watermarkSettings = ref.watch(watermarkSettingsProvider);
    final nearbyRadius = ref.watch(nearbySettingsProvider);
    final activeSite = ref.watch(siteControllerProvider).activeSite;
    final authUser = ref.watch(authServiceProvider).currentUser;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('SETTINGS'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ResponsiveContainer(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= ResponsiveBreakpoints.expandedMin;

              final leftColumn = [
                // SECTION 1: GPS ACCURACY
                _buildGpsSection(context, ref, gpsThreshold.lowAccuracyThresholdMeters),
                const SizedBox(height: 16),

                // SECTION 2: WATERMARK & STAMP
                _buildWatermarkSection(context, ref, timestampFormat, mapType, watermarkSettings),
              ];

              final rightColumn = [
                // SECTION 3: NEARBY SEARCH DEFAULTS
                _buildNearbySection(context, ref, nearbyRadius),
                const SizedBox(height: 16),

                // SECTION 4: STORAGE & LOCAL MEDIA
                _buildStorageSection(context, ref),
                const SizedBox(height: 16),

                // SECTION 5: GOOGLE PHOTOS AUTO-SYNC
                const GooglePhotosSettingsCard(),
                const SizedBox(height: 16),

                // SECTION 6: USER ACCOUNT & SITE
                _buildAccountSection(context, ref, authUser, activeSite),
                const SizedBox(height: 16),

                // SECTION 7: SUPPORT & ENQUIRIES
                _buildSupportSection(context),
                const SizedBox(height: 16),

                // SECTION 8: LEGAL & COMPLIANCE
                _buildLegalSection(context),
              ];

              if (isWide) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: leftColumn,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: rightColumn,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...leftColumn,
                    const SizedBox(height: 16),
                    ...rightColumn,
                    const SizedBox(height: 24),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ==========================================
  // SECTION 2: GPS ACCURACY
  // ==========================================
  Widget _buildGpsSection(BuildContext context, WidgetRef ref, double threshold) {
    return SettingsSectionCard(
      icon: Icons.gps_fixed_rounded,
      title: 'GPS & GEOLOCATION',
      subtitle: 'Precision tolerance and classification thresholds',
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text(
                    'Accuracy Threshold',
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Captures with precision > ${threshold.toInt()}m are tagged Weak',
                    style:  TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppRadii.pill),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                '±${threshold.toInt()}m',
                style:  TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.primary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => GpsSettingsModal.show(context),
            icon: const Icon(Icons.tune_rounded, size: 16),
            label: const Text('CONFIGURE GPS THRESHOLD', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side:  BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.pill)),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // SECTION 3: WATERMARK & STAMP
  // ==========================================
  Widget _buildWatermarkSection(
    BuildContext context,
    WidgetRef ref,
    TimestampDisplaySettings format,
    AppMapType mapType,
    dynamic watermarkSettings,
  ) {
    final showAddress = watermarkSettings.showAddress as bool;
    final showMapTile = watermarkSettings.showMapTile as bool;

    return SettingsSectionCard(
      icon: Icons.branding_watermark_rounded,
      title: 'WATERMARK & STAMP',
      subtitle: 'Burned-in evidence metadata and map tile overlay',
      children: [
        // Timestamp Format
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text(
                    'Timestamp Display',
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${format.timezoneMode.label} • ${format.formatStyle.label}',
                    style:  TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon:  Icon(Icons.edit_calendar_rounded, color: AppColors.primary, size: 20),
              tooltip: 'Change Timestamp Format',
              onPressed: () => TimestampSettingsModal.show(context),
            ),
          ],
        ),
         Divider(height: 16, color: AppColors.border),

        // Map Tile Type
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text(
                    'Map Tile Type',
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    mapType == AppMapType.normal ? 'Standard Roadmap' : 'Satellite Imagery',
                    style:  TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              value: mapType == AppMapType.satellite,
              activeThumbColor: AppColors.primary,
              onChanged: (_) => ref.read(mapTypeSettingsProvider.notifier).toggleMapType(),
            ),
          ],
        ),
         Divider(height: 16, color: AppColors.border),

        // Show Address Toggle
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
             Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Physical Address',
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontSize: 13),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Burn reverse-geocoded address into stamp',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              value: showAddress,
              activeThumbColor: AppColors.primary,
              onChanged: (val) => ref.read(watermarkSettingsProvider.notifier).setShowAddress(val),
            ),
          ],
        ),
         Divider(height: 16, color: AppColors.border),

        // Show Map Tile Toggle
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
             Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mini Map Tile',
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontSize: 13),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Include 100x100 preview map in watermark',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              value: showMapTile,
              activeThumbColor: AppColors.primary,
              onChanged: (val) => ref.read(watermarkSettingsProvider.notifier).setShowMapTile(val),
            ),
          ],
        ),
      ],
    );
  }

  // ==========================================
  // SECTION 4: NEARBY SEARCH DEFAULTS
  // ==========================================
  Widget _buildNearbySection(BuildContext context, WidgetRef ref, double defaultRadius) {
    const radiusPresets = [2.0, 5.0, 10.0, 25.0, 50.0];

    return SettingsSectionCard(
      icon: Icons.near_me_rounded,
      title: 'NEARBY SEARCH DEFAULTS',
      subtitle: 'Default spatial matching radius for Before/After linking',
      children: [
         Text(
          'Default Search Radius',
          style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontSize: 13),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: radiusPresets.map((r) {
            final isSelected = (defaultRadius - r).abs() < 0.1;
            return ChoiceChip(
              label: Text('${r.toInt()}m', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              selected: isSelected,
              selectedColor: AppColors.primary,
              backgroundColor: AppColors.surfaceContainerHigh,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : AppColors.textPrimary,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
              ),
              side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
              onSelected: (_) => ref.read(nearbySettingsProvider.notifier).setDefaultRadius(r),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ==========================================
  // SECTION 5: STORAGE & LOCAL MEDIA
  // ==========================================
  Widget _buildStorageSection(BuildContext context, WidgetRef ref) {
    return SettingsSectionCard(
      icon: Icons.storage_rounded,
      title: 'STORAGE & LOCAL MEDIA',
      subtitle: 'Reclaim device space and manage cached originals',
      children: [
         Text(
          'Free storage by clearing raw photo originals that have already been safely synchronized to Firebase Cloud Storage.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => StorageSettingsModal.show(context),
            icon: const Icon(Icons.cleaning_services_rounded, size: 16),
            label: const Text('MANAGE LOCAL STORAGE', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.surfaceContainerHigh,
              foregroundColor: AppColors.textPrimary,
              elevation: 0,
              side:  BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.pill)),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // SECTION 6: USER ACCOUNT & SITE
  // ==========================================
  Widget _buildAccountSection(
    BuildContext context,
    WidgetRef ref,
    dynamic authUser,
    dynamic activeSite,
  ) {
    return SettingsSectionCard(
      icon: Icons.account_circle_rounded,
      title: 'USER',
      subtitle: 'Active session credentials and site association',
      children: [
        // User Details
        _buildInfoRow('USER', authUser?.email ?? 'Unknown User'),
        const SizedBox(height: 8),
        _buildInfoRow('UID', authUser?.uid != null ? '${authUser!.uid.substring(0, 8)}...' : 'N/A'),
         Divider(height: 20, color: AppColors.border),

        // Site Details
        _buildInfoRow('ACTIVE SITE', activeSite != null ? '${activeSite.siteCode} • ${activeSite.name}' : 'No site selected'),
        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SiteSetupScreen()),
                  );
                },
                icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                label: const Text('SWITCH SITE', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side:  BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.pill)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _handleSignOut(context, ref),
                icon: const Icon(Icons.logout_rounded, size: 16),
                label: const Text('SIGN OUT', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.statusRed.withAlpha(25),
                  foregroundColor: AppColors.statusRed,
                  elevation: 0,
                  side:  BorderSide(color: AppColors.statusRed),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.pill)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: () {
              AccountDeletionDialog.show(
                context,
                authService: ref.read(authServiceProvider),
                appDatabase: ref.read(appDatabaseProvider),
              );
            },
            icon: const Icon(Icons.delete_forever_rounded, size: 16, color: AppColors.statusRed),
            label: const Text(
              'DELETE ACCOUNT',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 11,
                color: AppColors.statusRed,
                letterSpacing: 0.5,
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              backgroundColor: AppColors.statusRed.withAlpha(15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.pill),
                side: BorderSide(color: AppColors.statusRed.withAlpha(50)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // SECTION 7: SUPPORT & ENQUIRIES
  // ==========================================
  Widget _buildSupportSection(BuildContext context) {
    return SettingsSectionCard(
      icon: Icons.support_agent_rounded,
      title: 'SUPPORT & ENQUIRIES',
      subtitle: 'Technical assistance, feature requests, and enterprise contact',
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => UserEnquiryModal.show(context),
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('CONTACT SUPPORT & SUBMIT ENQUIRY', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary.withAlpha(30),
              foregroundColor: AppColors.primary,
              elevation: 0,
              side: const BorderSide(color: AppColors.primary),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.pill)),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // SECTION 8: LEGAL & COMPLIANCE
  // ==========================================
  Widget _buildLegalSection(BuildContext context) {
    return SettingsSectionCard(
      icon: Icons.gavel_rounded,
      title: 'LEGAL & COMPLIANCE',
      subtitle: 'Terms of service, data privacy, and evidence integrity policies',
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.description_outlined, color: AppColors.primary, size: 22),
          title: const Text(
            'Terms of Service',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
          subtitle: const Text(
            'Evidence provenance and application usage rules',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textSecondary),
          onTap: () => LegalDocModal.show(context, LegalDocType.termsOfService),
        ),
        const Divider(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.privacy_tip_outlined, color: AppColors.primary, size: 22),
          title: const Text(
            'Privacy Policy',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
          subtitle: const Text(
            'Location telemetry handling & offline storage policy',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textSecondary),
          onTap: () => LegalDocModal.show(context, LegalDocType.privacyPolicy),
        ),
      ],
    );
  }

  // ==========================================
  // HELPERS
  // ==========================================
  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style:  TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            style:  TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }

  Future<void> _handleSignOut(BuildContext context, WidgetRef ref) async {
    final confirm = await ConfirmationDialog.show(
      context,
      title: 'Sign Out',
      message: 'Are you sure you want to sign out from SiteLens?',
      confirmLabel: 'Sign Out',
    );

    if (confirm == true && context.mounted) {
      await ref.read(authServiceProvider).signOut();
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.root, (route) => false);
      }
    }
  }
}
