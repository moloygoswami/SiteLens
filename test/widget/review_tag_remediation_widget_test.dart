import 'dart:async';
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
import 'package:sitelens/features/gallery/widgets/media_tag_edit_modal.dart';
import 'package:sitelens/features/review/controllers/review_tag_controller.dart';
import 'package:sitelens/features/review/models/pending_capture_payload.dart';
import 'package:sitelens/features/review/review_tag_screen.dart';
import 'package:sitelens/features/review/widgets/smart_link_card.dart';

class MockWidgetReviewStorageService extends EvidenceStorageService {
  @override
  Future<bool> verifyArtifactsExist({
    required String originalRelativePath,
    required String evidenceRelativePath,
    String? thumbnailRelativePath,
  }) async =>
      true;

  @override
  Future<String> resolveAbsolutePath(String relativePath) async =>
      '/mock/path/$relativePath';

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

/// Repository whose [findSuggestedBeforeMatch] results are manually resolved so
/// tests can control which search response (older vs newer) completes first.
class ControllableSearchRepository extends LocalMediaRepository {
  ControllableSearchRepository(super.db);

  final List<Completer<MediaItem?>> pendingSearches = [];

  @override
  Future<MediaItem?> findSuggestedBeforeMatch({
    required double centerLat,
    required double centerLon,
    required String siteId,
    required String activityTag,
    double radiusMeters = 10.0,
    String? currentMediaId,
    String? creatorId,
    bool requireCreator = false,
  }) {
    final completer = Completer<MediaItem?>();
    pendingSearches.add(completer);
    return completer.future;
  }
}

void main() {
  late AppDatabase db;
  late LocalMediaRepository mediaRepo;

  setUpAll(() {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  });

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    mediaRepo = LocalMediaRepository(db);

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

  Widget buildReviewScope({
    required Widget child,
    MediaRepository? mediaRepository,
  }) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        mediaRepositoryProvider.overrideWithValue(mediaRepository ?? mediaRepo),
        evidenceStorageServiceProvider
            .overrideWithValue(MockWidgetReviewStorageService()),
        nearbySettingsProvider
            .overrideWith((ref) => FakeNearbySettingsNotifier(25.0)),
        authStateProvider.overrideWith(
          (ref) => Stream.value(const AuthUser(uid: 'inspector-123')),
        ),
      ],
      child: MaterialApp(
        home: child,
      ),
    );
  }

  group('F1: Smart-Link Dismissal Widget Tests', () {
    testWidgets(
        'Tapping "Not now" on SmartLinkCard dismisses the match, clears suggestion, and reveals fallback text',
        (tester) async {
      // Seed an eligible candidate within 10m
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'candidate-f1',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_f1.jpg'),
              uri: 'media/evid_f1.jpg',
              lat: 22.56298,
              lon: 88.30085,
              activityTag: const drift.Value('Excavation'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-15T04:00:00Z',
              creatorId: const drift.Value('inspector-123'),
            ),
          );

      final snapshot = EvidenceMetadataSnapshot(
        mediaId: 'capture-f1',
        siteId: 'SITE_001',
        siteCode: 'HOME',
        siteName: 'Sonar Kella Apartment',
        latitude: 22.56298,
        longitude: 88.30085,
        altitudeMeters: 18.0,
        accuracyMeters: 3.0,
        lowAccuracy: false,
        capturedAtUtc: DateTime.utc(2026, 8, 15, 4, 30, 0),
        canonicalTimestampUtc: '2026-08-15 04:30:00 UTC',
        resolvedAddress: 'Sonar Kella Apartment, Kolkata',
        creatorId: 'inspector-123',
      );

      final payload = PendingCapturePayload(
        mediaId: 'capture-f1',
        mediaType: MediaItemType.photo,
        originalFilePath: 'media/orig_f1.jpg',
        evidenceFilePath: 'media/evid_f1.jpg',
        thumbnailFilePath: 'media/thumb_f1.jpg',
        sha256Hash: 'hash-f1',
        fileSizeBytes: 100000,
        previewBytes: null,
        metadataSnapshot: snapshot,
      );

      await tester.pumpWidget(buildReviewScope(
        child: ReviewTagScreen(payload: payload),
      ));
      await tester.pumpAndSettle();

      // Enter matching activity and select Closed
      final activityField = find.byType(TextField).first;
      await tester.enterText(activityField, 'Excavation');
      await tester.pumpAndSettle();

      final closedChip = find.text('Closed');
      await tester.ensureVisible(closedChip);
      await tester.tap(closedChip);
      await tester.pumpAndSettle();

      // Verify SmartLinkCard appears with "Not now" button
      expect(find.byType(SmartLinkCard), findsOneWidget);
      expect(find.text('SMART-LINK SUGGESTION'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);

      // Tap "Not now"
      final notNowBtn = find.text('Not now');
      await tester.ensureVisible(notNowBtn);
      await tester.tap(notNowBtn);
      await tester.pumpAndSettle();

      // Card is dismissed and fallback text is shown
      expect(find.byType(SmartLinkCard), findsNothing);
      expect(
        find.text(
            'No 10m auto-match found. Tap "Find Nearby Evidence" to search and select the corresponding open Non-Conformity.'),
        findsOneWidget,
      );

      // Verify state was cleared
      final element = tester.element(find.byType(ReviewTagScreen));
      final container = ProviderScope.containerOf(element);
      final state = container.read(reviewTagControllerProvider);
      expect(state.suggestedBeforeMatch, isNull);
      expect(state.linkedMediaId, isNull);
      expect(state.isLinked, isFalse);
    });
  });

  group('F4: Edit-Modal Distance Widget Tests', () {
    testWidgets(
        'MediaTagEditModal displays non-zero Haversine distance for loaded linked candidate',
        (tester) async {
      // Seed a Before candidate ~5.4m away
      // Lat delta ~0.00004 deg (~4.45m), Lon delta ~0.00003 deg (~3.08m) => ~5.4m
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'candidate-loaded',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_l.jpg'),
              uri: 'media/evid_l.jpg',
              lat: 22.56302,
              lon: 88.30088,
              activityTag: const drift.Value('Excavation'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-15T03:00:00Z',
              creatorId: const drift.Value('inspector-123'),
            ),
          );

      final closedItem = MediaItem(
        id: 'closed-edit-1',
        siteId: 'SITE_001',
        type: MediaItemType.photo,
        uri: 'media/evid_c1.jpg',
        originalUri: 'media/orig_c1.jpg',
        thumbUri: 'media/thumb_c1.jpg',
        capturedAt: DateTime.utc(2026, 8, 15, 4, 0, 0),
        lat: 22.56298,
        lon: 88.30085,
        accuracyM: 3.0,
        lowAccuracy: false,
        activityTag: 'Excavation',
        observationType: ObservationType.closed,
        linkedMediaId: 'candidate-loaded',
        note: 'Evid_ID: candidate-loaded\nRectified',
        sha256Hash: 'hash-c1',
        syncStatus: SyncStatusType.pending,
        creatorId: 'inspector-123',
      );

      await tester.pumpWidget(buildReviewScope(
        child: Scaffold(
          body: MediaTagEditModal(item: closedItem),
        ),
      ));
      await tester.pumpAndSettle();

      // Verify SmartLinkCard is displayed
      expect(find.byType(SmartLinkCard), findsOneWidget);

      // Verify distance is NOT hardcoded 0.0m
      expect(find.textContaining('0.0m away'), findsNothing);

      // Verify distance string matches calculated ~5.4m
      expect(find.textContaining('5.4m away'), findsOneWidget);
    });

    testWidgets(
        'MediaTagEditModal displays non-zero Haversine distance for newly searched candidate',
        (tester) async {
      // Seed candidate ~5.4m away
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'candidate-searched',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_s.jpg'),
              uri: 'media/evid_s.jpg',
              lat: 22.56302,
              lon: 88.30088,
              activityTag: const drift.Value('Paving'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-15T03:00:00Z',
              creatorId: const drift.Value('inspector-123'),
            ),
          );

      // Unlinked item with Closed observation type
      final itemToEdit = MediaItem(
        id: 'closed-edit-2',
        siteId: 'SITE_001',
        type: MediaItemType.photo,
        uri: 'media/evid_c2.jpg',
        originalUri: 'media/orig_c2.jpg',
        thumbUri: 'media/thumb_c2.jpg',
        capturedAt: DateTime.utc(2026, 8, 15, 4, 0, 0),
        lat: 22.56298,
        lon: 88.30085,
        accuracyM: 3.0,
        lowAccuracy: false,
        activityTag: 'Paving',
        observationType: ObservationType.closed,
        linkedMediaId: null,
        note: 'Rectification work',
        sha256Hash: 'hash-c2',
        syncStatus: SyncStatusType.pending,
        creatorId: 'inspector-123',
      );

      await tester.pumpWidget(buildReviewScope(
        child: Scaffold(
          body: MediaTagEditModal(item: itemToEdit),
        ),
      ));
      await tester.pumpAndSettle();

      // Search runs automatically for Closed unlinked item
      expect(find.byType(SmartLinkCard), findsOneWidget);

      // Verify distance is NOT hardcoded 0.0m
      expect(find.textContaining('0.0m away'), findsNothing);
      expect(find.textContaining('5.4m away'), findsOneWidget);

      // Verify unlinking resets distance and candidate
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(find.byType(SmartLinkCard), findsNothing);
      expect(find.textContaining('5.4m away'), findsNothing);
    });
  });

  group('Modal Non-Destructive B→A Lifecycle (SiteLens #9 Correction)', () {
    testWidgets(
        'Test 1: Existing link survives edit — suggestion C never displaces linked A; save preserves B→A',
        (tester) async {
      // Seed Non-Conformity A (Excavation) and alternative candidate C (Paving)
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'candidate-A',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_a.jpg'),
              uri: 'media/evid_a.jpg',
              lat: 22.56298,
              lon: 88.30085,
              activityTag: const drift.Value('Excavation'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-15T03:00:00Z',
              creatorId: const drift.Value('inspector-123'),
            ),
          );
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'candidate-B',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_b.jpg'),
              uri: 'media/evid_b.jpg',
              lat: 22.56298,
              lon: 88.30085,
              activityTag: const drift.Value('Paving'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-15T03:00:00Z',
              creatorId: const drift.Value('inspector-123'),
            ),
          );

      // Seed Closed observation B already linked to A
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'closed-div-item',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_cd.jpg'),
              uri: 'media/evid_cd.jpg',
              lat: 22.56298,
              lon: 88.30085,
              activityTag: const drift.Value('Excavation'),
              observationType: const drift.Value('closed'),
              linkedMediaId: const drift.Value('candidate-A'),
              note: const drift.Value('Evid_ID: candidate-A\nUser remark preserved'),
              capturedAt: '2026-08-15T04:00:00Z',
              creatorId: const drift.Value('inspector-123'),
            ),
          );

      final linkedItem = MediaItem(
        id: 'closed-div-item',
        siteId: 'SITE_001',
        type: MediaItemType.photo,
        uri: 'media/evid_cd.jpg',
        originalUri: 'media/orig_cd.jpg',
        thumbUri: 'media/thumb_cd.jpg',
        capturedAt: DateTime.utc(2026, 8, 15, 4, 0, 0),
        lat: 22.56298,
        lon: 88.30085,
        accuracyM: 3.0,
        lowAccuracy: false,
        activityTag: 'Excavation',
        observationType: ObservationType.closed,
        linkedMediaId: 'candidate-A',
        note: 'Evid_ID: candidate-A\nUser remark preserved',
        sha256Hash: 'hash-cd',
        syncStatus: SyncStatusType.pending,
        creatorId: 'inspector-123',
      );

      bool? modalResult;
      await tester.pumpWidget(buildReviewScope(
        child: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                modalResult = await MediaTagEditModal.show(context, linkedItem);
              },
              child: const Text('Open Modal'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // 1. Existing A relationship is loaded and shown as selected
      expect(find.text('SELECTED BEFORE EVIDENCE'), findsOneWidget);
      TextField noteField() => tester.widget<TextField>(find.byType(TextField).last);
      expect(
        noteField().controller!.text,
        'Evid_ID: candidate-A\nUser remark preserved',
      );

      // 2. Editing the activity text discovers candidate C
      final activityField = find.byType(TextField).first;
      await tester.ensureVisible(activityField);
      await tester.enterText(activityField, 'Paving');
      await tester.pumpAndSettle();

      // 3. A remains selected/authoritative; C is presented only as a NEW suggestion
      expect(find.text('SELECTED BEFORE EVIDENCE'), findsOneWidget);
      expect(find.text('SMART-LINK SUGGESTION'), findsOneWidget);
      expect(
        noteField().controller!.text,
        'Evid_ID: candidate-A\nUser remark preserved',
      );
      expect(find.text('Save Changes'), findsOneWidget);

      // 4. Save preserves B.linkedMediaId = A and user remarks
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(modalResult, isTrue);

      final row = await (db.select(db.media)
            ..where((tbl) => tbl.id.equals('closed-div-item')))
          .getSingle();
      expect(row.observationType, 'closed');
      expect(row.linkedMediaId, 'candidate-A');
      expect(row.activityTag, 'Paving');
      expect(row.note, 'Evid_ID: candidate-A\nUser remark preserved');

      // 5. A and B both remain persisted and gallery-visible
      final aRow = await (db.select(db.media)
            ..where((tbl) => tbl.id.equals('candidate-A')))
          .getSingle();
      expect(aRow.isDeleted, 0);
      expect(aRow.observationType, 'nonConformity');
      expect(aRow.linkedMediaId, isNull);
      final bRow = await (db.select(db.media)
            ..where((tbl) => tbl.id.equals('closed-div-item')))
          .getSingle();
      expect(bRow.isDeleted, 0);
      expect(bRow.observationType, 'closed');
    });

    testWidgets(
        'Test 2: Explicit replacement — user selects C, B.linkedMediaId changes A → C, A stays persisted',
        (tester) async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'candidate-A',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_a.jpg'),
              uri: 'media/evid_a.jpg',
              lat: 22.56298,
              lon: 88.30085,
              activityTag: const drift.Value('Excavation'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-15T03:00:00Z',
              creatorId: const drift.Value('inspector-123'),
            ),
          );
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'candidate-B',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_b.jpg'),
              uri: 'media/evid_b.jpg',
              lat: 22.56298,
              lon: 88.30085,
              activityTag: const drift.Value('Paving'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-15T03:00:00Z',
              creatorId: const drift.Value('inspector-123'),
            ),
          );
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'closed-div-item',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_cd.jpg'),
              uri: 'media/evid_cd.jpg',
              lat: 22.56298,
              lon: 88.30085,
              activityTag: const drift.Value('Excavation'),
              observationType: const drift.Value('closed'),
              linkedMediaId: const drift.Value('candidate-A'),
              note: const drift.Value('Evid_ID: candidate-A\nUser remark preserved'),
              capturedAt: '2026-08-15T04:00:00Z',
              creatorId: const drift.Value('inspector-123'),
            ),
          );

      final linkedItem = MediaItem(
        id: 'closed-div-item',
        siteId: 'SITE_001',
        type: MediaItemType.photo,
        uri: 'media/evid_cd.jpg',
        originalUri: 'media/orig_cd.jpg',
        thumbUri: 'media/thumb_cd.jpg',
        capturedAt: DateTime.utc(2026, 8, 15, 4, 0, 0),
        lat: 22.56298,
        lon: 88.30085,
        accuracyM: 3.0,
        lowAccuracy: false,
        activityTag: 'Excavation',
        observationType: ObservationType.closed,
        linkedMediaId: 'candidate-A',
        note: 'Evid_ID: candidate-A\nUser remark preserved',
        sha256Hash: 'hash-cd',
        syncStatus: SyncStatusType.pending,
        creatorId: 'inspector-123',
      );

      bool? modalResult;
      await tester.pumpWidget(buildReviewScope(
        child: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                modalResult = await MediaTagEditModal.show(context, linkedItem);
              },
              child: const Text('Open Modal'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();
      expect(find.text('SELECTED BEFORE EVIDENCE'), findsOneWidget);

      // Discover C via activity edit; C must NOT replace A automatically
      final activityField = find.byType(TextField).first;
      await tester.ensureVisible(activityField);
      await tester.enterText(activityField, 'Paving');
      await tester.pumpAndSettle();
      expect(find.text('SELECTED BEFORE EVIDENCE'), findsOneWidget);
      expect(find.text('SMART-LINK SUGGESTION'), findsOneWidget);
      TextField noteField() => tester.widget<TextField>(find.byType(TextField).last);
      expect(
        noteField().controller!.text,
        'Evid_ID: candidate-A\nUser remark preserved',
      );

      // Explicit user action: Select as BEFORE for C
      await tester.ensureVisible(find.text('Select as BEFORE'));
      await tester.tap(find.text('Select as BEFORE'));
      await tester.pumpAndSettle();

      // A replaced by C; system Evid_ID updated; remark preserved
      expect(find.text('SELECTED BEFORE EVIDENCE'), findsOneWidget);
      expect(find.text('SMART-LINK SUGGESTION'), findsNothing);
      expect(
        noteField().controller!.text,
        'Evid_ID: candidate-B\nUser remark preserved',
      );

      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(modalResult, isTrue);

      final row = await (db.select(db.media)
            ..where((tbl) => tbl.id.equals('closed-div-item')))
          .getSingle();
      expect(row.linkedMediaId, 'candidate-B');
      expect(row.note, 'Evid_ID: candidate-B\nUser remark preserved');

      // A and C both remain persisted and gallery-visible
      final aRow = await (db.select(db.media)
            ..where((tbl) => tbl.id.equals('candidate-A')))
          .getSingle();
      expect(aRow.isDeleted, 0);
      expect(aRow.observationType, 'nonConformity');
      final cRow = await (db.select(db.media)
            ..where((tbl) => tbl.id.equals('candidate-B')))
          .getSingle();
      expect(cRow.isDeleted, 0);
      expect(cRow.observationType, 'nonConformity');
    });

    testWidgets(
        'Test 3: Explicit unlink — removes relationship and Evid_ID; A and B remain persisted',
        (tester) async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'candidate-A',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_a.jpg'),
              uri: 'media/evid_a.jpg',
              lat: 22.56298,
              lon: 88.30085,
              activityTag: const drift.Value('Excavation'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-15T03:00:00Z',
              creatorId: const drift.Value('inspector-123'),
            ),
          );
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'closed-div-item',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_cd.jpg'),
              uri: 'media/evid_cd.jpg',
              lat: 22.56298,
              lon: 88.30085,
              activityTag: const drift.Value('Excavation'),
              observationType: const drift.Value('closed'),
              linkedMediaId: const drift.Value('candidate-A'),
              note: const drift.Value('Evid_ID: candidate-A\nUser remark preserved'),
              capturedAt: '2026-08-15T04:00:00Z',
              creatorId: const drift.Value('inspector-123'),
            ),
          );

      final linkedItem = MediaItem(
        id: 'closed-div-item',
        siteId: 'SITE_001',
        type: MediaItemType.photo,
        uri: 'media/evid_cd.jpg',
        originalUri: 'media/orig_cd.jpg',
        thumbUri: 'media/thumb_cd.jpg',
        capturedAt: DateTime.utc(2026, 8, 15, 4, 0, 0),
        lat: 22.56298,
        lon: 88.30085,
        accuracyM: 3.0,
        lowAccuracy: false,
        activityTag: 'Excavation',
        observationType: ObservationType.closed,
        linkedMediaId: 'candidate-A',
        note: 'Evid_ID: candidate-A\nUser remark preserved',
        sha256Hash: 'hash-cd',
        syncStatus: SyncStatusType.pending,
        creatorId: 'inspector-123',
      );

      bool? modalResult;
      await tester.pumpWidget(buildReviewScope(
        child: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                modalResult = await MediaTagEditModal.show(context, linkedItem);
              },
              child: const Text('Open Modal'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();
      expect(find.text('SELECTED BEFORE EVIDENCE'), findsOneWidget);

      // Explicit user action: Unlink removes the relationship and its Evid_ID
      await tester.ensureVisible(find.text('Unlink'));
      await tester.tap(find.text('Unlink'));
      await tester.pumpAndSettle();

      expect(find.text('SELECTED BEFORE EVIDENCE'), findsNothing);
      expect(find.text('Link BEFORE to Save'), findsOneWidget);
      TextField noteField() => tester.widget<TextField>(find.byType(TextField).last);
      expect(noteField().controller!.text, 'User remark preserved');

      // Switch to General (explicit) so the unlinked state can be saved
      await tester.ensureVisible(find.text('General'));
      await tester.tap(find.text('General'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(modalResult, isTrue);

      final row = await (db.select(db.media)
            ..where((tbl) => tbl.id.equals('closed-div-item')))
          .getSingle();
      expect(row.observationType, 'general');
      expect(row.linkedMediaId, isNull);
      expect(row.note, 'User remark preserved');

      // A and B both remain persisted and gallery-visible
      final aRow = await (db.select(db.media)
            ..where((tbl) => tbl.id.equals('candidate-A')))
          .getSingle();
      expect(aRow.isDeleted, 0);
      expect(aRow.observationType, 'nonConformity');
      final bRow = await (db.select(db.media)
            ..where((tbl) => tbl.id.equals('closed-div-item')))
          .getSingle();
      expect(bRow.isDeleted, 0);
    });

    testWidgets(
        'Older search response cannot replace a newer candidate (request guard)',
        (tester) async {
      final controllableRepo = ControllableSearchRepository(db);

      final unlinkedItem = MediaItem(
        id: 'closed-race-item',
        siteId: 'SITE_001',
        type: MediaItemType.photo,
        uri: 'media/evid_race.jpg',
        originalUri: 'media/orig_race.jpg',
        thumbUri: 'media/thumb_race.jpg',
        capturedAt: DateTime.utc(2026, 8, 15, 4, 0, 0),
        lat: 22.56298,
        lon: 88.30085,
        accuracyM: 3.0,
        lowAccuracy: false,
        activityTag: 'Paving',
        observationType: ObservationType.closed,
        linkedMediaId: null,
        note: 'User remark preserved',
        sha256Hash: 'hash-race',
        syncStatus: SyncStatusType.pending,
        creatorId: 'inspector-123',
      );

      final candidateA = MediaItem(
        id: 'candidate-race-a',
        siteId: 'SITE_001',
        type: MediaItemType.photo,
        uri: 'media/evid_ra.jpg',
        originalUri: 'media/orig_ra.jpg',
        capturedAt: DateTime.utc(2026, 8, 15, 3, 0, 0),
        lat: 22.56298,
        lon: 88.30085,
        activityTag: 'Excavation',
        observationType: ObservationType.nonConformity,
        creatorId: 'inspector-123',
      );
      final candidateB = MediaItem(
        id: 'candidate-race-b',
        siteId: 'SITE_001',
        type: MediaItemType.photo,
        uri: 'media/evid_rb.jpg',
        originalUri: 'media/orig_rb.jpg',
        capturedAt: DateTime.utc(2026, 8, 15, 3, 0, 0),
        lat: 22.56298,
        lon: 88.30085,
        activityTag: 'Paving',
        observationType: ObservationType.nonConformity,
        creatorId: 'inspector-123',
      );

      await tester.pumpWidget(buildReviewScope(
        mediaRepository: controllableRepo,
        child: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => MediaTagEditModal.show(context, unlinkedItem),
              child: const Text('Open Modal'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open Modal'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Search #1 (init) is pending; typing fires search #2
      expect(controllableRepo.pendingSearches.length, 1);
      final activityField = find.byType(TextField).first;
      await tester.ensureVisible(activityField);
      await tester.enterText(activityField, 'Paving 2');
      await tester.pump();
      expect(controllableRepo.pendingSearches.length, 2);

      // Newer search (#2) resolves first with candidate B
      controllableRepo.pendingSearches[1].complete(candidateB);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(SmartLinkCard), findsOneWidget);
      expect(find.textContaining('Paving — select as BEFORE'), findsOneWidget);

      // Older search (#1) resolves later with candidate A; must be discarded
      controllableRepo.pendingSearches[0].complete(candidateA);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(SmartLinkCard), findsOneWidget);
      expect(find.textContaining('Paving — select as BEFORE'), findsOneWidget);
      expect(find.textContaining('Excavation — select as BEFORE'), findsNothing);
    });
  });

  group('Replace Pending Closure Selection (physical-device remediation)', () {
    testWidgets(
        'Discarding a wrong BEFORE selection re-surfaces candidates, leaves the wrong NC unchanged, and save links the correct NC',
        (tester) async {
      // Seed two open Non-Conformities: the nearest one (auto-suggested first,
      // but WRONG) and the correct one matching the intended activity.
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'nc-wrong',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_wrong.jpg'),
              uri: 'media/evid_wrong.jpg',
              lat: 22.562980,
              lon: 88.300850,
              activityTag: const drift.Value('Excavation'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-14T04:00:00Z',
              creatorId: const drift.Value('inspector-123'),
            ),
          );
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'nc-correct',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_correct.jpg'),
              uri: 'media/evid_correct.jpg',
              lat: 22.563020,
              lon: 88.300880,
              activityTag: const drift.Value('Paving'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-14T05:00:00Z',
              creatorId: const drift.Value('inspector-123'),
            ),
          );

      final snapshot = EvidenceMetadataSnapshot(
        mediaId: 'capture-replace-1',
        siteId: 'SITE_001',
        siteCode: 'HOME',
        siteName: 'Sonar Kella Apartment',
        latitude: 22.56298,
        longitude: 88.30085,
        altitudeMeters: 18.0,
        accuracyMeters: 3.0,
        lowAccuracy: false,
        capturedAtUtc: DateTime.utc(2026, 8, 15, 6, 0, 0),
        canonicalTimestampUtc: '2026-08-15 06:00:00 UTC',
        resolvedAddress: 'Sonar Kella Apartment, Kolkata',
        creatorId: 'inspector-123',
      );

      final payload = PendingCapturePayload(
        mediaId: 'capture-replace-1',
        mediaType: MediaItemType.photo,
        originalFilePath: 'media/orig_replace.jpg',
        evidenceFilePath: 'media/evid_replace.jpg',
        thumbnailFilePath: 'media/thumb_replace.jpg',
        sha256Hash: 'hash-replace-1',
        fileSizeBytes: 100000,
        previewBytes: null,
        metadataSnapshot: snapshot,
      );

      await tester.pumpWidget(buildReviewScope(
        child: ReviewTagScreen(payload: payload),
      ));
      await tester.pumpAndSettle();

      // 1. Classify the capture as Closed; the nearest open NC (nc-wrong) is
      //    auto-suggested as the BEFORE reference.
      final activityField = find.byType(TextField).first;
      await tester.enterText(activityField, 'Excavation');
      await tester.pumpAndSettle();

      final closedChip = find.text('Closed');
      await tester.ensureVisible(closedChip);
      await tester.tap(closedChip);
      await tester.pumpAndSettle();

      expect(find.text('SMART-LINK SUGGESTION'), findsOneWidget);

      // 2. Select the WRONG photo as the pending closure reference.
      final selectWrong = find.text('Select as BEFORE');
      await tester.ensureVisible(selectWrong);
      await tester.tap(selectWrong);
      await tester.pumpAndSettle();
      expect(find.text('SELECTED BEFORE EVIDENCE'), findsOneWidget);

      final element = tester.element(find.byType(ReviewTagScreen));
      final container = ProviderScope.containerOf(element);
      expect(
          container.read(reviewTagControllerProvider).linkedMediaId, 'nc-wrong');

      // 3. Discard the pending closure selection: the selection is removed and
      //    eligible candidates are re-surfaced immediately for re-selection.
      final unlinkButton = find.text('Unlink');
      await tester.ensureVisible(unlinkButton);
      await tester.tap(unlinkButton);
      await tester.pumpAndSettle();

      expect(
          container.read(reviewTagControllerProvider).linkedMediaId, isNull);
      expect(container.read(reviewTagControllerProvider).isLinked, isFalse);
      expect(container.read(reviewTagControllerProvider).note,
          isNot(contains('Evid_ID')));
      expect(find.text('SMART-LINK SUGGESTION'), findsOneWidget);
      expect(find.text('Select as BEFORE'), findsOneWidget);
      expect(find.text('Link BEFORE to Save'), findsOneWidget);

      // 4. The discarded Non-Conformity evidence is untouched in the database.
      final wrongRow = await (db.select(db.media)
            ..where((tbl) => tbl.id.equals('nc-wrong')))
          .getSingle();
      expect(wrongRow.isDeleted, 0);
      expect(wrongRow.observationType, 'nonConformity');
      expect(wrongRow.linkedMediaId, isNull);

      // 5. Select the CORRECT closure reference (matches the 'Paving' activity).
      final activityField2 = find.byType(TextField).first;
      await tester.enterText(activityField2, 'Paving');
      await tester.pumpAndSettle();

      final selectCorrect = find.text('Select as BEFORE');
      await tester.ensureVisible(selectCorrect);
      await tester.tap(selectCorrect);
      await tester.pumpAndSettle();
      expect(
          container.read(reviewTagControllerProvider).linkedMediaId,
          'nc-correct');
      expect(container.read(reviewTagControllerProvider).isLinked, isTrue);

      // 6. Saving associates the CORRECT closure evidence with the Closed
      //    observation.
      final saveButton = find.text('Save Evidence');
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      final savedRow = await (db.select(db.media)
            ..where((tbl) => tbl.id.equals('capture-replace-1')))
          .getSingle();
      expect(savedRow.observationType, 'closed');
      expect(savedRow.linkedMediaId, 'nc-correct');
      expect(savedRow.note, contains('Evid_ID: nc-correct'));
      expect(savedRow.note, isNot(contains('nc-wrong')));

      // 7. Both Non-Conformity records remain persisted and unchanged.
      final wrongRowAfter = await (db.select(db.media)
            ..where((tbl) => tbl.id.equals('nc-wrong')))
          .getSingle();
      expect(wrongRowAfter.isDeleted, 0);
      expect(wrongRowAfter.observationType, 'nonConformity');
      expect(wrongRowAfter.linkedMediaId, isNull);

      final correctRowAfter = await (db.select(db.media)
            ..where((tbl) => tbl.id.equals('nc-correct')))
          .getSingle();
      expect(correctRowAfter.isDeleted, 0);
      expect(correctRowAfter.observationType, 'nonConformity');
      expect(correctRowAfter.linkedMediaId, isNull);
    });
  });
}
