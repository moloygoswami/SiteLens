import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sitelens/features/camera/camera_screen.dart';
import 'package:sitelens/features/settings/settings_screen.dart';
import 'package:sitelens/features/sites/site_setup_screen.dart';
import 'helpers/e2e_test_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('SiteLens Settings Navigation Smoke E2E', () {
    testWidgets('SiteSetupScreen -> CameraScreen -> SettingsScreen -> Back -> CameraScreen -> Back -> SiteSetupScreen',
        (tester) async {
      final harness = E2ETestHarness();
      addTearDown(harness.dispose);

      // 1. Initial State: Authenticated bootstrap on SiteSetupScreen
      await harness.bootstrapAuthenticatedApp(tester);

      expect(find.byType(SiteSetupScreen), findsOneWidget);
      expect(find.byType(CameraScreen), findsNothing);
      expect(find.byType(SettingsScreen), findsNothing);

      // 2. Open Camera to reach HUD
      await tester.tap(find.text('Confirm Site & Open Camera'));
      await tester.pumpAndSettle();

      expect(find.byType(CameraScreen), findsOneWidget);

      // 3. Settings Navigation: Tap Settings icon in CameraTopHud
      final settingsBtn = find.byTooltip('Settings & Sync');
      expect(settingsBtn, findsOneWidget);

      await tester.tap(settingsBtn, warnIfMissed: false);
      await tester.pumpAndSettle();

      // Verify SettingsScreen is active
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('SETTINGS'), findsOneWidget);

      // 4. Back from SettingsScreen: Tap leading back button
      final settingsBackBtn = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(IconButton),
      );
      expect(settingsBackBtn, findsOneWidget);

      await tester.tap(settingsBackBtn);
      await tester.pumpAndSettle();

      // Verify returned to CameraScreen
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.byType(CameraScreen), findsOneWidget);

      // 5. Back from CameraScreen: Tap back to SiteSetupScreen
      final cameraBackBtn = find.byTooltip('Back to Site Setup');
      await tester.tap(cameraBackBtn);
      await tester.pumpAndSettle();

      // Verify returned to SiteSetupScreen with active site intact
      expect(find.byType(CameraScreen), findsNothing);
      expect(find.byType(SiteSetupScreen), findsOneWidget);
      expect(find.textContaining('E2E'), findsWidgets);
      expect(find.textContaining('E2E Test Inspection Site'), findsWidgets);
    });

    testWidgets('Rapid tap check on Settings action does not duplicate route stack',
        (tester) async {
      final harness = E2ETestHarness();
      addTearDown(harness.dispose);

      await harness.bootstrapAuthenticatedApp(tester);

      // Navigate to Camera
      await tester.tap(find.text('Confirm Site & Open Camera'));
      await tester.pumpAndSettle();

      final settingsBtn = find.byTooltip('Settings & Sync');
      expect(settingsBtn, findsOneWidget);

      // Rapid tap twice
      await tester.tap(settingsBtn, warnIfMissed: false);
      await tester.tap(settingsBtn, warnIfMissed: false);
      await tester.pumpAndSettle();

      // Verify SettingsScreen is rendered
      expect(find.byType(SettingsScreen), findsOneWidget);

      // Tap back once
      final settingsBackBtn = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(IconButton),
      );
      await tester.tap(settingsBackBtn);
      await tester.pumpAndSettle();

      // Verify returning directly to CameraScreen (single back pop, no orphaned duplicate)
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.byType(CameraScreen), findsOneWidget);
    });
  });
}
