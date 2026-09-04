import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/local/database/app_database.dart';
import '../../../data/local/database/database_provider.dart';
import '../../../data/repositories/media_repository.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/media_item.dart';
import '../../review/models/pending_capture_payload.dart';
import '../models/processed_evidence_payload.dart';
import 'evidence_storage_service.dart';

class SiteAssociationException implements Exception {
  final String message;
  SiteAssociationException(this.message);

  @override
  String toString() => 'SiteAssociationException: $message';
}

class MediaPersistenceException implements Exception {
  final String message;
  MediaPersistenceException(this.message);

  @override
  String toString() => 'MediaPersistenceException: $message';
}

final mediaPersistenceCoordinatorProvider = Provider<MediaPersistenceCoordinator>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final mediaRepo = ref.watch(mediaRepositoryProvider);
  final storageService = ref.watch(evidenceStorageServiceProvider);
  return MediaPersistenceCoordinator(db, mediaRepo, storageService);
});

class MediaPersistenceCoordinator {
  final AppDatabase _db;
  final MediaRepository _mediaRepo;
  final EvidenceStorageService _storageService;

  MediaPersistenceCoordinator(this._db, this._mediaRepo, this._storageService);

  /// Persists a ProcessedEvidencePayload into the Drift SQLite database with transactional consistency.
  Future<MediaItem> persistCapturedEvidence(ProcessedEvidencePayload payload) async {
    if (!payload.isSuccess ||
        payload.evidenceFilePath == null ||
        payload.thumbnailFilePath == null) {
      throw MediaPersistenceException(
        'Cannot persist failed or incomplete evidence payload: ${payload.errorMessage}',
      );
    }

    final siteId = payload.metadataSnapshot.siteId.trim();

    // 1. Phase 1: Site Existence Validation (Strict Foreign-Key check)
    if (siteId.isEmpty) {
      throw SiteAssociationException(
        'Persistence Error: Active Site ID is empty. Media record must be associated with a valid site.',
      );
    }

    final siteEntry = await (_db.select(_db.sites)..where((tbl) => tbl.id.equals(siteId))).getSingleOrNull();
    if (siteEntry == null) {
      throw SiteAssociationException(
        'Persistence Error: Site "$siteId" does not exist in local database. Strict foreign-key validation failed.',
      );
    }

    // 2. Phase 2: File Existence & Non-Zero Size Verification
    final filesVerified = await _storageService.verifyArtifactsExist(
      originalRelativePath: payload.originalFilePath,
      evidenceRelativePath: payload.evidenceFilePath!,
      thumbnailRelativePath: payload.thumbnailFilePath!,
    );

    if (!filesVerified) {
      await _storageService.cleanupPartialArtifacts(payload.mediaId);
      throw MediaPersistenceException(
        'Persistence Error: One or more evidence artifacts failed physical disk verification.',
      );
    }

    // 3. Phase 3: Construct Immutable MediaItem
    final mediaItem = MediaItem(
      id: payload.mediaId,
      siteId: siteId,
      originalUri: payload.originalFilePath,
      uri: payload.evidenceFilePath!,
      thumbUri: payload.thumbnailFilePath,
      type: MediaItemType.photo,
      lat: payload.metadataSnapshot.latitude,
      lon: payload.metadataSnapshot.longitude,
      accuracyM: payload.metadataSnapshot.accuracyMeters,
      lowAccuracy: payload.metadataSnapshot.lowAccuracy,
      altitude: payload.metadataSnapshot.altitudeMeters, // Real capture elevation (vuln-0002)
      activityTag: null,
      observationType: ObservationType.general,
      linkedMediaId: null,
      note: null,
      capturedAt: payload.metadataSnapshot.capturedAtUtc,
      sha256Hash: payload.originalSha256,           // SHA-256 of orig_<id> — immutable original
      evidenceSha256Hash: payload.evidenceSha256,   // SHA-256 of evid_<id> — watermarked; mandatory audit metadata
      capturedAddress: payload.metadataSnapshot.resolvedAddress, // physical address at capture time
      creatorId: payload.metadataSnapshot.creatorId,             // creator UID for sync authorization
      syncStatus: SyncStatusType.pending,
      isDeleted: false,
    );

    // 4. Phase 4: Managed SQLite Transaction
    try {
      await _db.transaction(() async {
        await _mediaRepo.insertMedia(mediaItem);
      });
      return mediaItem;
    } catch (e) {
      // 5. Phase 5: Consistency Recovery on DB Failure
      // Rollback occurred automatically in transaction. Clean up derived files, retain original.
      await _storageService.cleanupPartialArtifacts(payload.mediaId);
      throw MediaPersistenceException('SQLite transaction failed: $e');
    }
  }

