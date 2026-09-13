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

abstract class SiteRepository {
  Future<List<SiteModel>> getAllSites({String? creatorId});
  Future<SiteModel?> getSiteById(String id);
  Future<void> saveSite(SiteModel site);
  Future<void> deleteSite(String id, {String? creatorId});
  Future<bool> hasMediaForSite(String siteId);
  Future<void> seedDefaultSitesIfEmpty();
}

class LocalSiteRepository implements SiteRepository {
  final AppDatabase _db;

  LocalSiteRepository(this._db);

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
  Future<SiteModel?> getSiteById(String id) async {
    final entry = await (_db.select(_db.sites)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
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
  Future<void> saveSite(SiteModel site) async {
    await _db.into(_db.sites).insertOnConflictUpdate(
          SitesCompanion.insert(
            id: site.id,
            siteCode: drift.Value(site.siteCode),
            name: drift.Value(site.name),
            address: drift.Value(site.address),
            creatorId: drift.Value(site.creatorId),
          ),
        );
  }

  @override
  Future<bool> hasMediaForSite(String siteId) async {
    final countExpr = _db.media.id.count();
    final query = _db.selectOnly(_db.media)
      ..addColumns([countExpr])
      ..where(_db.media.siteId.equals(siteId));
    final row = await query.getSingleOrNull();
    final count = row?.read(countExpr) ?? 0;
    return count > 0;
  }

  @override
  Future<void> deleteSite(String id, {String? creatorId}) async {
    final hasMedia = await hasMediaForSite(id);
    if (hasMedia) {
      throw const SiteReferencedByMediaException(
        'Cannot delete site because captured media references this site.',
      );
    }
    final query = _db.delete(_db.sites)..where((tbl) => tbl.id.equals(id));
    if (creatorId != null && creatorId.isNotEmpty) {
      query.where((tbl) => tbl.creatorId.equals(creatorId));
    }
    await query.go();
  }

  @override
  Future<void> seedDefaultSitesIfEmpty() async {
    // Clean-slate: no default dummy sites seeded in production
  }
}

final siteRepositoryProvider = Provider<SiteRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return LocalSiteRepository(db);
});
