import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/map_thumbnail_service.dart';
import '../../../domain/models/enums.dart';

enum MapThumbnailTier {
  live,
  staticCached,
  syntheticFallback,
}

@immutable
class MapThumbnailState {
  final MapThumbnailTier tier;
  final double lat;
  final double lon;
  final bool isLocked;
  final AppMapType mapType;
  final File? cachedImage;
  final DateTime? lastUpdate;
  final bool isLiveMapInitialized;
  final int failureCount;
  final DateTime? lastFailureTime;

  const MapThumbnailState({
    this.tier = MapThumbnailTier.live,
    this.lat = 0.0,
    this.lon = 0.0,
    this.isLocked = false,
    this.mapType = AppMapType.satellite,
    this.cachedImage,
    this.lastUpdate,
    this.isLiveMapInitialized = false,
    this.failureCount = 0,
    this.lastFailureTime,
  });

  /// Backward-compatible alias for cachedImage.
  File? get cachedTile => cachedImage;

  MapThumbnailState copyWith({
    MapThumbnailTier? tier,
    double? lat,
    double? lon,
    bool? isLocked,
    AppMapType? mapType,
    File? cachedImage,
    File? cachedTile,
    DateTime? lastUpdate,
    bool? isLiveMapInitialized,
    int? failureCount,
    DateTime? lastFailureTime,
    bool clearCachedImage = false,
  }) {
    return MapThumbnailState(
      tier: tier ?? this.tier,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      isLocked: isLocked ?? this.isLocked,
      mapType: mapType ?? this.mapType,
      cachedImage: clearCachedImage ? null : (cachedImage ?? cachedTile ?? this.cachedImage),
      lastUpdate: lastUpdate ?? this.lastUpdate,
      isLiveMapInitialized: isLiveMapInitialized ?? this.isLiveMapInitialized,
      failureCount: failureCount ?? this.failureCount,
      lastFailureTime: lastFailureTime ?? this.lastFailureTime,
    );
  }
}

final mapThumbnailServiceProvider = Provider<MapThumbnailService>((ref) {
  return MapThumbnailService();
});

class MapThumbnailNotifier extends StateNotifier<MapThumbnailState> {
  final MapThumbnailService _service;

  MapThumbnailNotifier(this._service) : super(const MapThumbnailState());

  /// Evaluates GPS updates and enforces centralized spatial (>=20m) and temporal (>=15s) throttling.
  Future<void> handleGpsUpdate({
    required double newLat,
    required double newLon,
    required bool isLocked,
    AppMapType mapType = AppMapType.satellite,
  }) async {
    if (!isLocked || (newLat == 0.0 && newLon == 0.0)) {
      if (state.isLocked != isLocked || state.mapType != mapType) {
        state = state.copyWith(isLocked: isLocked, mapType: mapType);
      }
      return;
    }

    final now = DateTime.now();
    final hasPriorLocation = state.lastUpdate != null && (state.lat != 0.0 || state.lon != 0.0);
    final isMapTypeChanged = state.mapType != mapType;
    double distance = 0.0;

    if (hasPriorLocation && !isMapTypeChanged) {
      distance = MapThumbnailService.haversineDistanceMeters(
        state.lat,
        state.lon,
        newLat,
        newLon,
      );
      final elapsed = now.difference(state.lastUpdate!);

      // Throttle: Movement >= 20m AND elapsed >= 15 seconds
      if (distance < MapThumbnailPolicy.movementThresholdMeters &&
          elapsed < MapThumbnailPolicy.minTimeBetweenStaticFetches) {
        return;
      }
    }

    // When map type changes (Normal ↔ Satellite), immediately clear the stale cached image
    // so a roadmap tile is never served when satellite is active (and vice versa).
    if (isMapTypeChanged) {
      state = state.copyWith(
        mapType: mapType,
        clearCachedImage: true,
        tier: MapThumbnailTier.live,
      );
    }

    // Check disk cache for static map image matching the NEW mapType
    final cached = await _service.getCachedImage(
      lat: newLat,
      lon: newLon,
      mapType: mapType.staticMapParam,
    );

    // If previously failed, recover to LIVE tier strictly upon significant spatial movement (>=20m)
    MapThumbnailTier targetTier = state.tier;
    if (state.tier != MapThumbnailTier.live && isLocked) {
      final shouldRecover = distance >= MapThumbnailPolicy.movementThresholdMeters || isMapTypeChanged;
      if (shouldRecover) {
        targetTier = MapThumbnailTier.live;
      }
    }

    state = state.copyWith(
      lat: newLat,
      lon: newLon,
      isLocked: isLocked,
      mapType: mapType,
      lastUpdate: now,
      cachedImage: cached,
      clearCachedImage: cached == null,
      tier: targetTier,
    );

    // Opportunistically pre-fetch/cache static map image for this coordinate bucket and mapType
    if (cached == null) {
      _fetchStaticImageInBackground(newLat, newLon, mapType);
    }
  }

