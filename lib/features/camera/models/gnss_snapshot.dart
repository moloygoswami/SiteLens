import 'package:flutter/foundation.dart';

/// Per-constellation satellite summary metrics.
@immutable
class GnssConstellationSummary {
  final String constellation;
  final int trackedCount;
  final int usedInFixCount;

  const GnssConstellationSummary({
    required this.constellation,
    required this.trackedCount,
    required this.usedInFixCount,
  });

  /// User-friendly standard name for the constellation.
  String get displayName {
    switch (constellation.toLowerCase()) {
      case 'gps':
        return 'GPS';
      case 'glonass':
        return 'GLONASS';
      case 'galileo':
        return 'Galileo';
      case 'beidou':
        return 'BeiDou';
      case 'qzss':
        return 'QZSS';
      case 'sbas':
        return 'SBAS';
      case 'irnss':
        return 'NavIC (IRNSS)';
      default:
        return constellation.toUpperCase();
    }
  }

  factory GnssConstellationSummary.fromMap(String key, Map<dynamic, dynamic> map) {
    return GnssConstellationSummary(
      constellation: key,
      trackedCount: (map['tracked'] as num?)?.toInt() ?? 0,
      usedInFixCount: (map['usedInFix'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'constellation': constellation,
      'tracked': trackedCount,
      'usedInFix': usedInFixCount,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GnssConstellationSummary &&
          runtimeType == other.runtimeType &&
          constellation == other.constellation &&
          trackedCount == other.trackedCount &&
          usedInFixCount == other.usedInFixCount;

  @override
  int get hashCode => Object.hash(constellation, trackedCount, usedInFixCount);

  @override
  String toString() =>
      '$displayName(tracked: $trackedCount, usedInFix: $usedInFixCount)';
}

/// Immutable snapshot of device GNSS status at a point in time.
@immutable
class GnssSnapshot {
  final bool isSupported;
  final bool isAvailable;

  /// Total tracked satellites. Null when the producer did not report the field
  /// — an absent count is unknown, never an established 0 (R10).
  final int? satelliteCount;

  /// Satellites used in the position fix. Null when the producer did not
  /// report the field (R10).
  final int? satellitesUsedInFix;
  final Map<String, GnssConstellationSummary> constellations;
  final DateTime? timestampUtc;

  const GnssSnapshot({
    this.isSupported = true,
    this.isAvailable = false,
    this.satelliteCount,
    this.satellitesUsedInFix,
    this.constellations = const {},
    this.timestampUtc,
  });

  static const GnssSnapshot unavailable = GnssSnapshot(
    isSupported: true,
    isAvailable: false,
  );

  static const GnssSnapshot unsupported = GnssSnapshot(
    isSupported: false,
    isAvailable: false,
  );

  /// True strictly if Android CONSTELLATION_IRNSS was reported by the device.
  /// Never inferred from country, model, chipset or location.
  bool get hasNavIC =>
      (constellations['irnss']?.trackedCount ?? 0) > 0;

  factory GnssSnapshot.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return GnssSnapshot.unavailable;

    final isSupported = map['isSupported'] as bool? ?? false;
    final isAvailable = map['isAvailable'] as bool? ?? false;
    // An absent count field is unknown — it must not be coerced to 0, which
    // would disclose "0 satellites" the producer never reported (R10).
    final satelliteCount = (map['satelliteCount'] as num?)?.toInt();
    final usedCount = (map['satellitesUsedInFix'] as num?)?.toInt();

    DateTime? timestampUtc;
    final timestampMillis = (map['timestampMillis'] as num?)?.toInt();
    if (timestampMillis != null && timestampMillis > 0) {
      timestampUtc = DateTime.fromMillisecondsSinceEpoch(timestampMillis, isUtc: true);
    }

    final rawConstellations = map['constellations'];
    final parsedConstellations = <String, GnssConstellationSummary>{};

    if (rawConstellations is Map) {
      rawConstellations.forEach((key, val) {
        if (key is String && val is Map) {
          parsedConstellations[key.toLowerCase()] =
              GnssConstellationSummary.fromMap(key.toLowerCase(), val);
        }
      });
    }

    return GnssSnapshot(
      isSupported: isSupported,
      isAvailable: isAvailable,
      satelliteCount: satelliteCount,
      satellitesUsedInFix: usedCount,
      constellations: parsedConstellations,
      timestampUtc: timestampUtc,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'isSupported': isSupported,
      'isAvailable': isAvailable,
      'satelliteCount': satelliteCount,
      'satellitesUsedInFix': satellitesUsedInFix,
      'constellations': constellations.map((k, v) => MapEntry(k, v.toMap())),
      'timestampMillis': timestampUtc?.millisecondsSinceEpoch,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GnssSnapshot &&
          runtimeType == other.runtimeType &&
          isSupported == other.isSupported &&
          isAvailable == other.isAvailable &&
          satelliteCount == other.satelliteCount &&
          satellitesUsedInFix == other.satellitesUsedInFix &&
          mapEquals(constellations, other.constellations) &&
          timestampUtc == other.timestampUtc;

  @override
  int get hashCode => Object.hash(
        isSupported,
        isAvailable,
        satelliteCount,
        satellitesUsedInFix,
        Object.hashAll(constellations.entries),
        timestampUtc,
      );

  @override
  String toString() =>
      'GnssSnapshot(supported: $isSupported, available: $isAvailable, satellites: $satelliteCount, usedInFix: $satellitesUsedInFix, constellations: ${constellations.keys.join(",")})';
}

/// Lightweight telemetry object capturing native Android MSL/WGS84 altitude state.
@immutable
class AltitudeTelemetry {
  final bool hasMslAltitude;
  final double? mslAltitudeMeters;
  final double? wgs84AltitudeMeters;

  const AltitudeTelemetry({
    required this.hasMslAltitude,
    this.mslAltitudeMeters,
    this.wgs84AltitudeMeters,
  });

  factory AltitudeTelemetry.fromMap(Map<dynamic, dynamic> map) {
    return AltitudeTelemetry(
      hasMslAltitude: map['hasMslAltitude'] as bool? ?? false,
      mslAltitudeMeters: (map['mslAltitudeMeters'] as num?)?.toDouble(),
      wgs84AltitudeMeters: (map['wgs84AltitudeMeters'] as num?)?.toDouble(),
    );
  }

  static const AltitudeTelemetry unavailable = AltitudeTelemetry(
    hasMslAltitude: false,
    mslAltitudeMeters: null,
    wgs84AltitudeMeters: null,
  );
}
