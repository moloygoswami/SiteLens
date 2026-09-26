import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../local/database/app_database.dart';
import '../local/database/database_provider.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/enums.dart';
import '../../core/utils/closed_evidence_integrity.dart';
import '../../core/utils/haversine.dart';
import '../../features/camera/hud/hud_data.dart';
import '../../features/camera/services/evidence_storage_service.dart';

class MediaConflictException implements Exception {
  final String message;
  MediaConflictException(this.message);

  @override
  String toString() => 'MediaConflictException: $message';
}

class MediaPersistenceException implements Exception {
  final String message;
  MediaPersistenceException(this.message);

  @override
  String toString() => 'MediaPersistenceException: $message';
}

class MediaIsolationException extends MediaPersistenceException {
  MediaIsolationException(super.message);

  @override
  String toString() => 'MediaIsolationException: $message';
}


abstract class MediaRepository {
  Future<void> insertMedia(MediaItem item, {String? creatorId});
  Future<MediaItem?> getMediaById(String id, {String? creatorId});
  Future<List<MediaItem>> getAllMediaEntriesIncludingDeleted({String? creatorId});
  Stream<List<MediaItem>> watchAllMedia({String? siteId, String? activity, ObservationType? observationType, bool? lowAccuracyOnly, String? creatorId});
  Future<List<MediaItem>> searchMedia({required String query, String? siteId, String? creatorId});
  Future<List<NearbyMediaResult>> findNearbyMedia({
    required double centerLat,
    required double centerLon,
    required double radiusMeters,
    String? siteId,
    String? activity,
    ObservationType? observationType,
    String? excludeMediaId,
    String? creatorId,
  });
  Future<MediaItem?> findSuggestedBeforeMatch({
    required double centerLat,
    required double centerLon,
    required String siteId,
    required String activityTag,
    required DateTime capturedBefore,
    double radiusMeters = 10.0,
    String? currentMediaId,
    String? creatorId,
    bool requireCreator = true,
  });
  Future<List<NearbyMediaResult>> findSiteWideCandidates({
    required double centerLat,
    required double centerLon,
    required String siteId,
    required DateTime capturedBefore,
    String? currentMediaId,
    String? creatorId,
  });
  Future<void> linkMedia({required String mediaId, required String linkedMediaId, String? creatorId});
  Future<Set<String>> getResolvedMediaIds({required String siteId, String? creatorId});
  Future<void> updateTags({
    required String mediaId,
    required String activityTag,
    required ObservationType observationType,
    String? note,
    String? linkedMediaId,
    String? creatorId,
  });
  Future<void> softDeleteMedia(String mediaId, {String? creatorId});
  Stream<int> watchUnsyncedCount({String? creatorId});
  Future<List<MediaItem>> getUnsyncedMedia({String? creatorId});
  Future<List<MediaItem>> getPendingOrFailedMedia({String? creatorId});
  Future<List<MediaItem>> getSyncedPhotos({String? creatorId});
  Future<void> updateSyncStatus(String mediaId, SyncStatusType status, {String? creatorId});
  Future<void> resetStuckSyncingMedia({String? creatorId});

  /// Marks a tombstone row as reconciled after its deletion ledger has been
  /// synced to the cloud (or confirmed to have never been published).
  Future<void> markTombstoneReconciled(String mediaId, {String? creatorId});

  /// Returns soft-deleted rows whose cloud deletion ledger may still be
  /// pending (Cross-Cutting Audit B, B-1). A tombstone candidate is any
  /// deleted row that is not currently mid-sync; the tombstone itself is a
  /// Firestore ledger state only and never deletes Storage artifacts.
  Future<List<MediaItem>> getTombstoneSyncCandidates({String? creatorId});

  /// Counts [getTombstoneSyncCandidates] rows so the sync coordinator can
  /// edge-trigger a cycle when a previously-synced item is soft-deleted.
  /// Scoped strictly to the authenticated creator (R04); null/empty UID → 0.
  Stream<int> watchTombstoneCandidateCount({String? creatorId});

  Future<void> removeFromGallery(String mediaId, {String? creatorId});
  Future<void> deletePermanently(String mediaId, {String? creatorId});
}

class NearbyMediaResult {
  final MediaItem item;
  final double distanceMeters;

  const NearbyMediaResult({
    required this.item,
    required this.distanceMeters,
  });
}

class LocalMediaRepository implements MediaRepository {
  final AppDatabase _db;
  final EvidenceStorageService _storageService;

  LocalMediaRepository(this._db, {EvidenceStorageService? storageService})
      : _storageService = storageService ?? EvidenceStorageService();

