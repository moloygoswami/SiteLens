enum GPSFixStatus {
  searching,
  high,
  weak,
  poor,
}

/// Why capture is currently blocked. UI must never claim a stronger GPS state
/// than the system has actually established.
enum GpsBlockReason {
  /// No fix yet; the receiver is actively searching for satellites.
  searching,

  /// Location permission is denied (or denied forever).
  permissionDenied,

  /// The device's location service is switched off.
  serviceDisabled,

  /// The camera is unavailable or initializing, independent of GPS state.
  cameraUnavailable,
}

class GPSUtils {
  /// Evaluates the GPS Fix Status based on accuracy in meters
  static GPSFixStatus evaluateAccuracy(double? accuracyMeters, {bool hasFix = true}) {
    if (!hasFix || accuracyMeters == null) {
      return GPSFixStatus.searching;
    }
    if (accuracyMeters <= 5.0) {
      return GPSFixStatus.high;
    } else if (accuracyMeters <= 20.0) {
      return GPSFixStatus.weak;
    } else {
      return GPSFixStatus.poor;
    }
  }

  /// Formats the GPS Badge label according to PRD specs (e.g. "GPS: High · ±2m")
  static String formatStatusLabel(GPSFixStatus status, double? accuracyMeters) {
    switch (status) {
      case GPSFixStatus.searching:
        return 'GPS: Searching…';
      case GPSFixStatus.high:
        final acc = accuracyMeters != null ? '±${accuracyMeters.toStringAsFixed(1)}m' : 'High';
        return 'GPS: High · $acc';
      case GPSFixStatus.weak:
        final acc = accuracyMeters != null ? '±${accuracyMeters.toStringAsFixed(1)}m' : 'Weak';
        return 'GPS: Weak · $acc';
      case GPSFixStatus.poor:
        final acc = accuracyMeters != null ? '±${accuracyMeters.toStringAsFixed(0)}m+' : 'Poor';
        return 'GPS: Poor · $acc';
    }
  }

  /// Standard high-precision inspection coordinate precision (6 decimal places ≈ 0.11m).
  static const int coordinateDecimalPrecision = 6;

  /// Formats a single coordinate value (latitude or longitude) with hemisphere direction.
  /// e.g. "22.572640° N" or "88.363910° E"
  static String formatSingleCoordinate(
    double value, {
    required bool isLatitude,
    int decimals = coordinateDecimalPrecision,
  }) {
    final dir = isLatitude ? (value >= 0 ? 'N' : 'S') : (value >= 0 ? 'E' : 'W');
    final absVal = value.abs().toStringAsFixed(decimals);
    return '$absVal° $dir';
  }

  /// Formats Latitude and Longitude to standardized inspection format:
  /// e.g. "Lat 22.572640° N, Long 88.363910° E"
  static String formatCoordinates(
    double lat,
    double lon, {
    int decimals = coordinateDecimalPrecision,
    String separator = ', ',
  }) {
    final latStr = formatSingleCoordinate(lat, isLatitude: true, decimals: decimals);
    final lonStr = formatSingleCoordinate(lon, isLatitude: false, decimals: decimals);
    return 'Lat $latStr$separator' 'Long $lonStr';
  }

  /// Formats coordinates in labeled key-value style:
  /// e.g. "LAT: 22.572640° N  LON: 88.363910° E"
  static String formatLabeledCoordinates(
    double lat,
    double lon, {
    int decimals = coordinateDecimalPrecision,
  }) {
    final latStr = formatSingleCoordinate(lat, isLatitude: true, decimals: decimals);
    final lonStr = formatSingleCoordinate(lon, isLatitude: false, decimals: decimals);
    return 'LAT: $latStr  LON: $lonStr';
  }

  /// Formats Altitude with clean positive (+) or negative (-) sign and truthful datum label:
  /// e.g. "+18.4 m ASL" (when MSL is established) or "-43.4 m (WGS84)" (when ellipsoidal),
  /// or "—" if unavailable.
  static String formatAltitude(
    double? altitudeMeters, {
    bool isMsl = true,
  }) {
    if (altitudeMeters == null) return '—';
    final sign = altitudeMeters >= 0 ? '+' : '';
    final datumSuffix = isMsl ? 'm ASL' : 'm (WGS84)';
    return '$sign${altitudeMeters.toStringAsFixed(1)} $datumSuffix';
  }

