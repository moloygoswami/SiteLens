import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/gps_utils.dart';
import 'gnss_snapshot.dart';

class GpsHardwareState {
  final GPSFixStatus fixStatus;
  final bool hasValidFix;
  final double? latitude;
  final double? longitude;
  final double? altitudeMeters;
  final double? accuracyMeters;
  final DateTime? timestampUtc;
  final bool isLocationServiceEnabled;
  final LocationPermission permissionStatus;
  final double? distanceToSiteMeters;
  final double? headingDegrees;
  final String? resolvedLocationName;
  final String? errorMessage;

  /// Coordinates for which [resolvedLocationName] was actually resolved.
  /// Null when no name has been resolved for the current fix. Used to reject a
  /// stale name when baking evidence — a name from a previous location must
  /// never be attached to different coordinates.
  final double? resolvedLocationLat;
  final double? resolvedLocationLon;
  final GnssSnapshot? gnssSnapshot;
  final bool isAltitudeMsl;

  const GpsHardwareState({
    this.fixStatus = GPSFixStatus.searching,
    this.hasValidFix = false,
    this.latitude,
    this.longitude,
    this.altitudeMeters,
    this.isAltitudeMsl = true,
    this.accuracyMeters,
    this.headingDegrees,
    this.timestampUtc,
    this.isLocationServiceEnabled = true,
    this.permissionStatus = LocationPermission.whileInUse,
    this.distanceToSiteMeters,
    this.resolvedLocationName,
    this.errorMessage,
    this.resolvedLocationLat,
    this.resolvedLocationLon,
    this.gnssSnapshot,
  });

  bool get isSearching => fixStatus == GPSFixStatus.searching || !hasValidFix;
  bool get isDegraded => hasValidFix && fixStatus == GPSFixStatus.poor;
  bool get isHighOrWeak => hasValidFix && (fixStatus == GPSFixStatus.high || fixStatus == GPSFixStatus.weak);

  bool get isPermissionGranted =>
      permissionStatus == LocationPermission.whileInUse ||
      permissionStatus == LocationPermission.always;

  /// Why the GPS cannot provide a valid fix right now. Used to surface
  /// cause-specific guidance ("Enable Location", "Open Settings") instead of a
  /// generic "Waiting for GPS lock".
  GpsBlockReason? get blockReason {
    if (hasValidFix) return null;
    if (!isLocationServiceEnabled) return GpsBlockReason.serviceDisabled;
    if (!isPermissionGranted) return GpsBlockReason.permissionDenied;
    return GpsBlockReason.searching;
  }

  String get coordinatesDisplay {
    if (!hasValidFix || latitude == null || longitude == null) {
      return 'Lat — , Long —';
    }
    return GPSUtils.formatCoordinates(latitude!, longitude!);
  }

  String get latitudeDisplay {
    if (!hasValidFix || latitude == null) return '—';
    return GPSUtils.formatSingleCoordinate(latitude!, isLatitude: true);
  }

  String get longitudeDisplay {
    if (!hasValidFix || longitude == null) return '—';
    return GPSUtils.formatSingleCoordinate(longitude!, isLatitude: false);
  }

  String get altitudeDisplay {
    if (!hasValidFix) return '—';
    return GPSUtils.formatAltitude(altitudeMeters, isMsl: isAltitudeMsl);
  }

  String get timestampUtcDisplay {
    if (timestampUtc == null) {
      return '—';
    }
    return '${DateFormat("yyyy-MM-dd HH:mm:ss").format(timestampUtc!)} UTC';
  }

  String get statusBadgeLabel {
    if (!isLocationServiceEnabled) {
      return 'GPS: Disabled';
    }
    if (!isPermissionGranted) {
      return 'GPS: Denied';
    }
    return GPSUtils.formatStatusLabel(fixStatus, hasValidFix ? accuracyMeters : null);
  }

  GpsHardwareState copyWith({
    GPSFixStatus? fixStatus,
    bool? hasValidFix,
    double? latitude,
    double? longitude,
    double? altitudeMeters,
    bool? isAltitudeMsl,
    bool clearAltitude = false,
    double? accuracyMeters,
    double? headingDegrees,
    bool clearHeading = false,
    DateTime? timestampUtc,
    bool? isLocationServiceEnabled,
    LocationPermission? permissionStatus,
    double? distanceToSiteMeters,
    bool clearDistanceToSite = false,
    String? resolvedLocationName,
    double? resolvedLocationLat,
    double? resolvedLocationLon,
    String? errorMessage,
    GnssSnapshot? gnssSnapshot,
    bool clearGnss = false,
    bool clearFix = false,
    bool clearError = false,
  }) {
    return GpsHardwareState(
      fixStatus: fixStatus ?? this.fixStatus,
      hasValidFix: clearFix ? false : (hasValidFix ?? this.hasValidFix),
      latitude: clearFix ? null : (latitude ?? this.latitude),
      longitude: clearFix ? null : (longitude ?? this.longitude),
      altitudeMeters: clearFix || clearAltitude ? null : (altitudeMeters ?? this.altitudeMeters),
      isAltitudeMsl: isAltitudeMsl ?? this.isAltitudeMsl,
      accuracyMeters: clearFix ? null : (accuracyMeters ?? this.accuracyMeters),
      headingDegrees: clearFix || clearHeading ? null : (headingDegrees ?? this.headingDegrees),
      timestampUtc: clearFix ? null : (timestampUtc ?? this.timestampUtc),
      isLocationServiceEnabled: isLocationServiceEnabled ?? this.isLocationServiceEnabled,
      permissionStatus: permissionStatus ?? this.permissionStatus,
      distanceToSiteMeters: clearFix || clearDistanceToSite
          ? null
          : (distanceToSiteMeters ?? this.distanceToSiteMeters),
      resolvedLocationName: clearFix ? null : (resolvedLocationName ?? this.resolvedLocationName),
      resolvedLocationLat: clearFix ? null : (resolvedLocationLat ?? this.resolvedLocationLat),
      resolvedLocationLon: clearFix ? null : (resolvedLocationLon ?? this.resolvedLocationLon),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      gnssSnapshot: clearFix || clearGnss ? null : (gnssSnapshot ?? this.gnssSnapshot),
    );
  }
}