  /// Deterministic sentinel instant for a malformed/absent `captured_at`.
  ///
  /// R26: a corrupt timestamp must never resolve to `DateTime.now()` — that
  /// would make ordering and filtering depend on wall-clock time. Epoch marks
  /// the row as "timestamp unknown" as a fixed sentinel without fabricating a
  /// real capture instant.
  static final DateTime _unknownCapturedAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  @override
  Future<void> insertMedia(MediaItem item, {String? creatorId}) async {
    final effectiveCreatorId = (creatorId != null && creatorId.isNotEmpty) ? creatorId : item.creatorId;
    if (effectiveCreatorId == null || effectiveCreatorId.isEmpty) {
      throw MediaIsolationException('Cannot insert media without authoritative creator identity.');
    }
    if (creatorId != null && creatorId.isNotEmpty && item.creatorId != null && item.creatorId!.isNotEmpty && item.creatorId != creatorId) {
      throw MediaIsolationException('Creator identity mismatch: creatorId $creatorId does not match item.creatorId ${item.creatorId}');
    }

    final existing = await (_db.select(_db.media)..where((tbl) => tbl.id.equals(item.id))).getSingleOrNull();
    if (existing != null) {
      if (existing.creatorId != null &&
          existing.creatorId!.isNotEmpty &&
          existing.creatorId != effectiveCreatorId) {
        throw MediaIsolationException('Creator isolation violation: Media ${item.id} belongs to a different creator.');
      }
      if (existing.isDeleted == 1) {
        throw MediaConflictException('Cannot insert media ${item.id}: Item was previously soft-deleted and is tombstoned.');
      }
      if (existing.originalUri == item.originalUri &&
          existing.sha256Hash == item.sha256Hash &&
          existing.siteId == item.siteId) {
        // Idempotent duplicate: existing record is identical
        return;
      }
      throw MediaConflictException('Media with ID ${item.id} already exists in local database.');
    }

    final validated = ClosedEvidenceIntegrity.enforceIntegrity(
      observationType: item.observationType,
      linkedMediaId: item.linkedMediaId,
      note: item.note,
    );

    // Validate creator and site isolation if linkedMediaId is present
    if (validated.linkedMediaId != null) {
      final linkedEntry = await (_db.select(_db.media)
            ..where((tbl) => tbl.id.equals(validated.linkedMediaId!))
            ..where((tbl) => tbl.isDeleted.equals(0)))
          .getSingleOrNull();
      if (linkedEntry != null) {
        if (linkedEntry.creatorId != null &&
            linkedEntry.creatorId!.isNotEmpty &&
            linkedEntry.creatorId != effectiveCreatorId) {
          throw MediaIsolationException('Creator isolation violation: Cannot link media belonging to different creator');
        }
        if (linkedEntry.siteId != null &&
            linkedEntry.siteId!.isNotEmpty &&
            item.siteId.isNotEmpty &&
            linkedEntry.siteId != item.siteId) {
          throw MediaPersistenceException('Site isolation violation: Cannot link media belonging to different site');
        }
      }
    }

    await _db.into(_db.media).insert(
          MediaCompanion.insert(
            id: item.id,
            siteId: drift.Value(item.siteId),
            originalUri: drift.Value(item.originalUri),
            uri: item.uri,
            thumbUri: drift.Value(item.thumbUri),
            type: drift.Value(item.type.name),
            lat: item.lat,
            lon: item.lon,
            accuracyM: drift.Value(item.accuracyM),
            lowAccuracy: drift.Value(item.lowAccuracy ? 1 : 0),
            altitudeM: drift.Value(item.altitude),                    // audit: real capture elevation ASL (vuln-0002)
            verificationStatus: drift.Value(item.verificationStatus?.name),
            isAltitudeMsl: drift.Value(item.isAltitudeMsl == null ? null : (item.isAltitudeMsl! ? 1 : 0)),
            gnssSatelliteCount: drift.Value(item.gnssSatelliteCount),
            gnssSatellitesUsedInFix: drift.Value(item.gnssSatellitesUsedInFix),
            gnssFixTimestamp: drift.Value(item.gnssFixTimestampUtc?.toIso8601String()),
            activityTag: drift.Value(item.activityTag),
            observationType: drift.Value(item.observationType.name),
            linkedMediaId: drift.Value(validated.linkedMediaId),
            note: drift.Value(validated.note),
            capturedAt: item.capturedAt.toUtc().toIso8601String(),
            sha256Hash: drift.Value(item.sha256Hash),
            evidenceSha256Hash: drift.Value(item.evidenceSha256Hash), // audit: SHA-256 of watermarked evidence file
            capturedAddress: drift.Value(item.capturedAddress),       // audit: physical address at capture time
            creatorId: drift.Value(effectiveCreatorId),               // audit: creator UID for sync authorization
            synced: drift.Value(item.syncStatus.toInt()),
            isDeleted: drift.Value(item.isDeleted ? 1 : 0),
            tombstoneReconciled: drift.Value(item.tombstoneReconciled ? 1 : 0),
            hasAudioTrack: drift.Value(item.hasAudioTrack == null ? null : (item.hasAudioTrack! ? 1 : 0)),
            headingDegrees: drift.Value(item.headingDegrees),
          ),
        );
  }

