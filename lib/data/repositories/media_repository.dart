import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../local/database/app_database.dart';
import '../local/database/database_provider.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/enums.dart';
import '../../core/utils/haversine.dart';
import '../../features/camera/services/evidence_storage_service.dart';

class MediaConflictException implements Exception {
  final String message;
  MediaConflictException(this.message);

  @override
  String toString() => 'MediaConflictException: $message';
}

abstract class MediaRepository {
  Future<void> insertMedia(MediaItem item);
  Future<MediaItem?> getMediaById(String id);
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
    double radiusMeters = 10.0,
    String? currentMediaId,
    String? creatorId,
  });
  Future<void> linkMedia({required String mediaId, required String linkedMediaId});
  Future<void> updateTags({required String mediaId, required String activityTag, required ObservationType observationType, String? note});
  Future<void> softDeleteMedia(String mediaId);
  Stream<int> watchUnsyncedCount({String? creatorId});
  Future<List<MediaItem>> getUnsyncedMedia({String? creatorId});
  Future<List<MediaItem>> getPendingOrFailedMedia({String? creatorId});
  Future<List<MediaItem>> getSyncedPhotos({String? creatorId});
  Future<void> updateSyncStatus(String mediaId, SyncStatusType status);
  Future<void> resetStuckSyncingMedia();
  Future<void> removeFromGallery(String mediaId);
  Future<void> deletePermanently(String mediaId);
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

  @override
  Future<void> insertMedia(MediaItem item) async {
    final existing = await (_db.select(_db.media)..where((tbl) => tbl.id.equals(item.id))).getSingleOrNull();
    if (existing != null) {
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
            activityTag: drift.Value(item.activityTag),
            observationType: drift.Value(item.observationType.name),
            linkedMediaId: drift.Value(item.linkedMediaId),
            note: drift.Value(item.note),
            capturedAt: item.capturedAt.toUtc().toIso8601String(),
            sha256Hash: drift.Value(item.sha256Hash),
            evidenceSha256Hash: drift.Value(item.evidenceSha256Hash), // audit: SHA-256 of watermarked evidence file
            capturedAddress: drift.Value(item.capturedAddress),       // audit: physical address at capture time
            creatorId: drift.Value(item.creatorId),                   // audit: creator UID for sync authorization
            synced: drift.Value(item.syncStatus.toInt()),
            isDeleted: drift.Value(item.isDeleted ? 1 : 0),
          ),
        );
  }

  @override
  Future<MediaItem?> getMediaById(String id) async {
    final entry = await (_db.select(_db.media)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
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
    final query = _db.select(_db.media)
      ..where((tbl) => tbl.isDeleted.equals(0))
      ..orderBy([(tbl) => drift.OrderingTerm.desc(tbl.capturedAt)]);

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
    if (creatorId != null && creatorId.isNotEmpty) {
      query.where((tbl) => tbl.creatorId.equals(creatorId));
    }

    return query.watch().map((list) => list.map(_entryToModel).toList());
  }

  @override
  Future<List<MediaItem>> searchMedia({required String query, String? siteId, String? creatorId}) async {
    final cleanQuery = query.toLowerCase().trim();
    final select = _db.select(_db.media)..where((tbl) => tbl.isDeleted.equals(0));
    if (siteId != null && siteId.isNotEmpty) {
      select.where((tbl) => tbl.siteId.equals(siteId));
    }
    if (creatorId != null && creatorId.isNotEmpty) {
      select.where((tbl) => tbl.creatorId.equals(creatorId));
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
  }) async {
    // Defense-in-depth: Fail closed if creatorId is required but omitted
    if (requireCreator && (creatorId == null || creatorId.isEmpty)) {
      return const [];
    }

    // Step 1: Compute Bounding Box
    final bbox = SpatialMathUtils.calculateBoundingBox(centerLat, centerLon, radiusMeters);

    // Step 2: Query candidate records using indexed lat/lon
    final query = _db.select(_db.media)
      ..where(
        (tbl) =>
            tbl.isDeleted.equals(0) &
            tbl.lat.isBiggerOrEqualValue(bbox.minLat) &
            tbl.lat.isSmallerOrEqualValue(bbox.maxLat) &
            tbl.lon.isBiggerOrEqualValue(bbox.minLon) &
            tbl.lon.isSmallerOrEqualValue(bbox.maxLon),
      );

    if (creatorId != null && creatorId.isNotEmpty) {
      query.where((tbl) => tbl.creatorId.equals(creatorId));
    }
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
      final distance = SpatialMathUtils.haversineDistanceMeters(centerLat, centerLon, candidate.lat, candidate.lon);
      if (distance <= radiusMeters) {
        results.add(NearbyMediaResult(
          item: _entryToModel(candidate),
          distanceMeters: distance,
        ));
      }
    }

    // Step 4: Sort by distance, then recency
    results.sort((a, b) {
      final dCompare = a.distanceMeters.compareTo(b.distanceMeters);
      if (dCompare != 0) return dCompare;
      return b.item.capturedAt.compareTo(a.item.capturedAt);
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
    double radiusMeters = 10.0,
    String? currentMediaId,
    String? creatorId,
  }) async {
    // 1. Fetch all already-resolved linked_media_ids on this site (Closed observations that are not deleted)
    final resolvedQuery = _db.selectOnly(_db.media)
      ..addColumns([_db.media.linkedMediaId])
      ..where(_db.media.siteId.equals(siteId) &
          _db.media.observationType.equals(ObservationType.closed.name) &
          _db.media.linkedMediaId.isNotNull() &
          _db.media.isDeleted.equals(0));

    if (creatorId != null && creatorId.isNotEmpty) {
      resolvedQuery.where(_db.media.creatorId.equals(creatorId));
    }

    final resolvedRows = await resolvedQuery.get();

    final resolvedIds = resolvedRows
        .map((r) => r.read(_db.media.linkedMediaId))
        .whereType<String>()
        .toSet();

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
        requireCreator: false,
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
      requireCreator: false,
    );

    for (final match in fallbackMatches) {
      if (!resolvedIds.contains(match.item.id)) {
        return match.item;
      }
    }

    return null;
  }

  @override
  Future<void> linkMedia({required String mediaId, required String linkedMediaId}) async {
    await (_db.update(_db.media)..where((tbl) => tbl.id.equals(mediaId))).write(
      MediaCompanion(linkedMediaId: drift.Value(linkedMediaId)),
    );
  }

  @override
  Future<void> updateTags({required String mediaId, required String activityTag, required ObservationType observationType, String? note}) async {
    await (_db.update(_db.media)..where((tbl) => tbl.id.equals(mediaId))).write(
      MediaCompanion(
        activityTag: drift.Value(activityTag),
        observationType: drift.Value(observationType.name),
        note: drift.Value(note),
        synced: const drift.Value(0), // Mark unsynced for update synchronization
      ),
    );
  }

  @override
  Future<void> softDeleteMedia(String mediaId) async {
    await (_db.update(_db.media)..where((tbl) => tbl.id.equals(mediaId))).write(
      const MediaCompanion(isDeleted: drift.Value(1)),
    );
  }

  @override
  Stream<int> watchUnsyncedCount({String? creatorId}) {
    final query = _db.selectOnly(_db.media)
      ..addColumns([_db.media.id.count()]);

    if (creatorId != null && creatorId.isNotEmpty) {
      query.where(_db.media.isDeleted.equals(0) & _db.media.synced.equals(0) & (_db.media.creatorId.equals(creatorId) | _db.media.creatorId.isNull()));
    } else {
      query.where(_db.media.isDeleted.equals(0) & _db.media.synced.equals(0));
    }

    return query.map((row) => row.read(_db.media.id.count()) ?? 0).watchSingle();
  }

  @override
  Future<List<MediaItem>> getUnsyncedMedia({String? creatorId}) async {
    final query = _db.select(_db.media)..where((tbl) => tbl.isDeleted.equals(0) & tbl.synced.equals(0));
    if (creatorId != null && creatorId.isNotEmpty) {
      query.where((tbl) => tbl.creatorId.equals(creatorId) | tbl.creatorId.isNull());
    }
    final entries = await query.get();
    return entries.map(_entryToModel).toList();
  }

  @override
  Future<List<MediaItem>> getPendingOrFailedMedia({String? creatorId}) async {
    final query = _db.select(_db.media)
      ..where((tbl) =>
          tbl.isDeleted.equals(0) &
          (tbl.synced.equals(0) | tbl.synced.equals(3)));

    if (creatorId != null) {
      query.where((tbl) => tbl.creatorId.equals(creatorId) | tbl.creatorId.isNull());
    }

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
  Future<void> updateSyncStatus(String mediaId, SyncStatusType status) async {
    await (_db.update(_db.media)..where((tbl) => tbl.id.equals(mediaId))).write(
      MediaCompanion(synced: drift.Value(status.toInt())),
    );
  }

  @override
  Future<void> resetStuckSyncingMedia() async {
    await (_db.update(_db.media)..where((tbl) => tbl.synced.equals(SyncStatusType.syncing.toInt()))).write(
      const MediaCompanion(synced: drift.Value(0)),
    );
  }

  @override
  Future<void> removeFromGallery(String mediaId) async {
    final entry = await (_db.select(_db.media)..where((tbl) => tbl.id.equals(mediaId))).getSingleOrNull();
    if (entry != null) {
      await _storageService.deleteLocalMediaFiles(
        mediaId: entry.id,
        originalUri: entry.originalUri,
        uri: entry.uri,
        thumbUri: entry.thumbUri,
        type: entry.type,
      );
    } else {
      await _storageService.deleteLocalMediaFiles(mediaId: mediaId);
    }
    await softDeleteMedia(mediaId);
  }

  @override
  Future<void> deletePermanently(String mediaId) async {
    final item = await getMediaById(mediaId);
    if (item != null) {
      await _storageService.deleteLocalMediaFiles(
        mediaId: item.id,
        originalUri: item.originalUri,
        uri: item.uri,
        thumbUri: item.thumbUri,
        type: item.type.name,
      );
    }
    await (_db.delete(_db.media)..where((tbl) => tbl.id.equals(mediaId))).go();
  }

  MediaItem _entryToModel(MediaEntry e) {
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
      activityTag: e.activityTag,
      observationType: ObservationType.fromString(e.observationType),
      linkedMediaId: e.linkedMediaId,
      note: e.note,
      capturedAt: DateTime.tryParse(e.capturedAt)?.toLocal() ?? DateTime.now(),
      sha256Hash: e.sha256Hash,
      evidenceSha256Hash: e.evidenceSha256Hash, // audit: SHA-256 of watermarked evidence file
      capturedAddress: e.capturedAddress,       // audit: physical address at capture time
      creatorId: e.creatorId,                   // audit: creator UID for sync authorization
      syncStatus: SyncStatusType.fromInt(e.synced),
      isDeleted: e.isDeleted == 1,
    );
  }
}

final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final storageService = ref.watch(evidenceStorageServiceProvider);
  return LocalMediaRepository(db, storageService: storageService);
});
