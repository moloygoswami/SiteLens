import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../core/utils/gps_utils.dart';
import '../hud/hud_data.dart';
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
  /// Video audio-track presence: true=recorded, false=muted, null=unknown or
  /// not applicable (photo). Truthful disclosure — never assumed (R09).
  final bool? hasAudioTrack;
  final bool lowAccuracy;
  final DateTime capturedAtUtc;
  final String canonicalTimestampUtc;

  /// Physical address resolved from capture coordinates via reverse geocoding.
  /// Mandatory audit metadata — always non-null. Falls back to "$siteCode VICINITY"
  /// when offline, or "NO FIX — LOCATION UNAVAILABLE" when GPS fix is absent.
  final String resolvedAddress;
  final String? creatorId;

  /// Whether the metadata snapshot contains a verified, valid GPS fix.
  final bool hasValidFix;

  /// GNSS satellite telemetry captured at shutter time.
  final int? gnssSatelliteCount;
  final int? gnssSatellitesUsedInFix;
  final Map<String, GnssConstellationSummary>? gnssConstellations;
  final GnssSnapshot? gnssSnapshot;

  /// Timestamp when the GNSS satellite fix was computed by the receiver.
  /// Preserved as GNSS telemetry metadata; strictly decoupled from physical capture instant.
  final DateTime? gnssFixTimestampUtc;

  /// Canonical evidence verification status established at capture time.
  final HudStatus? _verificationStatus;

  HudStatus get verificationStatus =>
      _verificationStatus ??
      (lowAccuracy
          ? HudStatus.degraded
          : (hasValidCoordinates ? HudStatus.verified : HudStatus.pending));

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
    this.hasAudioTrack,
    required this.lowAccuracy,
    required this.capturedAtUtc,
    required this.canonicalTimestampUtc,
    required this.resolvedAddress,
    this.creatorId,
    this.hasValidFix = true,
    this.gnssSatelliteCount,
    this.gnssSatellitesUsedInFix,
    this.gnssConstellations,
    this.gnssSnapshot,
    this.gnssFixTimestampUtc,
    HudStatus? verificationStatus,
  }) : _verificationStatus = verificationStatus;

  /// Evaluates the canonical verification status according to accuracy threshold and fix validity.
  static HudStatus evaluateVerificationStatus({
    required bool hasValidFix,
    required double? latitude,
    required double? longitude,
    required double? accuracyMeters,
    double lowAccuracyThresholdMeters = 20.0,
  }) {
    final hasCoordinates = hasValidFix &&
        latitude != null &&
        longitude != null &&
        !(latitude == 0.0 && longitude == 0.0);

    if (!hasCoordinates) {
      return HudStatus.pending;
    }

    if (accuracyMeters == null || accuracyMeters > lowAccuracyThresholdMeters) {
      return HudStatus.degraded;
    }

    return HudStatus.verified;
  }

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
    DateTime? customCaptureTimeUtc,
    bool? hasAudioTrack,
  }) {
    final mediaId = customMediaId ?? const Uuid().v4();
    final nowUtc = DateTime.now().toUtc();
    final captureUtc = customCaptureTimeUtc ?? nowUtc;
    final canonicalFormatted =
        '${DateFormat("yyyy-MM-dd HH:mm:ss").format(captureUtc)} UTC';

    final threshold = lowAccuracyThresholdMeters ?? 20.0;
    final accuracy = gpsState.accuracyMeters;
    final status = evaluateVerificationStatus(
      hasValidFix: gpsState.hasValidFix,
      latitude: gpsState.latitude,
      longitude: gpsState.longitude,
      accuracyMeters: accuracy,
      lowAccuracyThresholdMeters: threshold,
    );
    final isLowAcc = status == HudStatus.degraded;

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

    final hasValidGps = gpsState.hasValidFix &&
        gpsState.latitude != null &&
        gpsState.longitude != null &&
        !(gpsState.latitude == 0.0 && gpsState.longitude == 0.0);

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
      hasAudioTrack: hasAudioTrack,
      lowAccuracy: isLowAcc,
      capturedAtUtc: captureUtc,
      canonicalTimestampUtc: canonicalFormatted,
      resolvedAddress: address,
      creatorId: creatorId,
      hasValidFix: hasValidGps,
      gnssSatelliteCount: gnssAvailable ? gnss?.satelliteCount : null,
      gnssSatellitesUsedInFix: gnssAvailable ? gnss?.satellitesUsedInFix : null,
      gnssConstellations: gnssAvailable ? gnss?.constellations : null,
      gnssSnapshot: gnss,
      gnssFixTimestampUtc: gpsState.timestampUtc,
      verificationStatus: status,
    );
  }

  bool get hasValidCoordinates =>
      hasValidFix && !(latitude == 0.0 && longitude == 0.0);

  String get coordinatesDisplay => hasValidCoordinates
      ? GPSUtils.formatCoordinates(latitude, longitude)
      : 'Lat — , Long —';

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
