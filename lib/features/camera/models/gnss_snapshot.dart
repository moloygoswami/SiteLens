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
  final int satelliteCount;
  final int satellitesUsedInFix;
  final Map<String, GnssConstellationSummary> constellations;
  final DateTime? timestampUtc;

  const GnssSnapshot({
    this.isSupported = true,
    this.isAvailable = false,
    this.satelliteCount = 0,
    this.satellitesUsedInFix = 0,
    this.constellations = const {},
    this.timestampUtc,
  });

  static const GnssSnapshot unavailable = GnssSnapshot(
    isSupported: true,
    isAvailable: false,
    satelliteCount: 0,
    satellitesUsedInFix: 0,
    constellations: {},
  );

  static const GnssSnapshot unsupported = GnssSnapshot(
    isSupported: false,
    isAvailable: false,
    satelliteCount: 0,
    satellitesUsedInFix: 0,
    constellations: {},
  );

  /// True strictly if Android CONSTELLATION_IRNSS was reported by the device.
  /// Never inferred from country, model, chipset or location.
  bool get hasNavIC =>
      (constellations['irnss']?.trackedCount ?? 0) > 0;

  factory GnssSnapshot.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return GnssSnapshot.unavailable;

    final isSupported = map['isSupported'] as bool? ?? false;
    final isAvailable = map['isAvailable'] as bool? ?? false;
    final satelliteCount = (map['satelliteCount'] as num?)?.toInt() ?? 0;
    final usedCount = (map['satellitesUsedInFix'] as num?)?.toInt() ?? 0;

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
