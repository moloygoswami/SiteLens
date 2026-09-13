import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/closed_evidence_integrity.dart';
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
      // Clear smart link suggestion and system Evid_ID if switching away from Closed
      final updatedNote = state.linkedMediaId != null
          ? removeEvidIdFromNote(
              currentNote: state.note,
              linkedId: state.linkedMediaId!,
            )
          : (state.suggestedBeforeMatch != null
              ? removeEvidIdFromNote(
                  currentNote: state.note,
                  linkedId: state.suggestedBeforeMatch!.id,
                )
              : state.note);
      state = state.copyWith(
        clearLinkedMediaId: true,
        clearSuggestedBeforeMatch: true,
        note: updatedNote,
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
        creatorId: snapshot.creatorId,
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

        // A search result is only a SUGGESTION. An explicitly linked candidate
        // remains authoritative and is never displaced or cleared by a refresh.
        state = state.copyWith(
          isSearchingSmartLink: false,
          suggestedBeforeMatch: match,
          suggestedDistanceMeters: dist,
        );
      } else {
        state = state.copyWith(
          isSearchingSmartLink: false,
          clearSuggestedBeforeMatch: true,
        );
      }
    } catch (_) {
      if (currentId != _searchRequestId) return;
      state = state.copyWith(
        isSearchingSmartLink: false,
        clearSuggestedBeforeMatch: true,
      );
    }
  }

  static String formatEvidId(String id) => ClosedEvidenceIntegrity.formatEvidId(id);

  static String updateNoteWithEvidId({
    required String currentNote,
    required String newId,
    String? previousId,
  }) =>
      ClosedEvidenceIntegrity.updateNoteWithEvidId(
        currentNote: currentNote,
        newId: newId,
        previousId: previousId,
      );

  static String removeEvidIdFromNote({
    required String currentNote,
    required String linkedId,
  }) =>
      ClosedEvidenceIntegrity.removeEvidIdFromNote(
        currentNote: currentNote,
        linkedId: linkedId,
      );

  static String removeAllEvidIdsFromNote(String currentNote) =>
      ClosedEvidenceIntegrity.removeAllEvidIdsFromNote(currentNote);

  static ({String? linkedMediaId, String? note}) enforceClosedEvidenceIntegrity({
    required ObservationType observationType,
    required String? linkedMediaId,
    required String? note,
  }) =>
      ClosedEvidenceIntegrity.enforceIntegrity(
        observationType: observationType,
        linkedMediaId: linkedMediaId,
        note: note,
      );

  void linkSuggestedMatch() {
    if (state.suggestedBeforeMatch != null) {
      final updatedNote = updateNoteWithEvidId(
        currentNote: state.note,
        newId: state.suggestedBeforeMatch!.id,
        previousId: state.linkedMediaId,
      );
      state = state.copyWith(
        linkedMediaId: state.suggestedBeforeMatch!.id,
        linkedCandidate: state.suggestedBeforeMatch,
        clearSuggestedBeforeMatch: true,
        note: updatedNote,
      );
    }
  }

  void unlinkSuggestedMatch() {
    final updatedNote = state.linkedMediaId != null
        ? removeEvidIdFromNote(
            currentNote: state.note,
            linkedId: state.linkedMediaId!,
          )
        : state.note;
    state = state.copyWith(
      clearLinkedMediaId: true,
      note: updatedNote,
    );
  }

  void linkBeforeItem(MediaItem item) {
    _searchRequestId++;
    final updatedNote = updateNoteWithEvidId(
      currentNote: state.note,
      newId: item.id,
      previousId: state.linkedMediaId,
    );
    state = state.copyWith(
      linkedMediaId: item.id,
      linkedCandidate: item,
      clearSuggestedBeforeMatch: true,
      note: updatedNote,
    );
  }

  void unlinkBeforeItem() {
    final updatedNote = state.linkedMediaId != null
        ? removeEvidIdFromNote(
            currentNote: state.note,
            linkedId: state.linkedMediaId!,
          )
        : (state.suggestedBeforeMatch != null
            ? removeEvidIdFromNote(
                currentNote: state.note,
                linkedId: state.suggestedBeforeMatch!.id,
              )
            : state.note);
    state = state.copyWith(
      clearLinkedMediaId: true,
      clearSuggestedBeforeMatch: true,
      note: updatedNote,
    );
  }

  /// Dismisses the current Smart-Link SUGGESTION only. An explicitly linked
  /// candidate and its system Evid_ID line are never affected by a dismissal.
  void dismissSuggestedMatch() {
    state = state.copyWith(clearSuggestedBeforeMatch: true);
  }

  /// Commits the pending capture with tags, notes, and smart-link to Drift SQLite inside a transaction.
  Future<MediaItem?> saveEvidence(PendingCapturePayload payload) async {
    if (state.isSaving) return null;

    // Strict Business Rule: Closed observations MUST link to an eligible BEFORE photo.
    // isLinked is strict: the link must be represented by the explicitly linked
    // candidate, so a suggestion can never change what gets persisted.
    if (state.observationType == ObservationType.closed) {
      if (!state.isLinked) {
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
    if (payload.processingFuture != null) {
      try {
        await payload.processingFuture;
      } catch (_) {
        // Processing failures or cancellations are expected and safely handled during retake
      }
    }
    try {
      // 1. Clean up derived evidence and thumbnail files
      await _storageService.cleanupPartialArtifacts(payload.mediaId);

      // 2. Clean up original uncommitted file
      await _storageService.deleteOriginalMedia(payload.originalFilePath);
    } catch (e) {
      debugPrint('[ReviewTagNotifier] Retake artifact cleanup failed for ${payload.mediaId}: $e');
    }
  }
}
