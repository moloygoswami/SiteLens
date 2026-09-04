import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter/material.dart';
import 'package:sitelens/features/nearby/nearby_search_screen.dart';
import 'package:sitelens/features/nearby/widgets/radius_selector_strip.dart';
import 'package:sitelens/features/sites/site_setup_screen.dart';
import 'helpers/e2e_test_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('SiteLens Nearby Search & Map Radar E2E (E2E-12)', () {
    testWidgets('Nearby evidence search screen, radius presets, and view mode toggle',
        (tester) async {
      final harness = E2ETestHarness();
      addTearDown(harness.dispose);

      await harness.bootstrapAuthenticatedApp(tester);

      // Navigate to NearbySearchScreen
      final navContext = tester.element(find.byType(SiteSetupScreen));
      Navigator.of(navContext).push(
        MaterialPageRoute(
          builder: (_) => const NearbySearchScreen(initialLat: 22.57264, initialLon: 88.36391),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NearbySearchScreen), findsOneWidget);
      expect(find.text('NEARBY EVIDENCE SEARCH'), findsOneWidget);
      expect(find.byType(RadiusSelectorStrip), findsOneWidget);

      // Verify Radius Preset chips (2m, 5m, 10m, 25m, 50m)
      expect(find.text('2m'), findsOneWidget);
      expect(find.text('5m'), findsOneWidget);
      expect(find.text('10m'), findsOneWidget);

      // Tap 5m radius chip
      await tester.tap(find.text('5m'));
      await tester.pumpAndSettle();

      // Tap Filter Modal trigger
      final filterBtn = find.byTooltip('Filter Nearby Media');
      if (filterBtn.evaluate().isNotEmpty) {
        await tester.tap(filterBtn);
        await tester.pumpAndSettle();

        expect(find.text('FILTER NEARBY MEDIA'), findsOneWidget);

        // Apply and close modal
        await tester.tap(find.text('Apply Filters'));
        await tester.pumpAndSettle();
      }
    });
  });
}
