import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../core/utils/gps_utils.dart';
import 'gnss_snapshot.dart';
import 'gps_hardware_state.dart';

class EvidenceMetadataSnapshot {
  final String mediaId;
  final String siteId;
  final String siteCode;
  final String siteName;
  final double latitude;
  final double longitude;
  final double? altitudeMeters;
  final bool isAltitudeMsl;
  final double? accuracyMeters;
  final double? headingDegrees;
  final bool lowAccuracy;
  final DateTime capturedAtUtc;
  final String canonicalTimestampUtc;

  /// Physical address resolved from capture coordinates via reverse geocoding.
  /// Mandatory audit metadata — always non-null. Falls back to "$siteCode VICINITY"
  /// when offline, or "NO FIX — LOCATION UNAVAILABLE" when GPS fix is absent.
  final String resolvedAddress;
  final String? creatorId;

  /// GNSS satellite telemetry captured at shutter time.
  final int? gnssSatelliteCount;
  final int? gnssSatellitesUsedInFix;
  final Map<String, GnssConstellationSummary>? gnssConstellations;
  final GnssSnapshot? gnssSnapshot;

  const EvidenceMetadataSnapshot({
    required this.mediaId,
    required this.siteId,
    required this.siteCode,
    required this.siteName,
    required this.latitude,
    required this.longitude,
    this.altitudeMeters,
    this.isAltitudeMsl = true,
    this.accuracyMeters,
    this.headingDegrees,
    required this.lowAccuracy,
    required this.capturedAtUtc,
    required this.canonicalTimestampUtc,
    required this.resolvedAddress,
    this.creatorId,
    this.gnssSatelliteCount,
    this.gnssSatellitesUsedInFix,
    this.gnssConstellations,
    this.gnssSnapshot,
  });

  /// Factory constructor capturing a synchronous, immutable snapshot from live GPS
  /// and active site state at the exact moment of shutter press.
  factory EvidenceMetadataSnapshot.capture({
    required GpsHardwareState gpsState,
    required String siteId,
    required String siteCode,
    required String siteName,
    String? customMediaId,
    String? resolvedAddress,
    String? creatorId,
    double? lowAccuracyThresholdMeters,
    GnssSnapshot? customGnssSnapshot,
  }) {
    final mediaId = customMediaId ?? const Uuid().v4();
    final nowUtc = DateTime.now().toUtc();
    final captureUtc = gpsState.timestampUtc ?? nowUtc;
    final canonicalFormatted =
        '${DateFormat("yyyy-MM-dd HH:mm:ss").format(captureUtc)} UTC';

    final threshold = lowAccuracyThresholdMeters ?? 20.0;
    final accuracy = gpsState.accuracyMeters;
    final isLowAcc = !gpsState.hasValidFix || (accuracy != null && accuracy > threshold);

    final gnss = customGnssSnapshot ?? gpsState.gnssSnapshot;
    final gnssAvailable = gnss?.isAvailable == true;

    // Offline fallback chain — resolvedAddress must never be blank on evidence.
    // A resolved address is only accepted when it was resolved for the SAME
    // coordinates as the current fix; a stale name from a previous location
    // must never be baked into evidence for different coordinates.
    final String address;
    if (!gpsState.hasValidFix) {
      address = 'NO FIX — LOCATION UNAVAILABLE';
    } else if (resolvedAddress != null &&
        resolvedAddress.trim().isNotEmpty &&
        _addressMatchesFix(gpsState)) {
      address = resolvedAddress.trim();
    } else {
      address = '${siteCode.toUpperCase()} VICINITY';
    }

    return EvidenceMetadataSnapshot(
      mediaId: mediaId,
      siteId: siteId,
      siteCode: siteCode,
      siteName: siteName,
      latitude: gpsState.latitude ?? 0.0,
      longitude: gpsState.longitude ?? 0.0,
      altitudeMeters: gpsState.altitudeMeters,
      isAltitudeMsl: gpsState.isAltitudeMsl,
      accuracyMeters: accuracy,
      headingDegrees: gpsState.headingDegrees,
      lowAccuracy: isLowAcc,
      capturedAtUtc: captureUtc,
      canonicalTimestampUtc: canonicalFormatted,
      resolvedAddress: address,
      creatorId: creatorId,
      gnssSatelliteCount: gnssAvailable ? gnss?.satelliteCount : null,
      gnssSatellitesUsedInFix: gnssAvailable ? gnss?.satellitesUsedInFix : null,
      gnssConstellations: gnssAvailable ? gnss?.constellations : null,
      gnssSnapshot: gnss,
    );
  }

  String get coordinatesDisplay =>
      GPSUtils.formatCoordinates(latitude, longitude);

  String get altitudeDisplay => GPSUtils.formatAltitude(altitudeMeters, isMsl: isAltitudeMsl);

  String get accuracyDisplay => accuracyMeters != null
      ? '±${accuracyMeters!.toStringAsFixed(1)}m'
      : '±—m';

  /// True when [gpsState.resolvedLocationLat]/[resolvedLocationLon] are within
  /// ~50m (0.0005°, matching the geocoder's cache-bucket granularity) of the
  /// current fix coordinates — i.e. the resolved address belongs to this fix.
  static bool _addressMatchesFix(GpsHardwareState gpsState) {
    final assocLat = gpsState.resolvedLocationLat;
    final assocLon = gpsState.resolvedLocationLon;
    final fixLat = gpsState.latitude;
    final fixLon = gpsState.longitude;
    if (assocLat == null || assocLon == null || fixLat == null || fixLon == null) {
      return false;
    }
    return (assocLat - fixLat).abs() < 0.0005 &&
        (assocLon - fixLon).abs() < 0.0005;
  }
}
