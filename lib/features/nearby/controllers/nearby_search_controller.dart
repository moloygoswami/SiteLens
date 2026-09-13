import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/controllers/nearby_settings_controller.dart';
import '../../../core/services/auth_service.dart';
import '../../../data/repositories/media_repository.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/media_item.dart';
import '../models/nearby_search_state.dart';

final nearbySearchControllerProvider = StateNotifierProvider.autoDispose
    .family<NearbySearchNotifier, NearbySearchState, MediaItem?>((ref, sourceMedia) {
  final mediaRepo = ref.watch(mediaRepositoryProvider);
  final defaultRadius = ref.watch(nearbySettingsProvider);
  String? creatorId;
  try {
    final authUser = ref.read(authStateProvider).value;
    creatorId = authUser?.uid ?? sourceMedia?.creatorId;
    if (creatorId == null) {
      final authService = ref.read(authServiceProvider);
      creatorId = authService.currentUser?.uid;
    }
  } catch (_) {
    creatorId = sourceMedia?.creatorId;
  }
  final notifier = NearbySearchNotifier(
    mediaRepo,
    sourceMedia: sourceMedia,
    initialRadiusMeters: defaultRadius,
    creatorId: creatorId,
  );
  ref.listen<AsyncValue<AuthUser?>>(authStateProvider, (prev, next) {
    final newUid = next.value?.uid;
    if (newUid != null && newUid.isNotEmpty && newUid != notifier.creatorId) {
      notifier.updateCreatorId(newUid);
    }
  });
  return notifier;
});

class NearbySearchNotifier extends StateNotifier<NearbySearchState> {
  final MediaRepository _mediaRepo;
  String? _creatorId;

  String? get creatorId => _creatorId;

  void updateCreatorId(String uid) {
    if (_creatorId == uid) return;
    _creatorId = uid;
    executeSearch();
  }

  NearbySearchNotifier(
    this._mediaRepo, {
    MediaItem? sourceMedia,
    double defaultLat = 0.0,
    double defaultLon = 0.0,
    double initialRadiusMeters = 25.0,
    String? creatorId,
  })  : _creatorId = creatorId ?? sourceMedia?.creatorId,
        super(NearbySearchState(
          sourceMedia: sourceMedia,
          centerLat: sourceMedia?.lat ?? defaultLat,
          centerLon: sourceMedia?.lon ?? defaultLon,
          radiusMeters: initialRadiusMeters,
        )) {
    // Automatically trigger initial spatial search
    executeSearch();
  }

  /// Sets the search center point explicitly (e.g. for custom coordinate exploration).
  void setCenter(double lat, double lon) {
    if (state.centerLat == lat && state.centerLon == lon) return;
    state = state.copyWith(centerLat: lat, centerLon: lon);
    executeSearch();
  }

  /// Sets the target site ID and center point in a single search execution.
  void setTargetLocation({String? siteId, double? lat, double? lon}) {
    state = state.copyWith(
      targetSiteId: siteId ?? state.targetSiteId,
      centerLat: lat ?? state.centerLat,
      centerLon: lon ?? state.centerLon,
    );
    executeSearch();
  }

  /// Sets the target site ID explicitly (e.g. when launched from review tag picker).
  void setTargetSiteId(String? siteId) {
    if (state.targetSiteId == siteId) return;
    state = state.copyWith(targetSiteId: siteId);
    executeSearch();
  }

  /// Changes the search radius (in meters) and refreshes results.
  void setRadius(double radiusMeters) {
    if (state.radiusMeters == radiusMeters) return;
    state = state.copyWith(radiusMeters: radiusMeters);
    executeSearch();
  }

  /// Toggles view mode (Grouped List, Location Timeline, Spatial Map) without re-querying SQLite.
  void setViewMode(NearbyViewMode mode) {
    if (state.viewMode == mode) return;
    state = state.copyWith(viewMode: mode);
  }

  /// Updates search filters (same site, activity, observation type, date range) and refreshes results.
  void setFilters(NearbySearchFilters filters) {
    state = state.copyWith(filters: filters);
    executeSearch();
  }

