import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../app/router.dart';
import '../../shared/utils/responsive_layout.dart';
import '../../shared/widgets/app_drawer_icon.dart';
import '../../shared/widgets/primary_button.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= ResponsiveBreakpoints.expandedMin;

            if (isWide) {
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Left Pane: Brand & Hero Showcase
                        Expanded(
                          flex: 5,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(AppRadii.card),
                              border: Border.all(color: AppColors.border, width: 1),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const AppDrawerIcon(
                                  size: 112,
                                  tooltip: 'SiteLens Inspection Camera',
                                ),
                                const SizedBox(height: 24),
                                const Text(
                                  'SiteLens',
                                  style: AppTypography.displayLarge,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'GPS-Verified Construction Evidence',
                                  style: AppTypography.bodyLarge.copyWith(
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 24),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceContainer,
                                    borderRadius: BorderRadius.circular(AppRadii.sm),
                                    border: Border.all(color: AppColors.border, width: 1),
                                  ),
                                  child: Text(
                                    'Trusted by Quality & Site Supervision Teams',
                                    style: AppTypography.labelSmall.copyWith(
                                      color: AppColors.textMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(width: 32),

                        // Right Pane: Value Propositions & Action CTA
                        Expanded(
                          flex: 6,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildFeatureItem(
                                icon: Icons.pin_drop_rounded,
                                title: 'Burned-in Geotagging',
                                subtitle: 'Imprints coordinates, timestamp, and Site ID directly into photo pixels.',
                              ),
                              const SizedBox(height: 12),
                              _buildFeatureItem(
                                icon: Icons.compare_arrows_rounded,
                                title: 'Before/After Smart-Link',
                                subtitle: 'Find and pair historical inspection points within 10 meters.',
                              ),
                              const SizedBox(height: 12),
                              _buildFeatureItem(
                                icon: Icons.cloud_off_rounded,
                                title: '100% Offline-First',
                                subtitle: 'Capture evidence reliably in deep basements or remote zero-network sites.',
                              ),
                              const SizedBox(height: 28),
                              PrimaryButton(
                                label: 'Get Started',
                                onPressed: () {
                                  Navigator.of(context).pushNamed(AppRoutes.login);
                                },
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
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 12),
                      const Center(
                        child: AppDrawerIcon(
                          size: 88,
                          tooltip: 'SiteLens Inspection Camera',
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'SiteLens',
                        style: AppTypography.displayLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'GPS-Verified Construction Evidence',
                        style: AppTypography.bodyLarge.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      _buildFeatureItem(
                        icon: Icons.pin_drop_rounded,
                        title: 'Burned-in Geotagging',
                        subtitle: 'Imprints coordinates, timestamp, and Site ID directly into photo pixels.',
                      ),
                      const SizedBox(height: 10),
                      _buildFeatureItem(
                        icon: Icons.compare_arrows_rounded,
                        title: 'Before/After Smart-Link',
                        subtitle: 'Find and pair historical inspection points within 10 meters.',
                      ),
                      const SizedBox(height: 10),
                      _buildFeatureItem(
                        icon: Icons.cloud_off_rounded,
                        title: '100% Offline-First',
                        subtitle: 'Capture evidence reliably in deep basements or remote zero-network sites.',
                      ),
                      const SizedBox(height: 28),
                      PrimaryButton(
                        label: 'Get Started',
                        onPressed: () {
                          Navigator.of(context).pushNamed(AppRoutes.login);
                        },
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          'Trusted by Quality & Site Supervision Teams',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ),
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

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer.withAlpha(100),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTypography.bodyMedium.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