  /// Formats full inspection coordinates with elevation:
  /// e.g. "Lat 22.562865° N  Long 88.300896° E (Alt: +14.7 m ASL)"
  /// or   "Lat 22.562865° N  Long 88.300896° E (Alt: -42.4 m (WGS84))"
  static String formatInspectionCoordinates(
    double lat,
    double lon, {
    double? altitudeMeters,
    String? altitudeDisplay,
    bool isMsl = true,
    int decimals = coordinateDecimalPrecision,
  }) {
    final latStr = formatSingleCoordinate(lat, isLatitude: true, decimals: decimals);
    final lonStr = formatSingleCoordinate(lon, isLatitude: false, decimals: decimals);
    final alt = altitudeDisplay ?? (altitudeMeters != null ? formatAltitude(altitudeMeters, isMsl: isMsl) : '—');
    final altSuffix = (alt != '—' && alt.isNotEmpty) ? ' (Alt: $alt)' : '';
    return 'Lat $latStr  Long $lonStr$altSuffix';
  }

  /// Formats canonical UTC-first timestamp with Local and GMT offset:
  /// e.g. "UTC: 2026-08-28 14:43:08 UTC • Local: 2026-08-28 20:13:08 (GMT+05:30)"
  static String formatInspectionTimestamp(DateTime dateTime) {
    final utcTime = dateTime.toUtc();
    final utcFormatted =
        '${utcTime.year.toString().padLeft(4, '0')}-${utcTime.month.toString().padLeft(2, '0')}-${utcTime.day.toString().padLeft(2, '0')} ${utcTime.hour.toString().padLeft(2, '0')}:${utcTime.minute.toString().padLeft(2, '0')}:${utcTime.second.toString().padLeft(2, '0')}';

    final localTime = dateTime.toLocal();
    final localFormatted =
        '${localTime.year.toString().padLeft(4, '0')}-${localTime.month.toString().padLeft(2, '0')}-${localTime.day.toString().padLeft(2, '0')} ${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}:${localTime.second.toString().padLeft(2, '0')}';
    final offset = localTime.timeZoneOffset;
    final offsetHours = offset.inHours.abs().toString().padLeft(2, '0');
    final offsetMinutes =
        (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    final offsetSign = offset.isNegative ? '-' : '+';
    final timeZoneStr = 'GMT$offsetSign$offsetHours:$offsetMinutes';

    return 'UTC: $utcFormatted UTC • Local: $localFormatted ($timeZoneStr)';
  }

  /// Resolves country flag emoji for an address string.
  static String countryFlagForAddress(String? address) {
    if (address == null || address.isEmpty) return '';
    final lower = address.toLowerCase();
    if (lower.contains('india') || lower.contains('bharat')) return ' 🇮🇳';
    if (lower.contains('usa') || lower.contains('united states')) return ' 🇺🇸';
    if (lower.contains('uk') || lower.contains('united kingdom') || lower.contains('great britain')) return ' 🇬🇧';
    if (lower.contains('australia')) return ' 🇦🇺';
    if (lower.contains('canada')) return ' 🇨🇦';
    if (lower.contains('germany') || lower.contains('deutschland')) return ' 🇩🇪';
    if (lower.contains('japan') || lower.contains('nippon')) return ' 🇯🇵';
    if (lower.contains('singapore')) return ' 🇸🇬';
    if (lower.contains('uae') || lower.contains('emirates') || lower.contains('dubai')) return ' 🇦🇪';
    return '';
  }

  /// Resolves standard inspection headline from site name, site code, and address.
  static String formatInspectionHeadline({
    String? siteName,
    String? siteCode,
    String? resolvedAddress,
  }) {
    if (siteName != null && siteName.trim().isNotEmpty) {
      return siteName.trim();
    }
    if (siteCode != null && siteCode.trim().isNotEmpty && siteCode.trim().toUpperCase() != 'UNASSIGNED') {
      return siteCode.trim().toUpperCase();
    }
    final rawAddress = resolvedAddress?.trim() ?? '';
    if (rawAddress.isNotEmpty) {
      final parts = rawAddress
          .split(',')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();
      if (parts.length >= 3) {
        return '${parts[parts.length - 3]}, ${parts[parts.length - 2]}, ${parts.last}';
      } else if (parts.length == 2) {
        return '${parts[0]}, ${parts[1]}';
      } else {
        return rawAddress;
      }
    }
    return 'SITE CONTEXT';
  }
}
