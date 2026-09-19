import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/crypto_utils.dart';
import '../../../data/repositories/site_repository.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/media_item.dart';

class PermanentSyncException implements Exception {
  final String message;
  PermanentSyncException(this.message);
  @override
  String toString() => 'PermanentSyncException: $message';
}

class RetryableSyncException implements Exception {
  final String message;
  RetryableSyncException(this.message);
  @override
  String toString() => 'RetryableSyncException: $message';
}

class IntegrityConflictException implements Exception {
  final String message;
  IntegrityConflictException(this.message);
  @override
  String toString() => 'IntegrityConflictException: $message';
}

final cloudSyncServiceProvider = Provider<CloudSyncService>((ref) {
  final siteRepo = ref.watch(siteRepositoryProvider);
  return CloudSyncService(
    firestore: FirebaseFirestore.instance,
    storage: FirebaseStorage.instance,
    siteRepository: siteRepo,
  );
});

class CloudSyncService {
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final SiteRepository? _siteRepository;

  CloudSyncService({
    required FirebaseFirestore firestore,
    required FirebaseStorage storage,
    SiteRepository? siteRepository,
  })  : _firestore = firestore,
        _storage = storage,
        _siteRepository = siteRepository;

  /// Synchronizes a single local MediaItem to Firebase Storage and Firestore.
  /// Strictly follows the deterministic sequence:
  /// 1. Hash verification
  /// 2. Original upload (or idempotent match)
  /// 3. Thumbnail upload (or idempotent match)
  /// 4. Firestore document set / update
  Future<void> syncMediaItem({
    required MediaItem item,
    required String absoluteOriginalPath,
    required String absoluteEvidencePath,
    String? absoluteThumbnailPath,
    required String currentUserId,
  }) async {
    // 0. Creator Authorization Guard
    if (item.creatorId != null && item.creatorId != currentUserId) {
      throw PermanentSyncException(
        'Creator mismatch: Item was captured by ${item.creatorId}, active session is $currentUserId.',
      );
    }

    // 1. Local Pre-Flight Hash Integrity Checks
    final origFile = File(absoluteOriginalPath);
    if (await origFile.exists()) {
      final origBytes = await origFile.readAsBytes();
      final computedOrigSha = CryptoUtils.computeSha256(origBytes);
      if (computedOrigSha != item.sha256Hash) {
        throw IntegrityConflictException(
          'Local original file SHA-256 ($computedOrigSha) does not match expected hash (${item.sha256Hash}).',
        );
      }
    }

    final evidFile = File(absoluteEvidencePath);
    if (!await evidFile.exists()) {
      throw PermanentSyncException('Evidence file not found on disk: $absoluteEvidencePath');
    }
    final evidBytes = await evidFile.readAsBytes();
    final computedEvidSha = CryptoUtils.computeSha256(evidBytes);
    if (computedEvidSha != item.evidenceSha256Hash) {
      throw IntegrityConflictException(
        'Local evidence file SHA-256 ($computedEvidSha) does not match expected hash (${item.evidenceSha256Hash}).',
      );
    }

    String? localThumbSha;
    File? thumbFile;
    if (absoluteThumbnailPath != null) {
      thumbFile = File(absoluteThumbnailPath);
      if (await thumbFile.exists()) {
        final thumbBytes = await thumbFile.readAsBytes();
        localThumbSha = CryptoUtils.computeSha256(thumbBytes);
      }
    }

    await _runMappedSyncOperation(() async {
      // 1.5. Ensure Cloud Site is provisioned in Firestore with creator admin membership
      await _ensureSiteProvisioned(item.siteId, currentUserId);

      // 2. Firestore: Metadata Document Sync (Create / Update / Conflict Check)
      // Must execute BEFORE storage uploads so Storage Security Rules can verify doc creator_id (vuln-0001)
      await _ensureFirestoreDocSynced(item, currentUserId);

      // 3. Storage: Original File Upload (Idempotent)
      await _ensureOriginalUploaded(item, origFile);

      // 3b. Storage: Canonical Evidence Artifact Upload (R16 Option A).
      // Publication order is ledger -> original -> evidence -> thumbnail.
      await _ensureEvidenceUploaded(item, evidFile);

      // 4. Storage: Thumbnail File Upload (Idempotent with Deterministic Hash Verification)
      if (thumbFile != null && localThumbSha != null) {
        await _ensureThumbnailUploaded(item, thumbFile, localThumbSha);
      }
    });
  }

