import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../core/services/session_service.dart';
import 'welcome_screen.dart';
import '../onboarding/permission_onboarding_screen.dart';
import '../sites/site_setup_screen.dart';

class SessionRouter extends ConsumerWidget {
  const SessionRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(sessionServiceProvider);

    switch (sessionState.status) {
      case SessionStatus.loading:
        return const Scaffold(
          backgroundColor: AppColors.background,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.camera_enhance_rounded,
                  size: 56,
                  color: AppColors.primary,
                ),
                SizedBox(height: 16),
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ],
            ),
          ),
        );

      case SessionStatus.unauthenticated:
        return const WelcomeScreen();

      case SessionStatus.onboardingRequired:
        return const PermissionOnboardingScreen();

      case SessionStatus.authenticatedReady:
        return const SiteSetupScreen();
    }
  }
}