  @override
  Future<MediaItem?> getMediaById(String id, {String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) {
      // Fail closed: No unscoped lookup
      return null;
    }
    final entry = await (_db.select(_db.media)
          ..where((tbl) => tbl.id.equals(id) & tbl.creatorId.equals(creatorId)))
        .getSingleOrNull();
    if (entry == null) return null;
    return _entryToModel(entry);
  }


  @override
  Future<List<MediaItem>> getAllMediaEntriesIncludingDeleted({String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) {
      // Defense-in-depth: Fail closed if creatorId is omitted
      return const [];
    }
    final entries = await (_db.select(_db.media)
          ..where((tbl) => tbl.creatorId.equals(creatorId)))
        .get();
    return entries.map(_entryToModel).toList();
  }

  @override
  Stream<List<MediaItem>> watchAllMedia({String? siteId, String? activity, ObservationType? observationType, bool? lowAccuracyOnly, String? creatorId}) {
    if (creatorId == null || creatorId.isEmpty) {
      // Fail closed: Never emit media across users or when unauthenticated
      return Stream.value(const []);
    }
    final query = _db.select(_db.media)
      ..where((tbl) => tbl.isDeleted.equals(0))
      ..where((tbl) => tbl.creatorId.equals(creatorId))
      // Newest-first History semantics with a deterministic tiebreaker so records
      // sharing an identical captured_at always appear in a stable order.
      ..orderBy([
        (tbl) => drift.OrderingTerm.desc(tbl.capturedAt),
        (tbl) => drift.OrderingTerm.asc(tbl.id),
      ]);

    if (siteId != null && siteId.isNotEmpty) {
      query.where((tbl) => tbl.siteId.equals(siteId));
    }
    if (activity != null && activity.isNotEmpty) {
      query.where((tbl) => tbl.activityTag.equals(activity));
    }
    if (observationType != null) {
      query.where((tbl) => tbl.observationType.equals(observationType.name));
    }
    if (lowAccuracyOnly == true) {
      query.where((tbl) => tbl.lowAccuracy.equals(1));
    }

    return query.watch().map((list) => list.map(_entryToModel).toList());
  }

  @override
  Future<List<MediaItem>> searchMedia({required String query, String? siteId, String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) {
      // Fail closed: Never return media across users or when unauthenticated
      return const [];
    }
    final cleanQuery = query.toLowerCase().trim();
    final select = _db.select(_db.media)
      ..where((tbl) => tbl.isDeleted.equals(0))
      ..where((tbl) => tbl.creatorId.equals(creatorId))
      // R26: deterministic ordering — the authoritative captured_at DESC order
      // with a stable id ASC tie-breaker, independent of database return order.
      ..orderBy([
        (tbl) => drift.OrderingTerm.desc(tbl.capturedAt),
        (tbl) => drift.OrderingTerm.asc(tbl.id),
      ]);
    if (siteId != null && siteId.isNotEmpty) {
      select.where((tbl) => tbl.siteId.equals(siteId));
    }

    final entries = await select.get();
    return entries
        .where((e) {
          final noteMatch = e.note?.toLowerCase().contains(cleanQuery) ?? false;
          final activityMatch = e.activityTag?.toLowerCase().contains(cleanQuery) ?? false;
          final obsMatch = e.observationType?.toLowerCase().contains(cleanQuery) ?? false;
          return noteMatch || activityMatch || obsMatch;
        })
        .map(_entryToModel)
        .toList();
  }

