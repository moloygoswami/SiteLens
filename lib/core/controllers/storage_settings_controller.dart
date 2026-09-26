import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/storage_cleanup_models.dart';
import '../services/storage_cleanup_service.dart';

class StorageSettingsState {
  final bool isLoading;
  final bool isCleaning;
  final bool isRegenerating;
  final StorageCleanupSummary summary;
  final StorageCleanupResult? lastResult;
  final String? message;

  const StorageSettingsState({
    this.isLoading = false,
    this.isCleaning = false,
    this.isRegenerating = false,
    this.summary = const StorageCleanupSummary(),
    this.lastResult,
    this.message,
  });

  StorageSettingsState copyWith({
    bool? isLoading,
    bool? isCleaning,
    bool? isRegenerating,
    StorageCleanupSummary? summary,
    StorageCleanupResult? lastResult,
    bool clearLastResult = false,
    String? message,
    bool clearMessage = false,
  }) {
    return StorageSettingsState(
      isLoading: isLoading ?? this.isLoading,
      isCleaning: isCleaning ?? this.isCleaning,
      isRegenerating: isRegenerating ?? this.isRegenerating,
      summary: summary ?? this.summary,
      lastResult: clearLastResult ? null : (lastResult ?? this.lastResult),
      message: clearMessage ? null : (message ?? this.message),
    );
  }
}

final storageSettingsProvider =
    StateNotifierProvider<StorageSettingsNotifier, StorageSettingsState>((ref) {
  final cleanupService = ref.watch(storageCleanupServiceProvider);
  return StorageSettingsNotifier(cleanupService);
});

class StorageSettingsNotifier extends StateNotifier<StorageSettingsState> {
  final StorageCleanupService _cleanupService;

  StorageSettingsNotifier(this._cleanupService) : super(const StorageSettingsState()) {
    loadSummary();
  }

  Future<void> loadSummary() async {
    state = state.copyWith(isLoading: true, clearMessage: true);
    try {
      final summary = await _cleanupService.getCleanupSummary();
      if (mounted) {
        state = state.copyWith(
          isLoading: false,
          summary: summary,
        );
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
          isLoading: false,
          message: 'Error loading storage summary: $e',
        );
      }
    }
  }

  Future<StorageCleanupResult?> clearSyncedPhotoOriginals({
    Set<String>? activeSyncingIds,
  }) async {
    // Concurrency Mutex: Prevent concurrent cleanups
    if (state.isCleaning) return null;

    state = state.copyWith(isCleaning: true, clearMessage: true);

    try {
      final result = await _cleanupService.clearSyncedPhotoOriginals(
        activeSyncingIds: activeSyncingIds,
      );

      // Refresh storage summary after deletion
      final updatedSummary = await _cleanupService.getCleanupSummary(
        activeSyncingIds: activeSyncingIds,
      );

      if (mounted) {
        state = state.copyWith(
          isCleaning: false,
          summary: updatedSummary,
          lastResult: result,
          message: 'Reclaimed ${result.formattedReclaimedSize} across ${result.successfullyDeletedCount} photo originals.',
        );
      }
      return result;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
          isCleaning: false,
          message: 'Failed to clear originals: $e',
        );
      }
      return null;
    }
  }

  Future<int> regenerateThumbnails({String? creatorId}) async {
    if (state.isRegenerating) return 0;
    state = state.copyWith(isRegenerating: true, clearMessage: true);

    try {
      final count = await _cleanupService.regenerateThumbnails(creatorId: creatorId);
      final updatedSummary = await _cleanupService.getCleanupSummary(creatorId: creatorId);

      if (mounted) {
        state = state.copyWith(
          isRegenerating: false,
          summary: updatedSummary,
          message: 'Regenerated $count thumbnails successfully.',
        );
      }
      return count;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
          isRegenerating: false,
          message: 'Failed to regenerate thumbnails: $e',
        );
      }
      return 0;
    }
  }
}
