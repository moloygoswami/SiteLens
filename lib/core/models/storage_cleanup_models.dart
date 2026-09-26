class StorageCleanupSummary {
  final int eligiblePhotosCount;
  final int reclaimableBytes;
  final int totalPhotosCount;
  final int totalVideosCount;
  final int syncedPhotosCount;
  final int cacheSizeBytes;

  const StorageCleanupSummary({
    this.eligiblePhotosCount = 0,
    this.reclaimableBytes = 0,
    this.totalPhotosCount = 0,
    this.totalVideosCount = 0,
    this.syncedPhotosCount = 0,
    this.cacheSizeBytes = 0,
  });

  String get formattedReclaimableSize {
    if (reclaimableBytes < 1024) {
      return '$reclaimableBytes B';
    } else if (reclaimableBytes < 1024 * 1024) {
      return '${(reclaimableBytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(reclaimableBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  String get formattedCacheSize {
    if (cacheSizeBytes < 1024) {
      return '$cacheSizeBytes B';
    } else if (cacheSizeBytes < 1024 * 1024) {
      return '${(cacheSizeBytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(cacheSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  StorageCleanupSummary copyWith({
    int? eligiblePhotosCount,
    int? reclaimableBytes,
    int? totalPhotosCount,
    int? totalVideosCount,
    int? syncedPhotosCount,
    int? cacheSizeBytes,
  }) {
    return StorageCleanupSummary(
      eligiblePhotosCount: eligiblePhotosCount ?? this.eligiblePhotosCount,
      reclaimableBytes: reclaimableBytes ?? this.reclaimableBytes,
      totalPhotosCount: totalPhotosCount ?? this.totalPhotosCount,
      totalVideosCount: totalVideosCount ?? this.totalVideosCount,
      syncedPhotosCount: syncedPhotosCount ?? this.syncedPhotosCount,
      cacheSizeBytes: cacheSizeBytes ?? this.cacheSizeBytes,
    );
  }
}

class StorageCleanupResult {
  final int eligibleCount;
  final int successfullyDeletedCount;
  final int skippedCount;
  final int failedCount;
  final int bytesReclaimed;

  const StorageCleanupResult({
    required this.eligibleCount,
    required this.successfullyDeletedCount,
    required this.skippedCount,
    required this.failedCount,
    required this.bytesReclaimed,
  });

  String get formattedReclaimedSize {
    if (bytesReclaimed < 1024) {
      return '$bytesReclaimed B';
    } else if (bytesReclaimed < 1024 * 1024) {
      return '${(bytesReclaimed / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytesReclaimed / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  @override
  String toString() =>
      'StorageCleanupResult(eligible: $eligibleCount, deleted: $successfullyDeletedCount, '
      'skipped: $skippedCount, failed: $failedCount, reclaimed: $bytesReclaimed bytes)';
}