  /// Runs [action] mapping low-level Firebase/network failures onto the sync
  /// exception taxonomy shared by every synchronization entry point.
  Future<void> _runMappedSyncOperation(Future<void> Function() action) async {
    try {
      await action();
    } on IntegrityConflictException {
      rethrow;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied' || e.code == 'unauthenticated') {
        rethrow;
      } else if (e.code == 'quota-exceeded') {
        throw PermanentSyncException('Storage quota exceeded.');
      } else {
        throw RetryableSyncException('Firebase error (${e.code}): ${e.message}');
      }
    } on SocketException catch (e) {
      throw RetryableSyncException('Network socket error: ${e.message}');
    } catch (e) {
      if (e is PermanentSyncException || e is RetryableSyncException) rethrow;
      throw RetryableSyncException('Unexpected sync error: $e');
    }
  }

  /// Propagates a locally soft-deleted evidence item to its existing Firestore
  /// evidence document (Cross-Cutting Audit B, B-1).
  ///
  /// The cloud tombstone is a ledger state only: the write-once Storage
  /// artifacts (original and thumbnail) are never read, modified, or deleted
  /// here, and no artifact-sync status is recorded. When no cloud document
  /// exists the item was never published, so there is no cloud deletion ledger
  /// entry to reconcile and the call is a no-op — the local removal is already
  /// authoritative and nothing may claim a cloud deletion that never happened.
  Future<void> syncTombstone({
    required MediaItem item,
    required String currentUserId,
  }) async {
    // 0. Creator Authorization Guard (same policy as syncMediaItem)
    if (item.creatorId != null && item.creatorId != currentUserId) {
      throw PermanentSyncException(
        'Creator mismatch: Item was captured by ${item.creatorId}, active session is $currentUserId.',
      );
    }

    // R22: A never-attempted publication has no cloud ledger document to
    // reconcile, and Firestore rules deny reading a non-existent document
    // (`resource != null`). Probing the cloud would surface a spurious
    // permission-denied, so skip the read entirely: the local tombstone
    // lifecycle still reconciles it (markTombstoneReconciled on success).
    if (item.syncStatus == SyncStatusType.pending) {
      return;
    }

    await _runMappedSyncOperation(() async {
      final docRef = _firestore
          .collection('sites')
          .doc(item.siteId)
          .collection('media')
          .doc(item.id);

      final snapshot = await docRef.get();
      if (!snapshot.exists) {
        // Never published to the cloud: no deletion ledger entry exists to
        // reconcile, and the security rules forbid creating a document with
        // is_deleted == true. Nothing to claim, nothing to write.
        return;
      }

      // Reuses the canonical reconciliation path: immutable forensic fields
      // are conflict-checked (never overwritten) and the mutable is_deleted
      // diff — plus any legitimate mutable diffs — is written in one update.
      await _ensureFirestoreDocSynced(item, currentUserId);
    });
  }

  /// Ensures that the parent site document exists in Firestore.
  /// If the site is newly created offline, provisions it in Firestore.
  Future<void> _ensureSiteProvisioned(String siteId, String currentUserId) async {
    final siteDocRef = _firestore.collection('sites').doc(siteId);

    try {
      final siteDoc = await siteDocRef.get();
      if (siteDoc.exists) {
        // Site already provisioned in Firestore.
        return;
      }
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') {
        rethrow;
      }
      // If reading the site document returned permission-denied (caller not yet owner),
      // proceed to attempt site creation.
    }

    // Site does not exist in Firestore -> retrieve local site metadata to provision
    final localSite = await _siteRepository?.getSiteById(siteId, creatorId: currentUserId);
    if (localSite == null) {
      throw PermanentSyncException('Cannot provision site $siteId: Site not found in local database.');
    }

    if (localSite.creatorId != null && localSite.creatorId!.isNotEmpty && localSite.creatorId != currentUserId) {
      throw PermanentSyncException(
        'Creator mismatch for site $siteId: Created locally by ${localSite.creatorId}, active session is $currentUserId.',
      );
    }

    await siteDocRef.set({
      'id': siteId,
      'creator_id': currentUserId,
      'name': localSite.name,
      'site_code': localSite.siteCode,
      'address': localSite.address,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _ensureOriginalUploaded(MediaItem item, File origFile) async {
    final storageRef = _storage.ref('sites/${item.siteId}/media/${item.id}/original');

    try {
      final metadata = await storageRef.getMetadata();
      final customMeta = metadata.customMetadata ?? {};
      final cloudOrigSha = customMeta['x-sitelens-original-sha256'];
      final cloudEvidSha = customMeta['x-sitelens-evidence-sha256'];
      final cloudAddr = customMeta['x-sitelens-captured-address'];

      final expectedOrigSha = item.sha256Hash ?? '';
      final expectedEvidSha = item.evidenceSha256Hash ?? '';
      final expectedAddr = item.capturedAddress ?? '';

      // All forensic metadata fields are strictly REQUIRED on existing cloud original artifacts
      if (cloudOrigSha == null || cloudOrigSha != expectedOrigSha) {
        throw IntegrityConflictException(
          'Cloud original artifact missing or conflicting SHA-256 ($cloudOrigSha != $expectedOrigSha).',
        );
      }
      if (cloudEvidSha == null || cloudEvidSha != expectedEvidSha) {
        throw IntegrityConflictException(
          'Cloud original artifact missing or conflicting evidence SHA-256 ($cloudEvidSha != $expectedEvidSha).',
        );
      }
      if (cloudAddr == null || cloudAddr != expectedAddr) {
        throw IntegrityConflictException(
          'Cloud original artifact missing or conflicting captured address ($cloudAddr != $expectedAddr).',
        );
      }

      // All verified required metadata matches -> Idempotent success: already uploaded
      return;
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') {
        rethrow;
      }
      // Object does not exist -> Proceed to upload
    }

    if (!await origFile.exists()) {
      throw PermanentSyncException('Original file not found on disk: ${origFile.path}');
    }

    final metadata = SettableMetadata(
      contentType: item.type == MediaItemType.photo ? 'image/jpeg' : 'video/mp4',
      customMetadata: {
        'x-sitelens-original-sha256': item.sha256Hash ?? '',
        'x-sitelens-evidence-sha256': item.evidenceSha256Hash ?? '',
        'x-sitelens-captured-address': item.capturedAddress ?? '',
      },
    );

    await storageRef.putFile(origFile, metadata);
  }

  /// Storage object path (and matching Firestore ledger field) for the
  /// cloud-authoritative canonical evidence artifact (R16 Option A).
  static String evidenceStoragePath(String siteId, String mediaId) =>
      'sites/$siteId/media/$mediaId/evidence';

  /// R16 (Option A): replicates the canonical burned evidence artifact
  /// (`evid_<id>.jpg`) to Cloud Storage as a cloud-authoritative record so its
  /// exact bytes can be forensically verified without re-rendering the HUD.
  ///
  /// The upload is only considered complete once the replicated object reports
  /// the exact SHA-256 of the local evidence bytes; a mismatch throws
  /// [IntegrityConflictException] so the item is never marked synced. Videos have
  /// no separate burned artifact (their `orig_` is the evidence), so this is a
  /// no-op for them.
  Future<void> _ensureEvidenceUploaded(MediaItem item, File evidFile) async {
    if (item.type != MediaItemType.photo) return;

    final expectedEvidSha = item.evidenceSha256Hash;
    if (expectedEvidSha == null || expectedEvidSha.isEmpty) {
      throw PermanentSyncException(
        'Cannot replicate evidence artifact for ${item.id}: no evidence SHA-256 recorded.',
      );
    }

    final storageRef = _storage.ref(evidenceStoragePath(item.siteId, item.id));

    try {
      final metadata = await storageRef.getMetadata();
      final cloudEvidSha = metadata.customMetadata?['x-sitelens-evidence-sha256'];
      if (cloudEvidSha == null || cloudEvidSha != expectedEvidSha) {
        throw IntegrityConflictException(
          'Cloud evidence artifact missing or conflicting SHA-256 ($cloudEvidSha != $expectedEvidSha).',
        );
      }
      // Idempotent success: already replicated and verified.
      return;
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') {
        rethrow;
      }
      // Object does not exist -> Proceed to upload
    }

    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
      customMetadata: {
        'x-sitelens-evidence-sha256': expectedEvidSha,
      },
    );

    await storageRef.putFile(evidFile, metadata);

    // Post-upload verification: the replicated object must report the exact
    // digest of the local evidence bytes before the artifact counts as synced.
    final uploaded = await storageRef.getMetadata();
    final uploadedSha = uploaded.customMetadata?['x-sitelens-evidence-sha256'];
    if (uploadedSha != expectedEvidSha) {
      throw IntegrityConflictException(
        'Replicated evidence artifact SHA-256 verification failed '
        '($uploadedSha != $expectedEvidSha).',
      );
    }
  }

  Future<void> _ensureThumbnailUploaded(MediaItem item, File thumbFile, String localThumbSha) async {
    final storageRef = _storage.ref('sites/${item.siteId}/media/${item.id}/thumbnail');

    try {
      final metadata = await storageRef.getMetadata();
      final cloudThumbSha = metadata.customMetadata?['x-sitelens-thumbnail-sha256'];
      if (cloudThumbSha == null || cloudThumbSha != localThumbSha) {
        throw IntegrityConflictException(
          'Cloud thumbnail artifact missing or conflicting hash ($cloudThumbSha != $localThumbSha).',
        );
      }
      // Idempotent success: matching thumbnail hash
      return;
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') {
        rethrow;
      }
      // Object does not exist -> Proceed to upload
    }

    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
      customMetadata: {
        'x-sitelens-thumbnail-sha256': localThumbSha,
      },
    );

    await storageRef.putFile(thumbFile, metadata);
  }

  Future<void> _ensureFirestoreDocSynced(MediaItem item, String currentUserId) async {
    final docRef = _firestore
        .collection('sites')
        .doc(item.siteId)
        .collection('media')
        .doc(item.id);

    final snapshot = await docRef.get();

    if (!snapshot.exists) {
      // 1. Create new evidence document
      final payload = {
        'id': item.id,
        'site_id': item.siteId,
        'creator_id': currentUserId,
        'storage_original_path': 'sites/${item.siteId}/media/${item.id}/original',
        'storage_thumbnail_path': 'sites/${item.siteId}/media/${item.id}/thumbnail',
        // R16 Option A: only photos have a distinct cloud-authoritative
        // evidence artifact; a video's evidence IS its original.
        if (item.type == MediaItemType.photo)
          'storage_evidence_path': evidenceStoragePath(item.siteId, item.id),
        'type': item.type.name,
        'lat': item.lat,
        'lon': item.lon,
        'accuracy_m': item.accuracyM,
        'low_accuracy': item.lowAccuracy,
        'altitude': item.altitude,
        'is_altitude_msl': item.isAltitudeMsl,
        'verification_status': item.verificationStatus?.name,
        'gnss_satellite_count': item.gnssSatelliteCount,
        'gnss_satellites_used_in_fix': item.gnssSatellitesUsedInFix,
        'gnss_fix_timestamp': item.gnssFixTimestampUtc?.toUtc().toIso8601String(),
        'has_audio_track': item.hasAudioTrack,
        'heading_degrees': item.headingDegrees,
        'activity_tag': item.activityTag,
        'observation_type': item.observationType.name,
        'linked_media_id': item.linkedMediaId,
        'note': item.note,
        'captured_at': item.capturedAt.toUtc().toIso8601String(),
        'sha256_hash': item.sha256Hash,
        'evidence_sha256_hash': item.evidenceSha256Hash,
        'captured_address': item.capturedAddress,
        'is_deleted': item.isDeleted,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      await docRef.set(payload);
    } else {
      // 2. Existing document -> Reconcile all immutable forensic fields
      final data = snapshot.data()!;

      final cloudSha = data['sha256_hash'] as String?;
      if (cloudSha != null && cloudSha != item.sha256Hash) {
        throw IntegrityConflictException(
          'Firestore evidence document sha256_hash ($cloudSha) conflicts with local (${item.sha256Hash}).',
        );
      }

      final cloudEvidSha = data['evidence_sha256_hash'] as String?;
      if (cloudEvidSha != null && cloudEvidSha != item.evidenceSha256Hash) {
        throw IntegrityConflictException(
          'Firestore evidence document evidence_sha256_hash ($cloudEvidSha) conflicts with local (${item.evidenceSha256Hash}).',
        );
      }

      final cloudCapturedAddress = data['captured_address'] as String?;
      if (cloudCapturedAddress != null && cloudCapturedAddress != item.capturedAddress) {
        throw IntegrityConflictException(
          'Firestore evidence document captured_address ($cloudCapturedAddress) conflicts with local (${item.capturedAddress}).',
        );
      }

      final cloudCreatorId = data['creator_id'] as String?;
      final expectedCreatorId = item.creatorId ?? currentUserId;
      if (cloudCreatorId != null && cloudCreatorId != expectedCreatorId) {
        throw IntegrityConflictException(
          'Firestore evidence document creator_id ($cloudCreatorId) conflicts with local ($expectedCreatorId).',
        );
      }

      final cloudLat = (data['lat'] as num?)?.toDouble();
      if (cloudLat != null && cloudLat != item.lat) {
        throw IntegrityConflictException(
          'Firestore evidence document lat ($cloudLat) conflicts with local (${item.lat}).',
        );
      }

      final cloudLon = (data['lon'] as num?)?.toDouble();
      if (cloudLon != null && cloudLon != item.lon) {
        throw IntegrityConflictException(
          'Firestore evidence document lon ($cloudLon) conflicts with local (${item.lon}).',
        );
      }

      final cloudAccuracy = (data['accuracy_m'] as num?)?.toDouble();
      if (cloudAccuracy != null && cloudAccuracy != item.accuracyM) {
        throw IntegrityConflictException(
          'Firestore evidence document accuracy_m ($cloudAccuracy) conflicts with local (${item.accuracyM}).',
        );
      }

      final cloudAltitude = (data['altitude'] as num?)?.toDouble();
      if (cloudAltitude != null && cloudAltitude != item.altitude) {
        throw IntegrityConflictException(
          'Firestore evidence document altitude ($cloudAltitude) conflicts with local (${item.altitude}).',
        );
      }

      final cloudIsMsl = data['is_altitude_msl'] as bool?;
      if (cloudIsMsl != null && cloudIsMsl != item.isAltitudeMsl) {
        throw IntegrityConflictException(
          'Firestore evidence document is_altitude_msl ($cloudIsMsl) conflicts with local (${item.isAltitudeMsl}).',
        );
      }

      final cloudVerification = data['verification_status'] as String?;
      if (cloudVerification != null && cloudVerification != item.verificationStatus?.name) {
        throw IntegrityConflictException(
          'Firestore evidence document verification_status ($cloudVerification) conflicts with local (${item.verificationStatus?.name}).',
        );
      }

      final cloudSatCount = (data['gnss_satellite_count'] as num?)?.toInt();
      if (cloudSatCount != null && cloudSatCount != item.gnssSatelliteCount) {
        throw IntegrityConflictException(
          'Firestore evidence document gnss_satellite_count ($cloudSatCount) conflicts with local (${item.gnssSatelliteCount}).',
        );
      }

      final cloudSatUsed = (data['gnss_satellites_used_in_fix'] as num?)?.toInt();
      if (cloudSatUsed != null && cloudSatUsed != item.gnssSatellitesUsedInFix) {
        throw IntegrityConflictException(
          'Firestore evidence document gnss_satellites_used_in_fix ($cloudSatUsed) conflicts with local (${item.gnssSatellitesUsedInFix}).',
        );
      }

      final cloudFixTs = data['gnss_fix_timestamp'] as String?;
      final expectedFixTs = item.gnssFixTimestampUtc?.toUtc().toIso8601String();
      if (cloudFixTs != null && cloudFixTs != expectedFixTs) {
        throw IntegrityConflictException(
          'Firestore evidence document gnss_fix_timestamp ($cloudFixTs) conflicts with local ($expectedFixTs).',
        );
      }

      final cloudHasAudio = data['has_audio_track'] as bool?;
      if (cloudHasAudio != null && cloudHasAudio != item.hasAudioTrack) {
        throw IntegrityConflictException(
          'Firestore evidence document has_audio_track ($cloudHasAudio) conflicts with local (${item.hasAudioTrack}).',
        );
      }

      final cloudHeading = (data['heading_degrees'] as num?)?.toDouble();
      if (cloudHeading != null && cloudHeading != item.headingDegrees) {
        throw IntegrityConflictException(
          'Firestore evidence document heading_degrees ($cloudHeading) conflicts with local (${item.headingDegrees}).',
        );
      }

      final cloudType = data['type'] as String?;
      if (cloudType != null && cloudType != item.type.name) {
        throw IntegrityConflictException(
          'Firestore evidence document type ($cloudType) conflicts with local (${item.type.name}).',
        );
      }

      final cloudOrigPath = data['storage_original_path'] as String?;
      final expectedOrigPath = 'sites/${item.siteId}/media/${item.id}/original';
      if (cloudOrigPath != null && cloudOrigPath != expectedOrigPath) {
        throw IntegrityConflictException(
          'Firestore evidence document storage_original_path ($cloudOrigPath) conflicts with local ($expectedOrigPath).',
        );
      }

      final cloudThumbPath = data['storage_thumbnail_path'] as String?;
      final expectedThumbPath = 'sites/${item.siteId}/media/${item.id}/thumbnail';
      if (cloudThumbPath != null && cloudThumbPath != expectedThumbPath) {
        throw IntegrityConflictException(
          'Firestore evidence document storage_thumbnail_path ($cloudThumbPath) conflicts with local ($expectedThumbPath).',
        );
      }

      // R16: the cloud-authoritative evidence artifact path is deterministic for
      // photos. Never let a conflicting documented path stand.
      final cloudEvidPath = data['storage_evidence_path'] as String?;
      if (item.type == MediaItemType.photo && cloudEvidPath != null) {
        final expectedEvidPath = evidenceStoragePath(item.siteId, item.id);
        if (cloudEvidPath != expectedEvidPath) {
          throw IntegrityConflictException(
            'Firestore evidence document storage_evidence_path ($cloudEvidPath) conflicts with local ($expectedEvidPath).',
          );
        }
      }

      // Reconcile captured_at timestamp representation (handling ISO-8601 String or Firestore Timestamp)
      final rawCapturedAt = data['captured_at'];
      DateTime? cloudCapturedAt;
      if (rawCapturedAt is Timestamp) {
        cloudCapturedAt = rawCapturedAt.toDate().toUtc();
      } else if (rawCapturedAt is String) {
        cloudCapturedAt = DateTime.tryParse(rawCapturedAt)?.toUtc();
      }
      if (cloudCapturedAt == null) {
        throw IntegrityConflictException(
          'Firestore evidence document missing or unparseable captured_at timestamp.',
        );
      }
      final localCapturedAt = item.capturedAt.toUtc();
      if (!cloudCapturedAt.isAtSameMomentAs(localCapturedAt)) {
        throw IntegrityConflictException(
          'Firestore evidence document captured_at ($cloudCapturedAt) conflicts with local ($localCapturedAt).',
        );
      }

      // Check for mutable differences
      final updates = <String, dynamic>{};
      if (data['note'] != item.note) updates['note'] = item.note;
      if (data['activity_tag'] != item.activityTag) updates['activity_tag'] = item.activityTag;
      if (data['observation_type'] != item.observationType.name) updates['observation_type'] = item.observationType.name;
      if (data['linked_media_id'] != item.linkedMediaId) updates['linked_media_id'] = item.linkedMediaId;
      if (data['is_deleted'] != item.isDeleted) updates['is_deleted'] = item.isDeleted;

      if (updates.isNotEmpty) {
        updates['updated_at'] = FieldValue.serverTimestamp();
        await docRef.update(updates);
      }
    }
  }
}
