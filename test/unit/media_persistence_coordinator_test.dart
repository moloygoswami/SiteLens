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
import 'package:sitelens/features/camera/models/processed_evidence_payload.dart';
import 'package:sitelens/features/camera/services/evidence_storage_service.dart';
import 'package:sitelens/features/camera/services/media_persistence_coordinator.dart';
import 'package:sitelens/features/review/controllers/review_tag_controller.dart';
import 'package:sitelens/features/review/models/pending_capture_payload.dart';

class MockEvidenceStorageService extends EvidenceStorageService {
  final Map<String, bool> fileExistsMap = {};
  final List<String> cleanedUpMediaIds = [];
  final List<String> deletedMediaIds = [];
  final List<String> deletedOriginalPaths = [];
  bool forceVerificationFailure = false;

  @override
  Future<void> deleteOriginalMedia(String relativePath) async {
    deletedOriginalPaths.add(relativePath);
    fileExistsMap.remove(relativePath);
  }

  @override
  Future<bool> verifyArtifactsExist({
    required String originalRelativePath,
    required String evidenceRelativePath,
    String? thumbnailRelativePath,
  }) async {
    if (forceVerificationFailure) return false;
    final thumbValid = thumbnailRelativePath == null || (fileExistsMap[thumbnailRelativePath] ?? true);
    return (fileExistsMap[originalRelativePath] ?? true) &&
        (fileExistsMap[evidenceRelativePath] ?? true) &&
        thumbValid;
  }

  @override
  Future<void> cleanupPartialArtifacts(String mediaId) async {
    cleanedUpMediaIds.add(mediaId);
    fileExistsMap.remove('media/evid_$mediaId.jpg');
    fileExistsMap.remove('media/thumb_$mediaId.jpg');
  }

  @override
  Future<void> deleteLocalMediaFiles({
    required String mediaId,
    String? originalUri,
    String? uri,
    String? thumbUri,
    String? type,
  }) async {
    deletedMediaIds.add(mediaId);
  }
}

