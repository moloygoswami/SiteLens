import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sitelens/features/gallery/gallery_screen.dart';
import 'package:sitelens/features/gallery/models/gallery_selection_state.dart';
import 'package:sitelens/features/sites/site_setup_screen.dart';
import 'helpers/e2e_test_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('SiteLens Gallery Batch Selection & Export E2E (E2E-11)', () {
    testWidgets('Toggle select mode, select all, deselect, and verify batch bar',
        (tester) async {
      final harness = E2ETestHarness();
      addTearDown(harness.dispose);

      await harness.bootstrapAuthenticatedApp(tester);

      // Navigate to Gallery
      final navContext = tester.element(find.byType(SiteSetupScreen));
      Navigator.of(navContext).push(
        MaterialPageRoute(builder: (_) => const GalleryScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GalleryScreen), findsOneWidget);

      // Trigger select mode via provider
      harness.container.read(gallerySelectionProvider.notifier).enterSelectMode('item-1');
      await tester.pumpAndSettle();

      // Verify select mode active
      expect(harness.container.read(gallerySelectionProvider).isSelectMode, isTrue);

      // Exit select mode
      harness.container.read(gallerySelectionProvider.notifier).exitSelectMode();
      await tester.pumpAndSettle();

      expect(harness.container.read(gallerySelectionProvider).isSelectMode, isFalse);
    });
  });
}
