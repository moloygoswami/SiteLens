import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../app/theme.dart';
import '../../app/router.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/permission_service.dart';
import '../../core/services/session_service.dart';
import '../../shared/utils/responsive_layout.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/secondary_button.dart';

class PermissionRecoveryScreen extends ConsumerStatefulWidget {
  const PermissionRecoveryScreen({super.key});

  @override
  ConsumerState<PermissionRecoveryScreen> createState() =>
      _PermissionRecoveryScreenState();
}

class _PermissionRecoveryScreenState
    extends ConsumerState<PermissionRecoveryScreen>
    with WidgetsBindingObserver {
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndResume();
    }
  }

  Future<void> _checkAndResume() async {
    if (_isChecking) return;
    setState(() => _isChecking = true);
    try {
      final status =
          await ref.read(permissionServiceProvider.notifier).checkAllPermissions();
      if (mounted && status.areCorePermissionsGranted) {
        final sessionUser = ref.read(sessionServiceProvider).user ??
            ref.read(authServiceProvider).currentUser;
        if (sessionUser != null) {
          await ref.read(sessionServiceProvider.notifier).completeOnboarding(sessionUser.uid);
        }
        if (mounted) {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else {
            Navigator.of(context).pushReplacementNamed(AppRoutes.siteSetup);
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= ResponsiveBreakpoints.expandedMin;

            if (isWide) {
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left Pane: Alert Emblem, Title & Recovery Guidance
                        Expanded(
                          flex: 5,
                          child: Container(
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(AppRadii.card),
                              border: Border.all(color: AppColors.border, width: 1),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(8),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: AppColors.statusRedLight,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppColors.statusRed.withAlpha(80), width: 2),
                                  ),
                                  child: const Icon(
                                    Icons.gpp_bad_rounded,
                                    size: 34,
                                    color: AppColors.statusRed,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                const Text(
                                  'Permissions Blocked',
                                  style: AppTypography.headlineMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Camera or Location access was permanently disabled. SiteLens cannot create valid inspection evidence without these permissions.',
                                  style: AppTypography.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(width: 32),

                        // Right Pane: Recovery Steps & Actions
                        Expanded(
                          flex: 6,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(AppRadii.card),
                                  border: Border.all(color: AppColors.border, width: 1),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'HOW TO RESTORE PERMISSIONS',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.primaryDark,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    _buildStepRow(1, 'Tap "Open Device Settings" below'),
                                    _buildStepRow(2, 'Navigate to "Permissions" / "Privacy"'),
                                    _buildStepRow(3, 'Enable Camera & Precise Location ("While using app")'),
                                    _buildStepRow(4, 'Return to SiteLens to begin inspections'),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              PrimaryButton(
                                label: 'Open Device Settings',
                                icon: Icons.settings_rounded,
                                onPressed: () async {
                                  await openAppSettings();
                                },
                              ),
                              const SizedBox(height: 12),
                              SecondaryButton(
                                label: 'Re-check Permission Status',
                                isLoading: _isChecking,
                                icon: Icons.refresh_rounded,
                                onPressed: _checkAndResume,
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

            // Compact Mobile View
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: AppColors.statusRedLight,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.statusRed.withAlpha(80), width: 2),
                          ),
                          child: const Icon(
                            Icons.gpp_bad_rounded,
                            size: 38,
                            color: AppColors.statusRed,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Permissions Blocked',
                        style: AppTypography.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Camera or Location access was permanently disabled. SiteLens cannot create valid inspection evidence without these permissions.',
                        style: AppTypography.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadii.card),
                          border: Border.all(color: AppColors.border, width: 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'HOW TO RESTORE PERMISSIONS',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primaryDark,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildStepRow(1, 'Tap "Open Device Settings" below'),
                            _buildStepRow(2, 'Navigate to "Permissions" / "Privacy"'),
                            _buildStepRow(3, 'Enable Camera & Precise Location ("While using app")'),
                            _buildStepRow(4, 'Return to SiteLens to begin inspections'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      PrimaryButton(
                        label: 'Open Device Settings',
                        icon: Icons.settings_rounded,
                        onPressed: () async {
                          await openAppSettings();
                        },
                      ),
                      const SizedBox(height: 12),
                      SecondaryButton(
                        label: 'Re-check Permission Status',
                        isLoading: _isChecking,
                        icon: Icons.refresh_rounded,
                        onPressed: _checkAndResume,
                      ),
                      const SizedBox(height: 12),
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

  Widget _buildStepRow(int number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$number',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