  Future<List<NearbyMediaResult>> _findSpatialCandidatesInternal({
    required double centerLat,
    required double centerLon,
    required double radiusMeters,
    String? siteId,
    String? activity,
    ObservationType? observationType,
    String? excludeMediaId,
    String? creatorId,
    bool requireCreator = true,
    DateTime? capturedBefore,
  }) async {
    // Fail closed: creatorId is strictly required for spatial candidate discovery
    if (creatorId == null || creatorId.isEmpty) {
      return const [];
    }

    // Step 1: Compute Bounding Box
    final bbox = SpatialMathUtils.calculateBoundingBox(centerLat, centerLon, radiusMeters);

    // Step 2: Query candidate records using indexed lat/lon
    final query = _db.select(_db.media)
      ..where(
        (tbl) =>
            tbl.isDeleted.equals(0) &
            tbl.creatorId.equals(creatorId) &
            tbl.lat.isBiggerOrEqualValue(bbox.minLat) &
            tbl.lat.isSmallerOrEqualValue(bbox.maxLat) &
            tbl.lon.isBiggerOrEqualValue(bbox.minLon) &
            tbl.lon.isSmallerOrEqualValue(bbox.maxLon),
      );

    if (siteId != null && siteId.isNotEmpty) {
      query.where((tbl) => tbl.siteId.equals(siteId));
    }
    if (activity != null && activity.isNotEmpty) {
      query.where((tbl) => tbl.activityTag.equals(activity));
    }
    if (observationType != null) {
      query.where((tbl) => tbl.observationType.equals(observationType.name));
    }
    if (excludeMediaId != null) {
      query.where((tbl) => tbl.id.equals(excludeMediaId).not());
    }

    final candidates = await query.get();

    // Step 3: Exact Haversine distance refinement & radius filter
    final results = <NearbyMediaResult>[];
    for (final candidate in candidates) {
      // R19: a synthetic (0,0) pair is never a valid captured location.
      if (candidate.lat == 0.0 && candidate.lon == 0.0) continue;

      // R17: a candidate may only precede an observation when its authoritative
      // capture timestamp is strictly earlier. A missing/unparseable timestamp
      // is not temporal authority, so it can never be classified as BEFORE.
      if (capturedBefore != null) {
        final candidateCapturedAt = DateTime.tryParse(candidate.capturedAt);
        if (candidateCapturedAt == null) continue;
        if (!candidateCapturedAt.toUtc().isBefore(capturedBefore.toUtc())) continue;
      }

      final distance = SpatialMathUtils.haversineDistanceMeters(centerLat, centerLon, candidate.lat, candidate.lon);

      // R19: spatial uncertainty bounds. The candidate's own GNSS accuracy is
      // part of the radius test, so a low-accuracy position is neither excluded
      // nor presented as more precise than the receiver established.
      final uncertainty = candidate.accuracyM ?? 0.0;
      if (distance <= radiusMeters + uncertainty) {
        results.add(NearbyMediaResult(
          item: _entryToModel(candidate),
          distanceMeters: distance,
        ));
      }
    }

    // Step 4: Sort by distance, then recency, then deterministic id
    results.sort((a, b) {
      final dCompare = a.distanceMeters.compareTo(b.distanceMeters);
      if (dCompare != 0) return dCompare;
      final tCompare = b.item.capturedAt.compareTo(a.item.capturedAt);
      if (tCompare != 0) return tCompare;
      return a.item.id.compareTo(b.item.id);
    });

    return results;
  }

  @override
  Future<List<NearbyMediaResult>> findNearbyMedia({
    required double centerLat,
    required double centerLon,
    required double radiusMeters,
    String? siteId,
    String? activity,
    ObservationType? observationType,
    String? excludeMediaId,
    String? creatorId,
  }) {
    return _findSpatialCandidatesInternal(
      centerLat: centerLat,
      centerLon: centerLon,
      radiusMeters: radiusMeters,
      siteId: siteId,
      activity: activity,
      observationType: observationType,
      excludeMediaId: excludeMediaId,
      creatorId: creatorId,
      requireCreator: true,
    );
  }

  @override
  Future<MediaItem?> findSuggestedBeforeMatch({
    required double centerLat,
    required double centerLon,
    required String siteId,
    required String activityTag,
    required DateTime capturedBefore,
    double radiusMeters = 10.0,
    String? currentMediaId,
    String? creatorId,
    bool requireCreator = true,
  }) async {
    if (creatorId == null || creatorId.isEmpty) {
      // Fail closed: require creatorId
      return null;
    }
    // 1. Fetch all already-resolved linked_media_ids on this site (Closed observations that are not deleted)
    final resolvedIds = await getResolvedMediaIds(siteId: siteId, creatorId: creatorId);

    final cleanActivity = activityTag.trim();
    if (cleanActivity.isNotEmpty) {
      final exactActivityMatches = await _findSpatialCandidatesInternal(
        centerLat: centerLat,
        centerLon: centerLon,
        radiusMeters: radiusMeters,
        siteId: siteId,
        activity: cleanActivity,
        observationType: ObservationType.nonConformity,
        excludeMediaId: currentMediaId,
        creatorId: creatorId,
        requireCreator: requireCreator,
        capturedBefore: capturedBefore,
      );

      for (final match in exactActivityMatches) {
        if (!resolvedIds.contains(match.item.id)) {
          return match.item;
        }
      }
    }

    // If activity is blank or no open exact-activity match was found, search any open Non-Conformity within radius
    final fallbackMatches = await _findSpatialCandidatesInternal(
      centerLat: centerLat,
      centerLon: centerLon,
      radiusMeters: radiusMeters,
      siteId: siteId,
      activity: null,
      observationType: ObservationType.nonConformity,
      excludeMediaId: currentMediaId,
      creatorId: creatorId,
      requireCreator: requireCreator,
      capturedBefore: capturedBefore,
    );

    for (final match in fallbackMatches) {
      if (!resolvedIds.contains(match.item.id)) {
        return match.item;
      }
    }

    return null;
  }

