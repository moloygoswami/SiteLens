import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Centralized policy defining spatial and temporal thresholds for mini-map rendering and caching.
abstract final class MapThumbnailPolicy {
  /// Spatial displacement threshold in meters for triggering camera movement and cache refresh.
  static const double movementThresholdMeters = 20.0;

  /// Minimum duration between background Static Maps network fetches.
  static const Duration minTimeBetweenStaticFetches = Duration(seconds: 15);

  /// Minimum interval between taking snapshots from the live GoogleMap.
  static const Duration minSnapshotInterval = Duration(seconds: 30);

  /// Timeout waiting for native GoogleMap controller initialization before falling back.
  static const Duration liveMapInitTimeout = Duration(seconds: 5);

  /// Bounded settling duration for native GoogleMap layer transitions (Normal ↔ Satellite).
  static const Duration layerTransitionSettlingDuration = Duration(milliseconds: 1500);

  /// Coordinate quantization decimals (4 decimals = ~11.1m resolution, consistent with 20m threshold).
  static const int coordinateDecimals = 4;

  /// Canonical zoom level for map thumbnails and static fetches.
  static const int canonicalZoom = 18;

  /// Canonical style version for map thumbnails and static fetches.
  static const String canonicalStyleVersion = 'v2';

  /// Cache TTL for static map images on disk.
  static const Duration cacheTtl = Duration(days: 7);

  /// Network connection/read timeout for Static Maps API calls.
  static const Duration networkTimeout = Duration(seconds: 4);
}

/// Service managing Tier 2 (Static Maps) disk caching, coordinate bucketing,
/// and secure network retrieval.
class MapThumbnailService {
  final String? _apiKey;
  final Duration cacheTtl;
  final Duration networkTimeout;
  final Map<String, Future<File?>> _inFlightRequests = {};
  Directory? _cacheDir;

  static const String defaultStaticMapsKey = String.fromEnvironment(
    'STATIC_MAPS_API_KEY',
    defaultValue: '',
  );

  MapThumbnailService({
    String? apiKey,
    this.cacheTtl = MapThumbnailPolicy.cacheTtl,
    this.networkTimeout = MapThumbnailPolicy.networkTimeout,
  }) : _apiKey = apiKey ?? (defaultStaticMapsKey.isNotEmpty ? defaultStaticMapsKey : null);

  /// Computes a quantized coordinate bucket (~11.1m grid resolution at 4 decimals).
  static double quantizeCoordinate(double coord, {int decimals = MapThumbnailPolicy.coordinateDecimals}) {
    final factor = math.pow(10, decimals);
    return (coord * factor).round() / factor;
  }

