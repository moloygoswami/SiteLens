import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/media_repository.dart';
import '../../domain/models/enums.dart';
import '../../features/camera/services/evidence_storage_service.dart';
import '../models/storage_cleanup_models.dart';
import 'auth_service.dart';

final storageCleanupServiceProvider = Provider<StorageCleanupService>((ref) {
  final mediaRepo = ref.watch(mediaRepositoryProvider);
  final storageService = ref.watch(evidenceStorageServiceProvider);
  String? creatorId;
  try {
    final authUser = ref.watch(authStateProvider).value;
    creatorId = authUser?.uid;
  } catch (_) {
    creatorId = null;
  }
  return StorageCleanupService(
    mediaRepo,
    storageService,
    creatorId: creatorId,
  );
});

class StorageCleanupService {
  final MediaRepository _mediaRepo;
  final EvidenceStorageService _storageService;
  final String? _creatorId;

  StorageCleanupService(
    this._mediaRepo,
    this._storageService, {
    String? creatorId,
  }) : _creatorId = creatorId;

  /// Computes the current storage summary and reclaimable bytes from eligible synced photo originals.
  Future<StorageCleanupSummary> getCleanupSummary({
    Set<String>? activeSyncingIds,
    String? creatorId,
  }) async {
    final effectiveUid = creatorId ?? _creatorId;
    if (effectiveUid == null || effectiveUid.isEmpty) {
      return const StorageCleanupSummary(
        eligiblePhotosCount: 0,
        reclaimableBytes: 0,
        totalPhotosCount: 0,
        totalVideosCount: 0,
        syncedPhotosCount: 0,
      );
    }

    final allEntries = await _mediaRepo.getAllMediaEntriesIncludingDeleted(creatorId: effectiveUid);

    int totalPhotos = 0;
    int totalVideos = 0;
    int syncedPhotos = 0;
    int eligiblePhotos = 0;
    int reclaimableBytes = 0;

    for (final item in allEntries) {
      if (item.type == MediaItemType.video) {
        totalVideos++;
        continue;
      }

      totalPhotos++;
      if (item.syncStatus == SyncStatusType.synced) {
        syncedPhotos++;

        // Exclude active syncing items
        if (activeSyncingIds != null && activeSyncingIds.contains(item.id)) {
          continue;
        }

        // Check if original exists on disk
        final origPath = await _storageService.resolveAbsolutePath(item.originalUri);
        final origFile = File(origPath);
        if (!await origFile.exists()) {
          continue;
        }

        // Check if evidence file exists and is non-empty
        final evidPath = await _storageService.resolveAbsolutePath(item.uri);
        final evidFile = File(evidPath);
        if (!await evidFile.exists()) {
          continue;
        }

        final evidLength = await evidFile.length();
        if (evidLength <= 0) {
          continue;
        }

        eligiblePhotos++;
        reclaimableBytes += await origFile.length();
      }
    }

    return StorageCleanupSummary(
      eligiblePhotosCount: eligiblePhotos,
      reclaimableBytes: reclaimableBytes,
      totalPhotosCount: totalPhotos,
      totalVideosCount: totalVideos,
      syncedPhotosCount: syncedPhotos,
    );
  }

  /// Safely deletes local raw original photo files (`orig_*.jpg`) for eligible synced photos.
  /// Strictly enforces all safe deletion preconditions and preserves all evidence, thumbnails,
  /// video files, and database records.
  Future<StorageCleanupResult> clearSyncedPhotoOriginals({
    Set<String>? activeSyncingIds,
    String? creatorId,
  }) async {
    final effectiveUid = creatorId ?? _creatorId;
    if (effectiveUid == null || effectiveUid.isEmpty) {
      return const StorageCleanupResult(
        eligibleCount: 0,
        successfullyDeletedCount: 0,
        skippedCount: 0,
        failedCount: 0,
        bytesReclaimed: 0,
      );
    }

    final candidates = await _mediaRepo.getSyncedPhotos(creatorId: effectiveUid);

    int eligible = 0;
    int deleted = 0;
    int skipped = 0;
    int failed = 0;
    int bytesReclaimed = 0;

    for (final item in candidates) {
      // 1. Invariant: Strictly exclude videos
      if (item.type != MediaItemType.photo) {
        skipped++;
        continue;
      }

      // 2. Invariant: Strictly require synced status
      if (item.syncStatus != SyncStatusType.synced) {
        skipped++;
        continue;
      }

      // 3. Invariant: Exclude in-flight syncing items
      if (activeSyncingIds != null && activeSyncingIds.contains(item.id)) {
        skipped++;
        continue;
      }

      // 4. Resolve absolute paths
      final origAbsPath = await _storageService.resolveAbsolutePath(item.originalUri);
      final evidAbsPath = await _storageService.resolveAbsolutePath(item.uri);

      final origFile = File(origAbsPath);
      final evidFile = File(evidAbsPath);

      // 5. If original is already missing, treat as already cleared (idempotent)
      if (!await origFile.exists()) {
        skipped++;
        continue;
      }

      // 6. Evidence file MUST exist
      if (!await evidFile.exists()) {
        skipped++;
        continue;
      }

      // 7. Evidence file MUST be non-empty (> 0 bytes)
      final evidSize = await evidFile.length();
      if (evidSize <= 0) {
        skipped++;
        continue;
      }

      // Candidate is valid and eligible
      eligible++;
      final origSize = await origFile.length();

      try {
        await origFile.delete();
        deleted++;
        bytesReclaimed += origSize;
      } catch (_) {
        failed++;
      }
    }

    return StorageCleanupResult(
      eligibleCount: eligible,
      successfullyDeletedCount: deleted,
      skippedCount: skipped,
      failedCount: failed,
      bytesReclaimed: bytesReclaimed,
    );
  }
}
