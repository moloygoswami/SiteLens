import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sitelens/firebase_options.dart';
import 'package:sitelens/app/app.dart';
import 'package:sitelens/data/repositories/site_repository.dart';
import 'package:sitelens/features/auth/welcome_screen.dart';
import 'package:sitelens/features/sites/site_setup_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('SiteLens On-Device E2E Smoke Test', () {
    testWidgets('Application bootstraps and renders root session view', (tester) async {
      // 1. Ensure Firebase Core is initialized on the test target
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } catch (_) {
        // Already initialized by test runner or previous binding
      }

      // 2. Establish isolated ProviderContainer and seed offline site defaults
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(siteRepositoryProvider).seedDefaultSitesIfEmpty();

      // 3. Pump root application widget
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SiteLensApp(),
        ),
      );

      // 4. Settle initial frame and routing transition
      await tester.pumpAndSettle();

      // 5. Verify valid root UI renders (WelcomeScreen for unauthenticated, SiteSetupScreen for active session)
      final hasWelcome = find.byType(WelcomeScreen).evaluate().isNotEmpty;
      final hasSiteSetup = find.byType(SiteSetupScreen).evaluate().isNotEmpty;

      expect(
        hasWelcome || hasSiteSetup,
        isTrue,
        reason: 'SiteLens must render a valid root screen (WelcomeScreen or SiteSetupScreen)',
      );

      // 6. Verify header/title element matches the active root view
      if (hasWelcome) {
        expect(find.textContaining('SiteLens'), findsWidgets);
      } else if (hasSiteSetup) {
        expect(find.text('Project & Site Context'), findsOneWidget);
      }
    });
  });
}
