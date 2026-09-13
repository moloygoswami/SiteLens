import 'package:sitelens/data/repositories/site_repository.dart';
import 'package:sitelens/domain/models/site_model.dart';

class FakeSiteRepository implements SiteRepository {
  final List<SiteModel> _sites;

  FakeSiteRepository({List<SiteModel>? initialSites})
      : _sites = initialSites != null ? List.from(initialSites) : [];

  @override
  Future<List<SiteModel>> getAllSites({String? creatorId}) async => List.unmodifiable(_sites);

  @override
  Future<SiteModel?> getSiteById(String id) async {
    return _sites.where((s) => s.id == id).firstOrNull;
  }

  @override
  Future<void> saveSite(SiteModel site) async {
    final idx = _sites.indexWhere((s) => s.id == site.id);
    if (idx >= 0) {
      _sites[idx] = site;
    } else {
      _sites.add(site);
    }
  }

  @override
  Future<void> deleteSite(String id, {String? creatorId}) async {
    _sites.removeWhere((s) => s.id == id);
  }

  @override
  Future<bool> hasMediaForSite(String siteId) async => false;

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
}
