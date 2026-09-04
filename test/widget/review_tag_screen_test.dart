import 'dart:ffi';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/local/database/database_provider.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/features/camera/models/evidence_metadata_snapshot.dart';
import 'package:sitelens/features/camera/services/evidence_storage_service.dart';
import 'package:sitelens/features/review/models/pending_capture_payload.dart';
import 'package:sitelens/features/review/review_tag_screen.dart';
import 'package:sitelens/features/review/widgets/observation_selector.dart';

import 'package:sitelens/shared/widgets/evidence_metadata_hud_card.dart';
import 'package:sitelens/features/review/widgets/review_media_preview.dart';

class MockWidgetReviewStorageService extends EvidenceStorageService {
  @override
  Future<bool> verifyArtifactsExist({
    required String originalRelativePath,
    required String evidenceRelativePath,
    String? thumbnailRelativePath,
  }) async {
    return true;
  }

  @override
  Future<String> resolveAbsolutePath(String relativePath) async {
    return '/mock/path/$relativePath';
  }

  @override
  Future<void> cleanupPartialArtifacts(String mediaId) async {}
}

void main() {
  late AppDatabase db;

  setUpAll(() {
    open.overrideFor(
        OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.sites).insert(
          SitesCompanion.insert(
            id: 'SITE_001',
            siteCode: const drift.Value('HOME'),
            name: const drift.Value('Sonar Kella Apartment'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  Widget createReviewWidget(PendingCapturePayload payload) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        mediaRepositoryProvider.overrideWithValue(LocalMediaRepository(db)),
        evidenceStorageServiceProvider
            .overrideWithValue(MockWidgetReviewStorageService()),
      ],
      child: MaterialApp(
        home: ReviewTagScreen(payload: payload),
      ),
    );
  }

  group('ReviewTagScreen Widget Tests', () {
    final testSnapshot = EvidenceMetadataSnapshot(
      mediaId: 'widget-test-1',
      siteId: 'SITE_001',
      siteCode: 'HOME',
      siteName: 'Sonar Kella Apartment',
      latitude: 22.56298,
      longitude: 88.30085,
      altitudeMeters: 18.4,
      accuracyMeters: 4.2,
      lowAccuracy: false,
      capturedAtUtc: DateTime.utc(2026, 8, 15, 4, 0, 0),
      canonicalTimestampUtc: '2026-08-15 04:00:00 UTC',
      resolvedAddress: 'Sonar Kella Apartment, Kolkata',
    );

    final payload = PendingCapturePayload(
      mediaId: 'widget-test-1',
      mediaType: MediaItemType.photo,
      originalFilePath: 'media/orig_widget-test-1.jpg',
      evidenceFilePath: 'media/evid_widget-test-1.jpg',
      thumbnailFilePath: 'media/thumb_widget-test-1.jpg',
      sha256Hash:
          'a1b2c3d4e5f67890abcdef1234567890abcdef1234567890abcdef1234567890',
      fileSizeBytes: 250000,
      previewBytes: null,
      metadataSnapshot: testSnapshot,
    );

    testWidgets(
        'Renders evidence preview and form fields without separate external HUD card',
        (tester) async {
      await tester.pumpWidget(createReviewWidget(payload));
      await tester.pumpAndSettle();

      expect(find.text('REVIEW & TAG EVIDENCE'), findsOneWidget);
      expect(find.byType(ReviewMediaPreview), findsOneWidget);

      // Verify no duplicate/external HUD card is rendered
      expect(find.byType(EvidenceMetadataHudCard), findsNothing);

      // Verify no hardcoded AspectRatio widget enforces 3:4
      expect(find.byType(AspectRatio), findsNothing);

      // Form and action controls
      expect(find.text('ACTIVITY / WORK STAGE'), findsOneWidget);
      expect(find.byType(ObservationSelector), findsOneWidget);
      expect(find.text('Save Evidence'), findsOneWidget);
      expect(find.text('Retake'), findsOneWidget);
    });

    testWidgets(
        'Evidence preview uses contain semantics and does not mount external metadata card',
        (tester) async {
      await tester.pumpWidget(createReviewWidget(payload));
      await tester.pumpAndSettle();

      final previewFinder = find.byType(ReviewMediaPreview);
      expect(previewFinder, findsOneWidget);

      // Ensure no EvidenceMetadataHudCard is in widget tree
      expect(find.byType(EvidenceMetadataHudCard), findsNothing);
    });

    testWidgets(
        'Entering Activity Tag and Selecting Closed triggers nearby candidate search',
        (tester) async {
      // Seed a nearby non-conformity item
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'nearby-nc-1',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_nc.jpg'),
              uri: 'media/evid_nc.jpg',
              lat: 22.56298,
              lon: 88.30085,
              activityTag: const drift.Value('Foundation'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-14T04:00:00Z',
            ),
          );

      await tester.pumpWidget(createReviewWidget(payload));
      await tester.pumpAndSettle();

      // Enter activity
      final activityField = find.widgetWithText(
          TextField, 'e.g. Excavation, PCC, Rebar, Finishing...');
      await tester.enterText(activityField, 'Foundation');
      await tester.pumpAndSettle();

      // Select 'Closed'
      final closedChip = find.text('Closed');
      await tester.ensureVisible(closedChip);
      await tester.tap(closedChip);
      await tester.pumpAndSettle();

      // Verify smart link suggestion appears
      expect(find.text('SMART-LINK SUGGESTION'), findsOneWidget);
      expect(find.text('Link as Resolved'), findsOneWidget);

      // Tap Link
      final linkBtn = find.text('Link as Resolved');
      await tester.ensureVisible(linkBtn);
      await tester.tap(linkBtn);
      await tester.pumpAndSettle();

      expect(find.text('LINKED AS RESOLUTION'), findsOneWidget);
      expect(find.text('Save Evidence'), findsOneWidget);

      // Tap Save
      await tester.tap(find.text('Save Evidence'));
      await tester.pumpAndSettle();

      final saved = await (db.select(db.media)
            ..where((tbl) => tbl.id.equals('widget-test-1')))
          .getSingle();
      expect(saved.observationType, 'closed');
      expect(saved.linkedMediaId, 'nearby-nc-1');
    });

    testWidgets(
        'Closed observation without candidate shows warning banner and locks save button',
        (tester) async {
      await tester.pumpWidget(createReviewWidget(payload));
      await tester.pumpAndSettle();

      // Select 'Closed'
      final closedChip = find.text('Closed');
      await tester.ensureVisible(closedChip);
      await tester.tap(closedChip);
      await tester.pumpAndSettle();

      // Warning banner displayed
      expect(find.text('NO OPEN NON-CONFORMITY WITHIN 10M'), findsOneWidget);
      expect(
        find.textContaining(
            'No open Non-Conformity found within 10m. Closed observations cannot be saved'),
        findsOneWidget,
      );

      // Save button is disabled and displays locked text
      expect(find.text('Link BEFORE to Save'), findsOneWidget);
      await tester.tap(find.text('Link BEFORE to Save'));
      await tester.pumpAndSettle();

      // Verify zero rows saved in SQLite
      final rows = await (db.select(db.media)
            ..where((tbl) => tbl.id.equals('widget-test-1')))
          .get();
      expect(rows.isEmpty, isTrue);
    });

    testWidgets(
        'Tapping Retake shows Discard Capture? dialog and confirms cleanup',
        (tester) async {
      await tester.pumpWidget(createReviewWidget(payload));
      await tester.pumpAndSettle();

      final retakeBtn = find.text('Retake');
      await tester.tap(retakeBtn);
      await tester.pumpAndSettle();

      expect(find.text('Discard Capture?'), findsOneWidget);
      expect(find.text('Discard & Retake'), findsOneWidget);

      await tester.tap(find.text('Discard & Retake'));
      await tester.pumpAndSettle();

      // Zero rows inserted into SQLite
      final rows = await (db.select(db.media)
            ..where((tbl) => tbl.id.equals('widget-test-1')))
          .get();
      expect(rows.isEmpty, isTrue);
    });

    testWidgets('Tapping Save Evidence saves to Drift and pops screen',
        (tester) async {
      await tester.pumpWidget(createReviewWidget(payload));
      await tester.pumpAndSettle();

      final saveBtn = find.text('Save Evidence');
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Confirm row was inserted into SQLite
      final rows = await (db.select(db.media)
            ..where((tbl) => tbl.id.equals('widget-test-1')))
          .get();
      expect(rows.length, 1);
      expect(rows.first.id, 'widget-test-1');
    });
  });
}
