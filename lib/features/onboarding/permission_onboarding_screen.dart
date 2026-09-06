import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../app/theme.dart';
import '../../app/router.dart';
import '../../core/services/permission_service.dart';
import '../../core/services/session_service.dart';
import '../../shared/utils/responsive_layout.dart';
import '../../shared/widgets/primary_button.dart';

class PermissionOnboardingScreen extends ConsumerStatefulWidget {
  const PermissionOnboardingScreen({super.key});

  @override
  ConsumerState<PermissionOnboardingScreen> createState() =>
      _PermissionOnboardingScreenState();
}

class _PermissionOnboardingScreenState
    extends ConsumerState<PermissionOnboardingScreen>
    with WidgetsBindingObserver {
  bool _isRequesting = false;

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
      // Recheck permissions on resume (PRD Section 5.6)
      ref.read(permissionServiceProvider.notifier).checkAllPermissions().then((status) {
        if (status.areCorePermissionsGranted && mounted) {
          _proceedToSiteSetup();
        }
      });
    }
  }

  Future<void> _proceedToSiteSetup() async {
    final sessionUser = ref.read(sessionServiceProvider).user;
    if (sessionUser != null) {
      await ref.read(sessionServiceProvider.notifier).completeOnboarding(sessionUser.uid);
    }
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.root, (route) => false);
    }
  }

  Future<void> _handleRequestPermissions() async {
    setState(() => _isRequesting = true);
    final service = ref.read(permissionServiceProvider.notifier);

    await service.requestAllCorePermissions();
    final status = await service.checkAllPermissions();

    if (mounted) {
      if (status.areCorePermissionsGranted) {
        setState(() => _isRequesting = false);
        await _proceedToSiteSetup();
      } else if (status.isPermanentlyDenied) {
        setState(() => _isRequesting = false);
        Navigator.of(context).pushNamed(AppRoutes.recovery);
      } else {
        setState(() => _isRequesting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(permissionServiceProvider);

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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left Pane: Overview, Guidance & Primary Actions
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
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryContainer,
                                        borderRadius: BorderRadius.circular(AppRadii.pill),
                                      ),
                                      child: const Row(
                                        children: [
                                          Icon(Icons.verified_user_rounded, size: 14, color: AppColors.primaryDark),
                                          SizedBox(width: 6),
                                          Text(
                                            'HARDWARE ONBOARDING',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.primaryDark,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Device Permissions',
                                  style: AppTypography.headlineMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'SiteLens requires camera and precise location access to capture legally verifiable inspection evidence.',
                                  style: AppTypography.bodyMedium,
                                ),
                                const SizedBox(height: 24),
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceContainer,
                                    borderRadius: BorderRadius.circular(AppRadii.md),
                                    border: Border.all(color: AppColors.border, width: 1),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.shield_outlined, color: AppColors.primary, size: 20),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Hardware sensors are only queried during active inspection sessions.',
                                          style: AppTypography.bodyMedium.copyWith(fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 32),
                                if (status.isPermanentlyDenied) ...[
                                  PrimaryButton(
                                    label: 'Resolve Blocked Permissions',
                                    isDestructive: true,
                                    onPressed: () {
                                      Navigator.of(context).pushNamed(AppRoutes.recovery);
                                    },
                                  ),
                                ] else ...[
                                  PrimaryButton(
                                    label: status.areCorePermissionsGranted ? 'Continue to Site Setup' : 'Enable Required Permissions',
                                    isLoading: _isRequesting,
                                    onPressed: status.areCorePermissionsGranted
                                        ? () => _proceedToSiteSetup()
                                        : _handleRequestPermissions,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(width: 32),

                        // Right Pane: Permissions List
                        Expanded(
                          flex: 6,
                          child: ListView(
                            shrinkWrap: true,
                            children: [
                              _buildPermissionTile(
                                icon: Icons.camera_alt_rounded,
                                title: 'Camera Access',
                                subtitle: 'Capture high-resolution photos and video inspection records.',
                                isRequired: true,
                                status: status.camera,
                                onRequest: () async {
                                  await ref.read(permissionServiceProvider.notifier).requestCameraPermission();
                                  _checkProgression();
                                },
                              ),
                              const SizedBox(height: 12),
                              _buildPermissionTile(
                                icon: Icons.my_location_rounded,
                                title: 'Precise Location / GPS',
                                subtitle: 'Embed tamper-proof latitude, longitude, and elevation into photos.',
                                isRequired: true,
                                status: status.location,
                                onRequest: () async {
                                  await ref.read(permissionServiceProvider.notifier).requestLocationPermission();
                                  _checkProgression();
                                },
                              ),
                              const SizedBox(height: 12),
                              _buildPermissionTile(
                                icon: Icons.photo_library_rounded,
                                title: 'Photos & Storage',
                                subtitle: 'Save original evidence, thumbnails, and cache sites locally.',
                                isRequired: true,
                                status: status.photos,
                                onRequest: () async {
                                  await ref.read(permissionServiceProvider.notifier).requestPhotosPermission();
                                  _checkProgression();
                                },
                              ),
                              const SizedBox(height: 12),
                              _buildPermissionTile(
                                icon: Icons.mic_rounded,
                                title: 'Microphone (Video Notes)',
                                subtitle: 'Record verbal inspector notes during site video walk-throughs.',
                                isRequired: false,
                                status: status.microphone,
                                onRequest: () async {
                                  await ref.read(permissionServiceProvider.notifier).requestMicrophonePermission();
                                  _checkProgression();
                                },
                              ),
                              const SizedBox(height: 12),
                              _buildPermissionTile(
                                icon: Icons.notifications_none_rounded,
                                title: 'Push Notifications',
                                subtitle: 'Receive background cloud sync progress and sync failure alerts.',
                                isRequired: false,
                                status: status.notifications,
                                onRequest: () async {
                                  await ref.read(permissionServiceProvider.notifier).requestNotificationPermission();
                                  _checkProgression();
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

            // Compact Mobile View
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 12),
                      // Header Badge
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primaryContainer,
                              borderRadius: BorderRadius.circular(AppRadii.pill),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.verified_user_rounded, size: 14, color: AppColors.primaryDark),
                                SizedBox(width: 6),
                                Text(
                                  'HARDWARE ONBOARDING',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Device Permissions',
                        style: AppTypography.headlineMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'SiteLens requires camera and precise location access to capture legally verifiable inspection evidence.',
                        style: AppTypography.bodyMedium,
                      ),
                      const SizedBox(height: 20),

                      // Permissions List
                      Expanded(
                        child: ListView(
                          children: [
                            _buildPermissionTile(
                              icon: Icons.camera_alt_rounded,
                              title: 'Camera Access',
                              subtitle: 'Capture high-resolution photos and video inspection records.',
                              isRequired: true,
                              status: status.camera,
                              onRequest: () async {
                                await ref.read(permissionServiceProvider.notifier).requestCameraPermission();
                                _checkProgression();
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildPermissionTile(
                              icon: Icons.my_location_rounded,
                              title: 'Precise Location / GPS',
                              subtitle: 'Embed tamper-proof latitude, longitude, and elevation into photos.',
                              isRequired: true,
                              status: status.location,
                              onRequest: () async {
                                await ref.read(permissionServiceProvider.notifier).requestLocationPermission();
                                _checkProgression();
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildPermissionTile(
                              icon: Icons.photo_library_rounded,
                              title: 'Photos & Storage',
                              subtitle: 'Save original evidence, thumbnails, and cache sites locally.',
                              isRequired: true,
                              status: status.photos,
                              onRequest: () async {
                                await ref.read(permissionServiceProvider.notifier).requestPhotosPermission();
                                _checkProgression();
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildPermissionTile(
                              icon: Icons.mic_rounded,
                              title: 'Microphone (Video Notes)',
                              subtitle: 'Record verbal inspector notes during site video walk-throughs.',
                              isRequired: false,
                              status: status.microphone,
                              onRequest: () async {
                                await ref.read(permissionServiceProvider.notifier).requestMicrophonePermission();
                                _checkProgression();
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildPermissionTile(
                              icon: Icons.notifications_none_rounded,
                              title: 'Push Notifications',
                              subtitle: 'Receive background cloud sync progress and sync failure alerts.',
                              isRequired: false,
                              status: status.notifications,
                              onRequest: () async {
                                await ref.read(permissionServiceProvider.notifier).requestNotificationPermission();
                                _checkProgression();
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),
                      // Action Buttons
                      if (status.isPermanentlyDenied) ...[
                        PrimaryButton(
                          label: 'Resolve Blocked Permissions',
                          isDestructive: true,
                          onPressed: () {
                            Navigator.of(context).pushNamed(AppRoutes.recovery);
                          },
                        ),
                      ] else ...[
                        PrimaryButton(
                          label: status.areCorePermissionsGranted ? 'Continue to Site Setup' : 'Enable Required Permissions',
                          isLoading: _isRequesting,
                          onPressed: status.areCorePermissionsGranted
                              ? () => _proceedToSiteSetup()
                              : _handleRequestPermissions,
                        ),
                      ],
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

  void _checkProgression() {
    final status = ref.read(permissionServiceProvider);
    if (status.areCorePermissionsGranted && mounted) {
      _proceedToSiteSetup();
    } else if (status.isPermanentlyDenied && mounted) {
      Navigator.of(context).pushNamed(AppRoutes.recovery);
    }
  }

  Widget _buildPermissionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isRequired,
    required PermissionStatus status,
    required VoidCallback onRequest,
  }) {
    final isGranted = status.isGranted;
    final isDenied = status.isPermanentlyDenied;

    Color badgeBg;
    Color badgeFg;
    String badgeText;

    if (isGranted) {
      badgeBg = AppColors.statusGreenLight;
      badgeFg = AppColors.statusGreen;
      badgeText = 'Granted';
    } else if (isDenied) {
      badgeBg = AppColors.statusRedLight;
      badgeFg = AppColors.statusRed;
      badgeText = 'Denied';
    } else {
      badgeBg = isRequired ? AppColors.primaryContainer : AppColors.surfaceContainerHigh;
      badgeFg = isRequired ? AppColors.primaryDark : AppColors.textSecondary;
      badgeText = isRequired ? 'Required' : 'Optional';
    }

    return InkWell(
      onTap: isGranted ? null : onRequest,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(
            color: isGranted ? AppColors.statusGreen.withAlpha(80) : AppColors.border,
            width: isGranted ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isGranted ? AppColors.statusGreenLight : AppColors.primaryContainer.withAlpha(80),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isGranted ? Icons.check_circle_rounded : icon,
                size: 22,
                color: isGranted ? AppColors.statusGreen : AppColors.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: badgeFg,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AppTypography.bodyMedium.copyWith(fontSize: 12),
                  ),
                  if (!isGranted) ...[
                    const SizedBox(height: 8),
                    Text(
                      isDenied ? 'Permission blocked — tap to resolve →' : 'Tap to grant permission →',
                      style: TextStyle(
                        color: isDenied ? AppColors.statusRed : AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
