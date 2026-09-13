import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/closed_evidence_integrity.dart';
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

    // 1b. Strict GPS Fix & Non-(0,0) Coordinate Validation
    if (!payload.metadataSnapshot.hasValidCoordinates) {
      await _storageService.cleanupPartialArtifacts(payload.mediaId);
      throw MediaPersistenceException(
        'Persistence Error: Evidence capture requires a valid GPS fix. Cannot persist invalid or (0,0) GPS coordinates.',
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
      isAltitudeMsl: payload.metadataSnapshot.isAltitudeMsl,
      verificationStatus: payload.metadataSnapshot.verificationStatus,
      gnssSatelliteCount: payload.metadataSnapshot.gnssSatelliteCount,
      gnssSatellitesUsedInFix: payload.metadataSnapshot.gnssSatellitesUsedInFix,
      gnssFixTimestampUtc: payload.metadataSnapshot.gnssFixTimestampUtc,
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

    // 2. Phase 1b: Linked Media Existence, Creator & Site Isolation Validation
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

      // Creator isolation: linked candidate must belong to same creator
      if (snapshot.creatorId != null &&
          snapshot.creatorId!.isNotEmpty &&
          linkedEntry.creatorId != null &&
          linkedEntry.creatorId!.isNotEmpty &&
          linkedEntry.creatorId != snapshot.creatorId) {
        throw MediaPersistenceException(
          'Persistence Error: Linked BEFORE media "$cleanLinkedId" belongs to another creator (${linkedEntry.creatorId}). Cross-user linking prohibited.',
        );
      }

      // Site isolation: linked candidate must belong to same site
      if (linkedEntry.siteId != null &&
          linkedEntry.siteId!.isNotEmpty &&
          linkedEntry.siteId != siteId) {
        throw MediaPersistenceException(
          'Persistence Error: Linked BEFORE media "$cleanLinkedId" belongs to another site (${linkedEntry.siteId}). Site isolation violation.',
        );
      }
    }

    // Phase 1c: Strict GPS Fix & Non-(0,0) Validation
    if (!snapshot.hasValidCoordinates) {
      throw MediaPersistenceException(
        'Persistence Error: Evidence capture requires a valid GPS fix. Cannot persist invalid or (0,0) GPS coordinates.',
      );
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

    // 3. Phase 3: Construct Immutable MediaItem with Enforced Closed Evidence Integrity
    final cleanActivity = activityTag?.trim() ?? '';
    final validated = ClosedEvidenceIntegrity.enforceIntegrity(
      observationType: observationType,
      linkedMediaId: linkedMediaId,
      note: note,
    );

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
      isAltitudeMsl: snapshot.isAltitudeMsl,
      verificationStatus: snapshot.verificationStatus,
      gnssSatelliteCount: snapshot.gnssSatelliteCount,
      gnssSatellitesUsedInFix: snapshot.gnssSatellitesUsedInFix,
      gnssFixTimestampUtc: snapshot.gnssFixTimestampUtc,
      activityTag: cleanActivity.isNotEmpty ? cleanActivity : null,
      observationType: observationType,
      linkedMediaId: validated.linkedMediaId,
      note: validated.note,
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
      // Consistency Recovery on DB Failure:
      // Rollback occurred automatically in transaction.
      // For photo evidence, clean up only derived files while preserving the immutable original camera JPEG.
      // For video evidence, clean up unpersisted temporary artifacts.
      if (payload.isPhoto) {
        try {
          await _storageService.cleanupPartialArtifacts(payload.mediaId);
        } catch (_) {}
      } else {
        try {
          await _storageService.deleteLocalMediaFiles(
            mediaId: payload.mediaId,
            originalUri: payload.originalFilePath,
            uri: evidenceRelPath,
            thumbUri: payload.thumbnailFilePath,
          );
        } catch (_) {}
      }
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

    // Phase 1c: Strict GPS Fix & Non-(0,0) Validation
    if (!snapshot.hasValidCoordinates) {
      throw MediaPersistenceException(
        'Persistence Error: Evidence capture requires a valid GPS fix. Cannot persist invalid or (0,0) GPS coordinates.',
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
      altitude: snapshot.altitudeMeters,
      isAltitudeMsl: snapshot.isAltitudeMsl,
      verificationStatus: snapshot.verificationStatus,
      gnssSatelliteCount: snapshot.gnssSatelliteCount,
      gnssSatellitesUsedInFix: snapshot.gnssSatellitesUsedInFix,
      gnssFixTimestampUtc: snapshot.gnssFixTimestampUtc,
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
      if (payload.isPhoto) {
        try {
          await _storageService.cleanupPartialArtifacts(payload.mediaId);
        } catch (_) {}
      } else {
        try {
          await _storageService.deleteLocalMediaFiles(
            mediaId: payload.mediaId,
            originalUri: payload.originalFilePath,
            uri: evidenceRelPath,
            thumbUri: payload.thumbnailFilePath,
          );
        } catch (_) {}
      }
      throw MediaPersistenceException('Failed to save interrupted recording for later: $e');
    }
  }
}
