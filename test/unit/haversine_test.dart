import 'package:flutter_test/flutter_test.dart';
import 'package:sitelens/core/utils/haversine.dart';

void main() {
  group('SpatialMathUtils Haversine Tests', () {
    test('Calculates distance between identical points as 0', () {
      final distance = SpatialMathUtils.haversineDistanceMeters(22.5726, 88.3639, 22.5726, 88.3639);
      expect(distance, closeTo(0.0, 0.001));
    });

    test('Calculates known distance correctly (~10 meters offset)', () {
      // Offset of ~0.0001 deg latitude is roughly ~11.13 meters
      const lat1 = 22.5726;
      const lon1 = 88.3639;
      const lat2 = 22.5727;
      const lon2 = 88.3639;

      final distance = SpatialMathUtils.haversineDistanceMeters(lat1, lon1, lat2, lon2);
      expect(distance, closeTo(11.13, 0.5));
    });
  });

  group('SpatialMathUtils Bounding Box Tests', () {
    test('Calculates bounding box covering the radius', () {
      const centerLat = 22.5726;
      const centerLon = 88.3639;
      const radiusMeters = 50.0;

      final bbox = SpatialMathUtils.calculateBoundingBox(centerLat, centerLon, radiusMeters);

      expect(bbox.minLat, lessThan(centerLat));
      expect(bbox.maxLat, greaterThan(centerLat));
      expect(bbox.minLon, lessThan(centerLon));
      expect(bbox.maxLon, greaterThan(centerLon));

      // Point at center must be contained
      expect(bbox.contains(centerLat, centerLon), isTrue);

      // Point slightly outside bounding box must not be contained
      expect(bbox.contains(centerLat + 0.01, centerLon), isFalse);
    });
  });
}
