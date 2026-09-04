import 'google_photos_sync_status.dart';

class GooglePhotosSettings {
  final bool isConnected;
  final String? accountEmail;
  final bool autoUpload;
  final String albumName;
  final GooglePhotosSyncStatus overallStatus;
  final int pendingCount;
  final int uploadedCount;
  final int failedCount;
  final DateTime? lastSyncTime;
  final String? lastError;

  const GooglePhotosSettings({
    this.isConnected = false,
    this.accountEmail,
    this.autoUpload = false,
    this.albumName = 'SiteLens Evidence',
    this.overallStatus = GooglePhotosSyncStatus.disabled,
    this.pendingCount = 0,
    this.uploadedCount = 0,
    this.failedCount = 0,
    this.lastSyncTime,
    this.lastError,
  });

  GooglePhotosSettings copyWith({
    bool? isConnected,
    String? accountEmail,
    bool clearAccountEmail = false,
    bool? autoUpload,
    String? albumName,
    GooglePhotosSyncStatus? overallStatus,
    int? pendingCount,
    int? uploadedCount,
    int? failedCount,
    DateTime? lastSyncTime,
    String? lastError,
    bool clearLastError = false,
  }) {
    return GooglePhotosSettings(
      isConnected: isConnected ?? this.isConnected,
      accountEmail: clearAccountEmail ? null : (accountEmail ?? this.accountEmail),
      autoUpload: autoUpload ?? this.autoUpload,
      albumName: albumName ?? this.albumName,
      overallStatus: overallStatus ?? this.overallStatus,
      pendingCount: pendingCount ?? this.pendingCount,
      uploadedCount: uploadedCount ?? this.uploadedCount,
      failedCount: failedCount ?? this.failedCount,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }
}
