/// Canonical Evidence HUD Data Contract.
///
/// STRICT ARCHITECTURAL INVARIANTS:
/// 1. PURE DART ONLY: Zero imports from `package:flutter/...` and zero imports from `dart:ui`.
/// 2. ISOLATE TRANSFERABLE: All fields are primitive Dart types or pure enums.
/// 3. UPSTREAM ONLY: Used strictly in camera viewfinder, evidence processing,
///    and the canonical minimap/metadata display of the evidence detail and
///    review surfaces (rendered from persisted capture metadata only).
///    Never persisted to Drift/SQLite.
library;

/// Verification status badge for the Evidence HUD.
enum HudStatus {
  verified,
  degraded,
  pending;

  String get label => name.toUpperCase();
}

/// Canonical semantic data model for the Evidence HUD.
///
/// Contains the verified, pre-formatted text lines, status badge state,
/// and minimap telemetry required by both the live camera preview HUD
/// and the canonical evidence watermark renderer.
class HudData {
  // --- Line 1: Headline & Status Badge ---
  /// Formatted inspection headline (e.g., "Sonar Kella Apartment, Kolkata" or site code fallback).
  final String headlineText;

  /// Optional country flag emoji suffix derived from the resolved address (e.g. " 🇮🇳").
  final String countryFlagSuffix;

  /// Evidence verification status based on GPS lock, accuracy, and SHA presence.
  final HudStatus status;

  // --- Line 2: Street Address ---
  /// Physical resolved address or vicinity fallback.
  final String addressText;

  /// True when the address is actively being resolved via geocoding.
  final bool isAddressResolving;

  // --- Line 3: Capture Timestamp ---
  /// Canonical UTC timestamp string ("yyyy-MM-dd HH:mm:ss").
  final String utcTimestampText;

  /// Canonical Local timestamp string ("yyyy-MM-dd HH:mm:ss").
  final String localTimestampText;

  /// Local timezone offset string (e.g. "GMT+05:30").
  final String timeZoneText;

  // --- Line 4: GNSS Geocoordinates & Elevation ---
  /// Formatted latitude string (e.g. "22.56298° N").
  final String latitudeText;

  /// Formatted longitude string (e.g. "88.30085° E").
  final String longitudeText;

  /// Formatted elevation suffix (e.g. " (Alt: -43.4m)" or null if unavailable).
  final String? altitudeSuffix;

  // --- Line 5: Site Identifier & Forensic Integrity Hash ---
  /// Uppercase site code (e.g. "HOME" or "SITE_101").
  final String siteCodeText;

  /// Compact or full SHA-256 hash string. Null if hash is pending save.
  final String? displaySha256;

  // --- Optional Telemetry Tail (accuracy & GNSS satellite count) ---
  /// Pre-formatted positional accuracy (e.g. "±4.0m"). Null when unavailable.
  final String? accuracyText;

  /// Pre-formatted GNSS satellite usage (e.g. "SATS: 10/15"). Null when unavailable.
  final String? satellitesText;

  // --- Minimap & Telemetry State ---
  /// Whether GNSS has an active, valid positional fix.
  final bool isGpsLocked;

  /// Raw latitude coordinate for map pin / viewport centering.
  final double latitude;

  /// Raw longitude coordinate for map pin / viewport centering.
  final double longitude;

  /// Compass heading in degrees (0..360), if available.
  final double? headingDegrees;

  /// Whether Outdoor High-Contrast mode is enabled.
  final bool isHighContrast;

  /// Whether the minimap slot is enabled.
  final bool showMinimap;

  /// Whether the address line is enabled.
  final bool showAddress;

  const HudData({
    required this.headlineText,
    required this.countryFlagSuffix,
    required this.status,
    required this.addressText,
    this.isAddressResolving = false,
    required this.utcTimestampText,
    required this.localTimestampText,
    required this.timeZoneText,
    required this.latitudeText,
    required this.longitudeText,
    this.altitudeSuffix,
    required this.siteCodeText,
    this.displaySha256,
    this.accuracyText,
    this.satellitesText,
    required this.isGpsLocked,
    required this.latitude,
    required this.longitude,
    this.headingDegrees,
    this.isHighContrast = false,
    this.showMinimap = true,
    this.showAddress = true,
  });

  /// Complete headline including country flag suffix.
  String get fullHeadline => '$headlineText$countryFlagSuffix';

  /// Uppercase status text ("VERIFIED", "DEGRADED", or "PENDING").
  String get statusText => status.label;

  /// True when the forensic integrity hash has not yet been computed / saved.
  bool get isShaPending => displaySha256 == null || displaySha256!.isEmpty;
}