class FailingInsertMediaRepository implements MediaRepository {
  @override
  Future<void> insertMedia(MediaItem item) async {
    throw Exception('Simulated SQLite insert failure');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  late MediaRepository mediaRepo;
  late MockEvidenceStorageService mockStorage;
  late MediaPersistenceCoordinator coordinator;

  setUpAll(() {
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    mediaRepo = LocalMediaRepository(db);
    mockStorage = MockEvidenceStorageService();
    coordinator = MediaPersistenceCoordinator(db, mediaRepo, mockStorage);

    // Insert valid Site in database
    await db.into(db.sites).insert(
          SitesCompanion.insert(
            id: 'SITE_001',
            siteCode: const drift.Value('HOME'),
            name: const drift.Value('Sonar Kella Apartment'),
            address: const drift.Value('New Town, Kolkata'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  group('MediaPersistenceCoordinator Unit Tests', () {
    final validSnapshot = EvidenceMetadataSnapshot(
      mediaId: 'test-media-uuid-1',
      siteId: 'SITE_001',
      siteCode: 'HOME',
      siteName: 'Sonar Kella Apartment',
      latitude: 22.56298,
      longitude: 88.30085,
      altitudeMeters: -43.4,
      accuracyMeters: 7.6,
      lowAccuracy: false,
      capturedAtUtc: DateTime.utc(2026, 8, 15, 2, 24, 55),
      canonicalTimestampUtc: '2026-08-15 02:24:55 UTC',
      resolvedAddress: 'Sonar Kella Apartment, Kolkata',
    );

    final validPayload = ProcessedEvidencePayload(
      isSuccess: true,
      mediaId: 'test-media-uuid-1',
      originalFilePath: 'media/orig_test-media-uuid-1.jpg',
      evidenceFilePath: 'media/evid_test-media-uuid-1.jpg',
      thumbnailFilePath: 'media/thumb_test-media-uuid-1.jpg',
      originalSha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      evidenceSha256: '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08',
      originalFileSizeBytes: 500000,
      evidenceFileSizeBytes: 520000,
      thumbnailFileSizeBytes: 15000,
      thumbnailWidth: 200,
      thumbnailHeight: 150,
      metadataSnapshot: validSnapshot,
    );

    test('Successfully persists valid capture payload into Drift database', () async {
      final item = await coordinator.persistCapturedEvidence(validPayload);

      expect(item.id, 'test-media-uuid-1');
      expect(item.siteId, 'SITE_001');
      expect(item.originalUri, 'media/orig_test-media-uuid-1.jpg');
      expect(item.uri, 'media/evid_test-media-uuid-1.jpg');
      expect(item.thumbUri, 'media/thumb_test-media-uuid-1.jpg');
      expect(item.lat, 22.56298);
      expect(item.lon, 88.30085);
      expect(item.sha256Hash, 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(item.capturedAddress, 'Sonar Kella Apartment, Kolkata');

      // Verify row in SQLite
      final dbRow = await (db.select(db.media)..where((tbl) => tbl.id.equals('test-media-uuid-1'))).getSingle();
      expect(dbRow.id, 'test-media-uuid-1');
      expect(dbRow.originalUri, 'media/orig_test-media-uuid-1.jpg');
      expect(dbRow.uri, 'media/evid_test-media-uuid-1.jpg');
      expect(dbRow.thumbUri, 'media/thumb_test-media-uuid-1.jpg');
      expect(dbRow.siteId, 'SITE_001');
      expect(dbRow.capturedAddress, 'Sonar Kella Apartment, Kolkata');
    });

    test('Fails explicitly and throws SiteAssociationException when site does not exist', () async {
      final invalidSiteSnapshot = EvidenceMetadataSnapshot(
        mediaId: 'test-media-uuid-2',
        siteId: 'NON_EXISTENT_SITE',
        siteCode: 'GHOST',
        siteName: 'Ghost Site',
        latitude: 22.0,
        longitude: 88.0,
        lowAccuracy: false,
        capturedAtUtc: DateTime.utc(2026, 8, 15, 2, 0, 0),
        canonicalTimestampUtc: '2026-08-15 02:00:00 UTC',
        resolvedAddress: 'Ghost Address',
      );

      final invalidPayload = ProcessedEvidencePayload(
        isSuccess: true,
        mediaId: 'test-media-uuid-2',
        originalFilePath: 'media/orig_test-media-uuid-2.jpg',
        evidenceFilePath: 'media/evid_test-media-uuid-2.jpg',
        thumbnailFilePath: 'media/thumb_test-media-uuid-2.jpg',
        originalSha256: 'hash1',
        originalFileSizeBytes: 100,
        metadataSnapshot: invalidSiteSnapshot,
      );

      await expectLater(
        () => coordinator.persistCapturedEvidence(invalidPayload),
        throwsA(isA<SiteAssociationException>()),
      );

      // Verify no DB record was inserted
      final count = await (db.select(db.media)..where((tbl) => tbl.id.equals('test-media-uuid-2'))).get();
      expect(count.isEmpty, isTrue);
    });

    test('Duplicate identical mediaId succeeds idempotently without creating duplicate rows', () async {
      // First insert
      await coordinator.persistCapturedEvidence(validPayload);

      // Second identical insert
      final secondItem = await coordinator.persistCapturedEvidence(validPayload);
      expect(secondItem.id, validPayload.mediaId);

      final rows = await (db.select(db.media)..where((tbl) => tbl.id.equals(validPayload.mediaId))).get();
      expect(rows.length, 1);
    });

    test('Duplicate conflicting mediaId throws MediaConflictException (Integrity error)', () async {
      await coordinator.persistCapturedEvidence(validPayload);

      // Conflicting payload with same ID but different hash
      final conflictingPayload = ProcessedEvidencePayload(
        isSuccess: true,
        mediaId: validPayload.mediaId,
        originalFilePath: validPayload.originalFilePath,
        evidenceFilePath: validPayload.evidenceFilePath,
        thumbnailFilePath: validPayload.thumbnailFilePath,
        originalSha256: 'DIFFERENT_CONFLICTING_HASH',
        originalFileSizeBytes: 200,
        metadataSnapshot: validSnapshot,
      );

      await expectLater(
        () => coordinator.persistCapturedEvidence(conflictingPayload),
        throwsA(isA<MediaPersistenceException>()),
      );
    });

    test('Cleans up derived artifacts and preserves original when file verification fails', () async {
      mockStorage.forceVerificationFailure = true;

      await expectLater(
        () => coordinator.persistCapturedEvidence(validPayload),
        throwsA(isA<MediaPersistenceException>()),
      );

      expect(mockStorage.cleanedUpMediaIds, contains(validPayload.mediaId));
    });

    test('persistCapturedEvidence throws MediaPersistenceException when GPS is invalid or (0,0)', () async {
      final invalidGpsSnapshot = EvidenceMetadataSnapshot(
        mediaId: 'invalid-gps-uuid',
        siteId: 'SITE_001',
        siteCode: 'HOME',
        siteName: 'Sonar Kella Apartment',
        latitude: 0.0,
        longitude: 0.0,
        altitudeMeters: 0.0,
        accuracyMeters: 5.0,
        lowAccuracy: false,
        capturedAtUtc: DateTime.utc(2026, 8, 15, 2, 24, 55),
        canonicalTimestampUtc: '2026-08-15 02:24:55 UTC',
        resolvedAddress: 'Somewhere',
      );
      final invalidPayload = ProcessedEvidencePayload(
        isSuccess: true,
        mediaId: 'invalid-gps-uuid',
        originalFilePath: 'media/orig_invalid.jpg',
        evidenceFilePath: 'media/evid_invalid.jpg',
        thumbnailFilePath: 'media/thumb_invalid.jpg',
        originalSha256: 'HASH',
        originalFileSizeBytes: 1024,
        metadataSnapshot: invalidGpsSnapshot,
      );

      await expectLater(
        () => coordinator.persistCapturedEvidence(invalidPayload),
        throwsA(isA<MediaPersistenceException>()),
      );
    });
  });

  group('MediaPersistenceCoordinator keepForLater (R1 — interrupted recordings)', () {
    final interruptedSnapshot = EvidenceMetadataSnapshot(
      mediaId: 'interrupted-video-1',
      siteId: 'SITE_001',
      siteCode: 'HOME',
      siteName: 'Sonar Kella Apartment',
      latitude: 22.56298,
      longitude: 88.30085,
      altitudeMeters: 18.4,
      accuracyMeters: 3.8,
      lowAccuracy: false,
      capturedAtUtc: DateTime.utc(2026, 8, 21, 6, 30, 0),
      canonicalTimestampUtc: '2026-08-21 06:30:00 UTC',
      resolvedAddress: 'Sonar Kella Apartment, Kolkata',
      creatorId: 'user-42',
    );

    final interruptedPayload = PendingCapturePayload(
      mediaId: 'interrupted-video-1',
      mediaType: MediaItemType.video,
      originalFilePath: 'media/orig_interrupted-video-1.mp4',
      evidenceFilePath: 'media/orig_interrupted-video-1.mp4',
      thumbnailFilePath: 'media/thumb_interrupted-video-1.jpg',
      sha256Hash: 'aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d',
      fileSizeBytes: 2048,
      videoDuration: const Duration(seconds: 12),
      metadataSnapshot: interruptedSnapshot,
    );

    test('Persists the interrupted recording as a video MediaItem with correct metadata', () async {
      final item = await coordinator.keepForLater(interruptedPayload);

      expect(item.id, 'interrupted-video-1');
      expect(item.type, MediaItemType.video);
      expect(item.uri, 'media/orig_interrupted-video-1.mp4');
      expect(item.originalUri, 'media/orig_interrupted-video-1.mp4');
      expect(item.thumbUri, 'media/thumb_interrupted-video-1.jpg');
      expect(item.syncStatus, SyncStatusType.pending);
      expect(item.isDeleted, isFalse);
      expect(item.sha256Hash, 'aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d');
      expect(item.evidenceSha256Hash, 'aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d');
      expect(item.lat, 22.56298);
      expect(item.lon, 88.30085);
      expect(item.accuracyM, 3.8);
      expect(item.capturedAddress, 'Sonar Kella Apartment, Kolkata');
      expect(item.creatorId, 'user-42');

      // The row is queryable through the repository (the gallery's data source).
      final viaRepo = await mediaRepo.getMediaById('interrupted-video-1');
      expect(viaRepo, isNotNull);
      expect(viaRepo!.type, MediaItemType.video);
      expect(viaRepo.syncStatus, SyncStatusType.pending);
    });

    test('Keep for later media is discoverable through the gallery stream', () async {
      await coordinator.keepForLater(interruptedPayload);

      final watch = await mediaRepo.watchAllMedia(siteId: 'SITE_001', creatorId: 'user-42').first;
      expect(watch.any((m) => m.id == 'interrupted-video-1'), isTrue);
      final inGallery = watch.firstWhere((m) => m.id == 'interrupted-video-1');
      expect(inGallery.type, MediaItemType.video);
      expect(inGallery.isDeleted, isFalse);
    });

    test('Throws MediaPersistenceException on persistence failure and leaves no row', () async {
      // Same id but different hash → conflict path surfaces as a persistence failure.
      final conflicting = PendingCapturePayload(
        mediaId: 'interrupted-video-1',
        mediaType: MediaItemType.video,
        originalFilePath: 'media/orig_interrupted-video-1.mp4',
        evidenceFilePath: 'media/orig_interrupted-video-1.mp4',
        thumbnailFilePath: null,
        sha256Hash: 'DIFFERENT_CONFLICTING_HASH',
        fileSizeBytes: 2048,
        metadataSnapshot: interruptedSnapshot,
      );

      await coordinator.keepForLater(interruptedPayload);
      await expectLater(
        () => coordinator.keepForLater(conflicting),
        throwsA(isA<MediaPersistenceException>()),
      );

      // Only the original row remains — the failure did not fabricate a second one.
      final rows = await (db.select(db.media)..where((tbl) => tbl.id.equals('interrupted-video-1'))).get();
      expect(rows.length, 1);
    });

    test('keepForLater fails when physical file verification fails', () async {
      mockStorage.forceVerificationFailure = true;

      await expectLater(
        () => coordinator.keepForLater(interruptedPayload),
        throwsA(isA<MediaPersistenceException>()),
      );
    });

    test('persistPendingCapture successfully commits valid pending payload with tags and notes', () async {
      final item = await coordinator.persistPendingCapture(
        interruptedPayload,
        activityTag: 'Foundation Inspection',
        observationType: ObservationType.progress,
        note: 'Poured foundation curing as expected',
      );

      expect(item.id, 'interrupted-video-1');
      expect(item.activityTag, 'Foundation Inspection');
      expect(item.observationType, ObservationType.progress);
      expect(item.note, 'Poured foundation curing as expected');

      final persisted = await mediaRepo.getMediaById('interrupted-video-1');
      expect(persisted, isNotNull);
      expect(persisted!.activityTag, 'Foundation Inspection');
    });

    test('persistPendingCapture throws SiteAssociationException when site does not exist', () async {
      final invalidSiteSnapshot = EvidenceMetadataSnapshot(
        mediaId: 'invalid-site-media',
        siteId: 'NON_EXISTENT_SITE',
        siteCode: 'NONE',
        siteName: 'Nowhere',
        latitude: 22.5,
        longitude: 88.3,
        accuracyMeters: 5.0,
        lowAccuracy: false,
        capturedAtUtc: DateTime.now().toUtc(),
        canonicalTimestampUtc: '2026-08-25 00:00:00 UTC',
        resolvedAddress: 'Nowhere Address',
        creatorId: 'user-test',
      );

      final invalidSitePayload = PendingCapturePayload(
        mediaId: 'invalid-site-media',
        mediaType: MediaItemType.photo,
        originalFilePath: 'media/orig_invalid.jpg',
        evidenceFilePath: 'media/evid_invalid.jpg',
        thumbnailFilePath: 'media/thumb_invalid.jpg',
        sha256Hash: 'HASH',
        fileSizeBytes: 1024,
        metadataSnapshot: invalidSiteSnapshot,
      );

      await expectLater(
        () => coordinator.persistPendingCapture(invalidSitePayload),
        throwsA(isA<SiteAssociationException>()),
      );
    });

    test('persistPendingCapture throws MediaPersistenceException when linkedMediaId is non-existent', () async {
      await expectLater(
        () => coordinator.persistPendingCapture(
          interruptedPayload,
          linkedMediaId: 'NON_EXISTENT_BEFORE_ID',
        ),
        throwsA(isA<MediaPersistenceException>()),
      );
    });

    test('persistPendingCapture cleans up capture artifacts when DB transaction fails (video)', () async {
      final failingCoordinator = MediaPersistenceCoordinator(
        db,
        FailingInsertMediaRepository(),
        mockStorage,
      );

      await expectLater(
        () => failingCoordinator.persistPendingCapture(interruptedPayload),
        throwsA(isA<MediaPersistenceException>()),
      );

      expect(mockStorage.deletedMediaIds, contains(interruptedPayload.mediaId));
    });

    test('F1: persistPendingCapture for photo preserves original camera JPEG and cleans only derived artifacts on DB failure', () async {
      final photoSnapshot = EvidenceMetadataSnapshot(
        mediaId: 'photo-db-fail-1',
        siteId: 'SITE_001',
        siteCode: 'HOME',
        siteName: 'Sonar Kella Apartment',
        latitude: 22.5629,
        longitude: 88.3008,
        accuracyMeters: 3.5,
        lowAccuracy: false,
        capturedAtUtc: DateTime.utc(2026, 8, 15, 10, 0, 0),
        canonicalTimestampUtc: '2026-08-15 10:00:00 UTC',
        resolvedAddress: 'Site Address',
        creatorId: 'user-audit-1',
      );

      final photoPayload = PendingCapturePayload(
        mediaId: 'photo-db-fail-1',
        mediaType: MediaItemType.photo,
        originalFilePath: 'media/orig_photo-db-fail-1.jpg',
        evidenceFilePath: 'media/evid_photo-db-fail-1.jpg',
        thumbnailFilePath: 'media/thumb_photo-db-fail-1.jpg',
        sha256Hash: 'HASH_ORIG_IMMUTABLE',
        fileSizeBytes: 2048,
        metadataSnapshot: photoSnapshot,
      );

      // Seed all three artifacts in mock storage
      mockStorage.fileExistsMap['media/orig_photo-db-fail-1.jpg'] = true;
      mockStorage.fileExistsMap['media/evid_photo-db-fail-1.jpg'] = true;
      mockStorage.fileExistsMap['media/thumb_photo-db-fail-1.jpg'] = true;

      final failingCoordinator = MediaPersistenceCoordinator(
        db,
        FailingInsertMediaRepository(),
        mockStorage,
      );

      await expectLater(
        () => failingCoordinator.persistPendingCapture(photoPayload),
        throwsA(isA<MediaPersistenceException>()),
      );

      // 1. Derived artifacts are cleaned up
      expect(mockStorage.cleanedUpMediaIds, contains(photoPayload.mediaId));
      expect(mockStorage.fileExistsMap['media/evid_photo-db-fail-1.jpg'], isNull);
      expect(mockStorage.fileExistsMap['media/thumb_photo-db-fail-1.jpg'], isNull);

      // 2. The original camera JPEG MUST NEVER be deleted because of DB transaction failure
      expect(mockStorage.deletedMediaIds, isNot(contains(photoPayload.mediaId)));
      expect(mockStorage.fileExistsMap['media/orig_photo-db-fail-1.jpg'], isTrue);
    });

    test('F1: ReviewTagNotifier.retake explicitly cleans up both original and derived artifacts on retake', () async {
      final photoSnapshot = EvidenceMetadataSnapshot(
        mediaId: 'photo-retake-1',
        siteId: 'SITE_001',
        siteCode: 'HOME',
        siteName: 'Sonar Kella Apartment',
        latitude: 22.5629,
        longitude: 88.3008,
        accuracyMeters: 3.5,
        lowAccuracy: false,
        capturedAtUtc: DateTime.utc(2026, 8, 15, 10, 0, 0),
        canonicalTimestampUtc: '2026-08-15 10:00:00 UTC',
        resolvedAddress: 'Site Address',
        creatorId: 'user-audit-1',
      );

      final photoPayload = PendingCapturePayload(
        mediaId: 'photo-retake-1',
        mediaType: MediaItemType.photo,
        originalFilePath: 'media/orig_photo-retake-1.jpg',
        evidenceFilePath: 'media/evid_photo-retake-1.jpg',
        thumbnailFilePath: 'media/thumb_photo-retake-1.jpg',
        sha256Hash: 'HASH_ORIG_IMMUTABLE',
        fileSizeBytes: 2048,
        metadataSnapshot: photoSnapshot,
      );

      mockStorage.fileExistsMap['media/orig_photo-retake-1.jpg'] = true;
      mockStorage.fileExistsMap['media/evid_photo-retake-1.jpg'] = true;
      mockStorage.fileExistsMap['media/thumb_photo-retake-1.jpg'] = true;

      final reviewNotifier = ReviewTagNotifier(
        db,
        mediaRepo,
        mockStorage,
        persistenceCoordinator: coordinator,
      );

      await reviewNotifier.retake(photoPayload);

      // Retake intentionally deletes both derived and original files
      expect(mockStorage.cleanedUpMediaIds, contains('photo-retake-1'));
      expect(mockStorage.deletedOriginalPaths, contains('media/orig_photo-retake-1.jpg'));
    });

    test('persistPendingCapture throws MediaPersistenceException when GPS coordinates are invalid or (0,0)', () async {
      final invalidGpsSnapshot = EvidenceMetadataSnapshot(
        mediaId: interruptedSnapshot.mediaId,
        siteId: interruptedSnapshot.siteId,
        siteCode: interruptedSnapshot.siteCode,
        siteName: interruptedSnapshot.siteName,
        latitude: 0.0,
        longitude: 0.0,
        altitudeMeters: 0.0,
        accuracyMeters: 5.0,
        lowAccuracy: false,
        capturedAtUtc: interruptedSnapshot.capturedAtUtc,
        canonicalTimestampUtc: interruptedSnapshot.canonicalTimestampUtc,
        resolvedAddress: 'Somewhere',
      );
      final invalidGpsPayload = interruptedPayload.copyWith(
        metadataSnapshot: invalidGpsSnapshot,
      );

      await expectLater(
        () => coordinator.persistPendingCapture(invalidGpsPayload),
        throwsA(isA<MediaPersistenceException>()),
      );
    });

    test('keepForLater throws MediaPersistenceException when GPS coordinates are invalid or (0,0)', () async {
      final invalidGpsSnapshot = EvidenceMetadataSnapshot(
        mediaId: interruptedSnapshot.mediaId,
        siteId: interruptedSnapshot.siteId,
        siteCode: interruptedSnapshot.siteCode,
        siteName: interruptedSnapshot.siteName,
        latitude: 0.0,
        longitude: 0.0,
        altitudeMeters: 0.0,
        accuracyMeters: 5.0,
        lowAccuracy: false,
        capturedAtUtc: interruptedSnapshot.capturedAtUtc,
        canonicalTimestampUtc: interruptedSnapshot.canonicalTimestampUtc,
        resolvedAddress: 'Somewhere',
      );
      final invalidGpsPayload = interruptedPayload.copyWith(
        metadataSnapshot: invalidGpsSnapshot,
      );

      await expectLater(
        () => coordinator.keepForLater(invalidGpsPayload),
        throwsA(isA<MediaPersistenceException>()),
      );
    });

    test('keepForLater cleans up capture artifacts when DB transaction fails', () async {
      final failingCoordinator = MediaPersistenceCoordinator(
        db,
        FailingInsertMediaRepository(),
        mockStorage,
      );

      await expectLater(
        () => failingCoordinator.keepForLater(interruptedPayload),
        throwsA(isA<MediaPersistenceException>()),
      );

      expect(mockStorage.deletedMediaIds, contains(interruptedPayload.mediaId));
    });
  });

  group('B-1 Tombstone Discovery (LocalMediaRepository)', () {
    Future<void> seedRow({
      required String id,
      required SyncStatusType status,
      required bool deleted,
      String creatorId = 'user-1',
    }) {
      return mediaRepo.insertMedia(MediaItem(
        id: id,
        siteId: 'SITE_001',
        originalUri: 'media/orig_$id.jpg',
        uri: 'media/evid_$id.jpg',
        type: MediaItemType.photo,
        lat: 22.5,
        lon: 88.3,
        capturedAt: DateTime.utc(2026, 9, 10),
        creatorId: creatorId,
        syncStatus: status,
        isDeleted: deleted,
      ));
    }

    test('Discovers deleted rows that are not mid-sync and scopes them strictly to the creator', () async {
      await seedRow(id: 'm-synced-del', status: SyncStatusType.synced, deleted: true);
      await seedRow(id: 'm-failed-del', status: SyncStatusType.failed, deleted: true);
      await seedRow(id: 'm-pending-del', status: SyncStatusType.pending, deleted: true);
      await seedRow(id: 'm-syncing-del', status: SyncStatusType.syncing, deleted: true);
      await seedRow(id: 'm-synced-live', status: SyncStatusType.synced, deleted: false);
      await seedRow(id: 'm-other-creator', status: SyncStatusType.synced, deleted: true, creatorId: 'user-2');

      // Fail closed: an unauthenticated session (null/empty creatorId) must never
      // surface another user's tombstones (R04).
      expect(await mediaRepo.getTombstoneSyncCandidates(), isEmpty);
      expect(await mediaRepo.getTombstoneSyncCandidates(creatorId: ''), isEmpty);

      // Creator scoping: the active session only sees its own tombstones.
      final scoped = await mediaRepo.getTombstoneSyncCandidates(creatorId: 'user-1');
      expect(scoped.length, 3);
      expect(scoped.map((i) => i.id), containsAll([
        'm-synced-del',
        'm-failed-del',
        'm-pending-del',
      ]));
      expect(scoped.map((i) => i.id), isNot(contains('m-syncing-del')));
      expect(scoped.map((i) => i.id), isNot(contains('m-synced-live')));
      expect(scoped.map((i) => i.id), isNot(contains('m-other-creator')));

      // The count stream is creator-scoped and fails closed without a UID.
      expect(await mediaRepo.watchTombstoneCandidateCount(creatorId: 'user-1').first, 3);
      expect(await mediaRepo.watchTombstoneCandidateCount(creatorId: null).first, 0);
      expect(await mediaRepo.watchTombstoneCandidateCount(creatorId: '').first, 0);
    });

    test('C-2: deletePermanently keeps a hidden tombstone row instead of destroying it (deferred cloud propagation)', () async {
      await seedRow(id: 'm-pending-del', status: SyncStatusType.pending, deleted: false);
      await seedRow(id: 'm-failed-del', status: SyncStatusType.failed, deleted: false);

      await mediaRepo.deletePermanently('m-pending-del');
      await mediaRepo.deletePermanently('m-failed-del');

      // Rows survive as hidden tombstones so the B-1 pipeline can always
      // reconcile the cloud ledger (or verify it never existed). Physical row
      // removal would strand an already-published ledger as live forever.
      final pendingRow = await mediaRepo.getMediaById('m-pending-del');
      expect(pendingRow, isNotNull);
      expect(pendingRow!.isDeleted, isTrue);
      expect(pendingRow.syncStatus, SyncStatusType.pending);

      final failedRow = await mediaRepo.getMediaById('m-failed-del');
      expect(failedRow, isNotNull);
      expect(failedRow!.isDeleted, isTrue);
      expect(failedRow.syncStatus, SyncStatusType.failed);

      // Both are discoverable by the tombstone synchronization.
      final candidates = await mediaRepo.getTombstoneSyncCandidates(creatorId: 'user-1');
      expect(candidates.map((i) => i.id), containsAll(['m-pending-del', 'm-failed-del']));

      // The user-facing gallery no longer surfaces them.
      final visible = await mediaRepo.watchAllMedia(creatorId: 'user-1').first;
      expect(visible.map((i) => i.id), isNot(contains('m-pending-del')));
      expect(visible.map((i) => i.id), isNot(contains('m-failed-del')));
    });
  });
}
