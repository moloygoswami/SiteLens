import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:sitelens/core/services/geocoding_service.dart';

void main() {
  group('GeocodingService Formatting Tests', () {
    test('Formats comprehensive placemark with street, sublocality, city, state, zip, country', () {
      final placemark = Placemark(
        name: '14',
        street: '14 Kazipara Road',
        subLocality: 'Shalimar',
        locality: 'Howrah',
        administrativeArea: 'West Bengal',
        postalCode: '711103',
        country: 'India',
      );

      final formatted = GeocodingService.formatPlacemark(placemark);
      expect(formatted, '14 Kazipara Road, Shalimar, Howrah, West Bengal 711103, India');
    });

    test('Formats placemark with building premise name distinct from thoroughfare', () {
      final placemark = Placemark(
        name: 'Sonar Kella Apartment',
        thoroughfare: 'G.T. Road',
        subThoroughfare: '102',
        subLocality: 'Shalimar',
        locality: 'Howrah',
        administrativeArea: 'WB',
        postalCode: '711103',
        country: 'India',
      );

      final formatted = GeocodingService.formatPlacemark(placemark);
      expect(formatted, 'Sonar Kella Apartment, 102 G.T. Road, Shalimar, Howrah, WB 711103, India');
    });

    test('Avoids duplicates when street already contains house number or name', () {
      final placemark = Placemark(
        name: '1600',
        street: '1600 Amphitheatre Pkwy',
        locality: 'Mountain View',
        administrativeArea: 'CA',
        postalCode: '94043',
        country: 'USA',
      );

      final formatted = GeocodingService.formatPlacemark(placemark);
      expect(formatted, '1600 Amphitheatre Pkwy, Mountain View, CA 94043, USA');
    });

    test('Falls back to Site Vicinity when placemark is empty', () {
      final placemark = Placemark();
      final formatted = GeocodingService.formatPlacemark(placemark);
      expect(formatted, 'Site Vicinity');
    });
  });
}
