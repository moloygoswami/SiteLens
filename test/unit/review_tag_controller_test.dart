import 'dart:ffi';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/features/camera/models/evidence_metadata_snapshot.dart';
import 'package:sitelens/features/camera/models/processed_evidence_payload.dart';
import 'package:sitelens/features/camera/services/evidence_storage_service.dart';
import 'package:sitelens/features/review/controllers/review_tag_controller.dart';
import 'package:sitelens/features/review/models/pending_capture_payload.dart';

class MockReviewStorageService extends EvidenceStorageService {
  final List<String> cleanedUpIds = [];

  @override
  Future<bool> verifyArtifactsExist({
    required String originalRelativePath,
    required String evidenceRelativePath,
    String? thumbnailRelativePath,
  }) async {
    return true;
  }

  @override
  Future<void> cleanupPartialArtifacts(String mediaId) async {
    cleanedUpIds.add(mediaId);
  }

  @override
  Future<String> resolveAbsolutePath(String relativePath) async {
    return '/mock/path/$relativePath';
  }
}

void main() {
  late AppDatabase db;
  late MediaRepository mediaRepo;
  late MockReviewStorageService mockStorage;
  late ReviewTagNotifier notifier;

  setUpAll(() {
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    mediaRepo = LocalMediaRepository(db);
    mockStorage = MockReviewStorageService();
    notifier = ReviewTagNotifier(db, mediaRepo, mockStorage);

    // Insert Site
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

  group('ReviewTagController Unit Tests', () {
    final testSnapshot = EvidenceMetadataSnapshot(
      mediaId: 'pending-photo-123',
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
      creatorId: 'user-field-inspector-123',
    );

    final photoPayload = ProcessedEvidencePayload(
      isSuccess: true,
      mediaId: 'pending-photo-123',
      originalFilePath: 'media/orig_pending-photo-123.jpg',
      evidenceFilePath: 'media/evid_pending-photo-123.jpg',
      thumbnailFilePath: 'media/thumb_pending-photo-123.jpg',
      originalSha256: 'hash1234567890',
      evidenceSha256: 'evid_hash_9876543210',
      originalFileSizeBytes: 300000,
      metadataSnapshot: testSnapshot,
    );

    final pendingPayload = PendingCapturePayload(
      mediaId: 'pending-photo-123',
      mediaType: MediaItemType.photo,
      originalFilePath: 'media/orig_pending-photo-123.jpg',
      evidenceFilePath: 'media/evid_pending-photo-123.jpg',
      thumbnailFilePath: 'media/thumb_pending-photo-123.jpg',
      sha256Hash: 'hash1234567890',
      fileSizeBytes: 300000,
      metadataSnapshot: testSnapshot,
      photoPayload: photoPayload,
    );

    test('Initial state defaults to general observation and empty tags', () {
      expect(notifier.state.observationType, ObservationType.general);
      expect(notifier.state.activityTag, '');
      expect(notifier.state.note, '');
      expect(notifier.state.linkedMediaId, isNull);
    });

    test('Selecting Closed triggers smart-link search and links candidate', () async {
      // Seed a nearby Non-Conformity item
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'before-nc-item',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_nc.jpg'),
              uri: 'media/evid_nc.jpg',
              lat: 22.56298,
              lon: 88.30085,
              activityTag: const drift.Value('Rebar Inspection'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-14T04:00:00Z',
            ),
          );

      await notifier.setActivityTag('Rebar Inspection', pendingPayload);
      await notifier.setObservationType(ObservationType.closed, pendingPayload);

      expect(notifier.state.suggestedBeforeMatch, isNotNull);
      expect(notifier.state.suggestedBeforeMatch!.id, 'before-nc-item');
      expect(notifier.state.isLinked, isFalse);

      // Link candidate
      notifier.linkSuggestedMatch();
      expect(notifier.state.isLinked, isTrue);
      expect(notifier.state.linkedMediaId, 'before-nc-item');

      // Unlink candidate
      notifier.unlinkSuggestedMatch();
      expect(notifier.state.isLinked, isFalse);
      expect(notifier.state.linkedMediaId, isNull);
    });

    test('Save commits MediaItem with tags and smart-link into Drift SQLite and persists forensic fields', () async {
      await notifier.setActivityTag('Excavation Stage 1', pendingPayload);
      await notifier.setObservationType(ObservationType.progress, pendingPayload);
      notifier.setNote('Verified excavation depth meets design specifications');

      final savedItem = await notifier.saveEvidence(pendingPayload);

      expect(savedItem, isNotNull);
      expect(savedItem!.id, 'pending-photo-123');
      expect(savedItem.activityTag, 'Excavation Stage 1');
      expect(savedItem.observationType, ObservationType.progress);
      expect(savedItem.note, 'Verified excavation depth meets design specifications');
      expect(savedItem.syncStatus, SyncStatusType.pending);
      expect(savedItem.creatorId, 'user-field-inspector-123');
      expect(savedItem.capturedAddress, 'Sonar Kella Apartment, Kolkata');
      expect(savedItem.sha256Hash, 'hash1234567890');
      expect(savedItem.evidenceSha256Hash, 'evid_hash_9876543210');
      // Explicitly prove photo original and evidence hashes remain distinct
      expect(savedItem.sha256Hash, isNot(equals(savedItem.evidenceSha256Hash)));

      // Verify row in SQLite
      final dbRow = await (db.select(db.media)..where((tbl) => tbl.id.equals('pending-photo-123'))).getSingle();
      expect(dbRow.id, 'pending-photo-123');
      expect(dbRow.activityTag, 'Excavation Stage 1');
      expect(dbRow.observationType, 'progress');
      expect(dbRow.note, 'Verified excavation depth meets design specifications');
      expect(dbRow.creatorId, 'user-field-inspector-123');
      expect(dbRow.capturedAddress, 'Sonar Kella Apartment, Kolkata');
      expect(dbRow.sha256Hash, 'hash1234567890');
      expect(dbRow.evidenceSha256Hash, 'evid_hash_9876543210');
      expect(dbRow.sha256Hash, isNot(equals(dbRow.evidenceSha256Hash)));

      // Verify Creator Isolation: queried by owner vs non-owner
      final ownerItems = await mediaRepo.getPendingOrFailedMedia(creatorId: 'user-field-inspector-123');
      expect(ownerItems.any((item) => item.id == 'pending-photo-123'), isTrue);

      final otherUserItems = await mediaRepo.getPendingOrFailedMedia(creatorId: 'different-user-456');
      expect(otherUserItems.any((item) => item.id == 'pending-photo-123'), isFalse);
    });

    test('Video capture correctly persists evidenceSha256Hash matching authoritative video SHA-256', () async {
      const knownVideoHash = 'video_auth_sha256_0123456789abcdef0123456789abcdef0123456789abcdef';
      final videoSnapshot = EvidenceMetadataSnapshot(
        mediaId: 'pending-video-456',
        siteId: 'SITE_001',
        siteCode: 'HOME',
        siteName: 'Sonar Kella Apartment',
        latitude: 22.56298,
        longitude: 88.30085,
        altitudeMeters: 18.4,
        accuracyMeters: 4.2,
        lowAccuracy: false,
        capturedAtUtc: DateTime.utc(2026, 8, 15, 4, 30, 0),
        canonicalTimestampUtc: '2026-08-15 04:30:00 UTC',
        resolvedAddress: 'Sonar Kella Apartment, Kolkata',
        creatorId: 'user-field-inspector-123',
      );

      final videoPendingPayload = PendingCapturePayload(
        mediaId: 'pending-video-456',
        mediaType: MediaItemType.video,
        originalFilePath: 'media/orig_pending-video-456.mp4',
        evidenceFilePath: 'media/orig_pending-video-456.mp4',
        thumbnailFilePath: 'media/thumb_pending-video-456.jpg',
        sha256Hash: knownVideoHash,
        fileSizeBytes: 5000000,
        videoDuration: const Duration(seconds: 15),
        metadataSnapshot: videoSnapshot,
        photoPayload: null, // Video has no photoPayload
      );

      final savedVideo = await notifier.saveEvidence(videoPendingPayload);

      expect(savedVideo, isNotNull);
      expect(savedVideo!.id, 'pending-video-456');
      expect(savedVideo.type, MediaItemType.video);
      expect(savedVideo.sha256Hash, equals(knownVideoHash));
      expect(savedVideo.evidenceSha256Hash, equals(knownVideoHash));
      expect(savedVideo.creatorId, equals('user-field-inspector-123'));
      expect(savedVideo.capturedAddress, equals('Sonar Kella Apartment, Kolkata'));

      // Verify row in SQLite
      final dbRow = await (db.select(db.media)..where((tbl) => tbl.id.equals('pending-video-456'))).getSingle();
      expect(dbRow.id, 'pending-video-456');
      expect(dbRow.type, 'video');
      expect(dbRow.sha256Hash, equals(knownVideoHash));
      expect(dbRow.evidenceSha256Hash, equals(knownVideoHash));
      expect(dbRow.creatorId, equals('user-field-inspector-123'));
      expect(dbRow.capturedAddress, equals('Sonar Kella Apartment, Kolkata'));
    });

    test('Closed observation without linked candidate is strictly BLOCKED from saving', () async {
      await notifier.setObservationType(ObservationType.closed, pendingPayload);

      // Attempt to save without linking
      final result = await notifier.saveEvidence(pendingPayload);

      expect(result, isNull);
      expect(notifier.state.errorMessage, contains('A Closed observation requires linking'));

      // Confirm zero rows created in DB
      final rows = await (db.select(db.media)..where((tbl) => tbl.id.equals('pending-photo-123'))).get();
      expect(rows.isEmpty, isTrue);
    });

    test('Closed observation with linked candidate saves successfully', () async {
      // Seed a nearby open Non-Conformity
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'before-nc-item-2',
              siteId: const drift.Value('SITE_001'),
              originalUri: const drift.Value('media/orig_nc2.jpg'),
              uri: 'media/evid_nc2.jpg',
              lat: 22.56298,
              lon: 88.30085,
              activityTag: const drift.Value('Rebar'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-14T04:00:00Z',
            ),
          );

      await notifier.setActivityTag('Rebar', pendingPayload);
      await notifier.setObservationType(ObservationType.closed, pendingPayload);
      notifier.linkSuggestedMatch();

      final result = await notifier.saveEvidence(pendingPayload);

      expect(result, isNotNull);
      expect(result!.observationType, ObservationType.closed);
      expect(result.linkedMediaId, 'before-nc-item-2');
    });

    test('Dismissing suggestion keeps saving blocked, switching type allows saving', () async {
      await notifier.setObservationType(ObservationType.closed, pendingPayload);
      notifier.dismissSuggestedMatch();

      // Saving blocked under Closed
      var result = await notifier.saveEvidence(pendingPayload);
      expect(result, isNull);

      // Switching to Material allows saving
      await notifier.setObservationType(ObservationType.material, pendingPayload);
      result = await notifier.saveEvidence(pendingPayload);
      expect(result, isNotNull);
      expect(result!.observationType, ObservationType.material);
    });

    test('Retake calls partial artifact cleanup without creating database row', () async {
      await notifier.retake(pendingPayload);

      expect(mockStorage.cleanedUpIds, contains('pending-photo-123'));

      // Confirm no database row exists
      final rows = await (db.select(db.media)..where((tbl) => tbl.id.equals('pending-photo-123'))).get();
      expect(rows.isEmpty, isTrue);
    });

    test('clearErrorMessage properly clears error on copyWith and when switching observation types', () async {
      notifier.state = notifier.state.copyWith(errorMessage: 'Initial error');
      expect(notifier.state.errorMessage, 'Initial error');

      // Regular copyWith preserves errorMessage
      notifier.state = notifier.state.copyWith(note: 'Updated note');
      expect(notifier.state.errorMessage, 'Initial error');

      // clearErrorMessage clears it
      notifier.state = notifier.state.copyWith(clearErrorMessage: true);
      expect(notifier.state.errorMessage, isNull);

      // Switching observation type clears error message
      notifier.state = notifier.state.copyWith(errorMessage: 'Another error');
      await notifier.setObservationType(ObservationType.material, pendingPayload);
      expect(notifier.state.errorMessage, isNull);
    });
  });
}
