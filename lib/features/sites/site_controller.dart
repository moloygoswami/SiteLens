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

      if (!mounted) return;

      SiteModel? selected;
      // Active-site continuity invariant: if state.activeSite is currently set and valid, preserve it!
      if (state.activeSite != null && sites.any((s) => s.id == state.activeSite!.id)) {
        selected = sites.firstWhere((s) => s.id == state.activeSite!.id);
      } else if (savedSiteId != null && savedSiteId.isNotEmpty) {
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

      // Asynchronously trigger remote site hydration in background without blocking local-first startup
      hydrateSites(currentUserId: effectiveUserId);
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

  /// Asynchronously hydrates authorized sites from Firestore into local Drift cache.
  /// Enforces the Active Site Continuity Invariant:
  /// Remote hydration NEVER overrides, clears, or replaces an already active valid site.
  Future<void> hydrateSites({String? currentUserId}) async {
    final effectiveUserId = currentUserId ?? _currentUserId;
    if (effectiveUserId == null || effectiveUserId.isEmpty) return;

    try {
      final hydrated = await _siteRepository.hydrateRemoteSites(effectiveUserId);
      if (!mounted) return;
      if (hydrated.isNotEmpty) {
        final sites = await _siteRepository.getAllSites(creatorId: effectiveUserId);
        if (!mounted) return;

        SiteModel? selected = state.activeSite;
        if (selected != null && sites.any((s) => s.id == selected!.id)) {
          // Active site is still valid; keep it! NEVER displace valid active site.
          selected = sites.firstWhere((s) => s.id == selected!.id);
        } else if (selected == null) {
          // If no site was currently active (e.g. fresh device/login), check saved preference or first hydrated site
          final prefs = await SharedPreferences.getInstance();
          if (!mounted) return;
          final key = '${_activeSiteKey}_$effectiveUserId';
          final savedSiteId = prefs.getString(key);
          if (savedSiteId != null && savedSiteId.isNotEmpty) {
            selected = sites.where((s) => s.id == savedSiteId).firstOrNull;
          }
          selected ??= sites.isNotEmpty ? sites.first : null;
          if (selected != null) {
            await prefs.setString(key, selected.id);
          }
        }

        if (!mounted) return;
        state = state.copyWith(
          activeSite: selected,
          availableSites: sites,
        );
      }
    } catch (e) {
      debugPrint('Background site hydration error: $e');
    }
  }

  Future<void> setActiveSite(SiteModel site, {String? currentUserId}) async {
    final effectiveUserId = currentUserId ?? _currentUserId;
    state = state.copyWith(activeSite: site);
    if (effectiveUserId != null && effectiveUserId.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final key = '${_activeSiteKey}_$effectiveUserId';
        await prefs.setString(key, site.id);
      } catch (e) {
        debugPrint('Failed to persist active site ID: $e');
      }
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
      throw StateError('Cannot create site without authenticated user session');
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

    final existingSites = await _siteRepository.getAllSites(creatorId: effectiveUserId);
    final isDuplicate = existingSites.any(
      (s) => s.siteCode.toLowerCase() == trimmedCode.toLowerCase(),
    );
    if (isDuplicate) {
      throw DuplicateSiteCodeException('Site code "$trimmedCode" already exists.');
    }

    final autoId = CryptoUtils.generateFirestoreId();

    final newSite = SiteModel(
      id: autoId,
      siteCode: trimmedCode,
      name: trimmedName,
      address: trimmedAddress,
      creatorId: effectiveUserId,
    );

    try {
      await _siteRepository.saveSite(newSite);
      await loadSitesAndActiveContext(shouldSeed: false, currentUserId: effectiveUserId);
      await setActiveSite(newSite, currentUserId: effectiveUserId);
      return newSite;
    } catch (e) {
      debugPrint('Error creating custom offline site: $e');
      state = state.copyWith(errorMessage: 'Failed to add site: $e');
      rethrow;
    }
  }

  Future<void> deleteSite(String id, {String? currentUserId}) async {
    final effectiveUserId = currentUserId ?? _currentUserId;
    if (effectiveUserId == null || effectiveUserId.isEmpty) {
      throw StateError('Cannot delete site without authenticated user session');
    }

    final hasMedia = await _siteRepository.hasMediaForSite(id, creatorId: effectiveUserId);
    if (hasMedia) {
      throw const SiteReferencedByMediaException('Cannot delete site because captured media references this site.');
    }

    try {
      await _siteRepository.deleteSite(id, creatorId: effectiveUserId);
      if (state.activeSite?.id == id) {
        state = state.copyWith(activeSite: null);
        final prefs = await SharedPreferences.getInstance();
        final key = '${_activeSiteKey}_$effectiveUserId';
        await prefs.remove(key);
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
