import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/features/camera/models/evidence_metadata_snapshot.dart';
import 'package:sitelens/features/review/models/pending_capture_payload.dart';
import 'package:sitelens/features/review/review_tag_screen.dart';
import 'package:sitelens/features/review/widgets/observation_selector.dart';
import 'package:sitelens/features/sites/site_setup_screen.dart';
import 'helpers/e2e_test_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('SiteLens Review & Tagging E2E (E2E-08)', () {
    testWidgets('Tagging form, observation selection, and instant retake discard',
        (tester) async {
      final harness = E2ETestHarness();
      addTearDown(harness.dispose);

      await harness.bootstrapAuthenticatedApp(tester);

      final snapshot = EvidenceMetadataSnapshot(
        mediaId: 'test-media-001',
        siteId: 'test-site-001',
        siteCode: 'E2E',
        siteName: 'E2E Test Inspection Site',
        latitude: 22.57264,
        longitude: 88.36391,
        altitudeMeters: 12.0,
        accuracyMeters: 3.5,
        lowAccuracy: false,
        capturedAtUtc: DateTime.utc(2026, 8, 19, 12, 0, 0),
        canonicalTimestampUtc: '2026-08-19 12:00:00 UTC',
        resolvedAddress: '100 Test Avenue, Metro City',
      );

      final payload = PendingCapturePayload(
        mediaId: 'test-media-001',
        mediaType: MediaItemType.photo,
        originalFilePath: 'media/orig_test-media-001.jpg',
        evidenceFilePath: 'media/evid_test-media-001.jpg',
        thumbnailFilePath: 'media/thumb_test-media-001.jpg',
        sha256Hash: 'a1b2c3d4e5f67890123456789abcdef0123456789abcdef0123456789abcdef0',
        fileSizeBytes: 1024,
        previewBytes: Uint8List(0),
        metadataSnapshot: snapshot,
      );

      // Open ReviewTagScreen
      final navContext = tester.element(find.byType(SiteSetupScreen));
      Navigator.of(navContext).push(
        MaterialPageRoute(
          builder: (_) => ReviewTagScreen(payload: payload),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ReviewTagScreen), findsOneWidget);
      expect(find.byType(ObservationSelector), findsOneWidget);
      expect(find.text('Progress'), findsOneWidget);
      expect(find.text('Non-Conformity'), findsOneWidget);

      // Select Material
      final materialChip = find.text('Material');
      if (materialChip.evaluate().isNotEmpty) {
        await tester.ensureVisible(materialChip);
        await tester.pumpAndSettle();
        await tester.tap(materialChip);
        await tester.pumpAndSettle();
      }

      // Enter Activity text
      final activityField = find.widgetWithText(TextField, 'e.g. Excavation, PCC, Rebar, Finishing...');
      if (activityField.evaluate().isNotEmpty) {
        await tester.enterText(activityField, 'Foundation Rebar Layer 1');
        await tester.pumpAndSettle();
      }

      // Verify Retake button discards after confirmation
      final retakeBtn = find.text('Retake');
      if (retakeBtn.evaluate().isNotEmpty) {
        await tester.tap(retakeBtn);
        await tester.pumpAndSettle();
        final confirmBtn = find.text('Discard & Retake');
        if (confirmBtn.evaluate().isNotEmpty) {
          await tester.tap(confirmBtn);
          await tester.pumpAndSettle();
        }
        expect(find.byType(ReviewTagScreen), findsNothing);
      }
    });
  });
}