  /// Calculates a deterministic SHA-256 cache key based on:
  /// coordinate bucket + zoom + map type + style version.
  static String computeCacheKey({
    required double lat,
    required double lon,
    int zoom = MapThumbnailPolicy.canonicalZoom,
    String mapType = 'satellite',
    String styleVersion = MapThumbnailPolicy.canonicalStyleVersion,
  }) {
    final qLat = quantizeCoordinate(lat);
    final qLon = quantizeCoordinate(lon);
    final rawKey = '${qLat.toStringAsFixed(MapThumbnailPolicy.coordinateDecimals)}_${qLon.toStringAsFixed(MapThumbnailPolicy.coordinateDecimals)}_z${zoom}_${mapType}_$styleVersion';
    final bytes = utf8.encode(rawKey);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Calculates Haversine distance in meters between two lat/lon pairs.
  static double haversineDistanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadiusMeters = 6371000.0;
    final double dLat = _deg2rad(lat2 - lat1);
    final double dLon = _deg2rad(lon2 - lon1);

    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  static double _deg2rad(double deg) => deg * (math.pi / 180.0);

  Future<Directory> getCacheDirectory() async {
    if (_cacheDir != null && await _cacheDir!.exists()) {
      return _cacheDir!;
    }
    final appDir = await getApplicationSupportDirectory();
    final target = Directory(p.join(appDir.path, 'map_thumbnail_cache'));
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    _cacheDir = target;
    return target;
  }

  /// Retrieves a cached static map image file if available and unexpired.
  Future<File?> getCachedImage({
    required double lat,
    required double lon,
    int zoom = MapThumbnailPolicy.canonicalZoom,
    String mapType = 'satellite',
    String styleVersion = MapThumbnailPolicy.canonicalStyleVersion,
  }) async {
    try {
      final cacheDir = await getCacheDirectory();
      final cacheKey = computeCacheKey(
        lat: lat,
        lon: lon,
        zoom: zoom,
        mapType: mapType,
        styleVersion: styleVersion,
      );
      final file = File(p.join(cacheDir.path, '$cacheKey.png'));

      if (await file.exists()) {
        final lastModified = await file.lastModified();
        final age = DateTime.now().difference(lastModified);
        if (age <= cacheTtl) {
          return file;
        }
      }
    } catch (e) {
      debugPrint('[MapThumbnailService] Error reading disk cache: $e');
    }
    return null;
  }

  /// Invalidates (deletes) any cached image file on disk for a specific coordinate bucket and mapType.
  Future<void> invalidateCachedImage({
    required double lat,
    required double lon,
    int zoom = MapThumbnailPolicy.canonicalZoom,
    required String mapType,
    String styleVersion = MapThumbnailPolicy.canonicalStyleVersion,
  }) async {
    try {
      final cacheDir = await getCacheDirectory();
      final cacheKey = computeCacheKey(
        lat: lat,
        lon: lon,
        zoom: zoom,
        mapType: mapType,
        styleVersion: styleVersion,
      );
      final file = File(p.join(cacheDir.path, '$cacheKey.png'));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('[MapThumbnailService] Error invalidating disk cache: $e');
    }
  }

  /// Backward-compatible alias for getCachedImage.
  Future<File?> getCachedTile({
    required double lat,
    required double lon,
    int zoom = MapThumbnailPolicy.canonicalZoom,
    String mapType = 'satellite',
    String styleVersion = MapThumbnailPolicy.canonicalStyleVersion,
  }) => getCachedImage(
    lat: lat,
    lon: lon,
    zoom: zoom,
    mapType: mapType,
    styleVersion: styleVersion,
  );

  /// Retrieves or fetches a static map image with deduplication and caching.
  Future<File?> getOrFetchStaticMapImage({
    required double lat,
    required double lon,
    int zoom = MapThumbnailPolicy.canonicalZoom,
    int width = 300,
    int height = 300,
    int scale = 2,
    String mapType = 'satellite',
    String styleVersion = MapThumbnailPolicy.canonicalStyleVersion,
  }) async {
    final cacheKey = computeCacheKey(
      lat: lat,
      lon: lon,
      zoom: zoom,
      mapType: mapType,
      styleVersion: styleVersion,
    );

    // 1. Fast path: check local disk cache
    final cached = await getCachedImage(
      lat: lat,
      lon: lon,
      zoom: zoom,
      mapType: mapType,
      styleVersion: styleVersion,
    );
    if (cached != null) {
      return cached;
    }

    // 2. If already fetching this image in-flight, return the existing Future
    if (_inFlightRequests.containsKey(cacheKey)) {
      return _inFlightRequests[cacheKey];
    }

    // 3. Initiate deduplicated fetch
    final fetchFuture = _executeFetchAndCache(
      cacheKey: cacheKey,
      lat: lat,
      lon: lon,
      zoom: zoom,
      width: width,
      height: height,
      scale: scale,
      mapType: mapType,
    );

    _inFlightRequests[cacheKey] = fetchFuture;

    try {
      return await fetchFuture;
    } finally {
      _inFlightRequests.remove(cacheKey);
    }
  }

  /// Backward-compatible alias for getOrFetchStaticMapImage.
  Future<File?> getOrFetchStaticMapTile({
    required double lat,
    required double lon,
    int zoom = MapThumbnailPolicy.canonicalZoom,
    int width = 300,
    int height = 300,
    int scale = 2,
    String mapType = 'satellite',
    String styleVersion = MapThumbnailPolicy.canonicalStyleVersion,
  }) => getOrFetchStaticMapImage(
    lat: lat,
    lon: lon,
    zoom: zoom,
    width: width,
    height: height,
    scale: scale,
    mapType: mapType,
    styleVersion: styleVersion,
  );

  Future<File?> _executeFetchAndCache({
    required String cacheKey,
    required double lat,
    required double lon,
    required int zoom,
    required int width,
    required int height,
    required int scale,
    required String mapType,
  }) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) {
      return null;
    }

    final qLat = quantizeCoordinate(lat);
    final qLon = quantizeCoordinate(lon);

    final isSatellite = mapType == 'satellite' || mapType == 'hybrid';
    final styleParams = isSatellite
        ? ''
        : '&style=element:geometry|color:0x1b201e'
          '&style=element:labels.text.stroke|color:0x141815'
          '&style=element:labels.text.fill|color:0xb0bec5'
          '&style=feature:administrative|element:geometry|color:0x455a64'
          '&style=feature:road|element:geometry|color:0x2c3531'
          '&style=feature:road|element:geometry.stroke|color:0x1b201e'
          '&style=feature:road.highway|element:geometry|color:0xd97706'
          '&style=feature:road.arterial|element:geometry|color:0x37474f'
          '&style=feature:road|element:labels.text.fill|color:0xcfd8dc'
          '&style=feature:water|element:geometry|color:0x0f172a';

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/staticmap'
      '?center=$qLat,$qLon'
      '&zoom=$zoom'
      '&size=${width}x$height'
      '&scale=$scale'
      '&maptype=$mapType'
      '&format=png'
      '$styleParams'
      '&key=$_apiKey',
    );


    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = networkTimeout;
      final request = await client.getUrl(url).timeout(networkTimeout);
      if (!kIsWeb && Platform.isAndroid) {
        request.headers.set('X-Android-Package', 'com.sitelens.app');
        const certFingerprint = String.fromEnvironment('STATIC_MAPS_CERT_SHA1', defaultValue: '');
        if (certFingerprint.isNotEmpty) {
          request.headers.set('X-Android-Cert', certFingerprint);
        }
      }
      final response = await request.close().timeout(networkTimeout);

      if (response.statusCode == 200) {
        final bytes = await consolidateHttpClientResponseBytes(response);
        if (bytes.isNotEmpty) {
          final cacheDir = await getCacheDirectory();
          final tempFile = File(p.join(cacheDir.path, '$cacheKey.tmp'));
          final targetFile = File(p.join(cacheDir.path, '$cacheKey.png'));

          await tempFile.writeAsBytes(bytes, flush: true);
          if (await targetFile.exists()) {
            await targetFile.delete();
          }
          await tempFile.rename(targetFile.path);
          return targetFile;
        }
      } else {
        debugPrint('[MapThumbnailService] Static Maps HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[MapThumbnailService] Failed to fetch static map: $e');
    } finally {
      client?.close();
    }
    return null;
  }
}
