import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';

final geocodingServiceProvider = Provider<GeocodingService>((ref) {
  return GeocodingService();
});

class GeocodingService {
  final String? _apiKey;
  final HttpClient _httpClient;
  final Map<String, String> _cache = {};

  static const String defaultMapsKey = String.fromEnvironment(
    'MAPS_API_KEY',
    defaultValue: String.fromEnvironment(
      'STATIC_MAPS_API_KEY',
      defaultValue: '',
    ),
  );

  GeocodingService({
    String? apiKey,
    HttpClient? httpClient,
  })  : _apiKey = apiKey ?? (defaultMapsKey.isNotEmpty ? defaultMapsKey : null),
        _httpClient = httpClient ?? HttpClient();

  String _cacheKey(double lat, double lon) {
    // Group within ~50-100 meters (approx 0.001 deg)
    return '${lat.toStringAsFixed(3)},${lon.toStringAsFixed(3)}';
  }

  /// Formats a [Placemark] into a full, localized street address string.
  ///
  /// Joins components in order:
  /// [premise / street_number] [route / thoroughfare], [sublocality], [locality], [administrative_area] [postal_code], [country]
  static String formatPlacemark(Placemark place) {
    // 1. Street / Thoroughfare / Premise component
    String? streetPart;
    final subThoroughfare = place.subThoroughfare?.trim();
    final thoroughfare = place.thoroughfare?.trim();
    final street = place.street?.trim();
    final name = place.name?.trim();

    if (subThoroughfare != null && subThoroughfare.isNotEmpty && thoroughfare != null && thoroughfare.isNotEmpty) {
      streetPart = '$subThoroughfare $thoroughfare';
    } else if (street != null && street.isNotEmpty) {
      streetPart = street;
    } else if (thoroughfare != null && thoroughfare.isNotEmpty) {
      streetPart = thoroughfare;
    }

    // Include premise/building/landmark name if distinct from street and sublocality
    if (name != null &&
        name.isNotEmpty &&
        name != streetPart &&
        name != place.subLocality?.trim() &&
        name != place.locality?.trim() &&
        name != place.postalCode?.trim()) {
      if (streetPart != null && streetPart.isNotEmpty) {
        if (!streetPart.toLowerCase().contains(name.toLowerCase())) {
          streetPart = '$name, $streetPart';
        }
      } else {
        streetPart = name;
      }
    }

    // 2. SubLocality (Neighborhood, Ward, Sector, Colony)
    final subLocality = place.subLocality?.trim();

    // 3. Locality / City / SubAdministrativeArea
    final locality = place.locality?.trim();
    final subAdmin = place.subAdministrativeArea?.trim();
    String? cityPart;
    if (locality != null && locality.isNotEmpty) {
      cityPart = locality;
      if (subAdmin != null && subAdmin.isNotEmpty && subAdmin != locality && !locality.toLowerCase().contains(subAdmin.toLowerCase())) {
        cityPart = '$locality, $subAdmin';
      }
    } else if (subAdmin != null && subAdmin.isNotEmpty) {
      cityPart = subAdmin;
    }

    // 4. State / Province / Administrative Area + Postal Code
    final adminArea = place.administrativeArea?.trim();
    final postalCode = place.postalCode?.trim();
    String? stateZipPart;
    if (adminArea != null && adminArea.isNotEmpty && postalCode != null && postalCode.isNotEmpty) {
      stateZipPart = '$adminArea $postalCode';
    } else if (adminArea != null && adminArea.isNotEmpty) {
      stateZipPart = adminArea;
    } else if (postalCode != null && postalCode.isNotEmpty) {
      stateZipPart = postalCode;
    }

    // 5. Country
    final country = place.country?.trim();

    // Assemble components in order without duplicate strings
    final parts = <String>[];
    void addPart(String? p) {
      if (p == null || p.isEmpty) return;
      if (!parts.any((existing) => existing.toLowerCase() == p.toLowerCase())) {
        parts.add(p);
      }
    }

    addPart(streetPart);
    addPart(subLocality);
    addPart(cityPart);
    addPart(stateZipPart);
    addPart(country);

    if (parts.isEmpty) {
      return 'Site Vicinity';
    }
    return parts.join(', ');
  }

  Future<String?> _fetchFromGoogleMapsApi(double lat, double lon) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) return null;

    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'latlng': '$lat,$lon',
        'key': key,
        'result_type': 'street_address|premise|subpremise|route|sublocality|neighborhood',
      });

      final req = await _httpClient.getUrl(uri).timeout(const Duration(seconds: 4));
      final res = await req.close().timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final status = json['status'] as String?;
        if (status == 'OK') {
          final results = json['results'] as List<dynamic>?;
          if (results != null && results.isNotEmpty) {
            final first = results.first as Map<String, dynamic>;
            final formatted = first['formatted_address'] as String?;
            if (formatted != null && formatted.trim().isNotEmpty) {
              return formatted.trim();
            }
          }
        }
      }
    } catch (_) {
      // Network timeout or error — fallback to platform placemarks
    }
    return null;
  }

  Future<String?> reverseGeocode(double lat, double lon) async {
    final key = _cacheKey(lat, lon);
    if (_cache.containsKey(key)) {
      return _cache[key];
    }

    // 1. Try Google Maps Geocoding REST API first if configured
    final googleAddress = await _fetchFromGoogleMapsApi(lat, lon);
    if (googleAddress != null && googleAddress.isNotEmpty) {
      _cache[key] = googleAddress;
      return googleAddress;
    }

    // 2. Platform Geocoder fallback with rich localized component assembly
    try {
      final placemarks = await placemarkFromCoordinates(lat, lon);
      if (placemarks.isNotEmpty) {
        // Pick the placemark with the richest granularity (most populated address fields)
        Placemark bestPlacemark = placemarks.first;
        int bestScore = -1;
        for (final p in placemarks) {
          int score = 0;
          if (p.street != null && p.street!.isNotEmpty) score += 4;
          if (p.thoroughfare != null && p.thoroughfare!.isNotEmpty) score += 3;
          if (p.subThoroughfare != null && p.subThoroughfare!.isNotEmpty) score += 2;
          if (p.subLocality != null && p.subLocality!.isNotEmpty) score += 2;
          if (p.locality != null && p.locality!.isNotEmpty) score += 2;
          if (p.postalCode != null && p.postalCode!.isNotEmpty) score += 1;
          if (p.name != null && p.name!.isNotEmpty) score += 1;

          if (score > bestScore) {
            bestScore = score;
            bestPlacemark = p;
          }
        }

        final resolved = formatPlacemark(bestPlacemark);
        _cache[key] = resolved;
        return resolved;
      }
    } catch (_) {
      // Offline fallback: returns null, caller falls back to active site coordinates
    }
    return null;
  }
}