  @override
  Future<List<NearbyMediaResult>> findSiteWideCandidates({
    required double centerLat,
    required double centerLon,
    required String siteId,
    required DateTime capturedBefore,
    String? currentMediaId,
    String? creatorId,
  }) async {
    if (creatorId == null || creatorId.isEmpty) {
      // Fail closed: require creatorId
      return const [];
    }

    final resolvedIds = await getResolvedMediaIds(siteId: siteId, creatorId: creatorId);

    final query = _db.select(_db.media)
      ..where(
        (tbl) =>
            tbl.isDeleted.equals(0) &
            tbl.creatorId.equals(creatorId) &
            tbl.siteId.equals(siteId) &
            tbl.observationType.equals(ObservationType.nonConformity.name),
      );

    if (currentMediaId != null) {
      query.where((tbl) => tbl.id.equals(currentMediaId).not());
    }

    final candidates = await query.get();
    final results = <NearbyMediaResult>[];

    for (final candidate in candidates) {
      if (candidate.lat == 0.0 && candidate.lon == 0.0) continue;

      final candidateCapturedAt = DateTime.tryParse(candidate.capturedAt);
      if (candidateCapturedAt == null) continue;
      if (!candidateCapturedAt.toUtc().isBefore(capturedBefore.toUtc())) continue;

      if (resolvedIds.contains(candidate.id)) continue;

      final distance = SpatialMathUtils.haversineDistanceMeters(
        centerLat,
        centerLon,
        candidate.lat,
        candidate.lon,
      );

      results.add(NearbyMediaResult(
        item: _entryToModel(candidate),
        distanceMeters: distance,
      ));
    }

    results.sort((a, b) {
      final dCompare = a.distanceMeters.compareTo(b.distanceMeters);
      if (dCompare != 0) return dCompare;
      final tCompare = b.item.capturedAt.compareTo(a.item.capturedAt);
      if (tCompare != 0) return tCompare;
      return a.item.id.compareTo(b.item.id);
    });

    return results;
  }

  @override
  Future<void> linkMedia({required String mediaId, required String linkedMediaId, String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) {
      throw MediaIsolationException('Cannot link media without authoritative creator identity.');
    }
    final entry = await (_db.select(_db.media)
          ..where((tbl) => tbl.id.equals(mediaId) & tbl.creatorId.equals(creatorId)))
        .getSingleOrNull();
    if (entry == null) {
      throw MediaIsolationException('Target media "$mediaId" not found or not owned by creator.');
    }
    if (entry.observationType != ObservationType.closed.name) {
      // Prohibit linking for non-Closed observation
      return;
    }

    final linkedEntry = await (_db.select(_db.media)
          ..where((tbl) => tbl.id.equals(linkedMediaId))
          ..where((tbl) => tbl.isDeleted.equals(0)))
        .getSingleOrNull();
    if (linkedEntry == null) {
      throw MediaPersistenceException('Linked BEFORE media "$linkedMediaId" does not exist or is deleted.');
    }
    if (linkedEntry.creatorId != null &&
        linkedEntry.creatorId!.isNotEmpty &&
        linkedEntry.creatorId != creatorId) {
      throw MediaIsolationException('Creator isolation violation: Cannot link media belonging to different creator');
    }

    if (entry.siteId != null &&
        linkedEntry.siteId != null &&
        entry.siteId!.isNotEmpty &&
        linkedEntry.siteId!.isNotEmpty &&
        entry.siteId != linkedEntry.siteId) {
      throw MediaPersistenceException('Site isolation violation: Cannot link media belonging to different site');
    }

    // R17: temporal precedence is authoritative at the persistence boundary.
    // A candidate captured at or after the observation can never be its BEFORE.
    final sourceCapturedAt = DateTime.tryParse(entry.capturedAt);
    final candidateCapturedAt = DateTime.tryParse(linkedEntry.capturedAt);
    if (sourceCapturedAt == null ||
        candidateCapturedAt == null ||
        !candidateCapturedAt.toUtc().isBefore(sourceCapturedAt.toUtc())) {
      throw MediaPersistenceException(
        'Temporal precedence violation: a BEFORE Non-Conformity must be captured strictly earlier than the observation it precedes.',
      );
    }

    await (_db.update(_db.media)
          ..where((tbl) => tbl.id.equals(mediaId) & tbl.creatorId.equals(creatorId)))
        .write(
      MediaCompanion(
        linkedMediaId: drift.Value(linkedMediaId),
        synced: const drift.Value(0),
      ),
    );
  }