  Future<void> _fetchStaticImageInBackground(
    double lat,
    double lon,
    AppMapType mapType,
  ) async {
    try {
      final image = await _service.getOrFetchStaticMapImage(
        lat: lat,
        lon: lon,
        mapType: mapType.staticMapParam,
      );
      if (image != null && mounted) {
        final newTier = state.tier == MapThumbnailTier.syntheticFallback
            ? MapThumbnailTier.staticCached
            : state.tier;
        state = state.copyWith(cachedImage: image, tier: newTier);
      }
    } catch (_) {
      // Background cache fetch failure does not affect active viewfinder
    }
  }

  /// Optional live snapshot provider registered by the GpsMapThumbnail widget.
  /// Returns the current native GoogleMap frame (PNG bytes) or null when the
  /// live map is not available.
  Future<Uint8List?> Function()? _liveSnapshotProvider;

  /// Registers (or clears, with null) the live map snapshot provider.
  void registerLiveSnapshotProvider(Future<Uint8List?> Function()? provider) {
    _liveSnapshotProvider = provider;
  }

  /// Captures the current native live map frame for evidence compositing so the
  /// baked watermark matches exactly what the user sees (Normal or Satellite).
  /// Returns null when the live map is unavailable or fails.
  Future<Uint8List?> takeLiveSnapshotForEvidence() async {
    final provider = _liveSnapshotProvider;
    if (provider == null) return null;
    try {
      final Future<Uint8List?> snapshotFuture = Future<Uint8List?>.value(provider());
      return await snapshotFuture.timeout(
        const Duration(milliseconds: 3500),
        onTimeout: () => null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Persists the live GoogleMap bitmap snapshot into the disk static map cache.
  Future<void> updateLiveSnapshot(
    Uint8List snapshotBytes, {
    required double lat,
    required double lon,
    AppMapType mapType = AppMapType.satellite,
  }) async {
    try {
      final cacheDir = await _service.getCacheDirectory();
      final cacheKey = MapThumbnailService.computeCacheKey(
        lat: lat,
        lon: lon,
        mapType: mapType.staticMapParam,
      );
      final file = File('${cacheDir.path}/$cacheKey.png');
      await file.writeAsBytes(snapshotBytes, flush: true);
      if (mounted) {
        state = state.copyWith(cachedImage: file, mapType: mapType);
      }
    } catch (e) {
      debugPrint('[MapThumbnailNotifier] Failed to persist live map snapshot: $e');
    }
  }

  void onLiveMapInitialized() {
    state = state.copyWith(
      tier: MapThumbnailTier.live,
      isLiveMapInitialized: true,
      failureCount: 0,
    );
  }

  void onLiveMapFailed() {
    final now = DateTime.now();
    final newFailureCount = state.failureCount + 1;
    final hasCache = state.cachedImage != null && state.cachedImage!.existsSync();

    state = state.copyWith(
      tier: hasCache ? MapThumbnailTier.staticCached : MapThumbnailTier.syntheticFallback,
      isLiveMapInitialized: false,
      failureCount: newFailureCount,
      lastFailureTime: now,
    );

    // If no cache, attempt network fallback fetch
    if (!hasCache && (state.lat != 0.0 || state.lon != 0.0)) {
      _fetchStaticImageInBackground(state.lat, state.lon, state.mapType);
    }
  }

  void switchToStaticTier() {
    if (state.cachedImage != null) {
      state = state.copyWith(tier: MapThumbnailTier.staticCached);
    } else {
      state = state.copyWith(tier: MapThumbnailTier.syntheticFallback);
    }
  }

  void switchToLiveTier() {
    state = state.copyWith(tier: MapThumbnailTier.live);
  }
}

final mapThumbnailControllerProvider =
    StateNotifierProvider<MapThumbnailNotifier, MapThumbnailState>((ref) {
  final service = ref.watch(mapThumbnailServiceProvider);
  return MapThumbnailNotifier(service);
});
