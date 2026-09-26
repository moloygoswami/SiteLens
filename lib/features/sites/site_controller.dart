import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/session_service.dart';
import '../../core/utils/crypto_utils.dart';
import '../../domain/models/site_model.dart';
import '../../data/repositories/site_repository.dart';

/// Lifecycle of a remote site-hydration attempt for the authenticated creator.
///
/// The zero-local-sites UI distinguishes four genuinely different conditions
/// (PRD §9.3, AC-SITE-07); this status keeps a failed hydration from ever being
/// conflated with a successful hydration that returned zero sites.
enum SiteHydrationStatus {
  /// No hydration attempt has completed this session (initial, or offline).
  idle,

  /// A remote hydration attempt is currently in flight.
  hydrating,

  /// The last hydration attempt completed successfully (zero remote sites is a
  /// valid, explicit result of a successful hydration).
  hydrated,

  /// The last hydration attempt failed (auth/permission error, transient
  /// network failure, timeout). This is never evidence of zero sites.
  failed,
}

class SiteState {
  final SiteModel? activeSite;
  final List<SiteModel> availableSites;
  final bool isLoading;
  final String? errorMessage;
  final SiteHydrationStatus hydrationStatus;
  final bool isOnline;

  const SiteState({
    this.activeSite,
    this.availableSites = const [],
    this.isLoading = false,
    this.errorMessage,
    this.hydrationStatus = SiteHydrationStatus.idle,
    this.isOnline = true,
  });

  SiteState copyWith({
    SiteModel? activeSite,
    bool clearActiveSite = false,
    List<SiteModel>? availableSites,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    SiteHydrationStatus? hydrationStatus,
    bool? isOnline,
  }) {
    return SiteState(
      activeSite: clearActiveSite ? null : (activeSite ?? this.activeSite),
      availableSites: availableSites ?? this.availableSites,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      hydrationStatus: hydrationStatus ?? this.hydrationStatus,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}

class SiteController extends StateNotifier<SiteState> {
  final SiteRepository _siteRepository;
  final Connectivity? _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  String? _currentUserId;
  static const String _activeSiteKey = 'sitelens_active_site_id';

  SiteController(
    this._siteRepository, {
    String? initialUserId,
    Connectivity? connectivity,
  })  : _currentUserId = initialUserId,
        _connectivity = connectivity,
        super(const SiteState()) {
    _listenConnectivity();
    loadSitesAndActiveContext(currentUserId: _currentUserId);
  }

  String? get currentUserId => _currentUserId;

  /// Connectivity transitions NEVER touch the active site — network loss or
  /// restoration must never clear, replace, duplicate, or silently switch it
  /// (PRD §9.3, architecture §8.2, AC-SITE-04).
  void _listenConnectivity() {
    final connectivity = _connectivity;
    if (connectivity == null) return;
    try {
      _connectivitySub = connectivity.onConnectivityChanged.listen(
        (results) {
          final online = !results.contains(ConnectivityResult.none);
          if (mounted && state.isOnline != online) {
            state = state.copyWith(isOnline: online);
          }
        },
        onError: (_) {},
      );
    } catch (_) {
      // Connectivity stream unavailable (e.g. headless test environment):
      // the controller simply keeps its default online assumption.
    }
  }

  Future<bool> _checkOnline() async {
    final connectivity = _connectivity;
    if (connectivity == null) return true;
    try {
      final results = await connectivity.checkConnectivity();
      return !results.contains(ConnectivityResult.none);
    } catch (_) {
      // Plugin unavailable: assume online so the UI never falsely reports
      // an offline state.
      return true;
    }
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  void updateUser(String? newUserId) {
    if (_currentUserId != newUserId) {
      _currentUserId = newUserId;
      if (newUserId != null && newUserId.isNotEmpty) {
        // Session isolation: the previous user's site state is cleared
        // synchronously, before the new creator-scoped load completes, so a
        // shared device never exposes one user's sites to another (PRD §6).
        state = const SiteState(isLoading: true);
        loadSitesAndActiveContext(currentUserId: newUserId);
      } else {
        resetSession();
      }
    }
  }

  Future<void> loadSitesAndActiveContext({
    bool shouldSeed = false,
    String? currentUserId,
    bool allowDefaultSelection = true,
  }) async {
    final effectiveUserId = currentUserId ?? _currentUserId;
    if (effectiveUserId == null || effectiveUserId.isEmpty) {
      // Unauthenticated session: clear site state without error
      state = const SiteState();
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);
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
        // Creator-authorized restoration: the persisted per-user id is honored
        // only when it resolves to one of THIS creator's cached sites. An
        // invalid or foreign id fails closed — it is never activated.
        selected = sites.where((s) => s.id == savedSiteId).firstOrNull;
      }
      // Startup/restoration default: first cached site (architecture §8.1).
      // Never applied where an explicit-selection-only context forbids it
      // (e.g. after deleting the active site).
      if (selected == null && allowDefaultSelection) {
        selected = sites.isNotEmpty ? sites.first : null;
      }

      if (!mounted) return;
      state = SiteState(
        activeSite: selected,
        availableSites: sites,
        isLoading: false,
        hydrationStatus: state.hydrationStatus,
        isOnline: state.isOnline,
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
        hydrationStatus: state.hydrationStatus,
        isOnline: state.isOnline,
      );
    }
  }

  /// Asynchronously hydrates authorized sites from Firestore into local Drift cache.
  /// Enforces the Active Site Continuity Invariant:
  /// Remote hydration NEVER overrides, clears, or replaces an already active valid site.
  /// A hydration failure is recorded as [SiteHydrationStatus.failed] and is never
  /// conflated with a successful hydration that returned zero sites.
  Future<void> hydrateSites({String? currentUserId}) async {
    final effectiveUserId = currentUserId ?? _currentUserId;
    if (effectiveUserId == null || effectiveUserId.isEmpty) return;

    final online = await _checkOnline();
    if (!mounted) return;
    if (state.isOnline != online) {
      state = state.copyWith(isOnline: online);
    }
    if (!online) {
      // Offline: hydration is not attempted and offline is never reported as
      // a hydration failure — the local cache remains fully authoritative.
      return;
    }

    state = state.copyWith(hydrationStatus: SiteHydrationStatus.hydrating);

    try {
      final hydrated = await _siteRepository.hydrateRemoteSites(effectiveUserId);
      if (!mounted) return;

      var sites = state.availableSites;
      if (hydrated.isNotEmpty) {
        // Re-read the merged local cache so newly hydrated sites become
        // immediately selectable.
        sites = await _siteRepository.getAllSites(creatorId: effectiveUserId);
        if (!mounted) return;
      }

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
        hydrationStatus: SiteHydrationStatus.hydrated,
        clearError: true,
      );
    } catch (e) {
      debugPrint('Background site hydration error: $e');
      if (!mounted) return;
      // Fail closed: a failed hydration is not evidence of zero sites. The
      // valid active site and the local cache are preserved untouched.
      state = state.copyWith(hydrationStatus: SiteHydrationStatus.failed);
    }
  }

