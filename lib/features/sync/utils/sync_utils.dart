import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../domain/models/media_item.dart';
import '../services/cloud_sync_service.dart';

/// Normative set of mutable media document fields defined in 02_ARCHITECTURE.MD §17.3.
/// Any update payload containing a field outside this set is strictly rejected before
/// network execution.
const Set<String> allowedMutableMediaFields = {
  'is_deleted',
  'tombstone_reconciled',
  'activity_tag',
  'observation_type',
  'note',
  'linked_media_id',
  'verification_status',
  'updated_at',
};

/// Classification of sync failure types according to 01_PRD.MD §10 and 02_ARCHITECTURE.MD §18.3.
enum SyncFailureCategory {
  /// Retryable failures (network disconnection, timeouts, transient server errors)
  /// retried automatically with exponential backoff and jitter.
  retryable,

  /// Permanent failures (schema/validation rejection, quota exceeded, permission denial,
  /// missing creator identity) marked failed immediately, with background retry halted.
  permanent,
}

/// Computes the exponential backoff delay with jitter according to the normative formula in
/// 02_ARCHITECTURE.MD §18.3:
/// delay = min(maxDelay, baseDelay * 2^attempt) ± jitter
Duration calculateBackoffDelay({
  required int attempt,
  Duration baseDelay = const Duration(seconds: 2),
  Duration maxDelay = const Duration(minutes: 5),
  Random? random,
  bool withJitter = true,
}) {
  if (attempt < 0) attempt = 0;
  // Cap effective attempt power to 20 to avoid integer overflow
  final effectiveAttempt = min(attempt, 20);
  final exponentialSeconds = baseDelay.inSeconds * pow(2, effectiveAttempt).toDouble();
  final boundedSeconds = min(maxDelay.inSeconds.toDouble(), exponentialSeconds);

  if (!withJitter) {
    return Duration(seconds: boundedSeconds.round());
  }

  final rng = random ?? Random();
  // Bounded jitter in [-1.0, 1.0] seconds
  final jitterSeconds = rng.nextDouble() * 2.0 - 1.0;
  final totalSeconds = max(1.0, boundedSeconds + jitterSeconds);
  return Duration(milliseconds: (totalSeconds * 1000).round());
}

/// Classifies a synchronization error into retryable or permanent category.
SyncFailureCategory classifySyncFailure(Object error) {
  if (error is PermanentSyncException) {
    return SyncFailureCategory.permanent;
  }
  if (error is IntegrityConflictException) {
    return SyncFailureCategory.permanent;
  }
  if (error is SocketException) {
    return SyncFailureCategory.retryable;
  }
  if (error is TimeoutException) {
    return SyncFailureCategory.retryable;
  }
  if (error is FirebaseException) {
    switch (error.code) {
      case 'quota-exceeded':
      case 'permission-denied':
      case 'unauthenticated':
      case 'invalid-argument':
        return SyncFailureCategory.permanent;
      case 'unavailable':
      case 'deadline-exceeded':
      case 'resource-exhausted':
      case 'internal':
      case 'cancelled':
        return SyncFailureCategory.retryable;
      default:
        return SyncFailureCategory.retryable;
    }
  }
  if (error is RetryableSyncException) {
    return SyncFailureCategory.retryable;
  }
  // Default unclassified errors remain retryable per R25
  return SyncFailureCategory.retryable;
}

/// Computes differences on the permitted mutable fields between remote Firestore data
/// and the local [MediaItem].
Map<String, dynamic> computeMutableFieldDiff(
  Map<String, dynamic> remoteData,
  MediaItem localItem,
) {
  final updates = <String, dynamic>{};

  if (remoteData['note'] != localItem.note) {
    updates['note'] = localItem.note;
  }
  if (remoteData['activity_tag'] != localItem.activityTag) {
    updates['activity_tag'] = localItem.activityTag;
  }
  if (remoteData['observation_type'] != localItem.observationType.name) {
    updates['observation_type'] = localItem.observationType.name;
  }
  if (remoteData['linked_media_id'] != localItem.linkedMediaId) {
    updates['linked_media_id'] = localItem.linkedMediaId;
  }
  if (remoteData['is_deleted'] != localItem.isDeleted) {
    updates['is_deleted'] = localItem.isDeleted;
  }
  if (localItem.verificationStatus != null &&
      remoteData['verification_status'] != localItem.verificationStatus?.name) {
    updates['verification_status'] = localItem.verificationStatus?.name;
  }

  return updates;
}

/// Validates that [proposedUpdates] touches ONLY fields in [allowedMutableMediaFields].
/// Throws [PermanentSyncException] if any immutable field is present.
Map<String, dynamic> validateMutableFieldUpdate(Map<String, dynamic> proposedUpdates) {
  for (final key in proposedUpdates.keys) {
    if (!allowedMutableMediaFields.contains(key)) {
      throw PermanentSyncException(
        'Field "$key" is immutable and cannot be updated. Only mutable fields ($allowedMutableMediaFields) are permitted.',
      );
    }
  }
  return proposedUpdates;
}
