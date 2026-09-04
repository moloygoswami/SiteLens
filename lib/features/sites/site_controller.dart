import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/crypto_utils.dart';
import '../../domain/models/site_model.dart';
import '../../data/repositories/site_repository.dart';

class SiteState {
  final SiteModel? activeSite;
  final List<SiteModel> availableSites;
  final bool isLoading;
  final String? errorMessage;

  const SiteState({
    this.activeSite,
    this.availableSites = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  SiteState copyWith({
    SiteModel? activeSite,
    List<SiteModel>? availableSites,
    bool? isLoading,
    String? errorMessage,
  }) {
    return SiteState(
      activeSite: activeSite ?? this.activeSite,
      availableSites: availableSites ?? this.availableSites,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class SiteController extends StateNotifier<SiteState> {
  final SiteRepository _siteRepository;
  static const String _activeSiteKey = 'sitelens_active_site_id';

  SiteController(this._siteRepository) : super(const SiteState()) {
    loadSitesAndActiveContext();
  }

  Future<void> loadSitesAndActiveContext({bool shouldSeed = false, String? currentUserId}) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final sites = await _siteRepository.getAllSites(creatorId: currentUserId);

      final prefs = await SharedPreferences.getInstance();
      final key = currentUserId != null ? '${_activeSiteKey}_$currentUserId' : _activeSiteKey;
      final savedSiteId = prefs.getString(key) ?? prefs.getString(_activeSiteKey);

      SiteModel? selected;
      if (savedSiteId != null && savedSiteId.isNotEmpty) {
        selected = sites.where((s) => s.id == savedSiteId).firstOrNull;
      }
      // If none saved or invalid, default to first available site if available
      selected ??= sites.isNotEmpty ? sites.first : null;

      state = SiteState(
        activeSite: selected,
        availableSites: sites,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('Error loading sites: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load sites: $e',
      );
    }
  }

  Future<void> setActiveSite(SiteModel site, {String? currentUserId}) async {
    state = state.copyWith(activeSite: site);
    final prefs = await SharedPreferences.getInstance();
    final key = currentUserId != null ? '${_activeSiteKey}_$currentUserId' : _activeSiteKey;
    await prefs.setString(key, site.id);
  }

  Future<void> addCustomOfflineSite({
    required String siteCode,
    required String name,
    required String address,
    String? currentUserId,
  }) async {
    final newSite = SiteModel(
      id: CryptoUtils.generateFirestoreId(),
      siteCode: siteCode,
      name: name,
      address: address,
      creatorId: currentUserId,
    );

    await _siteRepository.saveSite(newSite);
    await loadSitesAndActiveContext(shouldSeed: false, currentUserId: currentUserId);
    await setActiveSite(newSite, currentUserId: currentUserId);
  }

  Future<void> deleteSite(String id, {String? currentUserId}) async {
    await _siteRepository.deleteSite(id);
    final prefs = await SharedPreferences.getInstance();
    final key = currentUserId != null ? '${_activeSiteKey}_$currentUserId' : _activeSiteKey;
    final savedSiteId = prefs.getString(key);
    if (savedSiteId == id) {
      await prefs.remove(key);
    }
    await loadSitesAndActiveContext(shouldSeed: false, currentUserId: currentUserId);
  }

  void resetSession() {
    state = const SiteState();
  }
}

final siteControllerProvider =
    StateNotifierProvider<SiteController, SiteState>((ref) {
  final repo = ref.watch(siteRepositoryProvider);
  return SiteController(repo);
});

final activeSiteProvider = Provider<SiteModel?>((ref) {
  final siteState = ref.watch(siteControllerProvider);
  return siteState.activeSite;
});
