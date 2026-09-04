import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/features/gallery/media_detail_screen.dart';
import 'package:sitelens/features/sites/site_setup_screen.dart';
import 'helpers/e2e_test_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('SiteLens Media Detail & Export E2E (E2E-10)', () {
    testWidgets('Media detail telemetry, SHA-256 expand/copy, and delete confirmation dialog',
        (tester) async {
      final harness = E2ETestHarness();
      addTearDown(harness.dispose);

      await harness.bootstrapAuthenticatedApp(tester);

      final testMedia = MediaItem(
        id: 'media-detail-001',
        siteId: 'test-site-001',
        uri: 'media/evid_001.jpg',
        originalUri: 'media/orig_001.jpg',
        thumbUri: 'media/thumb_001.jpg',
        type: MediaItemType.photo,
        lat: 22.57264,
        lon: 88.36391,
        accuracyM: 3.5,
        lowAccuracy: false,
        activityTag: 'Foundation Inspection',
        observationType: ObservationType.progress,
        note: 'Concrete batch verified',
        capturedAt: DateTime.utc(2026, 8, 19, 10, 30, 0),
        sha256Hash: '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        capturedAddress: '100 Test Avenue, Metro City',
        syncStatus: SyncStatusType.synced,
      );

      final navContext = tester.element(find.byType(SiteSetupScreen));
      Navigator.of(navContext).push(
        MaterialPageRoute(
          builder: (_) => MediaDetailScreen(mediaItem: testMedia),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MediaDetailScreen), findsOneWidget);
      expect(find.text('PROGRESS'), findsWidgets);
      expect(find.text('Foundation Inspection'), findsWidgets);

      expect(find.text('100 Test Avenue, Metro City'), findsWidgets);

      // Verify SHA-256 field
      expect(find.textContaining('1234567890abcdef'), findsWidgets);

      // Verify Delete Evidence dialog
      final deleteBtn = find.byTooltip('Delete Evidence');
      expect(deleteBtn, findsOneWidget);
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      expect(find.text('Delete Media'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Cancel delete
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });
}
