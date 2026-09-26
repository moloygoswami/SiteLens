import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/session_service.dart';
import '../../../data/repositories/media_repository.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/media_item.dart';
import '../../camera/services/evidence_storage_service.dart';
import '../models/sync_state.dart';
import 'cloud_sync_service.dart';

final syncCoordinatorProvider =
    StateNotifierProvider<SyncCoordinator, SyncState>((ref) {
  final mediaRepo = ref.watch(mediaRepositoryProvider);
  final cloudSyncService = ref.watch(cloudSyncServiceProvider);
  final storageService = ref.watch(evidenceStorageServiceProvider);
  final authService = ref.watch(authServiceProvider);
  final sessionService = ref.watch(sessionServiceProvider.notifier);

  final coordinator = SyncCoordinator(
    mediaRepo: mediaRepo,
    cloudSyncService: cloudSyncService,
    storageService: storageService,
    authService: authService,
    sessionService: sessionService,
  );

  ref.onDispose(() => coordinator.dispose());
  return coordinator;
});

class SyncCoordinator extends StateNotifier<SyncState> with WidgetsBindingObserver {
  final MediaRepository _mediaRepo;
  final CloudSyncService _cloudSyncService;
  final EvidenceStorageService _storageService;
  final AuthService _authService;
  final SessionService? _sessionService;

  StreamSubscription? _connectivitySub;
  StreamSubscription? _authSub;
  StreamSubscription? _unsyncedCountSub;
  StreamSubscription? _tombstoneCountSub;

  final Set<String> _inFlightMediaIds = {};
  final Map<String, int> _retryCounts = {};
  final Map<String, DateTime> _nextRetryTimes = {};
  final Set<String> _permanentFailedIds = {};
  bool _isProcessing = false;
  int _syncSessionGeneration = 0;
  bool _pendingManualRetry = false;
  bool _pendingAutoSync = false;
  String? _pendingSyncUserId;
  int _lastUnsyncedCount = 0;
  int _lastTombstoneCount = 0;

  static const int maxRetryAttempts = 5;

  SyncCoordinator({
    required MediaRepository mediaRepo,
    required CloudSyncService cloudSyncService,
    required EvidenceStorageService storageService,
    required AuthService authService,
    SessionService? sessionService,
    Connectivity? connectivity,
  })  : _mediaRepo = mediaRepo,
        _cloudSyncService = cloudSyncService,
        _storageService = storageService,
        _authService = authService,
        _sessionService = sessionService,
        super(const SyncState()) {
    _init(connectivity ?? Connectivity());
  }

  Future<void> _init(Connectivity connectivity) async {
    // 1. Crash Recovery Hook: Reset any stuck in-flight syncing items (synced=2 -> synced=0).
    // Gated on an authenticated session: unauthenticated startup must not initialize
    // evidence synchronization or mutate local state.
    if (_authService.currentUser != null) {
      await _mediaRepo.resetStuckSyncingMedia(creatorId: _authService.currentUser?.uid);
    }


    // 2. Observe app lifecycle so foreground resume offers the existing sync
    // pipeline a chance to process pending/retryable evidence.
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {
      // WidgetsBinding not initialized (e.g. in pure unit tests)
    }

    // 3. Initial connectivity check
    final initialStatus = await connectivity.checkConnectivity();
    final isOnline = !initialStatus.contains(ConnectivityResult.none);
    if (mounted) {
      state = state.copyWith(isOnline: isOnline);
    }

    // 4. Listen to network transitions
    _connectivitySub = connectivity.onConnectivityChanged.listen((results) {
      final online = !results.contains(ConnectivityResult.none);
      final wasOffline = !state.isOnline;
      if (mounted) {
        state = state.copyWith(isOnline: online);
      }

      if (online && wasOffline) {
        // Trigger auto-sync for retryable pending items
        triggerSync(isManual: false);
      }
    });

    // 5. Listen to Auth state changes
    _authSub = _authService.authStateChanges.listen((user) async {
      _syncSessionGeneration++;
      // R04: rebind the SQLite count streams to the active creator so a previous
      // user's subscription can never drive (or leak into) this session.
      _subscribeCountStreams(user?.uid);
      if (user == null) {
        // User signed out -> Cancel/Pause in-flight worker and zero UI counts
        _inFlightMediaIds.clear();
        if (mounted) {
          state = state.copyWith(
            isSyncing: false,
            pendingCount: 0,
            failedCount: 0,
            clearActiveMediaId: true,
          );
        }
      } else {
        // User signed in -> Session-scoped crash recovery, then user-specific
        // counts and sync. Idempotent: stuck syncing rows are normalized to pending.
        await _mediaRepo.resetStuckSyncingMedia(creatorId: user.uid);
        await _refreshCounts();
        triggerSync(isManual: false);
      }
    });

    // 6. Bind the creator-scoped SQLite count streams for the initial session.
    // The repository fails closed on a null/empty UID.
    _subscribeCountStreams(_authService.currentUser?.uid);

    await _refreshCounts();
    triggerSync(isManual: false);
  }

