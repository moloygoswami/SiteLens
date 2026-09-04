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
  final double? altitude; // Captured elevation in meters ASL — Added in v7 (remediates vuln-0002)
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
}
