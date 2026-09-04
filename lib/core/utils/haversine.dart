import 'dart:math' as math;

class LatLngBoundingBox {
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;

  const LatLngBoundingBox({
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
  });

  bool contains(double lat, double lon) {
    return lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon;
  }
}

class SpatialMathUtils {
  static const double earthRadiusMeters = 6371000.0;

  /// Calculates the great-circle distance between two points on the Earth's surface in meters
  static double haversineDistanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final lat1Rad = _degreesToRadians(lat1);
    final lat2Rad = _degreesToRadians(lat2);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.sin(dLon / 2) * math.sin(dLon / 2) * math.cos(lat1Rad) * math.cos(lat2Rad);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadiusMeters * c;
  }

  /// Calculates a lat/lon bounding box for a given center point and search radius in meters.
  /// Used for fast SQLite indexed bounding box queries before Haversine refinement.
  static LatLngBoundingBox calculateBoundingBox(
    double centerLat,
    double centerLon,
    double radiusMeters,
  ) {
    // 1 degree latitude ~ 111,320 meters
    const double metersPerLatDegree = 111320.0;
    final double deltaLat = radiusMeters / metersPerLatDegree;

    // 1 degree longitude depends on latitude
    final double latRad = _degreesToRadians(centerLat);
    final double metersPerLonDegree = metersPerLatDegree * math.cos(latRad);

    final double deltaLon = metersPerLonDegree > 0.0
        ? radiusMeters / metersPerLonDegree
        : radiusMeters / metersPerLatDegree;

    return LatLngBoundingBox(
      minLat: centerLat - deltaLat,
      maxLat: centerLat + deltaLat,
      minLon: centerLon - deltaLon,
      maxLon: centerLon + deltaLon,
    );
  }

  static double _degreesToRadians(double degrees) {
    return degrees * math.pi / 180.0;
  }
}
