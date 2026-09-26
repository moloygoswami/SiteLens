import '../../features/camera/hud/hud_data.dart';
import 'enums.dart';

class MediaItem {
  final String id;
  final String siteId;
  final String originalUri;
  final String uri;
  final String? thumbUri;
  final MediaItemType type;
  final double lat;
  final double lon;
  final double? accuracyM;
  final bool lowAccuracy;
  final double? altitude; // Captured elevation in meters — Added in v7 (remediates vuln-0002)
  final bool? isAltitudeMsl; // Datum: true = MSL, false = WGS84, null = unknown — Added in v8
  final HudStatus? verificationStatus; // Canonical verification status at capture time — Added in v8
  final int? gnssSatelliteCount; // Total tracked satellites at capture time — Added in v8
  final int? gnssSatellitesUsedInFix; // Satellites used in position fix — Added in v8
  final DateTime? gnssFixTimestampUtc; // GNSS receiver hardware fix timestamp — Added in v8
  final String? activityTag;
  final ObservationType observationType;
  final String? linkedMediaId;
  final String? note;
  final DateTime capturedAt;
  final String? sha256Hash;        // SHA-256 of orig_<id> — mandatory audit metadata
  final String? evidenceSha256Hash; // SHA-256 of evid_<id> — mandatory audit metadata
  final String? capturedAddress;    // Reverse-geocoded physical address at capture time — mandatory audit metadata
  final String? creatorId;          // Creator user UID for multi-user sync authorization — Added in v5
  final SyncStatusType syncStatus;
  final bool isDeleted; // Soft-delete support (PRD Section 10 & 26)
  final bool tombstoneReconciled; // Tombstone cloud-ledger reconciliation status
  final bool? hasAudioTrack; // Video audio-track presence: true=recorded, false=muted, null=unknown/photo — Added in v10 (R09)
  final double? headingDegrees; // Compass heading at capture time, null=unknown — Added in v10 (R10)

  const MediaItem({
    required this.id,
    required this.siteId,
    required this.originalUri,
    required this.uri,
    this.thumbUri,
    required this.type,
    required this.lat,
    required this.lon,
    this.accuracyM,
    this.lowAccuracy = false,
    this.altitude,
    this.isAltitudeMsl,
    this.verificationStatus,
    this.gnssSatelliteCount,
    this.gnssSatellitesUsedInFix,
    this.gnssFixTimestampUtc,
    this.activityTag,
    this.observationType = ObservationType.general,
    this.linkedMediaId,
    this.note,
    required this.capturedAt,
    this.sha256Hash,
    this.evidenceSha256Hash,
    this.capturedAddress,
    this.creatorId,
    this.syncStatus = SyncStatusType.pending,
    this.isDeleted = false,
    this.tombstoneReconciled = false,
    this.hasAudioTrack,
    this.headingDegrees,
  });

  MediaItem copyWith({
    String? id,
    String? siteId,
    String? originalUri,
    String? uri,
    String? thumbUri,
    MediaItemType? type,
    double? lat,
    double? lon,
    double? accuracyM,
    bool? lowAccuracy,
    double? altitude,
    bool? isAltitudeMsl,
    HudStatus? verificationStatus,
    int? gnssSatelliteCount,
    int? gnssSatellitesUsedInFix,
    DateTime? gnssFixTimestampUtc,
    String? activityTag,
    ObservationType? observationType,
    String? linkedMediaId,
    String? note,
    DateTime? capturedAt,
    String? sha256Hash,
    String? evidenceSha256Hash,
    String? capturedAddress,
    String? creatorId,
    SyncStatusType? syncStatus,
    bool? isDeleted,
    bool? tombstoneReconciled,
    bool? hasAudioTrack,
    double? headingDegrees,
  }) {
    return MediaItem(
      id: id ?? this.id,
      siteId: siteId ?? this.siteId,
      originalUri: originalUri ?? this.originalUri,
      uri: uri ?? this.uri,
      thumbUri: thumbUri ?? this.thumbUri,
      type: type ?? this.type,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      accuracyM: accuracyM ?? this.accuracyM,
      lowAccuracy: lowAccuracy ?? this.lowAccuracy,
      altitude: altitude ?? this.altitude,
      isAltitudeMsl: isAltitudeMsl ?? this.isAltitudeMsl,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      gnssSatelliteCount: gnssSatelliteCount ?? this.gnssSatelliteCount,
      gnssSatellitesUsedInFix: gnssSatellitesUsedInFix ?? this.gnssSatellitesUsedInFix,
      gnssFixTimestampUtc: gnssFixTimestampUtc ?? this.gnssFixTimestampUtc,
      activityTag: activityTag ?? this.activityTag,
      observationType: observationType ?? this.observationType,
      linkedMediaId: linkedMediaId ?? this.linkedMediaId,
      note: note ?? this.note,
      capturedAt: capturedAt ?? this.capturedAt,
      sha256Hash: sha256Hash ?? this.sha256Hash,
      evidenceSha256Hash: evidenceSha256Hash ?? this.evidenceSha256Hash,
      capturedAddress: capturedAddress ?? this.capturedAddress,
      creatorId: creatorId ?? this.creatorId,
      syncStatus: syncStatus ?? this.syncStatus,
      isDeleted: isDeleted ?? this.isDeleted,
      tombstoneReconciled: tombstoneReconciled ?? this.tombstoneReconciled,
      hasAudioTrack: hasAudioTrack ?? this.hasAudioTrack,
      headingDegrees: headingDegrees ?? this.headingDegrees,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaItem &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  /// Returns the authoritative SHA-256 hash matching the specified [artifactType].
  /// Never falls back from one artifact's hash to another (AC-EVID-06, AC-EVID-07).
  String? getArtifactHash(ArtifactType artifactType) {
    switch (artifactType) {
      case ArtifactType.original:
        return sha256Hash;
      case ArtifactType.evidence:
        return evidenceSha256Hash;
      case ArtifactType.thumbnail:
        return null;
    }
  }

  /// Returns the display string for the specified [artifactType]'s SHA-256 hash.
  /// If the hash is not established or unavailable, returns an explicit "UNAVAILABLE" string,
  /// strictly preserving the no-hash-field-fallback invariant (AC-EVID-07, TM-U-11).
  String getDisplayHash(ArtifactType artifactType) {
    final hash = getArtifactHash(artifactType);
    if (hash == null || hash.trim().isEmpty) {
      return 'UNAVAILABLE';
    }
    return hash;
  }
}

/// The three distinct artifacts produced by the capture pipeline (AC-EVID-01).
enum ArtifactType {
  original,
  evidence,
  thumbnail,
}
