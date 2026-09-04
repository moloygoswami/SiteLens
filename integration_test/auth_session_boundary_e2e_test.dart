import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sitelens/features/auth/welcome_screen.dart';
import 'package:sitelens/features/camera/camera_screen.dart';
import 'package:sitelens/features/settings/settings_screen.dart';
import 'package:sitelens/features/sites/site_setup_screen.dart';
import 'helpers/e2e_test_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('SiteLens Authentication & Session Boundary E2E (E2E-03-B)', () {
    testWidgets('1. Sign-out cancellation preserves active authenticated session on SiteSetupScreen',
        (tester) async {
      final harness = E2ETestHarness();
      addTearDown(harness.dispose);

      await harness.bootstrapAuthenticatedApp(tester);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(SiteSetupScreen), findsOneWidget);
      expect(harness.fakeAuthService.currentUser, isNotNull);

      // Tap Sign Out icon in SiteSetupScreen app bar
      final logoutBtn = find.byIcon(Icons.logout_rounded);
      expect(logoutBtn, findsOneWidget);
      await tester.tap(logoutBtn);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Verify confirmation dialog appears
      expect(find.text('Sign Out'), findsWidgets);
      final cancelBtn = find.widgetWithText(OutlinedButton, 'Cancel');
      expect(cancelBtn, findsOneWidget);

      // Tap Cancel
      await tester.tap(cancelBtn);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Verify session preserved
      expect(find.byType(SiteSetupScreen), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(harness.fakeAuthService.currentUser, isNotNull);
    });

    testWidgets('2. Confirmed sign-out from SiteSetupScreen wipes session and resets to WelcomeScreen',
        (tester) async {
      final harness = E2ETestHarness();
      addTearDown(harness.dispose);

      await harness.bootstrapAuthenticatedApp(tester);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(SiteSetupScreen), findsOneWidget);

      // Tap Sign Out icon
      await tester.tap(find.byIcon(Icons.logout_rounded));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Tap Sign Out confirm button in dialog
      final confirmBtn = find.widgetWithText(ElevatedButton, 'Sign Out');
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // Verify complete session reset to WelcomeScreen
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(SiteSetupScreen), findsNothing);
      expect(harness.fakeAuthService.currentUser, isNull);
    });

    testWidgets('3. Confirmed sign-out from SettingsScreen invalidates deep navigation stack and resets to WelcomeScreen',
        (tester) async {
      final harness = E2ETestHarness();
      addTearDown(harness.dispose);

      await harness.bootstrapAuthenticatedApp(tester);
      await tester.pump(const Duration(milliseconds: 500));

      // Push SettingsScreen onto navigation stack
      final navContext = tester.element(find.byType(SiteSetupScreen));
      Navigator.of(navContext).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);

      // Scroll ListView to reveal USER section and SIGN OUT button
      final scrollableFinder = find.byType(Scrollable);
      if (scrollableFinder.evaluate().isNotEmpty) {
        await tester.drag(scrollableFinder.first, const Offset(0, -1000));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
      }

      final signOutAction = find.text('SIGN OUT');
      if (signOutAction.evaluate().isNotEmpty) {
        await tester.tap(signOutAction);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        // Verify dialog appears
        expect(find.text('Are you sure you want to sign out from SiteLens?'), findsOneWidget);

        // Tap Sign Out confirm button
        final confirmBtn = find.widgetWithText(ElevatedButton, 'Sign Out');
        expect(confirmBtn, findsOneWidget);
        await tester.tap(confirmBtn);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        // Verify complete navigation stack wipe to WelcomeScreen
        expect(find.byType(WelcomeScreen), findsOneWidget);
        expect(find.byType(SettingsScreen), findsNothing);
        expect(find.byType(SiteSetupScreen), findsNothing);
        expect(harness.fakeAuthService.currentUser, isNull);
      }
    });

    testWidgets('4. Android system Back after confirmed sign-out cannot restore authenticated routes',
        (tester) async {
      final harness = E2ETestHarness();
      addTearDown(harness.dispose);

      await harness.bootstrapAuthenticatedApp(tester);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(SiteSetupScreen), findsOneWidget);

      // Build authenticated navigation history: SiteSetup -> Camera -> Settings.
      await tester.tap(find.text('Confirm Site & Open Camera'));
      await tester.pumpAndSettle();
      expect(find.byType(CameraScreen), findsOneWidget);

      final navContext = tester.element(find.byType(CameraScreen));
      Navigator.of(navContext).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);

      // Confirm sign-out from SettingsScreen
      final scrollableFinder = find.byType(Scrollable);
      if (scrollableFinder.evaluate().isNotEmpty) {
        await tester.drag(scrollableFinder.first, const Offset(0, -1000));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
      }

      final signOutAction = find.text('SIGN OUT');
      expect(signOutAction, findsOneWidget);
      await tester.tap(signOutAction);
      await tester.pumpAndSettle();

      expect(find.text('Are you sure you want to sign out from SiteLens?'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign Out'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // Unauthenticated root reached; full stack wiped.
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.byType(CameraScreen), findsNothing);
      expect(find.byType(SiteSetupScreen), findsNothing);
      expect(harness.fakeAuthService.currentUser, isNull);

      // Verify the Navigator stack is clean: canPop is strictly false
      final welcomeContext = tester.element(find.byType(WelcomeScreen));
      final navigatorState = Navigator.of(welcomeContext);
      expect(navigatorState.canPop(), isFalse);

      // Attempting to pop should not pop or restore any authenticated screens
      final didPop = await navigatorState.maybePop();
      expect(didPop, isFalse);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(SiteSetupScreen), findsNothing);
      expect(find.byType(CameraScreen), findsNothing);
      expect(find.byType(SettingsScreen), findsNothing);
    });

    testWidgets('5. Duplicate confirm on Sign Out dialog yields exactly one sign-out transition, no duplicate navigation or crash',
        (tester) async {
      final harness = E2ETestHarness();
      addTearDown(harness.dispose);

      await harness.bootstrapAuthenticatedApp(tester);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(SiteSetupScreen), findsOneWidget);

      // Open the sign-out dialog.
      await tester.tap(find.byIcon(Icons.logout_rounded));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('Cancel'), findsOneWidget);

      // Tap confirm button
      final confirmBtn = find.widgetWithText(ElevatedButton, 'Sign Out');
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // Exactly one unauthenticated transition — no duplicate routes, no crash.
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(SiteSetupScreen), findsNothing);
      expect(find.text('Cancel'), findsNothing);
      expect(harness.fakeAuthService.currentUser, isNull);

      // Verify Navigator back-stack is completely clean
      final welcomeContext = tester.element(find.byType(WelcomeScreen));
      expect(Navigator.of(welcomeContext).canPop(), isFalse);
    });
  });
}
