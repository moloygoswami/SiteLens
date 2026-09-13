import 'dart:async';
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

    // When map type changes (Normal ↔ Satellite), immediately invalidate all cached snapshots
    // and disk cache for the target mapType bucket, incrementing the generation token.
    if (isMapTypeChanged) {
      invalidateCachesOnMapTypeChange(
        mapType,
        lat: newLat,
        lon: newLon,
      );
    }

    // Check disk cache for static map image matching the NEW mapType only if not actively transitioning
    File? cached;
    if (!isMapTypeChanged && _transitionTargetMapType == null) {
      cached = await _service.getCachedImage(
        lat: newLat,
        lon: newLon,
        mapType: mapType.staticMapParam,
      );
    }

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
    if (cached == null && _transitionTargetMapType == null) {
      _fetchStaticImageInBackground(newLat, newLon, mapType);
    }

    // Pre-warm authentic live snapshot if map view is ready and no valid snapshot exists for new coordinates
    if (state.isLiveMapInitialized && _liveSnapshotProvider != null && _transitionTargetMapType == null) {
      final valid = getValidCachedSnapshotBytes(lat: newLat, lon: newLon, mapType: mapType);
      if (valid == null) {
        unawaited(prewarmLiveSnapshot(
          lat: newLat,
          lon: newLon,
          mapType: mapType,
        ));
      }
    }
  }

  Future<void> _fetchStaticImageInBackground(
    double lat,
    double lon,
    AppMapType mapType,
  ) async {
    final requestGen = _mapTypeGeneration;
    final requestMapType = mapType;
    try {
      final image = await _service.getOrFetchStaticMapImage(
        lat: lat,
        lon: lon,
        mapType: mapType.staticMapParam,
      );
      if (image != null && mounted) {
        // Stale-result protection invariant:
        // Must reject responses if generation or mapType changed during the fetch.
        if (requestGen != _mapTypeGeneration || state.mapType != requestMapType) {
          debugPrint(
            '[MapThumbnailNotifier] Discarding stale static map fetch '
            '(requestGen=$requestGen != currentGen=$_mapTypeGeneration, '
            'requestType=$requestMapType != currentType=${state.mapType})',
          );
          return;
        }

        final newTier = state.tier == MapThumbnailTier.syntheticFallback
            ? MapThumbnailTier.staticCached
            : state.tier;
        state = state.copyWith(cachedImage: image, tier: newTier);
      }
    } catch (_) {
      // Background cache fetch failure does not affect active viewfinder
    }
  }

  /// Monotonically increasing generation counter for map-type transitions.
  int _mapTypeGeneration = 0;
  int get mapTypeGeneration => _mapTypeGeneration;

  /// Active map-type transition state tracking.
  AppMapType? _transitionTargetMapType;
  int? _transitionGeneration;
  DateTime? _transitionStartTime;

  /// Returns true if a map-type transition is actively settling.
  bool get isMapTypeTransitioning => _transitionTargetMapType != null;
  AppMapType? get transitionTargetMapType => _transitionTargetMapType;

  /// Clears in-memory live snapshot provenance and invalidates target mapType disk cache.
  void invalidateCachesOnMapTypeChange(
    AppMapType newMapType, {
    double? lat,
    double? lon,
  }) {
    _mapTypeGeneration++;
    _transitionTargetMapType = newMapType;
    _transitionGeneration = _mapTypeGeneration;
    _transitionStartTime = DateTime.now();

    _latestLiveSnapshotBytes = null;
    _latestLiveSnapshotTimestamp = null;
    _latestLiveSnapshotLat = null;
    _latestLiveSnapshotLon = null;
    _latestLiveSnapshotMapType = null;

    if (lat != null && lon != null && (lat != 0.0 || lon != 0.0)) {
      unawaited(_service.invalidateCachedImage(
        lat: lat,
        lon: lon,
        mapType: newMapType.staticMapParam,
      ));
    }

    state = state.copyWith(
      mapType: newMapType,
      clearCachedImage: true,
      tier: MapThumbnailTier.live,
    );
  }

  /// Optional live snapshot provider registered by the GpsMapThumbnail widget.
  /// Returns the current native GoogleMap frame (PNG bytes) or null when the
  /// live map is not available.
  Future<Uint8List?> Function()? _liveSnapshotProvider;

  /// In-memory pre-cache of the latest authentic live map snapshot.
  Uint8List? _latestLiveSnapshotBytes;
  DateTime? _latestLiveSnapshotTimestamp;
  double? _latestLiveSnapshotLat;
  double? _latestLiveSnapshotLon;
  AppMapType? _latestLiveSnapshotMapType;

  bool _isPrewarming = false;

  /// Registers (or clears, with null) the live map snapshot provider.
  /// When registered and live GPS fix is ready, proactively pre-warms the snapshot.
  void registerLiveSnapshotProvider(Future<Uint8List?> Function()? provider) {
    _liveSnapshotProvider = provider;
    if (provider != null && state.isLocked && (state.lat != 0.0 || state.lon != 0.0) && _transitionTargetMapType == null) {
      unawaited(prewarmLiveSnapshot(
        lat: state.lat,
        lon: state.lon,
        mapType: state.mapType,
      ));
    }
  }

  /// Pre-warms and retains the authentic live map snapshot as soon as the live
  /// GPS fix and map view are ready, persisting it to disk cache and in-memory cache.
  Future<Uint8List?> prewarmLiveSnapshot({
    required double lat,
    required double lon,
    required AppMapType mapType,
    bool force = false,
  }) async {
    if (lat == 0.0 && lon == 0.0) return null;
    if (_transitionTargetMapType != null) return null;
    if (_isPrewarming) return null;

    if (!force) {
      final existing = getValidCachedSnapshotBytes(
        lat: lat,
        lon: lon,
        mapType: mapType,
      );
      if (existing != null) {
        return existing;
      }
    }

    final provider = _liveSnapshotProvider;
    if (provider == null) return null;

    final captureGeneration = _mapTypeGeneration;
    _isPrewarming = true;
    try {
      final snapshotFuture = Future<Uint8List?>.value(provider());
      final result = await snapshotFuture.timeout(
        const Duration(milliseconds: 2200),
        onTimeout: () => null,
      );

      if (result != null && result.isNotEmpty && _mapTypeGeneration == captureGeneration) {
        _cacheLiveSnapshot(result, lat: lat, lon: lon, mapType: mapType);
        await updateLiveSnapshot(
          result,
          lat: lat,
          lon: lon,
          mapType: mapType,
          captureGeneration: captureGeneration,
        );
        debugPrint('[MapThumbnailNotifier] Pre-warmed authentic live map snapshot at ($lat, $lon)');
        return result;
      }
    } catch (e) {
      debugPrint('[MapThumbnailNotifier] Pre-warm live snapshot failed: $e');
    } finally {
      _isPrewarming = false;
    }
    return null;
  }

  /// Returns the latest in-memory live map snapshot if it satisfies the strict
  /// freshness (<= 5 minutes), proximity (<= 20 meters), and mapType parity rules.
  Uint8List? getValidCachedSnapshotBytes({
    required double lat,
    required double lon,
    required AppMapType mapType,
  }) {
    if (_transitionTargetMapType != null ||
        _latestLiveSnapshotBytes == null ||
        _latestLiveSnapshotTimestamp == null ||
        _latestLiveSnapshotLat == null ||
        _latestLiveSnapshotLon == null ||
        _latestLiveSnapshotMapType != mapType) {
      return null;
    }

    final age = DateTime.now().difference(_latestLiveSnapshotTimestamp!);
    if (age > const Duration(minutes: 5)) {
      return null;
    }

    final distance = MapThumbnailService.haversineDistanceMeters(
      _latestLiveSnapshotLat!,
      _latestLiveSnapshotLon!,
      lat,
      lon,
    );
    if (distance > MapThumbnailPolicy.movementThresholdMeters) {
      return null;
    }

    return _latestLiveSnapshotBytes;
  }

  void _cacheLiveSnapshot(
    Uint8List bytes, {
    required double lat,
    required double lon,
    required AppMapType mapType,
  }) {
    _latestLiveSnapshotBytes = bytes;
    _latestLiveSnapshotTimestamp = DateTime.now();
    _latestLiveSnapshotLat = lat;
    _latestLiveSnapshotLon = lon;
    _latestLiveSnapshotMapType = mapType;
  }

  /// Captures the current native live map frame for evidence compositing so the
  /// baked watermark matches what the user sees (Normal or Satellite).
  ///
  /// Execution order:
  /// 1. Bounded layer transition settling guard: if a map-type transition is actively settling,
  ///    waits up to layerTransitionSettlingDuration (1500ms) for native OpenGL tiles to commit.
  /// 2. Preferred primary attempt: captures live snapshot from provider (2200ms timeout).
  /// 3. Bounded retry: if primary attempt threw or timed out, waits 150ms and retries once (1000ms timeout).
  /// 4. Verified recent fallback: if both live attempts fail or time out and NO transition is active,
  ///    returns the most recent valid pre-cached authentic snapshot provided it satisfies strict
  ///    freshness (<= 5m), proximity (<= 20m), and mapType match.
  /// 5. Returns null if no authentic map source satisfies the validation rules.
  Future<Uint8List?> takeLiveSnapshotForEvidence({
    double? lat,
    double? lon,
    AppMapType? mapType,
  }) async {
    final expectedMapType = mapType ?? state.mapType;
    final int captureGeneration = _mapTypeGeneration;

    // If map transition is active for this mapType, allow bounded settling window
    if (_transitionTargetMapType == expectedMapType && _transitionStartTime != null) {
      final elapsed = DateTime.now().difference(_transitionStartTime!);
      final remainingSettling = MapThumbnailPolicy.layerTransitionSettlingDuration - elapsed;
      if (remainingSettling > Duration.zero) {
        final waitDuration = remainingSettling > MapThumbnailPolicy.layerTransitionSettlingDuration
            ? MapThumbnailPolicy.layerTransitionSettlingDuration
            : remainingSettling;
        await Future.delayed(waitDuration);
      }
      if (_mapTypeGeneration != captureGeneration) {
        return null;
      }
    }

    final provider = _liveSnapshotProvider;
    if (provider != null) {
      // 1. Primary live capture attempt
      try {
        final Future<Uint8List?> snapshotFuture = Future<Uint8List?>.value(provider());
        final result = await snapshotFuture.timeout(
          const Duration(milliseconds: 2200),
          onTimeout: () => null,
        );
        if (result != null && result.isNotEmpty && _mapTypeGeneration == captureGeneration) {
          _transitionTargetMapType = null;
          _transitionGeneration = null;
          _transitionStartTime = null;

          if (lat != null && lon != null) {
            _cacheLiveSnapshot(result, lat: lat, lon: lon, mapType: expectedMapType);
            unawaited(updateLiveSnapshot(
              result,
              lat: lat,
              lon: lon,
              mapType: expectedMapType,
              captureGeneration: captureGeneration,
            ));
          }
          return result;
        }
      } catch (_) {
        // Fall through to bounded retry
      }

      // 2. Bounded retry: transient platform-view contention or brief frame drop
      try {
        await Future.delayed(const Duration(milliseconds: 150));
        if (_mapTypeGeneration != captureGeneration) return null;
        final Future<Uint8List?> retryFuture = Future<Uint8List?>.value(provider());
        final retryResult = await retryFuture.timeout(
          const Duration(milliseconds: 1000),
          onTimeout: () => null,
        );
        if (retryResult != null && retryResult.isNotEmpty && _mapTypeGeneration == captureGeneration) {
          _transitionTargetMapType = null;
          _transitionGeneration = null;
          _transitionStartTime = null;

          if (lat != null && lon != null) {
            _cacheLiveSnapshot(retryResult, lat: lat, lon: lon, mapType: expectedMapType);
            unawaited(updateLiveSnapshot(
              retryResult,
              lat: lat,
              lon: lon,
              mapType: expectedMapType,
              captureGeneration: captureGeneration,
            ));
          }
          return retryResult;
        }
      } catch (_) {
        // Retry failed, fall through to verified fallback
      }
    }

    // 3. Verified pre-cached fallback (only if not transitioning and matches validation)
    if (_transitionTargetMapType == null && lat != null && lon != null) {
      final validRecentBytes = getValidCachedSnapshotBytes(
        lat: lat,
        lon: lon,
        mapType: expectedMapType,
      );
      if (validRecentBytes != null) {
        debugPrint('[MapThumbnailNotifier] Shutter used verified recent authentic map snapshot fallback');
        return validRecentBytes;
      }

      // 4. Disk cache fallback if in-memory was cleared but disk cache has matching authentic file
      if (state.cachedImage != null &&
          state.cachedImage!.existsSync() &&
          state.mapType == expectedMapType &&
          state.lastUpdate != null) {
        final age = DateTime.now().difference(state.lastUpdate!);
        final distance = MapThumbnailService.haversineDistanceMeters(
          state.lat,
          state.lon,
          lat,
          lon,
        );
        if (age <= const Duration(minutes: 5) &&
            distance <= MapThumbnailPolicy.movementThresholdMeters) {
          try {
            final diskBytes = await state.cachedImage!.readAsBytes();
            if (diskBytes.isNotEmpty) {
              _cacheLiveSnapshot(diskBytes, lat: state.lat, lon: state.lon, mapType: expectedMapType);
              debugPrint('[MapThumbnailNotifier] Shutter used verified disk-cached authentic snapshot fallback');
              return diskBytes;
            }
          } catch (_) {}
        }
      }
    }

    return null;
  }

  /// Persists the live GoogleMap bitmap snapshot into the disk static map cache
  /// and updates both in-memory cache and controller state with the latest coordinates and timestamp.
  /// Discards stale asynchronous writes if captureGeneration does not match the current generation.
  Future<void> updateLiveSnapshot(
    Uint8List snapshotBytes, {
    required double lat,
    required double lon,
    AppMapType mapType = AppMapType.satellite,
    int? captureGeneration,
  }) async {
    // 1. Generation & mapType guard: Stale asynchronous snapshots must be discarded
    if (captureGeneration != null && captureGeneration != _mapTypeGeneration) {
      debugPrint('[MapThumbnailNotifier] Discarding stale snapshot write (captureGen=$captureGeneration != currentGen=$_mapTypeGeneration)');
      return;
    }
    if (state.mapType != mapType) {
      debugPrint('[MapThumbnailNotifier] Discarding mismatched snapshot write (state=${state.mapType} != snapshot=$mapType)');
      return;
    }

    // 2. Transition guard: If transitioning, do not accept until settled
    if (_transitionTargetMapType != null) {
      if (_transitionTargetMapType != mapType || _transitionGeneration != _mapTypeGeneration) {
        return;
      }
      final elapsed = _transitionStartTime == null
          ? Duration.zero
          : DateTime.now().difference(_transitionStartTime!);
      if (elapsed < MapThumbnailPolicy.layerTransitionSettlingDuration) {
        // Still within settling window: do not accept premature snapshot into verified cache
        return;
      }
      // Settling duration has elapsed; transition is now settled!
      _transitionTargetMapType = null;
      _transitionGeneration = null;
      _transitionStartTime = null;
    }

    _cacheLiveSnapshot(snapshotBytes, lat: lat, lon: lon, mapType: mapType);
    try {
      final cacheDir = await _service.getCacheDirectory();
      // Double check before writing to disk
      if (captureGeneration != null && captureGeneration != _mapTypeGeneration) {
        return;
      }
      if (state.mapType != mapType) {
        return;
      }

      final cacheKey = MapThumbnailService.computeCacheKey(
        lat: lat,
        lon: lon,
        mapType: mapType.staticMapParam,
      );
      final file = File('${cacheDir.path}/$cacheKey.png');
      await file.writeAsBytes(snapshotBytes, flush: true);
      if (mounted && (captureGeneration == null || captureGeneration == _mapTypeGeneration) && state.mapType == mapType) {
        state = state.copyWith(
          cachedImage: file,
          mapType: mapType,
          lat: lat,
          lon: lon,
          lastUpdate: DateTime.now(),
        );
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
    if (state.isLocked && (state.lat != 0.0 || state.lon != 0.0) && _transitionTargetMapType == null) {
      unawaited(prewarmLiveSnapshot(
        lat: state.lat,
        lon: state.lon,
        mapType: state.mapType,
      ));
    }
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
