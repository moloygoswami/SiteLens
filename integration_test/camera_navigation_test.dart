import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sitelens/features/camera/camera_screen.dart';
import 'package:sitelens/features/sites/site_setup_screen.dart';
import 'helpers/e2e_test_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('SiteLens Camera Navigation Smoke E2E', () {
    testWidgets('SiteSetupScreen -> Confirm Site & Open Camera -> CameraScreen -> Back -> SiteSetupScreen',
        (tester) async {
      final harness = E2ETestHarness();
      addTearDown(harness.dispose);

      // 1. Initial State: Authenticated bootstrap on SiteSetupScreen
      await harness.bootstrapAuthenticatedApp(tester);

      expect(find.byType(SiteSetupScreen), findsOneWidget);
      expect(find.byType(CameraScreen), findsNothing);
      expect(find.textContaining('E2E'), findsWidgets);
      expect(find.text('Confirm Site & Open Camera'), findsOneWidget);

      // 2. Camera Navigation: Tap Confirm Site & Open Camera
      final openCameraBtn = find.text('Confirm Site & Open Camera');
      await tester.tap(openCameraBtn);
      await tester.pumpAndSettle();

      // Verify CameraScreen is reached
      expect(find.byType(CameraScreen), findsOneWidget);
      expect(find.textContaining('E2E'), findsWidgets);

      // 3. Back Navigation: Tap back button in CameraTopHud
      final backButton = find.byTooltip('Back to Site Setup');
      expect(backButton, findsOneWidget);

      await tester.tap(backButton);
      await tester.pumpAndSettle();

      // 4. Return State: CameraScreen popped, SiteSetupScreen restored
      expect(find.byType(CameraScreen), findsNothing);
      expect(find.byType(SiteSetupScreen), findsOneWidget);

      // 5. Active Site Preservation: Context remains intact
      expect(find.text('Project & Site Context'), findsOneWidget);
      expect(find.textContaining('E2E'), findsWidgets);
      expect(find.textContaining('E2E Test Inspection Site'), findsWidgets);
    });
  });
}
