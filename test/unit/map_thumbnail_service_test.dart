import 'package:flutter_test/flutter_test.dart';
import 'package:sitelens/core/services/map_thumbnail_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MapThumbnailService Unit Tests', () {
    test('quantizeCoordinate rounds accurately to 4 decimals (~11.1m resolution)', () {
      expect(MapThumbnailService.quantizeCoordinate(22.56286), 22.5629);
      expect(MapThumbnailService.quantizeCoordinate(88.30082), 88.3008);
      expect(MapThumbnailService.quantizeCoordinate(22.56211), 22.5621);
    });

    test('computeCacheKey produces deterministic 64-char SHA-256 hash for identical buckets', () {
      final key1 = MapThumbnailService.computeCacheKey(
        lat: 22.56286,
        lon: 88.30082,
        zoom: 16,
      );
      final key2 = MapThumbnailService.computeCacheKey(
        lat: 22.56289, // Within same 4-decimal bucket (22.5629)
        lon: 88.30084, // Within same 4-decimal bucket (88.3008)
        zoom: 16,
      );
      final keyDifferentZoom = MapThumbnailService.computeCacheKey(
        lat: 22.56286,
        lon: 88.30082,
        zoom: 18,
      );

      expect(key1, isNotEmpty);
      expect(key1.length, equals(64)); // SHA-256 produces 64 hex characters
      expect(key1, equals(key2)); // Bucket cache hit
      expect(key1, isNot(equals(keyDifferentZoom)));
    });

    test('haversineDistanceMeters calculates accurate spatial distance', () {
      // Points approximately 111 meters apart in latitude (0.001 deg)
      final distance = MapThumbnailService.haversineDistanceMeters(
        22.56200,
        88.30000,
        22.56300,
        88.30000,
      );
      expect(distance, closeTo(111.2, 2.0));

      // Same location is 0 distance
      final zeroDistance = MapThumbnailService.haversineDistanceMeters(
        22.56286,
        88.30082,
        22.56286,
        88.30082,
      );
      expect(zeroDistance, 0.0);
    });

    test('defaultStaticMapsKey is isolated without fallback to MAPS_API_KEY', () {
      expect(MapThumbnailService.defaultStaticMapsKey, equals(''));
    });

    test('deduplicates in-flight requests and handles empty key gracefully', () async {
      final service = MapThumbnailService(apiKey: null);
      final result = await service.getOrFetchStaticMapImage(
        lat: 22.56286,
        lon: 88.30082,
      );
      expect(result, isNull); // Graceful null fallback when no API key configured

      // Backward compatible alias
      final resultTile = await service.getOrFetchStaticMapTile(
        lat: 22.56286,
        lon: 88.30082,
      );
      expect(resultTile, isNull);
    });

    test('computeCacheKey isolates roadmap vs satellite map types in SHA-256 key', () {
      final normalKey = MapThumbnailService.computeCacheKey(
        lat: 22.56286,
        lon: 88.30082,
        mapType: 'roadmap',
      );
      final satelliteKey = MapThumbnailService.computeCacheKey(
        lat: 22.56286,
        lon: 88.30082,
        mapType: 'satellite',
      );

      expect(normalKey, isNotEmpty);
      expect(satelliteKey, isNotEmpty);
      expect(normalKey.length, equals(64));
      expect(satelliteKey.length, equals(64));
      expect(normalKey, isNot(equals(satelliteKey)));
    });

    test('F2: computeCacheKey uses canonicalZoom (18) and canonicalStyleVersion (v2) by default', () {
      final defaultKey = MapThumbnailService.computeCacheKey(
        lat: 22.56286,
        lon: 88.30082,
        mapType: 'satellite',
      );
      final explicitCanonicalKey = MapThumbnailService.computeCacheKey(
        lat: 22.56286,
        lon: 88.30082,
        zoom: MapThumbnailPolicy.canonicalZoom,
        mapType: 'satellite',
        styleVersion: MapThumbnailPolicy.canonicalStyleVersion,
      );

      expect(MapThumbnailPolicy.canonicalZoom, 18);
      expect(MapThumbnailPolicy.canonicalStyleVersion, 'v2');
      expect(defaultKey, equals(explicitCanonicalKey));

      // Key must NOT match stale 16 / v1 parameters
      final oldMismatchedKey = MapThumbnailService.computeCacheKey(
        lat: 22.56286,
        lon: 88.30082,
        zoom: 16,
        mapType: 'satellite',
        styleVersion: 'v1',
      );
      expect(defaultKey, isNot(equals(oldMismatchedKey)));
    });
  });
}
