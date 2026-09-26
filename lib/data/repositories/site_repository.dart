import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../local/database/app_database.dart';
import '../local/database/database_provider.dart';
import '../../domain/models/site_model.dart';

class SiteReferencedByMediaException implements Exception {
  final String message;
  const SiteReferencedByMediaException([this.message = 'Cannot delete site because captured media references this site.']);
  @override
  String toString() => message;
}

class DuplicateSiteCodeException implements Exception {
  final String message;
  const DuplicateSiteCodeException([this.message = 'Site code already exists.']);
  @override
  String toString() => message;
}

class SiteIsolationException implements Exception {
  final String message;
  const SiteIsolationException([this.message = 'Creator isolation violation on site operation.']);
  @override
  String toString() => message;
}

abstract class SiteRepository {
  Future<List<SiteModel>> getAllSites({String? creatorId});
  Future<SiteModel?> getSiteById(String id, {String? creatorId});
  Future<void> saveSite(SiteModel site, {String? creatorId});
  Future<void> deleteSite(String id, {String? creatorId});
  Future<bool> hasMediaForSite(String siteId, {String? creatorId});
  Future<void> seedDefaultSitesIfEmpty();
  Future<List<SiteModel>> hydrateRemoteSites(String userId);
}

class LocalSiteRepository implements SiteRepository {
  final AppDatabase _db;
  final FirebaseFirestore? _firestore;

  LocalSiteRepository(this._db, {FirebaseFirestore? firestore}) : _firestore = firestore;

  @override
  Future<List<SiteModel>> getAllSites({String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) {
      // Fail closed: Never return all sites across users when unauthenticated or creatorId omitted
      return [];
    }
    final query = _db.select(_db.sites)..where((tbl) => tbl.creatorId.equals(creatorId));
    final entries = await query.get();
    return entries
        .map((e) => SiteModel(
              id: e.id,
              siteCode: e.siteCode ?? '',
              name: e.name ?? '',
              address: e.address ?? '',
              creatorId: e.creatorId,
            ))
        .toList();
  }

  @override
  Future<SiteModel?> getSiteById(String id, {String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) {
      // Strict fail-closed: unauthenticated sessions must never access local sites
      return null;
    }
    final query = _db.select(_db.sites)
      ..where((tbl) => tbl.id.equals(id) & tbl.creatorId.equals(creatorId));
    final entry = await query.getSingleOrNull();
    if (entry == null) return null;
    return SiteModel(
      id: entry.id,
      siteCode: entry.siteCode ?? '',
      name: entry.name ?? '',
      address: entry.address ?? '',
      creatorId: entry.creatorId,
    );
  }

  @override
  Future<void> saveSite(SiteModel site, {String? creatorId}) async {
    final effectiveCreatorId = creatorId ?? site.creatorId;
    if (effectiveCreatorId == null || effectiveCreatorId.isEmpty) {
      throw const SiteIsolationException('Fail closed: Site must have a valid non-empty creatorId.');
    }
    if (creatorId != null &&
        site.creatorId != null &&
        site.creatorId!.isNotEmpty &&
        creatorId != site.creatorId) {
      throw const SiteIsolationException('Creator isolation violation: Caller creatorId does not match site creatorId.');
    }

    final existing = await (_db.select(_db.sites)..where((tbl) => tbl.id.equals(site.id))).getSingleOrNull();
    if (existing != null) {
      if (existing.creatorId != null &&
          existing.creatorId!.isNotEmpty &&
          existing.creatorId != effectiveCreatorId) {
        throw const SiteIsolationException('Creator isolation violation: Cannot overwrite or mutate site belonging to different creator');
      }
    }

    await _db.into(_db.sites).insertOnConflictUpdate(
          SitesCompanion.insert(
            id: site.id,
            siteCode: drift.Value(site.siteCode),
            name: drift.Value(site.name),
            address: drift.Value(site.address),
            creatorId: drift.Value(effectiveCreatorId),
          ),
        );
  }

