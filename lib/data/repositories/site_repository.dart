import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../local/database/app_database.dart';
import '../local/database/database_provider.dart';
import '../../domain/models/site_model.dart';

abstract class SiteRepository {
  Future<List<SiteModel>> getAllSites({String? creatorId});
  Future<SiteModel?> getSiteById(String id);
  Future<void> saveSite(SiteModel site);
  Future<void> deleteSite(String id);
  Future<void> seedDefaultSitesIfEmpty();
}

class LocalSiteRepository implements SiteRepository {
  final AppDatabase _db;

  LocalSiteRepository(this._db);

  @override
  Future<List<SiteModel>> getAllSites({String? creatorId}) async {
    final query = _db.select(_db.sites);
    if (creatorId != null && creatorId.isNotEmpty) {
      query.where((tbl) => tbl.creatorId.equals(creatorId) | tbl.creatorId.isNull());
    }
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
  Future<void> deleteSite(String id) async {
    await (_db.delete(_db.sites)..where((tbl) => tbl.id.equals(id))).go();
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
