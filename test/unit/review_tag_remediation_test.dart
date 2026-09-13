import 'dart:ffi';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';

import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/features/camera/models/evidence_metadata_snapshot.dart';
import 'package:sitelens/features/camera/services/evidence_storage_service.dart';
import 'package:sitelens/features/camera/services/media_persistence_coordinator.dart';
import 'package:sitelens/features/review/controllers/review_tag_controller.dart';
import 'package:sitelens/features/review/models/pending_capture_payload.dart';

class MockStorageService extends EvidenceStorageService {
  final List<String> cleanedUpIds = [];

  @override
  Future<bool> verifyArtifactsExist({
    required String originalRelativePath,
    required String evidenceRelativePath,
    String? thumbnailRelativePath,
  }) async =>
      true;

  @override
  Future<void> cleanupPartialArtifacts(String mediaId) async {
    cleanedUpIds.add(mediaId);
  }

  @override
  Future<String> resolveAbsolutePath(String relativePath) async =>
      '/mock/path/$relativePath';
}

void main() {
  late AppDatabase db;
  late MediaRepository mediaRepo;
  late MockStorageService mockStorage;
  late MediaPersistenceCoordinator persistenceCoordinator;
  late ReviewTagNotifier notifier;

  setUpAll(() {
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    mediaRepo = LocalMediaRepository(db);
    mockStorage = MockStorageService();
    persistenceCoordinator = MediaPersistenceCoordinator(db, mediaRepo, mockStorage);
    notifier = ReviewTagNotifier(
      db,
      mediaRepo,
      mockStorage,
      persistenceCoordinator: persistenceCoordinator,
    );

    // Seed primary sites
    await db.into(db.sites).insert(
          SitesCompanion.insert(
            id: 'SITE_001',
            siteCode: const drift.Value('HOME'),
            name: const drift.Value('Sonar Kella Apartment'),
          ),
        );
    await db.into(db.sites).insert(
          SitesCompanion.insert(
            id: 'SITE_002',
            siteCode: const drift.Value('AWAY'),
            name: const drift.Value('Away Site Tower B'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  final testSnapshot = EvidenceMetadataSnapshot(
    mediaId: 'test-pending-media',
    siteId: 'SITE_001',
    siteCode: 'HOME',
    siteName: 'Sonar Kella Apartment',
    latitude: 22.56298,
    longitude: 88.30085,
    altitudeMeters: 18.4,
    accuracyMeters: 3.5,
    lowAccuracy: false,
    capturedAtUtc: DateTime.utc(2026, 8, 15, 10, 0, 0),
    canonicalTimestampUtc: '2026-08-15 10:00:00 UTC',
    resolvedAddress: 'Kolkata, WB',
    creatorId: 'inspector-current-uid',
  );

  final testPayload = PendingCapturePayload(
    mediaId: 'test-pending-media',
    mediaType: MediaItemType.photo,
    originalFilePath: 'media/orig_test.jpg',
    evidenceFilePath: 'media/evid_test.jpg',
    thumbnailFilePath: 'media/thumb_test.jpg',
    sha256Hash: 'dummy_sha256_hash_value',
    fileSizeBytes: 120000,
    metadataSnapshot: testSnapshot,
  );

  group('F1: Smart-Link Suggestion Dismissal (non-destructive)', () {
    test('dismissSuggestedMatch clears only the suggestion and preserves an established link and user notes', () async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'nc-candidate-1',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_nc1.jpg'),
              uri: 'media/evid_nc1.jpg',
              lat: 22.56298,
              lon: 88.30085,
              activityTag: const drift.Value('Excavation'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-14T04:00:00Z',
              creatorId: const drift.Value('inspector-current-uid'),
            ),
          );

      notifier.setNote('Inspector manual remark');
      await notifier.setActivityTag('Excavation', testPayload);
      await notifier.setObservationType(ObservationType.closed, testPayload);

      expect(notifier.state.suggestedBeforeMatch, isNotNull);
      notifier.linkSuggestedMatch();
      expect(notifier.state.isLinked, isTrue);
      expect(notifier.state.linkedMediaId, 'nc-candidate-1');
      expect(notifier.state.note, contains('Evid_ID: nc-candidate-1'));
      expect(notifier.state.note, contains('Inspector manual remark'));

      // A refreshed search re-surfaces a suggestion while the link stays established
      await notifier.searchSmartLink(testPayload);
      expect(notifier.state.suggestedBeforeMatch, isNotNull);
      expect(notifier.state.linkedMediaId, 'nc-candidate-1');
      expect(notifier.state.isLinked, isTrue);

      // Dismissing the suggestion must never affect the established link
      notifier.dismissSuggestedMatch();

      expect(notifier.state.suggestedBeforeMatch, isNull);
      expect(notifier.state.linkedMediaId, 'nc-candidate-1');
      expect(notifier.state.isLinked, isTrue);
      expect(notifier.state.note, contains('Evid_ID: nc-candidate-1'));
      expect(notifier.state.note, contains('Inspector manual remark'));
    });
  });

  group('F2: Candidate Consistency — existing link survives new suggestions', () {
    test('Linked A -> search returns B -> A link survives, B is only a suggestion, save persists A', () async {
      // Seed Candidate A (Rebar) and Candidate B (Concrete)
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'candidate-A',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_A.jpg'),
              uri: 'media/evid_A.jpg',
              lat: 22.56298,
              lon: 88.30085,
              activityTag: const drift.Value('Rebar'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-14T04:00:00Z',
              creatorId: const drift.Value('inspector-current-uid'),
            ),
          );
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'candidate-B',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_B.jpg'),
              uri: 'media/evid_B.jpg',
              lat: 22.56298,
              lon: 88.30085,
              activityTag: const drift.Value('Concrete'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-14T05:00:00Z',
              creatorId: const drift.Value('inspector-current-uid'),
            ),
          );

      // 1. Link candidate A explicitly
      await notifier.setActivityTag('Rebar', testPayload);
      await notifier.setObservationType(ObservationType.closed, testPayload);
      notifier.linkSuggestedMatch();

      expect(notifier.state.linkedCandidate!.id, 'candidate-A');
      expect(notifier.state.linkedMediaId, 'candidate-A');
      expect(notifier.state.isLinked, isTrue);
      expect(notifier.state.note, contains('Evid_ID: candidate-A'));

      // 2. Activity edit discovers candidate B
      await notifier.setActivityTag('Concrete', testPayload);

      // The established B -> A relationship must remain intact; B is only a suggestion
      expect(notifier.state.suggestedBeforeMatch!.id, 'candidate-B');
      expect(notifier.state.linkedCandidate!.id, 'candidate-A');
      expect(notifier.state.linkedMediaId, 'candidate-A');
      expect(notifier.state.isLinked, isTrue);
      expect(notifier.state.note, contains('Evid_ID: candidate-A'));

      // 3. Save persists the established link A, never the suggestion B
      final saved = await notifier.saveEvidence(testPayload);
      expect(saved, isNotNull);
      expect(saved!.linkedMediaId, 'candidate-A');
      expect(saved.note, contains('Evid_ID: candidate-A'));

      final row = await (db.select(db.media)..where((tbl) => tbl.id.equals(testPayload.mediaId))).getSingle();
      expect(row.linkedMediaId, 'candidate-A');
      expect(row.note, contains('Evid_ID: candidate-A'));
      expect(row.note, isNot(contains('candidate-B')));

      // 4. Explicitly linking B replaces A (explicit user action)
      notifier.linkSuggestedMatch();
      expect(notifier.state.linkedMediaId, 'candidate-B');
      expect(notifier.state.linkedCandidate!.id, 'candidate-B');
      expect(notifier.state.isLinked, isTrue);
      expect(notifier.state.note, contains('Evid_ID: candidate-B'));
      expect(notifier.state.note, isNot(contains('candidate-A')));
    });

    test('Defensive guard: save refuses a link that is not represented by a linked candidate without destroying it', () async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'cand-B',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_b.jpg'),
              uri: 'media/evid_b.jpg',
              lat: 22.56298,
              lon: 88.30085,
              activityTag: const drift.Value('Steel'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-14T05:00:00Z',
              creatorId: const drift.Value('inspector-current-uid'),
            ),
          );

      final candB = await mediaRepo.getMediaById('cand-B');
      // Artificially inject an unrepresented link (no linkedCandidate)
      notifier.state = notifier.state.copyWith(
        observationType: ObservationType.closed,
        suggestedBeforeMatch: candB,
        linkedMediaId: 'cand-A-diverged',
        note: 'Evid_ID: cand-A-diverged',
      );

      // isLinked must report false because the link has no represented candidate
      expect(notifier.state.isLinked, isFalse);

      // saveEvidence must refuse WITHOUT destroying the link or mutating the note
      final result = await notifier.saveEvidence(testPayload);
      expect(result, isNull);
      expect(notifier.state.linkedMediaId, 'cand-A-diverged');
      expect(notifier.state.note, contains('cand-A-diverged'));
    });
  });

  group('F3: Evid_ID / Link Invariant (link -> search no match -> save)', () {
    test('Controller path: link -> search no match -> link and Evid_ID survive; explicit type switch clears', () async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'candidate-valid',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_v.jpg'),
              uri: 'media/evid_v.jpg',
              lat: 22.56298,
              lon: 88.30085,
              activityTag: const drift.Value('Paving'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-14T05:00:00Z',
              creatorId: const drift.Value('inspector-current-uid'),
            ),
          );

      notifier.setNote('Inspectors authentic field note text');
      await notifier.setActivityTag('Paving', testPayload);
      await notifier.setObservationType(ObservationType.closed, testPayload);
      notifier.linkSuggestedMatch();

      expect(notifier.state.isLinked, isTrue);
      expect(notifier.state.note, contains('Evid_ID: candidate-valid'));
      expect(notifier.state.note, contains('Inspectors authentic field note text'));

      // Candidate becomes resolved/deleted, so search returns no match
      await (db.update(db.media)..where((tbl) => tbl.id.equals('candidate-valid')))
          .write(const MediaCompanion(isDeleted: drift.Value(1)));

      await notifier.searchSmartLink(testPayload);

      // A search miss clears only the suggestion; the established link and its
      // Evid_ID survive and user notes are preserved.
      expect(notifier.state.suggestedBeforeMatch, isNull);
      expect(notifier.state.linkedMediaId, 'candidate-valid');
      expect(notifier.state.isLinked, isTrue);
      expect(notifier.state.note, contains('Evid_ID: candidate-valid'));
      expect(notifier.state.note, contains('Inspectors authentic field note text'));

      // Explicitly switching observation type removes the relationship
      await notifier.setObservationType(ObservationType.general, testPayload);
      expect(notifier.state.linkedMediaId, isNull);
      expect(notifier.state.note, isNot(contains('Evid_ID')));

      final saved = await notifier.saveEvidence(testPayload);
      expect(saved, isNotNull);
      expect(saved!.linkedMediaId, isNull);
      expect(saved.note, equals('Inspectors authentic field note text'));

      final row = await (db.select(db.media)..where((tbl) => tbl.id.equals(testPayload.mediaId))).getSingle();
      expect(row.linkedMediaId, isNull);
      expect(row.note, equals('Inspectors authentic field note text'));
    });

    test('Persistence boundary: MediaPersistenceCoordinator cleanses non-Closed or unlinked Evid_ID lines', () async {
      // Directly persist with observationType: general, linkedMediaId: null, but note containing leaked Evid_ID
      final saved = await persistenceCoordinator.persistPendingCapture(
        testPayload,
        activityTag: 'Audit',
        observationType: ObservationType.general,
        linkedMediaId: null,
        note: 'Evid_ID: rogue-id-123\nAuthentic general note',
      );

      expect(saved.linkedMediaId, isNull);
      expect(saved.note, equals('Authentic general note'));
      expect(saved.note, isNot(contains('rogue-id-123')));

      final row = await (db.select(db.media)..where((tbl) => tbl.id.equals(testPayload.mediaId))).getSingle();
      expect(row.linkedMediaId, isNull);
      expect(row.note, equals('Authentic general note'));
    });

    test('Persistence boundary: MediaRepository.insertMedia enforces ClosedEvidenceIntegrity', () async {
      final directItem = MediaItem(
        id: 'direct-repo-item',
        siteId: 'SITE_001',
        originalUri: 'media/orig_direct.jpg',
        uri: 'media/evid_direct.jpg',
        type: MediaItemType.photo,
        lat: 22.56298,
        lon: 88.30085,
        activityTag: 'Inspection',
        observationType: ObservationType.material,
        linkedMediaId: null,
        note: 'Evid_ID: residual-item-999\nMaterial verified on truck',
        capturedAt: DateTime.utc(2026, 8, 15, 10, 0, 0),
      );

      await mediaRepo.insertMedia(directItem);

      final row = await (db.select(db.media)..where((tbl) => tbl.id.equals('direct-repo-item'))).getSingle();
      expect(row.linkedMediaId, isNull);
      expect(row.note, equals('Material verified on truck'));
      expect(row.note, isNot(contains('residual-item-999')));
    });
  });

  group('F5: Creator and Site Isolation', () {
    test('Auto Smart-Link rejects candidate from another user (cross-user isolation)', () async {
      // Seed candidate owned by another inspector
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'other-user-nc',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_other.jpg'),
              uri: 'media/evid_other.jpg',
              lat: 22.56298,
              lon: 88.30085,
              activityTag: const drift.Value('Masonry'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-14T05:00:00Z',
              creatorId: const drift.Value('another-inspector-uid'),
            ),
          );

      // Search with testPayload (creatorId is 'inspector-current-uid')
      await notifier.setActivityTag('Masonry', testPayload);
      await notifier.setObservationType(ObservationType.closed, testPayload);

      expect(notifier.state.suggestedBeforeMatch, isNull);
      expect(notifier.state.isLinked, isFalse);
    });

    test('Auto Smart-Link rejects candidate from another site even if same creator', () async {
      // Seed candidate on SITE_002
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'other-site-nc',
              siteId: const drift.Value('SITE_002'),
              originalUri: const drift.Value('media/orig_site2.jpg'),
              uri: 'media/evid_site2.jpg',
              lat: 22.56298,
              lon: 88.30085,
              activityTag: const drift.Value('Carpentry'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-14T05:00:00Z',
              creatorId: const drift.Value('inspector-current-uid'),
            ),
          );

      await notifier.setActivityTag('Carpentry', testPayload);
      await notifier.setObservationType(ObservationType.closed, testPayload);

      expect(notifier.state.suggestedBeforeMatch, isNull);
      expect(notifier.state.isLinked, isFalse);
    });

    test('Persistence boundary: persistPendingCapture throws MediaPersistenceException on cross-user candidate', () async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'cross-user-candidate',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_cross.jpg'),
              uri: 'media/evid_cross.jpg',
              lat: 22.56298,
              lon: 88.30085,
              activityTag: const drift.Value('Roofing'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-14T05:00:00Z',
              creatorId: const drift.Value('rival-inspector-uid'),
            ),
          );

      expect(
        () => persistenceCoordinator.persistPendingCapture(
          testPayload,
          activityTag: 'Roofing',
          observationType: ObservationType.closed,
          linkedMediaId: 'cross-user-candidate',
        ),
        throwsA(
          isA<MediaPersistenceException>().having(
            (e) => e.message,
            'message',
            contains('belongs to another creator'),
          ),
        ),
      );
    });

    test('Persistence boundary: persistPendingCapture throws MediaPersistenceException on cross-site candidate', () async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'cross-site-candidate',
              siteId: const drift.Value('SITE_002'),
              originalUri: const drift.Value('media/orig_cross_site.jpg'),
              uri: 'media/evid_cross_site.jpg',
              lat: 22.56298,
              lon: 88.30085,
              activityTag: const drift.Value('Roofing'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-14T05:00:00Z',
              creatorId: const drift.Value('inspector-current-uid'),
            ),
          );

      expect(
        () => persistenceCoordinator.persistPendingCapture(
          testPayload,
          activityTag: 'Roofing',
          observationType: ObservationType.closed,
          linkedMediaId: 'cross-site-candidate',
        ),
        throwsA(
          isA<MediaPersistenceException>().having(
            (e) => e.message,
            'message',
            contains('belongs to another site'),
          ),
        ),
      );
    });

    test('Repository boundary: linkMedia throws MediaPersistenceException on cross-user candidate', () async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'user1-closed-item',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_u1.jpg'),
              uri: 'media/evid_u1.jpg',
              lat: 22.56298,
              lon: 88.30085,
              observationType: const drift.Value('closed'),
              capturedAt: '2026-08-15T05:00:00Z',
              creatorId: const drift.Value('user-1'),
            ),
          );

      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'user2-nc-item',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_u2.jpg'),
              uri: 'media/evid_u2.jpg',
              lat: 22.56298,
              lon: 88.30085,
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-14T05:00:00Z',
              creatorId: const drift.Value('user-2'),
            ),
          );

      expect(
        () => mediaRepo.linkMedia(mediaId: 'user1-closed-item', linkedMediaId: 'user2-nc-item'),
        throwsA(
          isA<MediaPersistenceException>().having(
            (e) => e.message,
            'message',
            contains('Creator isolation violation'),
          ),
        ),
      );
    });

    test('Repository boundary: updateTags throws MediaPersistenceException on cross-user candidate', () async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'user1-item-to-update',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_u1_up.jpg'),
              uri: 'media/evid_u1_up.jpg',
              lat: 22.56298,
              lon: 88.30085,
              observationType: const drift.Value('general'),
              capturedAt: '2026-08-15T05:00:00Z',
              creatorId: const drift.Value('user-1'),
            ),
          );

      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'user2-nc-target',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_u2_target.jpg'),
              uri: 'media/evid_u2_target.jpg',
              lat: 22.56298,
              lon: 88.30085,
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-14T05:00:00Z',
              creatorId: const drift.Value('user-2'),
            ),
          );

      expect(
        () => mediaRepo.updateTags(
          mediaId: 'user1-item-to-update',
          activityTag: 'Audit',
          observationType: ObservationType.closed,
          linkedMediaId: 'user2-nc-target',
        ),
        throwsA(
          isA<MediaPersistenceException>().having(
            (e) => e.message,
            'message',
            contains('Creator isolation violation'),
          ),
        ),
      );
    });
  });

  group('Non-Destructive Smart-Link Lifecycle (Test 5)', () {
    test('Saving B linked to A leaves A and B independently persisted and gallery-visible', () async {
      // Seed Non-Conformity A (the BEFORE evidence)
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'before-a',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_before_a.jpg'),
              uri: 'media/evid_before_a.jpg',
              lat: 22.56298,
              lon: 88.30085,
              activityTag: const drift.Value('Paving'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-14T05:00:00Z',
              creatorId: const drift.Value('inspector-current-uid'),
            ),
          );

      notifier.setNote('Inspector remark for B');
      await notifier.setActivityTag('Paving', testPayload);
      await notifier.setObservationType(ObservationType.closed, testPayload);
      notifier.linkSuggestedMatch();

      // Composition operations never mutate the persisted A record
      final aDuringCompose = await (db.select(db.media)
            ..where((tbl) => tbl.id.equals('before-a')))
          .getSingle();
      expect(aDuringCompose.isDeleted, 0);
      expect(aDuringCompose.observationType, 'nonConformity');
      expect(aDuringCompose.linkedMediaId, isNull);

      final saved = await notifier.saveEvidence(testPayload);
      expect(saved!.linkedMediaId, 'before-a');

      // Both records remain persisted and gallery-visible (isDeleted = 0)
      final galleryItems = await mediaRepo
          .watchAllMedia(siteId: 'SITE_001', creatorId: 'inspector-current-uid')
          .first;
      final galleryIds = galleryItems.map((m) => m.id).toSet();
      expect(galleryIds, containsAll(['before-a', testPayload.mediaId]));

      final aRow = await (db.select(db.media)
            ..where((tbl) => tbl.id.equals('before-a')))
          .getSingle();
      expect(aRow.isDeleted, 0);
      expect(aRow.observationType, 'nonConformity');
      expect(aRow.linkedMediaId, isNull);

      final bRow = await (db.select(db.media)
            ..where((tbl) => tbl.id.equals(testPayload.mediaId)))
          .getSingle();
      expect(bRow.isDeleted, 0);
      expect(bRow.observationType, 'closed');
      expect(bRow.linkedMediaId, 'before-a');
      expect(bRow.note, contains('Evid_ID: before-a'));
      expect(bRow.note, contains('Inspector remark for B'));
    });
  });
}
