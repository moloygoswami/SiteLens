/// Canonical Evidence HUD Formatter and Adapter.
///
/// STRICT ARCHITECTURAL INVARIANTS:
/// 1. PURE DART ONLY: Zero imports from `package:flutter/...` and zero imports from `dart:ui`.
/// 2. SINGLE SOURCE OF TRUTH: All string formatting for HUD lines, timestamps,
///    coordinates, address resolution, status badges, and SHA hashes lives here.
/// 3. Zero rendering or layout mechanics.
library;

import '../../../core/utils/gps_utils.dart';
import '../models/evidence_metadata_snapshot.dart';
import 'hud_data.dart';

class HudFormatter {
  /// Adapts a shutter-time [EvidenceMetadataSnapshot] and [originalSha256] into canonical [HudData].
  static HudData fromSnapshot({
    required EvidenceMetadataSnapshot snapshot,
    required String originalSha256,
    bool isGpsLocked = true,
    bool showAddress = true,
    bool showMinimap = true,
    double? headingDegrees,
    bool isHighContrast = false,
  }) {
    final headline = GPSUtils.formatInspectionHeadline(
      siteName: snapshot.siteName,
      siteCode: snapshot.siteCode,
      resolvedAddress: snapshot.resolvedAddress,
    );
    final flagSuffix = GPSUtils.countryFlagForAddress(snapshot.resolvedAddress);

    final isVerified = isGpsLocked && !snapshot.lowAccuracy && originalSha256.isNotEmpty;
    final status = isVerified
        ? HudStatus.verified
        : (snapshot.lowAccuracy ? HudStatus.degraded : HudStatus.pending);

    final (utcText, localText, tzText) = formatTimestamps(snapshot.capturedAtUtc);
    final (latStr, lonStr, altSuffix) = formatCoordinates(
      snapshot.latitude,
      snapshot.longitude,
      snapshot.altitudeMeters,
    );

    final displaySha = formatSha(originalSha256);

    return HudData(
      headlineText: headline,
      countryFlagSuffix: flagSuffix,
      status: status,
      addressText: snapshot.resolvedAddress.trim(),
      isAddressResolving: false,
      utcTimestampText: utcText,
      localTimestampText: localText,
      timeZoneText: tzText,
      latitudeText: latStr,
      longitudeText: lonStr,
      altitudeSuffix: altSuffix,
      siteCodeText: snapshot.siteCode.toUpperCase(),
      displaySha256: displaySha,
      isGpsLocked: isGpsLocked,
      latitude: snapshot.latitude,
      longitude: snapshot.longitude,
      headingDegrees: headingDegrees,
      isHighContrast: isHighContrast,
      showMinimap: showMinimap,
      showAddress: showAddress,
    );
  }

  /// Adapts live camera viewfinder telemetry into canonical [HudData].
  static HudData fromLive({
    required String siteCode,
    String? siteName,
    String? resolvedAddress,
    required double latitude,
    required double longitude,
    double? altitudeMeters,
    double? accuracyMeters,
    required bool isGpsLocked,
    required bool isDegraded,
    DateTime? captureTime,
    double? headingDegrees,
    bool isHighContrast = false,
    bool showAddress = true,
    bool showMinimap = true,
  }) {
    final headline = GPSUtils.formatInspectionHeadline(
      siteName: siteName,
      siteCode: siteCode,
      resolvedAddress: resolvedAddress,
    );
    final flagSuffix = GPSUtils.countryFlagForAddress(resolvedAddress ?? '');

    final isVerified = isGpsLocked && !isDegraded;
    final status = isVerified
        ? HudStatus.verified
        : (isDegraded ? HudStatus.degraded : HudStatus.pending);

    final effectiveTime = captureTime ?? DateTime.now();
    final (utcText, localText, tzText) = formatTimestamps(effectiveTime);
    final (latStr, lonStr, altSuffix) = formatCoordinates(latitude, longitude, altitudeMeters);

    final rawAddress = (resolvedAddress ?? '').trim();
    final isResolving = rawAddress.isEmpty || rawAddress == 'RESOLVING...';

    return HudData(
      headlineText: headline,
      countryFlagSuffix: flagSuffix,
      status: status,
      addressText: isResolving ? 'RESOLVING...' : rawAddress,
      isAddressResolving: isResolving,
      utcTimestampText: utcText,
      localTimestampText: localText,
      timeZoneText: tzText,
      latitudeText: latStr,
      longitudeText: lonStr,
      altitudeSuffix: altSuffix,
      siteCodeText: siteCode.toUpperCase(),
      displaySha256: null, // Hash is pending until saved in live preview
      isGpsLocked: isGpsLocked,
      latitude: latitude,
      longitude: longitude,
      headingDegrees: headingDegrees,
      isHighContrast: isHighContrast,
      showMinimap: showMinimap,
      showAddress: showAddress,
    );
  }

  /// Formats a DateTime into UTC string, local string, and GMT timezone offset.
  static (String, String, String) formatTimestamps(DateTime time) {
    final utcTime = time.toUtc();
    final utcFormatted =
        '${utcTime.year.toString().padLeft(4, '0')}-${utcTime.month.toString().padLeft(2, '0')}-${utcTime.day.toString().padLeft(2, '0')} ${utcTime.hour.toString().padLeft(2, '0')}:${utcTime.minute.toString().padLeft(2, '0')}:${utcTime.second.toString().padLeft(2, '0')}';

    final localTime = time.toLocal();
    final localFormatted =
        '${localTime.year.toString().padLeft(4, '0')}-${localTime.month.toString().padLeft(2, '0')}-${localTime.day.toString().padLeft(2, '0')} ${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}:${localTime.second.toString().padLeft(2, '0')}';

    final offset = localTime.timeZoneOffset;
    final offsetHours = offset.inHours.abs().toString().padLeft(2, '0');
    final offsetMinutes =
        (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    final offsetSign = offset.isNegative ? '-' : '+';
    final timeZoneStr = 'GMT$offsetSign$offsetHours:$offsetMinutes';

    return (utcFormatted, localFormatted, timeZoneStr);
  }

  /// Formats latitude and longitude coordinates and signed altitude suffix.
  static (String, String, String?) formatCoordinates(
    double latitude,
    double longitude,
    double? altitudeMeters,
  ) {
    final latStr = GPSUtils.formatSingleCoordinate(latitude, isLatitude: true);
    final lonStr = GPSUtils.formatSingleCoordinate(longitude, isLatitude: false);

    String? altSuffix;
    if (altitudeMeters != null) {
      final sign = altitudeMeters >= 0 ? '+' : '';
      altSuffix = ' (Alt: $sign${altitudeMeters.toStringAsFixed(1)}m)';
    }

    return (latStr, lonStr, altSuffix);
  }

  /// Formats a 64-character SHA-256 hash into a compact 19-character representation (8...8).
  static String? formatSha(String? sha256) {
    if (sha256 == null || sha256.isEmpty) {
      return null;
    }
    if (sha256.length > 18) {
      return '${sha256.substring(0, 8)}...${sha256.substring(sha256.length - 8)}';
    }
    return sha256;
  }
}
