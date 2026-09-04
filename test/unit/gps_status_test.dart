import 'package:flutter_test/flutter_test.dart';
import 'package:sitelens/core/utils/gps_utils.dart';

void main() {
  group('GPSUtils Tests', () {
    test('Classifies High accuracy for <= 5m', () {
      final status = GPSUtils.evaluateAccuracy(3.2);
      expect(status, equals(GPSFixStatus.high));
      expect(GPSUtils.formatStatusLabel(status, 3.2), equals('GPS: High · ±3.2m'));
    });

    test('Classifies Weak accuracy for 5m - 20m', () {
      final status = GPSUtils.evaluateAccuracy(12.0);
      expect(status, equals(GPSFixStatus.weak));
      expect(GPSUtils.formatStatusLabel(status, 12.0), equals('GPS: Weak · ±12.0m'));
    });

    test('Classifies Poor accuracy for > 20m', () {
      final status = GPSUtils.evaluateAccuracy(35.0);
      expect(status, equals(GPSFixStatus.poor));
      expect(GPSUtils.formatStatusLabel(status, 35.0), equals('GPS: Poor · ±35m+'));
    });

    test('Classifies Searching when no fix exists', () {
      final status = GPSUtils.evaluateAccuracy(null, hasFix: false);
      expect(status, equals(GPSFixStatus.searching));
      expect(GPSUtils.formatStatusLabel(status, null), equals('GPS: Searching…'));
    });

    test('Formats coordinates correctly', () {
      final formatted = GPSUtils.formatCoordinates(22.5726, 88.3639);
      expect(formatted, equals('Lat 22.572600° N, Long 88.363900° E'));
      expect(
        GPSUtils.formatCoordinates(22.5726, 88.3639, decimals: 4),
        equals('Lat 22.5726° N, Long 88.3639° E'),
      );
      expect(
        GPSUtils.formatLabeledCoordinates(22.5726, 88.3639),
        equals('LAT: 22.572600° N  LON: 88.363900° E'),
      );
    });
  });
}
