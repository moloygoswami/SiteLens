import 'package:sitelens/data/repositories/site_repository.dart';
import 'package:sitelens/domain/models/site_model.dart';

class FakeSiteRepository implements SiteRepository {
  final List<SiteModel> _sites;

  FakeSiteRepository({List<SiteModel>? initialSites})
      : _sites = initialSites != null ? List.from(initialSites) : [];

  @override
  Future<List<SiteModel>> getAllSites({String? creatorId}) async {
    // Fail closed: an unresolved creator identity returns zero rows, matching
    // the production repository's creator-scoped query semantics.
    if (creatorId == null || creatorId.isEmpty) return const [];
    return List.unmodifiable(_sites.where((s) => s.creatorId == creatorId));
  }

  @override
  Future<SiteModel?> getSiteById(String id, {String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) return null;
    return _sites
        .where((s) => s.id == id && s.creatorId == creatorId)
        .firstOrNull;
  }

  @override
  Future<void> saveSite(SiteModel site, {String? creatorId}) async {
    final idx = _sites.indexWhere((s) => s.id == site.id);
    if (idx >= 0) {
      _sites[idx] = site;
    } else {
      _sites.add(site);
    }
  }

  @override
  Future<void> deleteSite(String id, {String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) return;
    _sites.removeWhere((s) => s.id == id && s.creatorId == creatorId);
  }

  @override
  Future<bool> hasMediaForSite(String siteId, {String? creatorId}) async => false;

  @override
  Future<void> seedDefaultSitesIfEmpty() async {
    if (_sites.isEmpty) {
      _sites.add(
        const SiteModel(
          id: 'test-site-001',
          siteCode: 'E2E',
          name: 'E2E Test Inspection Site',
          address: '100 Test Avenue, Metro City',
        ),
      );
    }
  }

  @override
  Future<List<SiteModel>> hydrateRemoteSites(String userId) async => [];
}
