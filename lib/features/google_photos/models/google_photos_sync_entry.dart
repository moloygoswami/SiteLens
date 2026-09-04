import 'google_photos_sync_status.dart';

class GooglePhotosSyncEntry {
  final String mediaId;
  final GooglePhotosSyncStatus status;
  final String? googlePhotosMediaId;
  final DateTime? uploadedAt;
  final String? errorMessage;
  final int retryCount;
  final DateTime? lastAttemptAt;

  const GooglePhotosSyncEntry({
    required this.mediaId,
    required this.status,
    this.googlePhotosMediaId,
    this.uploadedAt,
    this.errorMessage,
    this.retryCount = 0,
    this.lastAttemptAt,
  });

  GooglePhotosSyncEntry copyWith({
    String? mediaId,
    GooglePhotosSyncStatus? status,
    String? googlePhotosMediaId,
    DateTime? uploadedAt,
    String? errorMessage,
    int? retryCount,
    DateTime? lastAttemptAt,
    bool clearError = false,
  }) {
    return GooglePhotosSyncEntry(
      mediaId: mediaId ?? this.mediaId,
      status: status ?? this.status,
      googlePhotosMediaId: googlePhotosMediaId ?? this.googlePhotosMediaId,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      retryCount: retryCount ?? this.retryCount,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
    );
  }
}