  /// (Re)binds the SQLite count streams to [userId]. Previous subscriptions are
  /// always torn down first, so an auth transition (A signs out, B signs in)
  /// leaves A's streams disposed and only B's active (R04). A null/empty UID is
  /// fail-closed by the repository (0), so an unauthenticated session can never
  /// observe another user's counts.
  void _subscribeCountStreams(String? userId) {
    _unsyncedCountSub?.cancel();
    _tombstoneCountSub?.cancel();

    _lastUnsyncedCount = 0;
    _lastTombstoneCount = 0;

    // F1: A freshly persisted pending capture (online session) automatically
    // enters the existing sync pipeline; offline captures stay queued and sync
    // after reconnect via the connectivity listener. The local transaction has
    // already committed before this Drift-backed stream emits.
    _unsyncedCountSub = _mediaRepo.watchUnsyncedCount(creatorId: userId).listen((count) async {
      final increased = count > _lastUnsyncedCount;
      _lastUnsyncedCount = count;

      if (increased && state.isOnline) {
        unawaited(triggerSync(isManual: false));
      }
      await _refreshCounts();
    });

    // B-1: A newly soft-deleted previously-synced item must propagate its
    // is_deleted tombstone to the cloud ledger. Mirror of the unsynced-count
    // edge trigger: a new tombstone candidate enters the existing sync cycle.
    _tombstoneCountSub = _mediaRepo.watchTombstoneCandidateCount(creatorId: userId).listen((count) {
      final increased = count > _lastTombstoneCount;
      _lastTombstoneCount = count;

      if (increased && state.isOnline) {
        unawaited(triggerSync(isManual: false));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // F1: On foreground resume, give the existing sync pipeline an opportunity to
    // process pending/retryable evidence for an authenticated session. Offline
    // resumes are naturally skipped by triggerSync's connectivity guard.
    if (state == AppLifecycleState.resumed && mounted) {
      if (_authService.currentUser != null) {
        unawaited(triggerSync(isManual: false));
      }
    }
  }

  Future<void> _refreshCounts() async {
    final currentUserId = _authService.currentUser?.uid;
    final allItems = await _mediaRepo.getPendingOrFailedMedia(creatorId: currentUserId);

    int pending = 0;
    int failed = 0;
    for (final item in allItems) {
      if (item.syncStatus == SyncStatusType.failed) {
        failed++;
      } else if (item.syncStatus == SyncStatusType.pending || item.syncStatus == SyncStatusType.syncing) {
        pending++;
      }
    }

    if (mounted) {
      state = state.copyWith(
        pendingCount: pending,
        failedCount: failed,
      );
    }
  }

  /// Triggers a synchronization cycle with mutex lock protection.
  /// If [isManual] is true, resets permanent failure flags and retry timers for the active user's items.
  Future<void> triggerSync({bool isManual = false}) async {
    // Deferred follow-up cycles can land after dispose; a disposed notifier
    // must not touch its state at all.
    if (!mounted) return;
    final currentUser = _authService.currentUser;
    if (currentUser == null) return;
    if (!state.isOnline && !isManual) return;

    if (_isProcessing) {
      if (isManual) {
        _pendingManualRetry = true;
      } else if (_pendingSyncUserId != currentUser.uid) {
        _pendingSyncUserId = currentUser.uid;
      } else {
        _pendingAutoSync = true;
      }
      return;
    }

    _isProcessing = true;
    final sessionGen = _syncSessionGeneration;
    final sessionUid = currentUser.uid;

    if (mounted) {
      state = state.copyWith(isSyncing: true, clearLastError: isManual);
    }

    try {
      if (isManual) {
        _permanentFailedIds.clear();
        _retryCounts.clear();
        _nextRetryTimes.clear();
      }

      final items = await _mediaRepo.getPendingOrFailedMedia(creatorId: currentUser.uid);

      // B-1: tombstone candidates (soft-deleted rows with a possibly-pending
      // cloud deletion ledger entry) ride the same cycle, mutex, creator
      // filter, backoff and session-generation machinery as artifact sync.
      final tombstones = await _mediaRepo.getTombstoneSyncCandidates(creatorId: currentUser.uid);

      for (final item in [...items, ...tombstones]) {
        // P1-1: Check if auth session changed or user logged out mid-batch
        if (_syncSessionGeneration != sessionGen || _authService.currentUser?.uid != sessionUid) {
          break;
        }

        // Check if item is already in-flight
        if (_inFlightMediaIds.contains(item.id)) continue;

        // Check creator authorization: Only creator can sync new captures
        if (item.creatorId != null && item.creatorId != currentUser.uid) {
          continue; // Leave dormant for original creator
        }

        // Skip permanent failures unless manually triggered
        if (!isManual && _permanentFailedIds.contains(item.id)) {
          continue;
        }

        // R25: automatic cycles must also honour the DURABLE permanent-failure
        // marker persisted in the sync-status field, so the suppression survives
        // a process restart (the in-memory set above does not). Manual retry
        // explicitly re-evaluates failed items. Tombstone rows keep their
        // pre-deletion status and are never treated as artifact failures here
        // (B-1 forbids persisting an artifact-sync status for tombstones).
        if (!isManual && !item.isDeleted && item.syncStatus == SyncStatusType.failed) {
          continue;
        }

        // Check exponential backoff delay for retryable items
        if (!isManual && _nextRetryTimes.containsKey(item.id)) {
          if (DateTime.now().isBefore(_nextRetryTimes[item.id]!)) {
            continue; // Backoff not yet expired
          }
        }

        await _processSingleItem(item, currentUser.uid, isTombstone: item.isDeleted);
      }
    } finally {
      _isProcessing = false;
      await _refreshCounts();
      if (mounted) {
        state = state.copyWith(
          isSyncing: false,
          clearActiveMediaId: true,
          lastSyncTime: DateTime.now(),
        );
      }

      // P1-2: Handle deferred manual retry, auth-switch, or auto-sync follow-up
      if (_pendingManualRetry) {
        _pendingManualRetry = false;
        unawaited(triggerSync(isManual: true));
      } else if (_pendingSyncUserId != null ||
          (_authService.currentUser != null && _authService.currentUser?.uid != sessionUid)) {
        _pendingSyncUserId = null;
        _pendingAutoSync = false;
        unawaited(triggerSync(isManual: false));
      } else if (_pendingAutoSync) {
        _pendingAutoSync = false;
        unawaited(triggerSync(isManual: false));
      }
    }
  }

  /// Persists an artifact-sync status unless the item is a tombstone candidate:
  /// deleted rows keep their row state as the propagation marker and their
  /// artifact-sync status column is never written by tombstone synchronization
  /// (B-1: a tombstone must never be marked artifact-synced, attempted or not).
  Future<void> _updateArtifactSyncStatus(String mediaId, SyncStatusType status, {required bool isTombstone, String? currentUserId}) async {
    if (isTombstone) return;
    await _mediaRepo.updateSyncStatus(mediaId, status, creatorId: currentUserId);
  }

  Future<void> _processSingleItem(MediaItem item, String currentUserId, {bool isTombstone = false}) async {
    _inFlightMediaIds.add(item.id);
    if (mounted) {
      state = state.copyWith(activeMediaId: item.id);
    }

    try {
      if (!isTombstone) {
        await _mediaRepo.updateSyncStatus(item.id, SyncStatusType.syncing, creatorId: currentUserId);
      }

      if (isTombstone) {
        // Cloud-ledger-only operation: never reads or writes Storage artifacts.
        await _cloudSyncService.syncTombstone(item: item, currentUserId: currentUserId);
      } else {
        final mediaDir = await _storageService.getMediaDirectory();
        final rootPath = mediaDir.parent.path;

        final absOrigPath = '$rootPath/${item.originalUri}';
        final absEvidPath = '$rootPath/${item.uri}';
        final absThumbPath = item.thumbUri != null ? '$rootPath/${item.thumbUri}' : null;

        await _cloudSyncService.syncMediaItem(
          item: item,
          absoluteOriginalPath: absOrigPath,
          absoluteEvidencePath: absEvidPath,
          absoluteThumbnailPath: absThumbPath,
          currentUserId: currentUserId,
        );
      }

      // Successfully synced
      if (!isTombstone) {
        await _mediaRepo.updateSyncStatus(item.id, SyncStatusType.synced, creatorId: currentUserId);
      } else {
        await _mediaRepo.markTombstoneReconciled(item.id, creatorId: currentUserId);
      }
      _retryCounts.remove(item.id);
      _nextRetryTimes.remove(item.id);
      _permanentFailedIds.remove(item.id);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied' || e.code == 'unauthenticated') {
        if (_sessionService != null) {
          final resolution = await _sessionService.handleOperationAnomaly(
            operationErrorCode: e.code,
            siteId: item.siteId,
            details: e.message,
          );
          switch (resolution) {
            case SessionAnomalyResolution.sessionInvalidated:
              _permanentFailedIds.add(item.id);
              await _updateArtifactSyncStatus(item.id, SyncStatusType.failed, isTombstone: isTombstone, currentUserId: currentUserId);
              state = state.copyWith(lastError: 'Session terminated: ${e.message ?? e.code}');
              return;
            case SessionAnomalyResolution.sitePermissionDenied:
              _permanentFailedIds.add(item.id);
              await _updateArtifactSyncStatus(item.id, SyncStatusType.failed, isTombstone: isTombstone, currentUserId: currentUserId);
              state = state.copyWith(
                lastError: 'Permission denied: User does not own site ${item.siteId}.',
              );
              return;
            case SessionAnomalyResolution.retryable:
              break;
          }
        }
        await _handleRetryableFailure(item, e.message ?? e.code, isTombstone: isTombstone, currentUserId: currentUserId);
      } else if (e.code == 'quota-exceeded') {
        _permanentFailedIds.add(item.id);
        await _updateArtifactSyncStatus(item.id, SyncStatusType.failed, isTombstone: isTombstone, currentUserId: currentUserId);
        state = state.copyWith(lastError: 'Storage quota exceeded.');
      } else {
        await _handleRetryableFailure(item, e.message ?? e.code, isTombstone: isTombstone, currentUserId: currentUserId);
      }
    } on PermanentSyncException catch (e) {
      _permanentFailedIds.add(item.id);
      await _updateArtifactSyncStatus(item.id, SyncStatusType.failed, isTombstone: isTombstone, currentUserId: currentUserId);
      state = state.copyWith(lastError: e.message);
    } on IntegrityConflictException catch (e) {
      _permanentFailedIds.add(item.id);
      await _updateArtifactSyncStatus(item.id, SyncStatusType.failed, isTombstone: isTombstone, currentUserId: currentUserId);
      state = state.copyWith(lastError: e.message);
    } on RetryableSyncException catch (e) {
      await _handleRetryableFailure(item, e.message, isTombstone: isTombstone, currentUserId: currentUserId);
    } catch (e) {
      // R25: an unclassified/unexpected exception carries no evidence of
      // permanence, so it must remain retryable — routed through the same
      // bounded exponential backoff / max-attempt policy as any transient
      // failure. It must never be silently promoted to a permanent failure.
      await _handleRetryableFailure(item, e.toString(), isTombstone: isTombstone, currentUserId: currentUserId);
    } finally {
      _inFlightMediaIds.remove(item.id);
    }
  }

  Future<void> _handleRetryableFailure(MediaItem item, String message, {bool isTombstone = false, String? currentUserId}) async {
    final currentRetries = (_retryCounts[item.id] ?? 0) + 1;
    _retryCounts[item.id] = currentRetries;

    if (currentRetries >= maxRetryAttempts) {
      _permanentFailedIds.add(item.id);
      await _updateArtifactSyncStatus(item.id, SyncStatusType.failed, isTombstone: isTombstone, currentUserId: currentUserId);
      state = state.copyWith(lastError: 'Max retries exceeded: $message');
    } else {
      // Compute exponential backoff with jitter per 02_ARCHITECTURE.MD §18.3
      final delay = calculateBackoffDelay(attempt: currentRetries);
      _nextRetryTimes[item.id] = DateTime.now().add(delay);
      await _updateArtifactSyncStatus(item.id, SyncStatusType.pending, isTombstone: isTombstone, currentUserId: currentUserId);
    }
  }


  @override
  void dispose() {
    _connectivitySub?.cancel();
    _authSub?.cancel();
    _unsyncedCountSub?.cancel();
    _tombstoneCountSub?.cancel();
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    super.dispose();
  }
}
