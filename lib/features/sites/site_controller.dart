import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/session_service.dart';
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
  String? _currentUserId;
  static const String _activeSiteKey = 'sitelens_active_site_id';

  SiteController(this._siteRepository, {String? initialUserId})
      : _currentUserId = initialUserId,
        super(const SiteState()) {
    loadSitesAndActiveContext(currentUserId: _currentUserId);
  }

  String? get currentUserId => _currentUserId;

  void updateUser(String? newUserId) {
    if (_currentUserId != newUserId) {
      _currentUserId = newUserId;
      if (newUserId != null && newUserId.isNotEmpty) {
        loadSitesAndActiveContext(currentUserId: newUserId);
      } else {
        resetSession();
      }
    }
  }

  Future<void> loadSitesAndActiveContext({bool shouldSeed = false, String? currentUserId}) async {
    final effectiveUserId = currentUserId ?? _currentUserId;
    if (effectiveUserId == null || effectiveUserId.isEmpty) {
      // Unauthenticated session: clear site state without error
      state = const SiteState();
      return;
    }

    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final sites = await _siteRepository.getAllSites(creatorId: effectiveUserId);

      final prefs = await SharedPreferences.getInstance();
      final key = '${_activeSiteKey}_$effectiveUserId';
      final savedSiteId = prefs.getString(key);

      SiteModel? selected;
      if (savedSiteId != null && savedSiteId.isNotEmpty) {
        selected = sites.where((s) => s.id == savedSiteId).firstOrNull;
      }
      // If none saved or invalid, default to first available site if available
      selected ??= sites.isNotEmpty ? sites.first : null;

      if (!mounted) return;
      state = SiteState(
        activeSite: selected,
        availableSites: sites,
        isLoading: false,
        errorMessage: null,
      );
    } catch (e) {
      debugPrint('Error loading sites: $e');
      if (!mounted) return;
      state = SiteState(
        activeSite: null,
        availableSites: const [],
        isLoading: false,
        errorMessage: 'Failed to load sites: $e',
      );
    }
  }

  Future<void> setActiveSite(SiteModel site, {String? currentUserId}) async {
    final effectiveUserId = currentUserId ?? _currentUserId;
    state = state.copyWith(activeSite: site);
    if (effectiveUserId != null && effectiveUserId.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final key = '${_activeSiteKey}_$effectiveUserId';
      await prefs.setString(key, site.id);
    }
  }

  Future<SiteModel> addCustomOfflineSite({
    required String siteCode,
    required String name,
    required String address,
    String? currentUserId,
  }) async {
    final effectiveUserId = currentUserId ?? _currentUserId;
    if (effectiveUserId == null || effectiveUserId.isEmpty) {
      throw StateError('Cannot add site: user is not authenticated');
    }

    final trimmedCode = siteCode.trim();
    final trimmedName = name.trim();
    final trimmedAddress = address.trim();

    if (trimmedCode.isEmpty) {
      throw ArgumentError('Site code cannot be empty');
    }
    if (trimmedName.isEmpty) {
      throw ArgumentError('Site name cannot be empty');
    }

    // Check duplicate site code within current user's scope
    final existingSites = await _siteRepository.getAllSites(creatorId: effectiveUserId);
    if (existingSites.any((s) => s.siteCode.trim().toLowerCase() == trimmedCode.toLowerCase())) {
      throw DuplicateSiteCodeException('Site code "$trimmedCode" already exists');
    }

    try {
      final newSite = SiteModel(
        id: CryptoUtils.generateFirestoreId(),
        siteCode: trimmedCode,
        name: trimmedName,
        address: trimmedAddress,
        creatorId: effectiveUserId,
      );

      await _siteRepository.saveSite(newSite);
      await loadSitesAndActiveContext(shouldSeed: false, currentUserId: effectiveUserId);
      await setActiveSite(newSite, currentUserId: effectiveUserId);
      return newSite;
    } catch (e) {
      debugPrint('Error adding custom site: $e');
      state = state.copyWith(errorMessage: 'Failed to add site: $e');
      rethrow;
    }
  }

  Future<void> deleteSite(String id, {String? currentUserId}) async {
    final effectiveUserId = currentUserId ?? _currentUserId;
    try {
      await _siteRepository.deleteSite(id, creatorId: effectiveUserId);
      if (effectiveUserId != null && effectiveUserId.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final key = '${_activeSiteKey}_$effectiveUserId';
        final savedSiteId = prefs.getString(key);
        if (savedSiteId == id) {
          await prefs.remove(key);
        }
      }
      await loadSitesAndActiveContext(shouldSeed: false, currentUserId: effectiveUserId);
    } catch (e) {
      debugPrint('Error deleting site: $e');
      state = state.copyWith(errorMessage: 'Failed to delete site: $e');
      rethrow;
    }
  }

  void resetSession() {
    _currentUserId = null;
    state = const SiteState();
  }
}

final siteControllerProvider =
    StateNotifierProvider<SiteController, SiteState>((ref) {
  final repo = ref.watch(siteRepositoryProvider);
  final session = ref.watch(sessionServiceProvider);
  final controller = SiteController(
    repo,
    initialUserId: session.user?.uid,
  );

  ref.listen<UserSessionState>(sessionServiceProvider, (previous, next) {
    if (next.status == SessionStatus.unauthenticated || next.user == null) {
      controller.resetSession();
    } else if (next.user?.uid != controller.currentUserId) {
      controller.updateUser(next.user!.uid);
    }
  });

  return controller;
});

final activeSiteProvider = Provider<SiteModel?>((ref) {
  final siteState = ref.watch(siteControllerProvider);
  return siteState.activeSite;
});
