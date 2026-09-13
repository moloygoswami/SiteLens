/// Canonical Evidence HUD Formatter and Adapter.
///
/// STRICT ARCHITECTURAL INVARIANTS:
/// 1. PURE DART ONLY: Zero imports from `package:flutter/...` and zero imports from `dart:ui`.
/// 2. SINGLE SOURCE OF TRUTH: All string formatting for HUD lines, timestamps,
///    coordinates, address resolution, status badges, and SHA hashes lives here.
/// 3. Zero rendering or layout mechanics.
library;

import '../../../core/utils/gps_utils.dart';
import '../../../domain/models/media_item.dart';
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

    final status = isGpsLocked ? snapshot.verificationStatus : HudStatus.pending;

    final (utcText, localText, tzText) = formatTimestamps(snapshot.capturedAtUtc);
    final (latStr, lonStr, altSuffix) = formatCoordinates(
      snapshot.latitude,
      snapshot.longitude,
      snapshot.altitudeMeters,
      isMsl: snapshot.isAltitudeMsl,
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

  /// Resolves the canonical user-facing site identifier from a persisted site
  /// code: uppercased, with the established neutral "SITE" fallback when the
  /// code is missing, blank, or the "UNASSIGNED" sentinel. The internal
  /// Firestore-style site document id is never used as an identifier.
  static String resolveSiteIdentifier(String? siteCode) {
    final code = siteCode?.trim() ?? '';
    if (code.isEmpty || code.toUpperCase() == 'UNASSIGNED') {
      return 'SITE';
    }
    return code.toUpperCase();
  }

  /// Adapts a persisted [MediaItem] into canonical [HudData] for runtime
  /// evidence viewing (the shared Photo/Video fullscreen metadata card).
  ///
  /// Uses ONLY capture-time persisted fields — no metadata is re-evaluated or
  /// synthesized here. Unavailable values (heading, accuracy, satellites, hash)
  /// stay unknown; the headline prefers the persisted site context and falls
  /// back to the captured address, and the status falls back exactly like the
  /// existing detail-screen telemetry row.
  static HudData fromMediaItem(
    MediaItem item, {
    String? siteCode,
    String? siteName,
  }) {
    final headline = GPSUtils.formatInspectionHeadline(
      siteName: siteName,
      siteCode: siteCode,
      resolvedAddress: item.capturedAddress,
    );
    final flagSuffix = GPSUtils.countryFlagForAddress(item.capturedAddress ?? '');

    final hasValidCoordinates = !(item.lat == 0.0 && item.lon == 0.0);
    final status = item.verificationStatus ??
        (item.lowAccuracy ? HudStatus.degraded : HudStatus.verified);

    final (utcText, localText, tzText) = formatTimestamps(item.capturedAt);
    final (latStr, lonStr, altSuffix) = formatCoordinates(
      item.lat,
      item.lon,
      item.altitude,
      isMsl: item.isAltitudeMsl ?? true,
    );

    final rawAddress = (item.capturedAddress ?? '').trim();

    final accuracyText = item.accuracyM != null
        ? '±${item.accuracyM!.toStringAsFixed(1)}m'
        : null;
    final satellitesText = item.gnssSatelliteCount != null
        ? 'SATS: ${item.gnssSatellitesUsedInFix ?? item.gnssSatelliteCount}/${item.gnssSatelliteCount}'
        : null;

    return HudData(
      headlineText: headline,
      countryFlagSuffix: flagSuffix,
      status: status,
      addressText: rawAddress,
      isAddressResolving: false,
      utcTimestampText: utcText,
      localTimestampText: localText,
      timeZoneText: tzText,
      latitudeText: latStr,
      longitudeText: lonStr,
      altitudeSuffix: altSuffix,
      siteCodeText: resolveSiteIdentifier(siteCode),
      displaySha256: formatSha(item.sha256Hash),
      accuracyText: accuracyText,
      satellitesText: satellitesText,
      isGpsLocked: hasValidCoordinates,
      latitude: item.lat,
      longitude: item.lon,
      isHighContrast: false,
      showMinimap: true,
      showAddress: true,
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
    bool isAltitudeMsl = true,
    double? accuracyMeters,
    required bool isGpsLocked,
    bool isDegraded = false,
    DateTime? captureTime,
    double? headingDegrees,
    bool isHighContrast = false,
    bool showAddress = true,
    bool showMinimap = true,
    double lowAccuracyThresholdMeters = 20.0,
  }) {
    final headline = GPSUtils.formatInspectionHeadline(
      siteName: siteName,
      siteCode: siteCode,
      resolvedAddress: resolvedAddress,
    );
    final flagSuffix = GPSUtils.countryFlagForAddress(resolvedAddress ?? '');

    final status = EvidenceMetadataSnapshot.evaluateVerificationStatus(
      hasValidFix: isGpsLocked,
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
      lowAccuracyThresholdMeters: lowAccuracyThresholdMeters,
    );

    final effectiveTime = captureTime ?? DateTime.now();
    final (utcText, localText, tzText) = formatTimestamps(effectiveTime);
    final (latStr, lonStr, altSuffix) = formatCoordinates(
      latitude,
      longitude,
      altitudeMeters,
      isMsl: isAltitudeMsl,
    );

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
    double? altitudeMeters, {
    bool isMsl = true,
  }) {
    final latStr = GPSUtils.formatSingleCoordinate(latitude, isLatitude: true);
    final lonStr = GPSUtils.formatSingleCoordinate(longitude, isLatitude: false);

    String? altSuffix;
    if (altitudeMeters != null) {
      final sign = altitudeMeters >= 0 ? '+' : '';
      final datum = isMsl ? 'm' : 'm WGS84';
      altSuffix = ' (Alt: $sign${altitudeMeters.toStringAsFixed(1)}$datum)';
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
