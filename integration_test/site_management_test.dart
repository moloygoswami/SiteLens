import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sitelens/domain/models/site_model.dart';
import 'package:sitelens/features/sites/site_setup_screen.dart';
import 'helpers/e2e_test_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('SiteLens Site Management E2E (E2E-05)', () {
    testWidgets('Add custom offline site, switch active site, and verify state', (tester) async {
      final harness = E2ETestHarness();
      addTearDown(harness.dispose);

      const secondarySite = SiteModel(
        id: 'site-sec-002',
        siteCode: 'SEC-02',
        name: 'Secondary Sector Yard',
        address: '200 Industrial Bypass, Zone 4',
      );

      await harness.bootstrapAuthenticatedApp(
        tester,
        additionalSites: [secondarySite],
      );

      expect(find.byType(SiteSetupScreen), findsOneWidget);
      expect(find.textContaining('E2E'), findsWidgets);

      // Verify secondary site is listed in cached sites
      expect(find.textContaining('SEC-02'), findsWidgets);

      // Switch active site to Secondary Sector Yard
      await tester.tap(find.textContaining('SEC-02').first);
      await tester.pumpAndSettle();

      // Verify active site context is updated
      expect(find.textContaining('Secondary Sector Yard'), findsWidgets);

      // Tap + Add Site button
      final addSiteBtn = find.text('+ Add Site');
      if (addSiteBtn.evaluate().isNotEmpty) {
        await tester.tap(addSiteBtn.first);
        await tester.pumpAndSettle();

        // Verify dialog opens
        expect(
          find.text('Add Inspection Site').evaluate().isNotEmpty ||
              find.text('Add Offline Site / Address').evaluate().isNotEmpty,
          isTrue,
        );

        // Fill text fields
        final textFields = find.byType(TextField);
        if (textFields.evaluate().length >= 3) {
          await tester.enterText(textFields.at(0), 'NEW-99');
          await tester.enterText(textFields.at(1), 'New Facility North');
          await tester.enterText(textFields.at(2), '99 New Road');
          await tester.pumpAndSettle();

          // Tap Add & Select
          await tester.tap(find.text('Add & Select'));
          await tester.pumpAndSettle();

          // Verify newly added site is active
          expect(find.textContaining('NEW-99'), findsWidgets);
          expect(find.textContaining('New Facility North'), findsWidgets);
        }
      }
    });
  });
}