  /// Persists a PendingCapturePayload into Drift SQLite with strict foreign-key and physical file verification.
  Future<MediaItem> persistPendingCapture(
    PendingCapturePayload payload, {
    String? activityTag,
    ObservationType observationType = ObservationType.general,
    String? linkedMediaId,
    String? note,
  }) async {
    final snapshot = payload.metadataSnapshot;
    final siteId = snapshot.siteId.trim();

    // 1. Phase 1: Site Existence Validation (Strict Foreign-Key check)
    if (siteId.isEmpty) {
      throw SiteAssociationException(
        'Persistence Error: Active Site ID is empty. Media record must be associated with a valid site.',
      );
    }

    final siteEntry = await (_db.select(_db.sites)..where((tbl) => tbl.id.equals(siteId))).getSingleOrNull();
    if (siteEntry == null) {
      throw SiteAssociationException(
        'Persistence Error: Site "$siteId" does not exist in local database. Strict foreign-key validation failed.',
      );
    }

    // 2. Phase 1b: Linked Media Existence Validation
    if (linkedMediaId != null && linkedMediaId.trim().isNotEmpty) {
      final cleanLinkedId = linkedMediaId.trim();
      final linkedEntry = await (_db.select(_db.media)
            ..where((tbl) => tbl.id.equals(cleanLinkedId))
            ..where((tbl) => tbl.isDeleted.equals(0)))
          .getSingleOrNull();
      if (linkedEntry == null) {
        throw MediaPersistenceException(
          'Persistence Error: Linked BEFORE media "$cleanLinkedId" does not exist or has been deleted.',
        );
      }
    }

    // 2. Phase 2: File Existence Verification
    if (payload.isPhoto && (payload.evidenceFilePath == null || payload.thumbnailFilePath == null)) {
      throw MediaPersistenceException(
        'Persistence Error: Canonical photo evidence has not been generated or is missing.',
      );
    }
    final evidenceRelPath = payload.evidenceFilePath ?? payload.originalFilePath;

    final filesVerified = await _storageService.verifyArtifactsExist(
      originalRelativePath: payload.originalFilePath,
      evidenceRelativePath: evidenceRelPath,
      thumbnailRelativePath: payload.thumbnailFilePath,
    );

    if (!filesVerified) {
      throw MediaPersistenceException(
        'Persistence Error: One or more evidence artifacts failed physical disk verification.',
      );
    }

    // 3. Phase 3: Construct Immutable MediaItem
    final cleanActivity = activityTag?.trim() ?? '';
    final cleanNote = note?.trim() ?? '';

    final mediaItem = MediaItem(
      id: payload.mediaId,
      siteId: siteId,
      originalUri: payload.originalFilePath,
      uri: evidenceRelPath,
      thumbUri: payload.thumbnailFilePath,
      type: payload.mediaType,
      lat: snapshot.latitude,
      lon: snapshot.longitude,
      accuracyM: snapshot.accuracyMeters,
      lowAccuracy: snapshot.lowAccuracy,
      altitude: snapshot.altitudeMeters, // Real capture elevation (vuln-0002)
      activityTag: cleanActivity.isNotEmpty ? cleanActivity : null,
      observationType: observationType,
      linkedMediaId: linkedMediaId,
      note: cleanNote.isNotEmpty ? cleanNote : null,
      capturedAt: snapshot.capturedAtUtc,
      sha256Hash: payload.sha256Hash,
      evidenceSha256Hash: payload.mediaType == MediaItemType.video
          ? payload.sha256Hash
          : payload.photoPayload?.evidenceSha256,
      capturedAddress: snapshot.resolvedAddress,
      creatorId: snapshot.creatorId,
      syncStatus: SyncStatusType.pending,
      isDeleted: false,
    );

    // 4. Phase 4: Managed SQLite Transaction
    try {
      await _db.transaction(() async {
        await _mediaRepo.insertMedia(mediaItem);
      });
      return mediaItem;
    } catch (e) {
      throw MediaPersistenceException('SQLite transaction failed: $e');
    }
  }

  /// Persists an interrupted recording's preserved video as a real, gallery-queryable
  /// [MediaItem]. The physical file is already preserved by the caller — no second copy
  /// is created here. Throws on persistence failure so the caller can report truthfully.
  Future<MediaItem> keepForLater(PendingCapturePayload payload) async {
    final snapshot = payload.metadataSnapshot;
    final siteId = snapshot.siteId.trim();

    if (siteId.isNotEmpty) {
      final siteEntry = await (_db.select(_db.sites)..where((tbl) => tbl.id.equals(siteId))).getSingleOrNull();
      if (siteEntry == null) {
        throw SiteAssociationException(
          'Persistence Error: Site "$siteId" does not exist in local database.',
        );
      }
    }

    final evidenceRelPath = payload.evidenceFilePath ?? payload.originalFilePath;

    final filesVerified = await _storageService.verifyArtifactsExist(
      originalRelativePath: payload.originalFilePath,
      evidenceRelativePath: evidenceRelPath,
      thumbnailRelativePath: payload.thumbnailFilePath,
    );

    if (!filesVerified) {
      throw MediaPersistenceException(
        'Persistence Error: Interrupted video file failed physical disk verification.',
      );
    }

    final mediaItem = MediaItem(
      id: payload.mediaId,
      siteId: snapshot.siteId,
      originalUri: payload.originalFilePath,
      uri: evidenceRelPath,
      thumbUri: payload.thumbnailFilePath,
      type: payload.mediaType,
      lat: snapshot.latitude,
      lon: snapshot.longitude,
      accuracyM: snapshot.accuracyMeters,
      lowAccuracy: snapshot.lowAccuracy,
      activityTag: null,
      observationType: ObservationType.general,
      linkedMediaId: null,
      note: null,
      capturedAt: snapshot.capturedAtUtc,
      // The interrupted recording was preserved from the in-flight file without a
      // watermarked re-encode, so the original hash is the evidence hash.
      sha256Hash: payload.sha256Hash,
      evidenceSha256Hash: payload.sha256Hash,
      capturedAddress: snapshot.resolvedAddress,
      creatorId: snapshot.creatorId,
      syncStatus: SyncStatusType.pending,
      isDeleted: false,
    );

    try {
      await _db.transaction(() async {
        await _mediaRepo.insertMedia(mediaItem);
      });
      return mediaItem;
    } catch (e) {
      throw MediaPersistenceException('Failed to save interrupted recording for later: $e');
    }
  }
}