  @override
  Future<Set<String>> getResolvedMediaIds({required String siteId, String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) {
      // Fail closed: never resolve another user's linked evidence
      return const <String>{};
    }
    final resolvedQuery = _db.selectOnly(_db.media)
      ..addColumns([_db.media.linkedMediaId])
      ..where(_db.media.siteId.equals(siteId) &
          _db.media.observationType.equals(ObservationType.closed.name) &
          _db.media.linkedMediaId.isNotNull() &
          _db.media.isDeleted.equals(0) &
          _db.media.creatorId.equals(creatorId));

    final resolvedRows = await resolvedQuery.get();

    return resolvedRows
        .map((r) => r.read(_db.media.linkedMediaId))
        .whereType<String>()
        .toSet();
  }

  @override
  Future<void> updateTags({
    required String mediaId,
    required String activityTag,
    required ObservationType observationType,
    String? note,
    String? linkedMediaId,
    String? creatorId,
  }) async {
    if (creatorId == null || creatorId.isEmpty) {
      throw MediaIsolationException('Cannot update tags without authoritative creator identity.');
    }
    final existing = await getMediaById(mediaId, creatorId: creatorId);
    if (existing == null) {
      throw MediaIsolationException('Media "$mediaId" not found or not owned by creator.');
    }
    final rawLinkedId = linkedMediaId ??
        (observationType == ObservationType.closed ? existing.linkedMediaId : null);

    final validated = ClosedEvidenceIntegrity.enforceIntegrity(
      observationType: observationType,
      linkedMediaId: rawLinkedId,
      note: note,
    );

    if (validated.linkedMediaId != null) {
      final linkedEntry = await (_db.select(_db.media)
            ..where((tbl) => tbl.id.equals(validated.linkedMediaId!))
            ..where((tbl) => tbl.isDeleted.equals(0)))
          .getSingleOrNull();
      if (linkedEntry == null) {
        throw MediaPersistenceException('Linked BEFORE media "${validated.linkedMediaId}" does not exist or is deleted.');
      }
      if (linkedEntry.creatorId != null &&
          linkedEntry.creatorId!.isNotEmpty &&
          linkedEntry.creatorId != creatorId) {
        throw MediaIsolationException('Creator isolation violation: Cannot link media belonging to different creator');
      }
      if (existing.siteId.isNotEmpty &&
          linkedEntry.siteId != null &&
          linkedEntry.siteId!.isNotEmpty &&
          linkedEntry.siteId != existing.siteId) {
        throw MediaPersistenceException('Site isolation violation: Cannot link media belonging to different site');
      }

      // R17: temporal precedence at the persistence boundary.
      final candidateCapturedAt = DateTime.tryParse(linkedEntry.capturedAt);
      if (candidateCapturedAt == null ||
          !candidateCapturedAt.toUtc().isBefore(existing.capturedAt.toUtc())) {
        throw MediaPersistenceException(
          'Temporal precedence violation: a BEFORE Non-Conformity must be captured strictly earlier than the observation it precedes.',
        );
      }
    }

    await (_db.update(_db.media)
          ..where((tbl) => tbl.id.equals(mediaId) & tbl.creatorId.equals(creatorId)))
        .write(
      MediaCompanion(
        activityTag: drift.Value(activityTag),
        observationType: drift.Value(observationType.name),
        linkedMediaId: drift.Value(validated.linkedMediaId),
        note: drift.Value(validated.note),
        synced: const drift.Value(0), // Mark unsynced for update synchronization
      ),
    );
  }

  @override
  Future<void> softDeleteMedia(String mediaId, {String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) {
      throw MediaIsolationException('Cannot soft delete media without authoritative creator identity.');
    }
    final count = await (_db.update(_db.media)
          ..where((tbl) => tbl.id.equals(mediaId) & tbl.creatorId.equals(creatorId)))
        .write(
      const MediaCompanion(isDeleted: drift.Value(1)),
    );
    if (count == 0) {
      throw MediaIsolationException('Media "$mediaId" not found or not owned by creator.');
    }
  }