  Future<void> setActiveSite(SiteModel site, {String? currentUserId}) async {
    final effectiveUserId = currentUserId ?? _currentUserId;
    if (effectiveUserId != null &&
        effectiveUserId.isNotEmpty &&
        site.creatorId != null &&
        site.creatorId!.isNotEmpty &&
        site.creatorId != effectiveUserId) {
      throw const SiteIsolationException('Cannot set active site belonging to another creator.');
    }
    state = state.copyWith(activeSite: site, clearError: true);
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
      final wasActive = state.activeSite?.id == id;
      if (wasActive) {
        // Active-site authority: deleting the active site clears the selection
        // and its persisted per-user preference. It never silently substitutes
        // another site — the active site changes only through explicit user
        // selection or the session boundary.
        final prefs = await SharedPreferences.getInstance();
        final key = '${_activeSiteKey}_$effectiveUserId';
        await prefs.remove(key);
      }
      await loadSitesAndActiveContext(
        shouldSeed: false,
        currentUserId: effectiveUserId,
        allowDefaultSelection: !wasActive,
      );
    } catch (e) {
      debugPrint('Error deleting site: $e');
      state = state.copyWith(errorMessage: 'Failed to delete site: $e');
      rethrow;
    }
  }

  /// Session-boundary clearing (architecture §6.2, security §9): in-memory
  /// active-site state is cleared on sign-out. The persisted per-user
  /// preference is already scoped per identity and requires no clearing.
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
    connectivity: Connectivity(),
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
