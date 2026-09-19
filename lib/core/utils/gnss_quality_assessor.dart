import 'gps_utils.dart';
import '../../features/camera/models/gnss_snapshot.dart';

/// Fix confidence determined by combining GNSS telemetry with the OS location fix.
/// Positional accuracy (meters) is ALWAYS derived directly from the OS location provider;
/// GNSS telemetry provides structural verification of the fix without overwriting accuracy.
enum GnssFixConfidence {
  /// No valid location fix from OS.
  none,

  /// Valid OS location fix exists, but GNSS telemetry is unavailable or reporting
  /// fewer than 4 participating satellites (e.g. network-assisted / single-satellite).
  basic,

  /// Valid OS location fix verified by 4 or more participating GNSS satellites.
  multiSatelliteVerified,
}

/// Deterministic GNSS quality assessment result.
class GnssQualityAssessment {
  final bool hasValidFix;
  final double? accuracyMeters;
  final GPSFixStatus fixStatus;
  final GnssFixConfidence confidence;
  final int satellitesUsedInFix;
  final int totalSatellitesTracked;
  final bool isGnssAvailable;

  const GnssQualityAssessment({
    required this.hasValidFix,
    required this.accuracyMeters,
    required this.fixStatus,
    required this.confidence,
    required this.satellitesUsedInFix,
    required this.totalSatellitesTracked,
    required this.isGnssAvailable,
  });

  /// Evaluates GNSS quality deterministically.
  /// Note: Satellite count is NOT equated with positional accuracy in meters.
  /// Horizontal accuracy comes strictly from the Android/OS provider.
  factory GnssQualityAssessment.evaluate({
    required bool hasValidFix,
    required double? accuracyMeters,
    GnssSnapshot? gnssSnapshot,
  }) {
    if (!hasValidFix || accuracyMeters == null) {
      return const GnssQualityAssessment(
        hasValidFix: false,
        accuracyMeters: null,
        fixStatus: GPSFixStatus.searching,
        confidence: GnssFixConfidence.none,
        satellitesUsedInFix: 0,
        totalSatellitesTracked: 0,
        isGnssAvailable: false,
      );
    }

    final fixStatus = GPSUtils.evaluateAccuracy(accuracyMeters, hasFix: true);
    final gnss = gnssSnapshot ?? GnssSnapshot.unavailable;
    final isAvailable = gnss.isAvailable;
    // A count the producer never reported stays unknown, and an unknown count
    // can never establish multi-satellite verification: it collapses to the
    // conservative 0 for this confidence heuristic only — the disclosed
    // evidence telemetry preserves null (R10).
    final used = isAvailable ? (gnss.satellitesUsedInFix ?? 0) : 0;
    final tracked = isAvailable ? (gnss.satelliteCount ?? 0) : 0;

    final GnssFixConfidence confidence;
    if (isAvailable && used >= 4) {
      confidence = GnssFixConfidence.multiSatelliteVerified;
    } else {
      confidence = GnssFixConfidence.basic;
    }

    return GnssQualityAssessment(
      hasValidFix: true,
      accuracyMeters: accuracyMeters,
      fixStatus: fixStatus,
      confidence: confidence,
      satellitesUsedInFix: used,
      totalSatellitesTracked: tracked,
      isGnssAvailable: isAvailable,
    );
  }
}
