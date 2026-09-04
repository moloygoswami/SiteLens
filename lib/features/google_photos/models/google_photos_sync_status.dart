enum GooglePhotosSyncStatus {
  disabled,
  pending,
  uploading,
  uploaded,
  failed,
  authRequired;

  String get label {
    switch (this) {
      case GooglePhotosSyncStatus.disabled:
        return 'Disabled';
      case GooglePhotosSyncStatus.pending:
        return 'Pending';
      case GooglePhotosSyncStatus.uploading:
        return 'Uploading';
      case GooglePhotosSyncStatus.uploaded:
        return 'Uploaded';
      case GooglePhotosSyncStatus.failed:
        return 'Failed';
      case GooglePhotosSyncStatus.authRequired:
        return 'Auth Required';
    }
  }

  static GooglePhotosSyncStatus fromString(String? val) {
    if (val == null) return GooglePhotosSyncStatus.disabled;
    return GooglePhotosSyncStatus.values.firstWhere(
      (e) => e.name.toLowerCase() == val.toLowerCase().trim(),
      orElse: () => GooglePhotosSyncStatus.disabled,
    );
  }
}