  @override
  Future<bool> hasMediaForSite(String siteId, {String? creatorId}) async {
    // R24 retention gate (creator-scoped, fail-closed).
    //
    // A site may be deleted only when EVERY media row it contains is a
    // purge-eligible tombstone. Purge-eligible means fully reconciled with the
    // cloud deletion ledger (architecture §8.4 / §25.1):
    //   is_deleted = 1 AND tombstone_reconciled = 1 AND creator_id = creatorId
    //
    // Everything else blocks deletion and is retained:
    //   * active media (is_deleted = 0) — the R23 active-media guard,
    //   * unreconciled tombstones (tombstone_reconciled = 0), including
    //     never-published items not yet settled by the verification no-op, and
    //   * rows not owned by the authenticated creator (fail-closed).
    if (creatorId == null || creatorId.isEmpty) {
      // Fail closed: an unauthenticated/unscoped caller may never delete a site.
      return true;
    }

    final totalExpr = _db.media.id.count();
    final totalRow = await (_db.selectOnly(_db.media)
          ..addColumns([totalExpr])
          ..where(_db.media.siteId.equals(siteId)))
        .getSingleOrNull();
    final total = totalRow?.read(totalExpr) ?? 0;
    if (total == 0) {
      // No media: nothing to retain and nothing to purge.
      return false;
    }

    final eligibleExpr = _db.media.id.count();
    final eligibleRow = await (_db.selectOnly(_db.media)
          ..addColumns([eligibleExpr])
          ..where(_db.media.siteId.equals(siteId) &
              _db.media.creatorId.equals(creatorId) &
              _db.media.isDeleted.equals(1) &
              _db.media.tombstoneReconciled.equals(1)))
        .getSingleOrNull();
    final eligible = eligibleRow?.read(eligibleExpr) ?? 0;

    // Block unless every row in the site is purge-eligible, so a partial purge
    // can never strand a row behind a deleted site.
    return total != eligible;
  }

  @override
  Future<void> deleteSite(String id, {String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) {
      // Fail closed: Never delete site without authenticated creatorId
      return;
    }

    await _db.transaction(() async {
      // Creator authorization check: verify site exists and belongs to creator
      final site = await (_db.select(_db.sites)
            ..where((tbl) => tbl.id.equals(id) & tbl.creatorId.equals(creatorId)))
          .getSingleOrNull();
      if (site == null) {
        // Site does not exist or does not belong to creator
        return;
      }

      final hasBlockingMedia = await hasMediaForSite(id, creatorId: creatorId);
      if (hasBlockingMedia) {
        throw const SiteReferencedByMediaException(
          'Cannot delete site because captured media references this site.',
        );
      }

      // R24: atomically purge only fully reconciled, creator-owned tombstones.
      // The retention gate above guarantees the site contains nothing else, so
      // this removes every remaining row and satisfies the SQLite FOREIGN KEY
      // constraint. The predicate is deterministic and idempotent.
      await (_db.delete(_db.media)
            ..where((tbl) =>
                tbl.siteId.equals(id) &
                tbl.creatorId.equals(creatorId) &
                tbl.isDeleted.equals(1) &
                tbl.tombstoneReconciled.equals(1)))
          .go();

      final query = _db.delete(_db.sites)
        ..where((tbl) => tbl.id.equals(id) & tbl.creatorId.equals(creatorId));
      await query.go();
    });
  }

  @override
  Future<void> seedDefaultSitesIfEmpty() async {
    // Clean-slate: no default dummy sites seeded in production
  }

  @override
  Future<List<SiteModel>> hydrateRemoteSites(String userId) async {
    final firestore = _firestore;
    if (firestore == null || userId.isEmpty) {
      return [];
    }

    // Creator-scoped query: only sites recorded as created by this identity
    // (v1 creator-owned domain). Errors deliberately propagate to the caller:
    // a failed hydration is NOT evidence that the user has zero sites, and the
    // two states must never be conflated (PRD §9.3, AC-SITE-07).
    final createdSnap = await firestore
        .collection('sites')
        .where('creator_id', isEqualTo: userId)
        .get();

    final hydratedSites = <String, SiteModel>{};
    for (final doc in createdSnap.docs) {
      final data = doc.data();
      final docCreatorId = (data['creator_id'] as String?) ?? '';
      // Defense in depth: never adopt a row whose recorded creator differs,
      // even if it somehow surfaces through the creator-scoped query.
      if (docCreatorId != userId) continue;
      hydratedSites[doc.id] = SiteModel(
        id: doc.id,
        siteCode: (data['site_code'] as String?) ?? '',
        name: (data['name'] as String?) ?? '',
        address: (data['address'] as String?) ?? '',
        creatorId: userId,
      );
    }

    // Upsert discovered remote sites into the local Drift cache. saveSite
    // rejects any attempt to re-stamp an existing row's creator identity
    // (fail-closed), so hydration can never reassign site ownership.
    for (final site in hydratedSites.values) {
      await saveSite(site);
    }

    return hydratedSites.values.toList();
  }
}

final siteRepositoryProvider = Provider<SiteRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  FirebaseFirestore? firestore;
  try {
    firestore = FirebaseFirestore.instance;
  } catch (_) {
    // Firebase not initialized in unit test or headless environment
  }
  return LocalSiteRepository(db, firestore: firestore);
});