  @override
  Stream<int> watchUnsyncedCount({String? creatorId}) {
    if (creatorId == null || creatorId.isEmpty) {
      // Fail closed: No unauthenticated counting
      return Stream.value(0);
    }
    final query = _db.selectOnly(_db.media)
      ..addColumns([_db.media.id.count()])
      ..where(_db.media.isDeleted.equals(0) &
          _db.media.synced.equals(0) &
          _db.media.creatorId.equals(creatorId));

    return query.map((row) => row.read(_db.media.id.count()) ?? 0).watchSingle();
  }

  @override
  Future<List<MediaItem>> getUnsyncedMedia({String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) {
      // Fail closed: Never return unsynced media across users or when unauthenticated
      return const [];
    }
    final query = _db.select(_db.media)
      ..where((tbl) =>
          tbl.isDeleted.equals(0) &
          tbl.synced.equals(0) &
          tbl.creatorId.equals(creatorId));

    final entries = await query.get();
    return entries.map(_entryToModel).toList();
  }

  @override
  Future<List<MediaItem>> getPendingOrFailedMedia({String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) {
      // Fail closed: Never return media across users or when unauthenticated
      return const [];
    }
    final query = _db.select(_db.media)
      ..where((tbl) =>
          tbl.isDeleted.equals(0) &
          (tbl.synced.equals(0) | tbl.synced.equals(3)) &
          tbl.creatorId.equals(creatorId));

    final entries = await query.get();
    return entries.map(_entryToModel).toList();
  }

  @override
  Future<List<MediaItem>> getSyncedPhotos({String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) {
      // Defense-in-depth: Fail closed if creatorId is omitted
      return const [];
    }
    final entries = await (_db.select(_db.media)
          ..where((tbl) =>
              tbl.isDeleted.equals(0) &
              tbl.synced.equals(1) &
              tbl.type.equals(MediaItemType.photo.name) &
              tbl.creatorId.equals(creatorId)))
        .get();
    return entries.map(_entryToModel).toList();
  }

  @override
  Future<void> updateSyncStatus(String mediaId, SyncStatusType status, {String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) {
      throw MediaIsolationException('Cannot update sync status without authoritative creator identity.');
    }
    final count = await (_db.update(_db.media)
          ..where((tbl) => tbl.id.equals(mediaId) & tbl.creatorId.equals(creatorId)))
        .write(
      MediaCompanion(synced: drift.Value(status.toInt())),
    );
    if (count == 0) {
      throw MediaIsolationException('Media "$mediaId" not found or not owned by creator.');
    }
  }

  @override
  Future<void> resetStuckSyncingMedia({String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) {
      return;
    }
    await (_db.update(_db.media)
          ..where((tbl) => tbl.synced.equals(SyncStatusType.syncing.toInt()) & tbl.creatorId.equals(creatorId)))
        .write(
      const MediaCompanion(synced: drift.Value(0)),
    );
  }

  @override
  Future<void> markTombstoneReconciled(String mediaId, {String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) {
      throw MediaIsolationException('Cannot mark tombstone reconciled without authoritative creator identity.');
    }
    final count = await (_db.update(_db.media)
          ..where((tbl) => tbl.id.equals(mediaId) & tbl.creatorId.equals(creatorId)))
        .write(
      const MediaCompanion(tombstoneReconciled: drift.Value(1)),
    );
    if (count == 0) {
      throw MediaIsolationException('Media "$mediaId" not found or not owned by creator.');
    }
  }

  @override
  Future<List<MediaItem>> getTombstoneSyncCandidates({String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) {
      // Fail closed: never surface another user's tombstones when unauthenticated
      return const [];
    }
    final query = _db.select(_db.media)
      ..where((tbl) =>
          tbl.isDeleted.equals(1) &
          tbl.synced.equals(SyncStatusType.syncing.toInt()).not() &
          tbl.creatorId.equals(creatorId));

    final entries = await query.get();
    return entries.map(_entryToModel).toList();
  }

  @override
  Stream<int> watchTombstoneCandidateCount({String? creatorId}) {
    if (creatorId == null || creatorId.isEmpty) {
      // Fail closed: no unauthenticated tombstone counting
      return Stream.value(0);
    }
    final query = _db.selectOnly(_db.media)
      ..addColumns([_db.media.id.count()])
      ..where(_db.media.isDeleted.equals(1) &
          _db.media.synced.equals(SyncStatusType.syncing.toInt()).not() &
          _db.media.creatorId.equals(creatorId));

    return query.map((row) => row.read(_db.media.id.count()) ?? 0).watchSingle();
  }

