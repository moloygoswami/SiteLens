import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sitelens/features/auth/welcome_screen.dart';
import 'package:sitelens/features/sites/site_setup_screen.dart';
import 'helpers/e2e_test_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('SiteLens Deterministic State & Authentication E2E', () {
    testWidgets(
        'Deterministic Authenticated Bootstrap reaches SiteSetupScreen with active test site',
        (tester) async {
      final harness = E2ETestHarness();
      addTearDown(harness.dispose);

      // Bootstrap into known authenticated state with test site
      await harness.bootstrapAuthenticatedApp(tester);

      // Verify root screen is deterministically SiteSetupScreen
      expect(find.byType(SiteSetupScreen), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);

      // Verify active site and context header
      expect(find.text('Project & Site Context'), findsOneWidget);
      expect(find.textContaining('E2E'), findsWidgets);
      expect(find.textContaining('E2E Test Inspection Site'), findsWidgets);
      expect(find.text('100 Test Avenue, Metro City'), findsOneWidget);

      // Verify primary action button is available
      expect(find.text('Confirm Site & Open Camera'), findsOneWidget);
    });

    testWidgets(
        'Deterministic Unauthenticated Bootstrap reaches WelcomeScreen',
        (tester) async {
      final harness = E2ETestHarness();
      addTearDown(harness.dispose);

      // Bootstrap into known unauthenticated state
      await harness.bootstrapUnauthenticatedApp(tester);

      // Verify root screen is deterministically WelcomeScreen
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(SiteSetupScreen), findsNothing);

      // Verify branding and welcome actions
      expect(find.textContaining('SiteLens'), findsWidgets);
      expect(find.text('Get Started'), findsOneWidget);
    });
  });
}
