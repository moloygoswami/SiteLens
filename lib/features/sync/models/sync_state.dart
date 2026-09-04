class SyncState {
  final bool isSyncing;
  final int pendingCount;
  final int failedCount;
  final String? lastError;
  final DateTime? lastSyncTime;
  final bool isOnline;
  final String? activeMediaId;

  const SyncState({
    this.isSyncing = false,
    this.pendingCount = 0,
    this.failedCount = 0,
    this.lastError,
    this.lastSyncTime,
    this.isOnline = true,
    this.activeMediaId,
  });

  bool get hasErrors => failedCount > 0 || lastError != null;
  bool get isFullySynced => pendingCount == 0 && failedCount == 0 && !isSyncing;

  SyncState copyWith({
    bool? isSyncing,
    int? pendingCount,
    int? failedCount,
    String? lastError,
    DateTime? lastSyncTime,
    bool? isOnline,
    String? activeMediaId,
    bool clearLastError = false,
    bool clearActiveMediaId = false,
  }) {
    return SyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      pendingCount: pendingCount ?? this.pendingCount,
      failedCount: failedCount ?? this.failedCount,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      isOnline: isOnline ?? this.isOnline,
      activeMediaId: clearActiveMediaId ? null : (activeMediaId ?? this.activeMediaId),
    );
  }
}
