import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/haversine.dart';
import '../../../data/local/database/app_database.dart';
import '../../../data/local/database/database_provider.dart';
import '../../../data/repositories/media_repository.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/media_item.dart';
import '../../camera/services/evidence_storage_service.dart';
import '../../camera/services/media_persistence_coordinator.dart';
import '../models/pending_capture_payload.dart';
import '../models/review_tag_state.dart';

final reviewTagControllerProvider =
    StateNotifierProvider.autoDispose<ReviewTagNotifier, ReviewTagState>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final mediaRepo = ref.watch(mediaRepositoryProvider);
  final storageService = ref.watch(evidenceStorageServiceProvider);
  final persistenceCoordinator = ref.watch(mediaPersistenceCoordinatorProvider);
  return ReviewTagNotifier(
    db,
    mediaRepo,
    storageService,
    persistenceCoordinator: persistenceCoordinator,
  );
});

class ReviewTagNotifier extends StateNotifier<ReviewTagState> {
  final MediaRepository _mediaRepo;
  final EvidenceStorageService _storageService;
  final MediaPersistenceCoordinator _persistenceCoordinator;
  int _searchRequestId = 0;

  ReviewTagNotifier(
    AppDatabase? db,
    this._mediaRepo,
    this._storageService, {
    MediaPersistenceCoordinator? persistenceCoordinator,
  })  : _persistenceCoordinator = persistenceCoordinator ??
            MediaPersistenceCoordinator(db!, _mediaRepo, _storageService),
        super(const ReviewTagState());

  void setNote(String note) {
    state = state.copyWith(note: note);
  }

  Future<void> setActivityTag(String activity, PendingCapturePayload payload) async {
    state = state.copyWith(
      activityTag: activity,
      clearErrorMessage: true,
    );
    if (state.observationType == ObservationType.closed) {
      await searchSmartLink(payload);
    }
  }

  Future<void> setObservationType(
    ObservationType observationType,
    PendingCapturePayload payload,
  ) async {
    state = state.copyWith(
      observationType: observationType,
      clearErrorMessage: true,
    );
    if (observationType == ObservationType.closed) {
      await searchSmartLink(payload);
    } else {
      // Clear smart link suggestion if not Closed/After
      state = state.copyWith(
        clearLinkedMediaId: true,
        clearSuggestedBeforeMatch: true,
      );
    }
  }

  Future<void> searchSmartLink(PendingCapturePayload payload) async {
    final currentId = ++_searchRequestId;
    state = state.copyWith(isSearchingSmartLink: true);
    try {
      final snapshot = payload.metadataSnapshot;
      final match = await _mediaRepo.findSuggestedBeforeMatch(
        centerLat: snapshot.latitude,
        centerLon: snapshot.longitude,
        siteId: snapshot.siteId,
        activityTag: state.activityTag,
        radiusMeters: 10.0,
        currentMediaId: payload.mediaId,
      );

      // Discard result if a newer search request was initiated
      if (currentId != _searchRequestId) return;

      if (match != null) {
        final dist = SpatialMathUtils.haversineDistanceMeters(
          snapshot.latitude,
          snapshot.longitude,
          match.lat,
          match.lon,
        );
        state = state.copyWith(
          isSearchingSmartLink: false,
          suggestedBeforeMatch: match,
          suggestedDistanceMeters: dist,
        );
      } else {
        state = state.copyWith(
          isSearchingSmartLink: false,
          clearSuggestedBeforeMatch: true,
          clearLinkedMediaId: true,
        );
      }
    } catch (_) {
      if (currentId != _searchRequestId) return;
      state = state.copyWith(
        isSearchingSmartLink: false,
        clearSuggestedBeforeMatch: true,
        clearLinkedMediaId: true,
      );
    }
  }

  void linkSuggestedMatch() {
    if (state.suggestedBeforeMatch != null) {
      state = state.copyWith(linkedMediaId: state.suggestedBeforeMatch!.id);
    }
  }

  void unlinkSuggestedMatch() {
    state = state.copyWith(
      clearLinkedMediaId: true,
    );
  }

  void linkBeforeItem(MediaItem item) {
    state = state.copyWith(
      linkedMediaId: item.id,
      suggestedBeforeMatch: item,
    );
  }

  void unlinkBeforeItem() {
    state = state.copyWith(
      clearLinkedMediaId: true,
      clearSuggestedBeforeMatch: true,
    );
  }

  void dismissSuggestedMatch() {
    state = state.copyWith(
      clearLinkedMediaId: true,
      clearSuggestedBeforeMatch: true,
    );
  }

  /// Commits the pending capture with tags, notes, and smart-link to Drift SQLite inside a transaction.
  Future<MediaItem?> saveEvidence(PendingCapturePayload payload) async {
    if (state.isSaving) return null;

    // Strict Business Rule: Closed observations MUST link to an eligible BEFORE photo
    if (state.observationType == ObservationType.closed) {
      if (state.linkedMediaId == null || state.linkedMediaId!.isEmpty) {
        state = state.copyWith(
          isSaving: false,
          errorMessage: 'A Closed observation requires linking to an eligible open Non-Conformity within 10m.',
        );
        return null;
      }
    }

    state = state.copyWith(isSaving: true, clearErrorMessage: true);
    try {
      PendingCapturePayload effectivePayload = payload;

      // If background processing is still in-flight, await canonical evidence generation
      if (payload.processingFuture != null) {
        final processed = await payload.processingFuture!;
        if (!processed.isSuccess ||
            processed.evidenceFilePath == null ||
            processed.thumbnailFilePath == null) {
          throw Exception(processed.errorMessage ?? 'Canonical evidence processing failed');
        }
        effectivePayload = payload.copyWith(
          evidenceFilePath: processed.evidenceFilePath,
          thumbnailFilePath: processed.thumbnailFilePath,
          photoPayload: processed,
        );
      }

      final mediaItem = await _persistenceCoordinator.persistPendingCapture(
        effectivePayload,
        activityTag: state.activityTag,
        observationType: state.observationType,
        linkedMediaId: state.linkedMediaId,
        note: state.note,
      );

      state = state.copyWith(isSaving: false);
      return mediaItem;
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Failed to save evidence: $e',
      );
      return null;
    }
  }

  /// Retake action: Safely cancels in-flight processing and cleans up pending uncommitted artifacts.
  Future<void> retake(PendingCapturePayload payload) async {
    payload.cancelProcessing();
    try {
      // 1. Clean up derived evidence and thumbnail files
      await _storageService.cleanupPartialArtifacts(payload.mediaId);

      // 2. Clean up original uncommitted file
      final origAbs = await _storageService.resolveAbsolutePath(payload.originalFilePath);
      final origFile = File(origAbs);
      if (await origFile.exists()) {
        await origFile.delete();
      }
    } catch (e) {
      debugPrint('[ReviewTagNotifier] Retake artifact cleanup failed for ${payload.mediaId}: $e');
    }
  }
}
