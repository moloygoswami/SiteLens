import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitelens/core/services/storage_cleanup_service.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/features/camera/services/evidence_storage_service.dart';

class LocalTestEvidenceStorageService extends EvidenceStorageService {
  final Directory tempDir;
  LocalTestEvidenceStorageService(this.tempDir);

  @override
  Future<Directory> getBaseDirectory() async => tempDir;
}

class FakeMediaRepository implements MediaRepository {
  List<MediaItem> items = [];

  @override
  Future<List<MediaItem>> getAllMediaEntriesIncludingDeleted({String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) return [];
    return items.where((i) => i.creatorId == creatorId).toList();
  }

  @override
  Future<List<MediaItem>> getSyncedPhotos({String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) return [];
    return items
        .where((i) =>
            i.type == MediaItemType.photo &&
            i.syncStatus == SyncStatusType.synced &&
            i.creatorId == creatorId)
        .toList();
  }

  @override
  Future<void> insertMedia(MediaItem item, {String? creatorId}) async => items.add(item);

  @override
  Future<MediaItem?> getMediaById(String id, {String? creatorId}) async {
    try {
      final item = items.firstWhere((i) => i.id == id);
      if (creatorId != null && creatorId.isNotEmpty && item.creatorId != null && item.creatorId != creatorId) {
        return null;
      }
      return item;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<MediaItem>> searchMedia({required String query, String? siteId, String? creatorId}) async => [];

  @override
  Future<void> softDeleteMedia(String mediaId, {String? creatorId}) async {}

  @override
  Future<void> removeFromGallery(String mediaId, {String? creatorId}) async {}

  @override
  Future<void> deletePermanently(String mediaId, {String? creatorId}) async {}

  @override
  Future<Set<String>> getResolvedMediaIds({required String siteId, String? creatorId}) async => const {};

  @override
  Future<void> updateSyncStatus(String mediaId, SyncStatusType status, {String? creatorId}) async {}

  @override
  Future<void> markTombstoneReconciled(String mediaId, {String? creatorId}) async {}

  @override
  Future<void> updateTags({required String mediaId, required String activityTag, required ObservationType observationType, String? note, String? linkedMediaId, String? creatorId}) async {}

  @override
  Stream<List<MediaItem>> watchAllMedia({String? siteId, String? activity, ObservationType? observationType, bool? lowAccuracyOnly, String? creatorId}) =>
      Stream.value(items);

  @override
  Stream<int> watchUnsyncedCount({String? creatorId}) => Stream.value(0);

  @override
  Future<List<MediaItem>> getTombstoneSyncCandidates({String? creatorId}) async => const [];

  @override
  Stream<int> watchTombstoneCandidateCount({String? creatorId}) => const Stream<int>.empty();

  @override
  Future<MediaItem?> findSuggestedBeforeMatch({required double centerLat, required double centerLon, required String siteId, required String activityTag, required DateTime capturedBefore, double radiusMeters = 10.0, String? currentMediaId, String? creatorId, bool requireCreator = false}) async => null;

  @override
  Future<List<NearbyMediaResult>> findNearbyMedia({required double centerLat, required double centerLon, required double radiusMeters, String? siteId, String? activity, ObservationType? observationType, String? excludeMediaId, String? creatorId}) async => [];

  @override
  Future<List<MediaItem>> getPendingOrFailedMedia({String? creatorId}) async => [];

  @override
  Future<List<MediaItem>> getUnsyncedMedia({String? creatorId}) async => [];

  @override
  Future<void> linkMedia({required String mediaId, required String linkedMediaId, String? creatorId}) async {}

  @override
  Future<List<NearbyMediaResult>> findSiteWideCandidates({
    required double centerLat,
    required double centerLon,
    required String siteId,
    required DateTime capturedBefore,
    String? currentMediaId,
    String? creatorId,
  }) async => [];

  @override
  Future<void> resetStuckSyncingMedia({String? creatorId}) async {}

}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDir;
  late FakeMediaRepository fakeRepo;
  late LocalTestEvidenceStorageService storageService;
  late StorageCleanupService cleanupService;

  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('storage_cleanup_test_');

    fakeRepo = FakeMediaRepository();
    storageService = LocalTestEvidenceStorageService(testDir);
    cleanupService = StorageCleanupService(fakeRepo, storageService, creatorId: 'user-xyz');

    // Create media directory
    final mediaDir = Directory('${testDir.path}/media');
    await mediaDir.create(recursive: true);
  });

  tearDown(() async {
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }
  });

  Future<void> createDummyFile(String relativePath, {int bytes = 1024}) async {
    final file = File('${testDir.path}/$relativePath');
    await file.writeAsBytes(Uint8List(bytes), flush: true);
  }

  group('StorageCleanupService Eligibility Tests', () {
    test('1. Synced photo with valid non-empty evidence is eligible', () async {
      const mediaId = 'photo-1';
      await createDummyFile('media/orig_$mediaId.jpg', bytes: 2048);
      await createDummyFile('media/evid_$mediaId.jpg', bytes: 1024);

      fakeRepo.items = [
        MediaItem(
          id: mediaId,
          siteId: 'site-1',
          uri: 'media/evid_$mediaId.jpg',
          originalUri: 'media/orig_$mediaId.jpg',
          type: MediaItemType.photo,
          lat: 22.5,
          lon: 88.3,
          capturedAt: DateTime.utc(2026, 1, 1),
          syncStatus: SyncStatusType.synced,
          creatorId: 'user-xyz',
          sha256Hash: 'hash-orig',
          evidenceSha256Hash: 'hash-evid',
        ),
      ];

      final summary = await cleanupService.getCleanupSummary();
      expect(summary.eligiblePhotosCount, 1);
      expect(summary.reclaimableBytes, 2048);
      expect(summary.totalPhotosCount, 1);
      expect(summary.totalVideosCount, 0);
    });

    test('2. Pending photo is strictly excluded', () async {
      const mediaId = 'photo-pending';
      await createDummyFile('media/orig_$mediaId.jpg', bytes: 2048);
      await createDummyFile('media/evid_$mediaId.jpg', bytes: 1024);

      fakeRepo.items = [
        MediaItem(
          id: mediaId,
          siteId: 'site-1',
          uri: 'media/evid_$mediaId.jpg',
          originalUri: 'media/orig_$mediaId.jpg',
          type: MediaItemType.photo,
          lat: 22.5,
          lon: 88.3,
          capturedAt: DateTime.utc(2026, 1, 1),
          creatorId: 'user-xyz',
          syncStatus: SyncStatusType.pending,
        ),
      ];

      final summary = await cleanupService.getCleanupSummary();
      expect(summary.eligiblePhotosCount, 0);
      expect(summary.reclaimableBytes, 0);

      final result = await cleanupService.clearSyncedPhotoOriginals();
      expect(result.eligibleCount, 0);
      expect(result.successfullyDeletedCount, 0);
      expect(File('${testDir.path}/media/orig_$mediaId.jpg').existsSync(), isTrue);
    });

    test('3. Syncing photo (or active in-flight) is strictly excluded', () async {
      const mediaId = 'photo-syncing';
      await createDummyFile('media/orig_$mediaId.jpg', bytes: 2048);
      await createDummyFile('media/evid_$mediaId.jpg', bytes: 1024);

      fakeRepo.items = [
        MediaItem(
          id: mediaId,
          siteId: 'site-1',
          uri: 'media/evid_$mediaId.jpg',
          originalUri: 'media/orig_$mediaId.jpg',
          type: MediaItemType.photo,
          lat: 22.5,
          lon: 88.3,
          capturedAt: DateTime.utc(2026, 1, 1),
          creatorId: 'user-xyz',
          syncStatus: SyncStatusType.syncing,
        ),
      ];

      final summary = await cleanupService.getCleanupSummary();
      expect(summary.eligiblePhotosCount, 0);

      final result = await cleanupService.clearSyncedPhotoOriginals(activeSyncingIds: {mediaId});
      expect(result.eligibleCount, 0);
      expect(File('${testDir.path}/media/orig_$mediaId.jpg').existsSync(), isTrue);
    });

    test('4. Failed photo is strictly excluded', () async {
      const mediaId = 'photo-failed';
      await createDummyFile('media/orig_$mediaId.jpg', bytes: 2048);
      await createDummyFile('media/evid_$mediaId.jpg', bytes: 1024);

      fakeRepo.items = [
        MediaItem(
          id: mediaId,
          siteId: 'site-1',
          uri: 'media/evid_$mediaId.jpg',
          originalUri: 'media/orig_$mediaId.jpg',
          type: MediaItemType.photo,
          lat: 22.5,
          lon: 88.3,
          capturedAt: DateTime.utc(2026, 1, 1),
          creatorId: 'user-xyz',
          syncStatus: SyncStatusType.failed,
        ),
      ];

      final summary = await cleanupService.getCleanupSummary();
      expect(summary.eligiblePhotosCount, 0);
      expect(File('${testDir.path}/media/orig_$mediaId.jpg').existsSync(), isTrue);
    });

    test('5. Synced video is strictly excluded from cleanup', () async {
      const mediaId = 'video-synced';
      await createDummyFile('media/orig_$mediaId.mp4', bytes: 1024 * 1024);
      await createDummyFile('media/thumb_$mediaId.jpg', bytes: 512);

      fakeRepo.items = [
        MediaItem(
          id: mediaId,
          siteId: 'site-1',
          uri: 'media/orig_$mediaId.mp4',
          originalUri: 'media/orig_$mediaId.mp4',
          type: MediaItemType.video,
          lat: 22.5,
          lon: 88.3,
          capturedAt: DateTime.utc(2026, 1, 1),
          creatorId: 'user-xyz',
          syncStatus: SyncStatusType.synced,
        ),
      ];

      final summary = await cleanupService.getCleanupSummary();
      expect(summary.eligiblePhotosCount, 0);
      expect(summary.reclaimableBytes, 0);
      expect(summary.totalVideosCount, 1);

      final result = await cleanupService.clearSyncedPhotoOriginals();
      expect(result.eligibleCount, 0);
      expect(result.successfullyDeletedCount, 0);
      expect(File('${testDir.path}/media/orig_$mediaId.mp4').existsSync(), isTrue);
    });

    test('6. Synced photo with missing evidence is excluded (original protected)', () async {
      const mediaId = 'photo-no-evid';
      await createDummyFile('media/orig_$mediaId.jpg', bytes: 2048);
      // Notice: evid_*.jpg is NOT created on disk

      fakeRepo.items = [
        MediaItem(
          id: mediaId,
          siteId: 'site-1',
          uri: 'media/evid_$mediaId.jpg',
          originalUri: 'media/orig_$mediaId.jpg',
          type: MediaItemType.photo,
          lat: 22.5,
          lon: 88.3,
          capturedAt: DateTime.utc(2026, 1, 1),
          creatorId: 'user-xyz',
          syncStatus: SyncStatusType.synced,
        ),
      ];

      final summary = await cleanupService.getCleanupSummary();
      expect(summary.eligiblePhotosCount, 0);

      final result = await cleanupService.clearSyncedPhotoOriginals();
      expect(result.eligibleCount, 0);
      expect(result.successfullyDeletedCount, 0);
      expect(File('${testDir.path}/media/orig_$mediaId.jpg').existsSync(), isTrue);
    });

    test('7. Synced photo with zero-byte evidence is excluded (original protected)', () async {
      const mediaId = 'photo-corrupt-evid';
      await createDummyFile('media/orig_$mediaId.jpg', bytes: 2048);
      await createDummyFile('media/evid_$mediaId.jpg', bytes: 0); // 0-byte corrupt file

      fakeRepo.items = [
        MediaItem(
          id: mediaId,
          siteId: 'site-1',
          uri: 'media/evid_$mediaId.jpg',
          originalUri: 'media/orig_$mediaId.jpg',
          type: MediaItemType.photo,
          lat: 22.5,
          lon: 88.3,
          capturedAt: DateTime.utc(2026, 1, 1),
          creatorId: 'user-xyz',
          syncStatus: SyncStatusType.synced,
        ),
      ];

      final summary = await cleanupService.getCleanupSummary();
      expect(summary.eligiblePhotosCount, 0);

      final result = await cleanupService.clearSyncedPhotoOriginals();
      expect(result.eligibleCount, 0);
      expect(File('${testDir.path}/media/orig_$mediaId.jpg').existsSync(), isTrue);
    });

    test('8. Missing original file is safely treated as already cleared (idempotent)', () async {
      const mediaId = 'photo-already-cleared';
      // orig_*.jpg does not exist
      await createDummyFile('media/evid_$mediaId.jpg', bytes: 1024);

      fakeRepo.items = [
        MediaItem(
          id: mediaId,
          siteId: 'site-1',
          uri: 'media/evid_$mediaId.jpg',
          originalUri: 'media/orig_$mediaId.jpg',
          type: MediaItemType.photo,
          lat: 22.5,
          lon: 88.3,
          capturedAt: DateTime.utc(2026, 1, 1),
          creatorId: 'user-xyz',
          syncStatus: SyncStatusType.synced,
        ),
      ];

      final summary = await cleanupService.getCleanupSummary();
      expect(summary.eligiblePhotosCount, 0);

      final result = await cleanupService.clearSyncedPhotoOriginals();
      expect(result.eligibleCount, 0);
      expect(result.skippedCount, 1);
      expect(result.successfullyDeletedCount, 0);
    });
  });

  group('StorageCleanupService Physical Deletion & Forensic Invariants', () {
    test('9-14. Synced photo original is deleted while evidence, thumbnail, DB row, and forensic metadata remain intact', () async {
      const mediaId = 'photo-full-check';
      await createDummyFile('media/orig_$mediaId.jpg', bytes: 4096);
      await createDummyFile('media/evid_$mediaId.jpg', bytes: 2048);
      await createDummyFile('media/thumb_$mediaId.jpg', bytes: 512);

      final item = MediaItem(
        id: mediaId,
        siteId: 'site-101',
        uri: 'media/evid_$mediaId.jpg',
        originalUri: 'media/orig_$mediaId.jpg',
        thumbUri: 'media/thumb_$mediaId.jpg',
        type: MediaItemType.photo,
        lat: 22.5726,
        lon: 88.3639,
        accuracyM: 3.2,
        lowAccuracy: false,
        capturedAt: DateTime.utc(2026, 8, 18, 12, 0, 0),
        capturedAddress: 'Kolkata Sector V',
        creatorId: 'user-xyz',
        sha256Hash: 'hash-orig-abc',
        evidenceSha256Hash: 'hash-evid-xyz',
        syncStatus: SyncStatusType.synced,
        isDeleted: false,
      );

      fakeRepo.items = [item];

      final result = await cleanupService.clearSyncedPhotoOriginals();
      expect(result.eligibleCount, 1);
      expect(result.successfullyDeletedCount, 1);
      expect(result.bytesReclaimed, 4096);

      // 9. Original is physically deleted
      expect(File('${testDir.path}/media/orig_$mediaId.jpg').existsSync(), isFalse);

      // 10. Evidence physically remains
      expect(File('${testDir.path}/media/evid_$mediaId.jpg').existsSync(), isTrue);
      expect(File('${testDir.path}/media/evid_$mediaId.jpg').lengthSync(), 2048);

      // 11. Thumbnail physically remains
      expect(File('${testDir.path}/media/thumb_$mediaId.jpg').existsSync(), isTrue);
      expect(File('${testDir.path}/media/thumb_$mediaId.jpg').lengthSync(), 512);

      // 12. SQLite Media row remains in repository
      final dbItem = await fakeRepo.getMediaById(mediaId);
      expect(dbItem, isNotNull);

      // 13. Sync status remains synced
      expect(dbItem!.syncStatus, SyncStatusType.synced);

      // 14. Forensic fields remain untouched
      expect(dbItem.sha256Hash, 'hash-orig-abc');
      expect(dbItem.evidenceSha256Hash, 'hash-evid-xyz');
      expect(dbItem.capturedAddress, 'Kolkata Sector V');
      expect(dbItem.creatorId, 'user-xyz');
      expect(dbItem.lat, 22.5726);
      expect(dbItem.lon, 88.3639);
    });

    test('15-17. Cleanup operates completely locally without network, is idempotent, and preserves unrelated files', () async {
      const mediaId = 'photo-repeat';
      await createDummyFile('media/orig_$mediaId.jpg', bytes: 1024);
      await createDummyFile('media/evid_$mediaId.jpg', bytes: 1024);

      fakeRepo.items = [
        MediaItem(
          id: mediaId,
          siteId: 'site-1',
          uri: 'media/evid_$mediaId.jpg',
          originalUri: 'media/orig_$mediaId.jpg',
          type: MediaItemType.photo,
          lat: 22.5,
          lon: 88.3,
          capturedAt: DateTime.utc(2026, 1, 1),
          creatorId: 'user-xyz',
          syncStatus: SyncStatusType.synced,
        ),
      ];

      // First run: deletes original
      final result1 = await cleanupService.clearSyncedPhotoOriginals();
      expect(result1.successfullyDeletedCount, 1);
      expect(File('${testDir.path}/media/orig_$mediaId.jpg').existsSync(), isFalse);

      // Second run: idempotent, skips cleanly
      final result2 = await cleanupService.clearSyncedPhotoOriginals();
      expect(result2.successfullyDeletedCount, 0);
      expect(result2.skippedCount, 1);
      expect(File('${testDir.path}/media/evid_$mediaId.jpg').existsSync(), isTrue);
    });
  });

  group('StorageCleanupService Multi-User Isolation & Defense-in-Depth Tests', () {
    test('18. MUST DENY: User B cleanup does NOT delete User A local originals', () async {
      const photoA = 'photo-userA';
      await createDummyFile('media/orig_$photoA.jpg', bytes: 3072);
      await createDummyFile('media/evid_$photoA.jpg', bytes: 1024);

      fakeRepo.items = [
        MediaItem(
          id: photoA,
          siteId: 'site-1',
          uri: 'media/evid_$photoA.jpg',
          originalUri: 'media/orig_$photoA.jpg',
          type: MediaItemType.photo,
          lat: 22.5,
          lon: 88.3,
          capturedAt: DateTime.utc(2026, 1, 1),
          creatorId: 'user-A',
          syncStatus: SyncStatusType.synced,
        ),
      ];

      // User B session
      final userBCleanup = StorageCleanupService(fakeRepo, storageService, creatorId: 'user-B');

      // User B checks summary: 0 eligible
      final summary = await userBCleanup.getCleanupSummary();
      expect(summary.eligiblePhotosCount, 0);
      expect(summary.reclaimableBytes, 0);

      // User B triggers cleanup: 0 deleted
      final result = await userBCleanup.clearSyncedPhotoOriginals();
      expect(result.eligibleCount, 0);
      expect(result.successfullyDeletedCount, 0);

      // User A's raw original is untouched on disk
      expect(File('${testDir.path}/media/orig_$photoA.jpg').existsSync(), isTrue);
      expect(File('${testDir.path}/media/orig_$photoA.jpg').lengthSync(), 3072);
    });

    test('19. MUST FAIL CLOSED: Missing or null creatorId causes cleanup to return empty / no deletions', () async {
      const photoA = 'photo-userA-unauth';
      await createDummyFile('media/orig_$photoA.jpg', bytes: 3072);
      await createDummyFile('media/evid_$photoA.jpg', bytes: 1024);

      fakeRepo.items = [
        MediaItem(
          id: photoA,
          siteId: 'site-1',
          uri: 'media/evid_$photoA.jpg',
          originalUri: 'media/orig_$photoA.jpg',
          type: MediaItemType.photo,
          lat: 22.5,
          lon: 88.3,
          capturedAt: DateTime.utc(2026, 1, 1),
          creatorId: 'user-A',
          syncStatus: SyncStatusType.synced,
        ),
      ];

      // Unauthenticated / null creator cleanup
      final unauthCleanup = StorageCleanupService(fakeRepo, storageService, creatorId: null);

      final summary = await unauthCleanup.getCleanupSummary();
      expect(summary.eligiblePhotosCount, 0);
      expect(summary.reclaimableBytes, 0);

      final result = await unauthCleanup.clearSyncedPhotoOriginals();
      expect(result.eligibleCount, 0);
      expect(result.successfullyDeletedCount, 0);

      // Disk remains unchanged
      expect(File('${testDir.path}/media/orig_$photoA.jpg').existsSync(), isTrue);
    });

    test('20. MUST ALLOW: User A cleanup removes User A eligible originals and preserves User B originals', () async {
      const photoA = 'photo-A-mixed';
      const photoB = 'photo-B-mixed';

      await createDummyFile('media/orig_$photoA.jpg', bytes: 2048);
      await createDummyFile('media/evid_$photoA.jpg', bytes: 1024);

      await createDummyFile('media/orig_$photoB.jpg', bytes: 4096);
      await createDummyFile('media/evid_$photoB.jpg', bytes: 1024);

      fakeRepo.items = [
        MediaItem(
          id: photoA,
          siteId: 'site-1',
          uri: 'media/evid_$photoA.jpg',
          originalUri: 'media/orig_$photoA.jpg',
          type: MediaItemType.photo,
          lat: 22.5,
          lon: 88.3,
          capturedAt: DateTime.utc(2026, 1, 1),
          creatorId: 'user-A',
          syncStatus: SyncStatusType.synced,
        ),
        MediaItem(
          id: photoB,
          siteId: 'site-1',
          uri: 'media/evid_$photoB.jpg',
          originalUri: 'media/orig_$photoB.jpg',
          type: MediaItemType.photo,
          lat: 22.5,
          lon: 88.3,
          capturedAt: DateTime.utc(2026, 1, 1),
          creatorId: 'user-B',
          syncStatus: SyncStatusType.synced,
        ),
      ];

      // User A cleanup
      final userACleanup = StorageCleanupService(fakeRepo, storageService, creatorId: 'user-A');

      final summary = await userACleanup.getCleanupSummary();
      expect(summary.eligiblePhotosCount, 1);
      expect(summary.reclaimableBytes, 2048);

      final result = await userACleanup.clearSyncedPhotoOriginals();
      expect(result.eligibleCount, 1);
      expect(result.successfullyDeletedCount, 1);
      expect(result.bytesReclaimed, 2048);

      // User A original deleted
      expect(File('${testDir.path}/media/orig_$photoA.jpg').existsSync(), isFalse);
      // User B original strictly preserved
      expect(File('${testDir.path}/media/orig_$photoB.jpg').existsSync(), isTrue);
      expect(File('${testDir.path}/media/orig_$photoB.jpg').lengthSync(), 4096);
    });
  });
}
