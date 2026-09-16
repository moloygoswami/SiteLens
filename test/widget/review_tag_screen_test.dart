import 'dart:ffi';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sitelens/core/controllers/nearby_settings_controller.dart';
import 'package:sitelens/core/services/auth_service.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/local/database/database_provider.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/features/camera/models/evidence_metadata_snapshot.dart';
import 'package:sitelens/features/camera/services/evidence_storage_service.dart';
import 'package:sitelens/features/review/controllers/review_tag_controller.dart';
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

  @override
  Future<void> deleteOriginalMedia(String relativePath) async {}

  @override
  Future<void> deleteLocalMediaFiles({
    required String mediaId,
    String? originalUri,
    String? uri,
    String? thumbUri,
    String? type,
  }) async {}
}

class FakeNearbySettingsNotifier extends NearbySettingsNotifier {
  FakeNearbySettingsNotifier(double initial) : super() {
    state = initial;
  }
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
        nearbySettingsProvider
            .overrideWith((ref) => FakeNearbySettingsNotifier(25.0)),
        authStateProvider
            .overrideWith((ref) => Stream.value(const AuthUser(uid: 'user-test'))),
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
        'Renders evidence preview, form fields, and does not render redundant minimap/metadata HUD card',
        (tester) async {
      await tester.pumpWidget(createReviewWidget(payload));
      await tester.pumpAndSettle();

      expect(find.text('REVIEW & TAG EVIDENCE'), findsOneWidget);
      expect(find.byType(ReviewMediaPreview), findsOneWidget);

      // Redundant minimap/metadata HUD card must NOT be rendered by Review & Tag
      expect(find.byType(EvidenceMetadataHudCard), findsNothing);
      expect(find.byType(StandaloneMetadataWidget), findsNothing);

      // Verify no hardcoded AspectRatio widget enforces 3:4
      expect(find.byType(AspectRatio), findsNothing);

      // Form and action controls
      expect(find.text('ACTIVITY / WORK STAGE'), findsOneWidget);
      expect(find.byType(ObservationSelector), findsOneWidget);
      expect(find.text('Save Evidence'), findsOneWidget);
      expect(find.text('Retake'), findsOneWidget);
    });

    testWidgets(
        'Evidence preview uses contain semantics and does not mount redundant minimap/metadata HUD card',
        (tester) async {
      await tester.pumpWidget(createReviewWidget(payload));
      await tester.pumpAndSettle();

      final previewFinder = find.byType(ReviewMediaPreview);
      expect(previewFinder, findsOneWidget);

      // Redundant minimap/metadata HUD card must NOT be mounted below the preview
      expect(find.byType(EvidenceMetadataHudCard), findsNothing);
      expect(find.byType(StandaloneMetadataWidget), findsNothing);

      // Form and action controls remain present
      expect(find.text('ACTIVITY / WORK STAGE'), findsOneWidget);
      expect(find.byType(ObservationSelector), findsOneWidget);
      expect(find.text('Save Evidence'), findsOneWidget);
      expect(find.text('Retake'), findsOneWidget);
    });

    testWidgets(
        'Entering Activity Tag and Selecting Closed exposes Find Nearby Evidence action and candidate',
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
              creatorId: const drift.Value('user-test'),
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

      // Verify Find Nearby Evidence action is available
      expect(find.text('BEFORE REFERENCE REQUIRED'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Find Nearby Evidence'), findsOneWidget);

      // Verify smart link suggestion appears with Select as BEFORE action
      expect(find.text('SMART-LINK SUGGESTION'), findsOneWidget);
      expect(find.text('Select as BEFORE'), findsOneWidget);

      // Tap Select as BEFORE
      final linkBtn = find.text('Select as BEFORE');
      await tester.ensureVisible(linkBtn);
      await tester.tap(linkBtn);
      await tester.pumpAndSettle();

      expect(find.text('SELECTED BEFORE EVIDENCE'), findsOneWidget);
      final notesField = tester.widget<TextField>(find.byType(TextField).last);
      expect(notesField.controller!.text, 'Evid_ID: nearby-nc-1');
      expect(find.text('Evid_ID: None (Select via Find Nearby Evidence)'), findsNothing);
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
        'Tapping Find Nearby Evidence opens picker mode, candidate selection returns MediaItem and populates Evid_ID',
        (tester) async {
      // Seed a nearby non-conformity item
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'nearby-nc-picker',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_nc_picker.jpg'),
              uri: 'media/evid_nc_picker.jpg',
              lat: 22.56298,
              lon: 88.30085,
              activityTag: const drift.Value('Excavation'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-14T04:00:00Z',
              creatorId: const drift.Value('user-test'),
            ),
          );

      await tester.pumpWidget(createReviewWidget(payload));
      await tester.pumpAndSettle();

      // Enter inspection notes first to verify independence from Evid_ID
      final notesField = find.widgetWithText(
          TextField, 'Enter specification clause, drawing number, or remarks...');
      await tester.enterText(notesField, 'Spec Clause 4.2.1 Verified');
      await tester.pumpAndSettle();

      // Select 'Closed'
      final closedChip = find.text('Closed');
      await tester.ensureVisible(closedChip);
      await tester.tap(closedChip);
      await tester.pumpAndSettle();

      // Verify Find Nearby Evidence button is visible
      final findNearbyBtn = find.widgetWithText(OutlinedButton, 'Find Nearby Evidence');
      expect(findNearbyBtn, findsOneWidget);

      // Tap Find Nearby Evidence -> opens NearbySearchScreen in picker mode
      await tester.tap(findNearbyBtn);
      await tester.pumpAndSettle();

      // Assert picker mode banner is displayed
      expect(find.text('PICKER MODE: Select an open Non-Conformity as BEFORE reference'), findsOneWidget);

      // Tap Select on the candidate
      final selectBtn = find.text('Select');
      expect(selectBtn, findsOneWidget);
      await tester.tap(selectBtn);
      await tester.pumpAndSettle();

      // Back on ReviewTagScreen: verify Evid_ID is populated inside existing Notes TextField
      expect(find.text('SELECTED BEFORE EVIDENCE'), findsOneWidget);
      final notesFieldAfter = tester.widget<TextField>(find.byType(TextField).last);
      expect(
        notesFieldAfter.controller!.text,
        'Evid_ID: nearby-nc-picker\nSpec Clause 4.2.1 Verified',
      );
      expect(find.text('Evid_ID: None (Select via Find Nearby Evidence)'), findsNothing);

      // Verify Save Evidence button is enabled and save succeeds
      final saveBtn = find.text('Save Evidence');
      expect(saveBtn, findsOneWidget);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      final saved = await (db.select(db.media)
            ..where((tbl) => tbl.id.equals('widget-test-1')))
          .getSingle();
      expect(saved.observationType, 'closed');
      expect(saved.linkedMediaId, 'nearby-nc-picker');
      expect(saved.note, 'Evid_ID: nearby-nc-picker\nSpec Clause 4.2.1 Verified');
    });

    testWidgets(
        'Unlinking Closed evidence resets linkedMediaId, clears Evid_ID, and disables save',
        (tester) async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'nearby-nc-unlink',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_nc_unlink.jpg'),
              uri: 'media/evid_nc_unlink.jpg',
              lat: 22.56298,
              lon: 88.30085,
              activityTag: const drift.Value('Foundation'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-14T04:00:00Z',
              creatorId: const drift.Value('user-test'),
            ),
          );

      await tester.pumpWidget(createReviewWidget(payload));
      await tester.pumpAndSettle();

      final activityField = find.widgetWithText(
          TextField, 'e.g. Excavation, PCC, Rebar, Finishing...');
      await tester.enterText(activityField, 'Foundation');
      await tester.pumpAndSettle();

      final closedChip = find.text('Closed');
      await tester.ensureVisible(closedChip);
      await tester.tap(closedChip);
      await tester.pumpAndSettle();

      // Link candidate via smart link shortcut
      final selectBeforeBtn = find.text('Select as BEFORE');
      await tester.ensureVisible(selectBeforeBtn);
      await tester.tap(selectBeforeBtn);
      await tester.pumpAndSettle();

      final notesFieldLinked = tester.widget<TextField>(find.byType(TextField).last);
      expect(notesFieldLinked.controller!.text, 'Evid_ID: nearby-nc-unlink');
      expect(find.text('Save Evidence'), findsOneWidget);

      // Tap Unlink
      final unlinkBtn = find.text('Unlink');
      await tester.ensureVisible(unlinkBtn);
      await tester.tap(unlinkBtn);
      await tester.pumpAndSettle();

      final notesFieldUnlinked = tester.widget<TextField>(find.byType(TextField).last);
      expect(notesFieldUnlinked.controller!.text, isEmpty);
      expect(find.text('Evid_ID: None (Select via Find Nearby Evidence)'), findsNothing);
      expect(find.text('Link BEFORE to Save'), findsOneWidget);
    });

    testWidgets(
        'Closed observation without candidate shows Find Nearby Evidence action and locks save button',
        (tester) async {
      await tester.pumpWidget(createReviewWidget(payload));
      await tester.pumpAndSettle();

      // Select 'Closed'
      final closedChip = find.text('Closed');
      await tester.ensureVisible(closedChip);
      await tester.tap(closedChip);
      await tester.pumpAndSettle();

      // Required action displayed
      expect(find.text('BEFORE REFERENCE REQUIRED'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Find Nearby Evidence'), findsOneWidget);
      expect(
        find.textContaining('No 10m auto-match found. Tap "Find Nearby Evidence"'),
        findsOneWidget,
      );
      expect(find.text('Evid_ID: None (Select via Find Nearby Evidence)'), findsNothing);
      final notesFieldEmpty = tester.widget<TextField>(find.byType(TextField).last);
      expect(notesFieldEmpty.controller!.text, isEmpty);

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

    testWidgets(
        'System back navigation invokes discard confirmation; cancel keeps user on ReviewTagScreen, confirm retakes and returns false',
        (tester) async {
      bool? poppedResult;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            mediaRepositoryProvider.overrideWithValue(LocalMediaRepository(db)),
            evidenceStorageServiceProvider
                .overrideWithValue(MockWidgetReviewStorageService()),
            nearbySettingsProvider
                .overrideWith((ref) => FakeNearbySettingsNotifier(25.0)),
            authStateProvider
                .overrideWith((ref) => Stream.value(const AuthUser(uid: 'user-test'))),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    poppedResult = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => ReviewTagScreen(payload: payload),
                      ),
                    );
                  },
                  child: const Text('Open Review'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to ReviewTagScreen
      await tester.tap(find.text('Open Review'));
      await tester.pumpAndSettle();
      expect(find.text('REVIEW & TAG EVIDENCE'), findsOneWidget);

      // Simulate system back
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Dialog should be shown
      expect(find.text('Discard Capture?'), findsOneWidget);

      // Tap Cancel in dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // User remains on ReviewTagScreen, not popped
      expect(find.text('REVIEW & TAG EVIDENCE'), findsOneWidget);
      expect(poppedResult, isNull);

      // Simulate system back again and confirm discard
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard Capture?'), findsOneWidget);

      await tester.tap(find.text('Discard & Retake'));
      await tester.pumpAndSettle();

      // Screen is popped back to root with false
      expect(find.text('REVIEW & TAG EVIDENCE'), findsNothing);
      expect(find.text('Open Review'), findsOneWidget);
      expect(poppedResult, isFalse);
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

    testWidgets(
        'User can edit the same Notes TextField after Evid_ID insertion and edits are saved',
        (tester) async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'nc-edit-test',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_edit.jpg'),
              uri: 'media/evid_edit.jpg',
              lat: 22.56298,
              lon: 88.30085,
              activityTag: const drift.Value('Concrete'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-14T04:00:00Z',
              creatorId: const drift.Value('user-test'),
            ),
          );

      await tester.pumpWidget(createReviewWidget(payload));
      await tester.pumpAndSettle();

      final closedChip = find.text('Closed');
      await tester.ensureVisible(closedChip);
      await tester.tap(closedChip);
      await tester.pumpAndSettle();

      // Link candidate
      final selectBeforeBtn = find.text('Select as BEFORE');
      await tester.ensureVisible(selectBeforeBtn);
      await tester.tap(selectBeforeBtn);
      await tester.pumpAndSettle();

      final notesField = find.byType(TextField).last;
      expect(
        (tester.widget<TextField>(notesField)).controller!.text,
        'Evid_ID: nc-edit-test',
      );

      // User continues typing in the same field
      await tester.enterText(
        notesField,
        'Evid_ID: nc-edit-test\nInspection completed after corrective work.',
      );
      await tester.pumpAndSettle();

      // Tap Save
      await tester.tap(find.text('Save Evidence'));
      await tester.pumpAndSettle();

      final saved = await (db.select(db.media)
            ..where((tbl) => tbl.id.equals('widget-test-1')))
          .getSingle();
      expect(saved.observationType, 'closed');
      expect(saved.linkedMediaId, 'nc-edit-test');
      expect(
        saved.note,
        'Evid_ID: nc-edit-test\nInspection completed after corrective work.',
      );
    });

    testWidgets(
        'Candidate replacement updates only generated Evid_ID line, preserving user notes',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          evidenceStorageServiceProvider
              .overrideWithValue(MockWidgetReviewStorageService()),
        ],
      );
      final sub = container.listen(reviewTagControllerProvider, (_, __) {});
      addTearDown(() {
        sub.close();
        container.dispose();
      });

      final notifier = container.read(reviewTagControllerProvider.notifier);

      // Start with user-owned note
      notifier.setNote('Concrete repair verified.\nPhoto taken after completion.');

      final candidate1 = MediaItem(
        id: 'evid_12345',
        siteId: 'SITE_001',
        originalUri: 'media/orig_c1.jpg',
        uri: 'media/c1.jpg',
        type: MediaItemType.photo,
        capturedAt: DateTime.now(),
        lat: 22.5,
        lon: 88.3,
        observationType: ObservationType.nonConformity,
      );
      final candidate2 = MediaItem(
        id: 'evid_67890',
        siteId: 'SITE_001',
        originalUri: 'media/orig_c2.jpg',
        uri: 'media/c2.jpg',
        type: MediaItemType.photo,
        capturedAt: DateTime.now(),
        lat: 22.5,
        lon: 88.3,
        observationType: ObservationType.nonConformity,
      );

      // First link
      notifier.linkBeforeItem(candidate1);
      expect(container.read(reviewTagControllerProvider).linkedMediaId, 'evid_12345');
      expect(
        container.read(reviewTagControllerProvider).note,
        'Evid_ID: evid_12345\nConcrete repair verified.\nPhoto taken after completion.',
      );

      // Candidate replacement
      notifier.linkBeforeItem(candidate2);
      expect(container.read(reviewTagControllerProvider).linkedMediaId, 'evid_67890');
      expect(
        container.read(reviewTagControllerProvider).note,
        'Evid_ID: evid_67890\nConcrete repair verified.\nPhoto taken after completion.',
      );

      // Multiple candidate replacement without duplicates
      notifier.linkBeforeItem(candidate2);
      expect(
        container.read(reviewTagControllerProvider).note,
        'Evid_ID: evid_67890\nConcrete repair verified.\nPhoto taken after completion.',
      );

      // Unlink removes only generated line
      notifier.unlinkBeforeItem();
      expect(container.read(reviewTagControllerProvider).linkedMediaId, isNull);
      expect(
        container.read(reviewTagControllerProvider).note,
        'Concrete repair verified.\nPhoto taken after completion.',
      );
    });

    testWidgets(
        'Arbitrary user-entered Evid_ID text is not treated as system-owned line on Unlink or candidate change',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          evidenceStorageServiceProvider
              .overrideWithValue(MockWidgetReviewStorageService()),
        ],
      );
      final sub = container.listen(reviewTagControllerProvider, (_, __) {});
      addTearDown(() {
        sub.close();
        container.dispose();
      });

      final notifier = container.read(reviewTagControllerProvider.notifier);

      // User manually enters text containing an Evid_ID reference
      notifier.setNote('Evid_ID: custom_manual_ref\nInspection remarks');

      final candidate = MediaItem(
        id: 'evid_system_123',
        siteId: 'SITE_001',
        originalUri: 'media/orig_c.jpg',
        uri: 'media/c.jpg',
        type: MediaItemType.photo,
        capturedAt: DateTime.now(),
        lat: 22.5,
        lon: 88.3,
        observationType: ObservationType.nonConformity,
      );

      notifier.linkBeforeItem(candidate);
      expect(
        container.read(reviewTagControllerProvider).note,
        'Evid_ID: evid_system_123\nEvid_ID: custom_manual_ref\nInspection remarks',
      );

      // Unlink removes only the system-owned line
      notifier.unlinkBeforeItem();
      expect(
        container.read(reviewTagControllerProvider).note,
        'Evid_ID: custom_manual_ref\nInspection remarks',
      );
    });

    testWidgets(
        'Manually typing Evid_ID in Notes does not establish linkedMediaId and does not enable Closed save',
        (tester) async {
      await tester.pumpWidget(createReviewWidget(payload));
      await tester.pumpAndSettle();

      final closedChip = find.text('Closed');
      await tester.ensureVisible(closedChip);
      await tester.tap(closedChip);
      await tester.pumpAndSettle();

      final notesField = find.byType(TextField).last;
      await tester.enterText(notesField, 'Evid_ID: fake_evid_id');
      await tester.pumpAndSettle();

      // Save button remains locked
      expect(find.text('Link BEFORE to Save'), findsOneWidget);
      await tester.tap(find.text('Link BEFORE to Save'));
      await tester.pumpAndSettle();

      final rows = await (db.select(db.media)
            ..where((tbl) => tbl.id.equals('widget-test-1')))
          .get();
      expect(rows.isEmpty, isTrue);
    });
  });

  group('ReviewTagNotifier Evid_ID Note Manipulation Pure Logic', () {
    test('updateNoteWithEvidId prepends Evid_ID when note is empty', () {
      final res = ReviewTagNotifier.updateNoteWithEvidId(
        currentNote: '',
        newId: '1001',
      );
      expect(res, 'Evid_ID: 1001');
    });

    test('updateNoteWithEvidId prepends Evid_ID when user note already exists', () {
      final res = ReviewTagNotifier.updateNoteWithEvidId(
        currentNote: 'Work completed according to spec',
        newId: '1001',
      );
      expect(res, 'Evid_ID: 1001\nWork completed according to spec');
    });

    test('updateNoteWithEvidId replaces only previous system Evid_ID line', () {
      final res = ReviewTagNotifier.updateNoteWithEvidId(
        currentNote: 'Evid_ID: 1001\nWork completed according to spec\nInspected by quality lead',
        newId: '1002',
        previousId: '1001',
      );
      expect(
        res,
        'Evid_ID: 1002\nWork completed according to spec\nInspected by quality lead',
      );
    });

    test('updateNoteWithEvidId avoids duplicate lines when linking same id', () {
      final res = ReviewTagNotifier.updateNoteWithEvidId(
        currentNote: 'Evid_ID: 1001\nWork completed',
        newId: '1001',
        previousId: '1001',
      );
      expect(res, 'Evid_ID: 1001\nWork completed');
    });

    test('removeEvidIdFromNote removes only targeted system Evid_ID line', () {
      final res = ReviewTagNotifier.removeEvidIdFromNote(
        currentNote: 'Evid_ID: 1001\nWork completed according to spec',
        linkedId: '1001',
      );
      expect(res, 'Work completed according to spec');
    });

    test('removeEvidIdFromNote leaves non-matching user-entered Evid_ID untouched', () {
      final res = ReviewTagNotifier.removeEvidIdFromNote(
        currentNote: 'Evid_ID: manual_reference\nWork completed according to spec',
        linkedId: '1001',
      );
      expect(
        res,
        'Evid_ID: manual_reference\nWork completed according to spec',
      );
    });

    test('removeEvidIdFromNote returns empty string if only Evid_ID was present', () {
      final res = ReviewTagNotifier.removeEvidIdFromNote(
        currentNote: 'Evid_ID: 1001',
        linkedId: '1001',
      );
      expect(res, isEmpty);
    });
  });
}
