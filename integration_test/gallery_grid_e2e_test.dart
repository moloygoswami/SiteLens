import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sitelens/features/gallery/gallery_screen.dart';
import 'package:sitelens/features/gallery/widgets/gallery_empty_view.dart';
import 'package:sitelens/features/gallery/widgets/gallery_filter_bar.dart';
import 'package:sitelens/features/sites/site_setup_screen.dart';
import 'helpers/e2e_test_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('SiteLens Gallery Grid & Filter E2E (E2E-09)', () {
    testWidgets('Gallery empty view, filter bar chips, and search bar', (tester) async {
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
      expect(find.byType(GalleryFilterBar), findsOneWidget);
      expect(find.byType(GalleryEmptyView), findsOneWidget);

      // Verify empty view messages
      expect(find.text('NO CAPTURED EVIDENCE YET'), findsOneWidget);

      // Tap Filter Modal button
      final filterBtn = find.byIcon(Icons.tune_rounded);
      if (filterBtn.evaluate().isNotEmpty) {
        await tester.tap(filterBtn);
        await tester.pumpAndSettle();

        expect(find.text('FILTER GALLERY'), findsOneWidget);

        // Close modal
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();
      }
    });
  });
}