  @override
  Future<void> removeFromGallery(String mediaId, {String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) {
      throw MediaIsolationException('Cannot remove media from gallery without authoritative creator identity.');
    }
    final entry = await (_db.select(_db.media)
          ..where((tbl) => tbl.id.equals(mediaId) & tbl.creatorId.equals(creatorId)))
        .getSingleOrNull();
    if (entry == null) {
      throw MediaIsolationException('Media "$mediaId" not found or not owned by creator.');
    }
    await _storageService.deleteLocalMediaFiles(
      mediaId: entry.id,
      originalUri: entry.originalUri,
      uri: entry.uri,
      thumbUri: entry.thumbUri,
      type: entry.type,
    );
    await softDeleteMedia(mediaId, creatorId: creatorId);
  }

  @override
  Future<void> deletePermanently(String mediaId, {String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) {
      throw MediaIsolationException('Cannot delete media permanently without authoritative creator identity.');
    }
    final item = await getMediaById(mediaId, creatorId: creatorId);
    if (item == null) {
      throw MediaIsolationException('Media "$mediaId" not found or not owned by creator.');
    }
    await _storageService.deleteLocalMediaFiles(
      mediaId: item.id,
      originalUri: item.originalUri,
      uri: item.uri,
      thumbUri: item.thumbUri,
      type: item.type.name,
    );
    // C-2: the row becomes a hidden tombstone instead of being physically
    // destroyed. A physically deleted row could never propagate its cloud
    // tombstone, so an already-published Firestore ledger would stay live
    // (is_deleted = false) forever after the local record was destroyed. As a
    // tombstone candidate the row rides the existing B-1 synchronization —
    // retry/backoff/session-safe and idempotent, and a verified no-op for
    // items that were never published. Storage artifacts are untouched by
    // that propagation; physical row removal remains an account-deletion
    // concern (AppDatabase.clearAllUserData).
    await softDeleteMedia(mediaId, creatorId: creatorId);
  }


  MediaItem _entryToModel(MediaEntry e) {
    final isMsl = e.isAltitudeMsl != null ? e.isAltitudeMsl == 1 : null;
    final fixTimestamp = e.gnssFixTimestamp != null
        ? DateTime.tryParse(e.gnssFixTimestamp!)?.toUtc()
        : null;

    return MediaItem(
      id: e.id,
      siteId: e.siteId ?? '',
      originalUri: e.originalUri,
      uri: e.uri,
      thumbUri: e.thumbUri,
      type: MediaItemType.fromString(e.type),
      lat: e.lat,
      lon: e.lon,
      accuracyM: e.accuracyM,
      lowAccuracy: e.lowAccuracy == 1,
      altitude: e.altitudeM,                    // audit: real capture elevation ASL (vuln-0002)
      isAltitudeMsl: isMsl,
      verificationStatus: _resolveVerificationStatus(e),
      gnssSatelliteCount: e.gnssSatelliteCount,
      gnssSatellitesUsedInFix: e.gnssSatellitesUsedInFix,
      gnssFixTimestampUtc: fixTimestamp,
      activityTag: e.activityTag,
      observationType: ObservationType.fromString(e.observationType),
      linkedMediaId: e.linkedMediaId,
      note: e.note,
      capturedAt: DateTime.tryParse(e.capturedAt)?.toLocal() ?? _unknownCapturedAt,
      sha256Hash: e.sha256Hash,
      evidenceSha256Hash: e.evidenceSha256Hash, // audit: SHA-256 of watermarked evidence file
      capturedAddress: e.capturedAddress,       // audit: physical address at capture time
      creatorId: e.creatorId,                   // audit: creator UID for sync authorization
      syncStatus: SyncStatusType.fromInt(e.synced),
      isDeleted: e.isDeleted == 1,
      tombstoneReconciled: e.tombstoneReconciled == 1,
      hasAudioTrack: e.hasAudioTrack == null ? null : e.hasAudioTrack == 1,
      headingDegrees: e.headingDegrees,
    );
  }

  static HudStatus _resolveVerificationStatus(MediaEntry e) {
    if (e.verificationStatus != null && e.verificationStatus!.isNotEmpty) {
      return HudStatus.values.firstWhere(
        (s) => s.name.toUpperCase() == e.verificationStatus!.toUpperCase(),
        orElse: () => HudStatus.pending,
      );
    }
    // Legacy record fallback (pre-v8): Preserve the weakest defensible semantic.
    // Never imply a stronger verification state than established.
    final hasCoordinates = !(e.lat == 0.0 && e.lon == 0.0);
    if (!hasCoordinates) {
      return HudStatus.pending;
    }
    if (e.lowAccuracy == 1) {
      return HudStatus.degraded;
    }
    if (e.accuracyM == null) {
      return HudStatus.pending;
    }
    if (e.accuracyM! > 20.0) {
      return HudStatus.degraded;
    }
    return HudStatus.verified;
  }
}

final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final storageService = ref.watch(evidenceStorageServiceProvider);
  return LocalMediaRepository(db, storageService: storageService);
});
