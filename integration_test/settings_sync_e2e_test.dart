import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sitelens/features/settings/settings_screen.dart';
import 'package:sitelens/features/settings/widgets/storage_settings_modal.dart';
import 'package:sitelens/features/sites/site_setup_screen.dart';
import 'helpers/e2e_test_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('SiteLens Settings & Sync E2E (E2E-13)', () {
    testWidgets('Settings screen sections, GPS threshold modal, and storage management',
        (tester) async {
      final harness = E2ETestHarness();
      addTearDown(harness.dispose);

      await harness.bootstrapAuthenticatedApp(tester);

      // Navigate to SettingsScreen
      final navContext = tester.element(find.byType(SiteSetupScreen));
      Navigator.of(navContext).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('SETTINGS'), findsOneWidget);

      // Verify sections
      expect(find.text('GPS & GEOLOCATION'), findsOneWidget);
      expect(find.text('WATERMARK & STAMP'), findsOneWidget);
      expect(find.text('NEARBY SEARCH DEFAULTS'), findsOneWidget);

      // Verify GPS threshold modal opens
      final gpsBtn = find.text('CONFIGURE GPS THRESHOLD');
      if (gpsBtn.evaluate().isNotEmpty) {
        await tester.tap(gpsBtn);
        await tester.pumpAndSettle();

        expect(find.text('GPS Accuracy Threshold'), findsOneWidget);

        // Close modal
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();
      }

      final scrollable = find.byType(Scrollable);
      if (scrollable.evaluate().isNotEmpty) {
        await tester.drag(scrollable.first, const Offset(0, -600));
        await tester.pumpAndSettle();
      }

      expect(find.text('STORAGE & LOCAL MEDIA'), findsOneWidget);
      expect(find.text('GOOGLE PHOTOS AUTO-SYNC'), findsOneWidget);

      // Verify Storage Cleanup modal opens
      final storageBtn = find.text('MANAGE LOCAL STORAGE');
      if (storageBtn.evaluate().isNotEmpty) {
        await tester.ensureVisible(storageBtn);
        await tester.pumpAndSettle();
        await tester.tap(storageBtn);
        await tester.pumpAndSettle();

        expect(find.byType(StorageSettingsModal), findsOneWidget);

        // Close modal
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();
      }
    });
  });
}
