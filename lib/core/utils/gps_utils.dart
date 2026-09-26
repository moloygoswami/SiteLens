import '../constants/app_constants.dart';

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

  /// The OS could not determine the location permission state. This is NOT a
  /// denial and must never be reported as one.
  permissionUnknown,

  /// The device's location service is switched off.
  serviceDisabled,

  /// Only a cached/last-known location is available — no live fix has been
  /// received yet. Cached coordinates never unlock evidence capture.
  lastKnownOnly,

  /// A previously live fix was held, but has gone stale without fresh stream emissions.
  liveGoneStale,
}

/// Re-entrancy guard ensuring strict serialized capture execution (AC-GPS-12, PRD §9.4).
class ShutterReentrancyGuard {
  bool _isExecuting = false;

  bool get isExecuting => _isExecuting;

  /// Attempts to acquire the capture lock. Returns true if lock was successfully
  /// acquired; returns false if a capture is already in-flight.
  bool tryAcquire() {
    if (_isExecuting) return false;
    _isExecuting = true;
    return true;
  }

  /// Releases the capture lock upon completion of processing and persistence.
  void release() {
    _isExecuting = false;
  }
}

class GPSUtils {
  /// Evaluates the GPS Fix Status based on accuracy in meters against the single
  /// authoritative configurable threshold (AC-GPS-05, TM-U-05).
  static GPSFixStatus evaluateAccuracy(
    double? accuracyMeters, {
    bool hasFix = true,
    double lowAccuracyThresholdMeters = AppConstants.gpsDefaultLowAccuracyThresholdMeters,
  }) {
    if (!hasFix || accuracyMeters == null) {
      return GPSFixStatus.searching;
    }
    if (accuracyMeters <= AppConstants.gpsHighAccuracyThresholdMeters) {
      return GPSFixStatus.high;
    } else if (accuracyMeters <= lowAccuracyThresholdMeters) {
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
  /// e.g. "+18.4 m ASL" (when MSL is established), "-43.4 m (WGS84)" (when ellipsoidal),
  /// "+18.4 m" (when datum is unknown), or "—" if unavailable.
  static String formatAltitude(
    double? altitudeMeters, {
    bool? isMsl,
  }) {
    if (altitudeMeters == null) return '—';
    final sign = altitudeMeters >= 0 ? '+' : '';
    final String datumSuffix;
    if (isMsl == true) {
      datumSuffix = 'm ASL';
    } else if (isMsl == false) {
      datumSuffix = 'm (WGS84)';
    } else {
      datumSuffix = 'm';
    }
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
    bool? isMsl,
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

  /// Canonical distance + GNSS uncertainty formatting (R19).
  ///
  /// A distance is never presented as more spatially precise than the captured
  /// GPS accuracy supports. An unknown accuracy is disclosed as unknown rather
  /// than silently treated as exact; a null distance is not established and
  /// yields null (callers must render a truthful unknown state).
  static String? formatDistanceWithUncertainty(
    double? distanceMeters, {
    double? accuracyMeters,
  }) {
    if (distanceMeters == null) return null;
    final distance = '${distanceMeters.toStringAsFixed(1)}m';
    final uncertainty = accuracyMeters == null
        ? '±—'
        : '±${accuracyMeters.toStringAsFixed(1)}m';
    return '$distance ($uncertainty)';
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