  /// Sets Same Site Only filter state.
  void setSameSiteOnly(bool value) {
    if (state.filters.sameSiteOnly == value) return;
    state = state.copyWith(filters: state.filters.copyWith(sameSiteOnly: value));
    executeSearch();
  }

  /// Sets or clears observation type filter.
  void setObservationType(ObservationType? type) {
    if (state.filters.observationType == type) return;
    state = state.copyWith(
      filters: type == null
          ? state.filters.copyWith(clearObservationType: true)
          : state.filters.copyWith(observationType: type),
    );
    executeSearch();
  }

  /// Sets or clears activity tag filter.
  void setActivityTag(String? tag) {
    final clean = tag?.trim();
    if (state.filters.activityTag == clean) return;
    state = state.copyWith(
      filters: clean == null || clean.isEmpty
          ? state.filters.copyWith(clearActivityTag: true)
          : state.filters.copyWith(activityTag: clean),
    );
    executeSearch();
  }

  /// Sets or clears date range filter.
  void setDateRange(DateTime? start, DateTime? end) {
    if (state.filters.startDate == start && state.filters.endDate == end) return;
    state = state.copyWith(
      filters: state.filters.copyWith(
        startDate: start,
        endDate: end,
        clearStartDate: start == null,
        clearEndDate: end == null,
      ),
    );
    executeSearch();
  }

  /// Clears only the observation type filter chip.
  void clearObservationTypeFilter() {
    setObservationType(null);
  }

  /// Clears only the activity filter chip.
  void clearActivityFilter() {
    setActivityTag(null);
  }

  /// Clears only the date range filter chip.
  void clearDateRangeFilter() {
    setDateRange(null, null);
  }

  /// Resets all filters to default settings (sameSiteOnly=true, activity=null, observation=null, dateRange=null).
  /// Note: PRD contract explicitly preserves the currently selected spatial radius!
  void resetFilters() {
    state = state.copyWith(filters: const NearbySearchFilters());
    executeSearch();
  }

  /// Executes the spatial query against Drift SQLite with bounding-box index scan + Haversine refinement.
  Future<void> executeSearch() async {
    state = state.copyWith(isLoading: true, clearErrorMessage: true);

    try {
      final siteIdFilter = state.filters.sameSiteOnly
          ? (state.sourceMedia?.siteId ?? state.targetSiteId)
          : null;

      final rawResults = await _mediaRepo.findNearbyMedia(
        centerLat: state.centerLat,
        centerLon: state.centerLon,
        radiusMeters: state.radiusMeters,
        siteId: siteIdFilter,
        activity: state.filters.activityTag,
        observationType: state.filters.observationType,
        excludeMediaId: state.sourceMedia?.id,
        creatorId: _creatorId,
      );

      if (!mounted) return;

      Set<String> resolvedIds = const {};
      final lookupSite = state.sourceMedia?.siteId ?? state.targetSiteId;
      if (lookupSite != null && lookupSite.isNotEmpty) {
        resolvedIds = await _mediaRepo.getResolvedMediaIds(
          siteId: lookupSite,
          creatorId: _creatorId,
        );
      }

      if (!mounted) return;

      // Apply date range filters if configured with inclusive local boundaries
      List<NearbyMediaResult> filtered = rawResults;
      if (state.filters.startDate != null) {
        final startBoundary = DateTime(
          state.filters.startDate!.year,
          state.filters.startDate!.month,
          state.filters.startDate!.day,
          0, 0, 0, 0,
        );
        filtered = filtered.where((r) {
          final local = r.item.capturedAt.toLocal();
          return local.isAfter(startBoundary) || local.isAtSameMomentAs(startBoundary);
        }).toList();
      }
      if (state.filters.endDate != null) {
        final endBoundary = DateTime(
          state.filters.endDate!.year,
          state.filters.endDate!.month,
          state.filters.endDate!.day,
          23, 59, 59, 999,
        );
        filtered = filtered.where((r) {
          final local = r.item.capturedAt.toLocal();
          return local.isBefore(endBoundary) || local.isAtSameMomentAs(endBoundary);
        }).toList();
      }

      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        results: filtered,
        resolvedMediaIds: resolvedIds,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to query nearby media: $e',
      );
    }
  }
}
