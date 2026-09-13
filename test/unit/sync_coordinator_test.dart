import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sitelens/core/services/auth_service.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/features/camera/services/evidence_storage_service.dart';
import 'package:sitelens/features/sync/services/cloud_sync_service.dart';
import 'package:sitelens/features/sync/services/sync_coordinator.dart';

class FakeConnectivity implements Connectivity {
  final _controller = StreamController<List<ConnectivityResult>>.broadcast();
  List<ConnectivityResult> currentResults;

  FakeConnectivity({this.currentResults = const [ConnectivityResult.wifi]});

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => currentResults;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _controller.stream;

  void emit(List<ConnectivityResult> results) {
    currentResults = results;
    _controller.add(results);
  }

  void dispose() {
    _controller.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMediaRepository implements MediaRepository {
  final List<MediaItem> _items = [];
  final _countController = StreamController<int>.broadcast();
  final _tombstoneCountController = StreamController<int>.broadcast();

  int _pendingCount() =>
      _items.where((i) => !i.isDeleted && i.syncStatus == SyncStatusType.pending).length;

  int _tombstoneCandidateCount() =>
      _items.where((i) => i.isDeleted && i.syncStatus != SyncStatusType.syncing).length;

  void setItems(List<MediaItem> items) {
    _items.clear();
    _items.addAll(items);
    _emitCount();
  }

  void _emitCount() {
    if (!_countController.isClosed) {
      _countController.add(_pendingCount());
    }
    _emitTombstoneCount();
  }

  void _emitTombstoneCount() {
    if (!_tombstoneCountController.isClosed) {
      _tombstoneCountController.add(_tombstoneCandidateCount());
    }
  }

  @override
  Future<void> resetStuckSyncingMedia() async {
    for (int i = 0; i < _items.length; i++) {
      if (_items[i].syncStatus == SyncStatusType.syncing) {
        _items[i] = _items[i].copyWith(syncStatus: SyncStatusType.pending);
      }
    }
    _emitCount();
  }

  @override
  Stream<int> watchUnsyncedCount({String? creatorId}) => _countController.stream;

  @override
  Stream<int> watchTombstoneCandidateCount() => _tombstoneCountController.stream;

  @override
  Future<List<MediaItem>> getPendingOrFailedMedia({String? creatorId}) async {
    return _items.where((i) {
      if (i.isDeleted) return false;
      if (i.syncStatus == SyncStatusType.synced) return false;
      if (creatorId != null && i.creatorId != null && i.creatorId != creatorId) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<List<MediaItem>> getTombstoneSyncCandidates({String? creatorId}) async {
    return _items.where((i) {
      if (!i.isDeleted) return false;
      if (i.syncStatus == SyncStatusType.syncing) return false;
      if (creatorId != null && i.creatorId != null && i.creatorId != creatorId) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<void> updateSyncStatus(String mediaId, SyncStatusType status) async {
    final index = _items.indexWhere((i) => i.id == mediaId);
    if (index != -1) {
      _items[index] = _items[index].copyWith(syncStatus: status);
    }
    _emitCount();
  }

  @override
  Future<void> deletePermanently(String mediaId) async {
    // C-2 semantics: permanent user deletion converts the row into a hidden
    // tombstone candidate instead of destroying it, so the cloud ledger can
    // always be reconciled by the existing tombstone synchronization.
    final index = _items.indexWhere((i) => i.id == mediaId);
    if (index != -1) {
      _items[index] = _items[index].copyWith(isDeleted: true);
    }
    _emitCount();
  }

  @override
  Future<List<MediaItem>> getAllMediaEntriesIncludingDeleted({String? creatorId}) async {
    if (creatorId != null && creatorId.isNotEmpty) {
      return _items.where((i) => i.creatorId == creatorId).toList();
    }
    return List.from(_items);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuthService implements AuthService {
  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? _user;

  FakeAuthService(this._user);

  void setUser(AuthUser? user) {
    _user = user;
    _controller.add(user);
  }

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  void dispose() {
    _controller.close();
  }

  @override
  Future<AuthUser> signInWithEmailPassword(String email, String password) async {
    return _user!;
  }

  @override
  Future<AuthUser?> signInWithGoogle() async {
    return _user;
  }

  @override
  Future<AuthUser> signUpWithEmailPassword(
    String email,
    String password, {
    String? displayName,
  }) async {
    return _user ?? AuthUser(uid: 'uid-fake', email: email, isEmailVerified: true);
  }

  @override
  Future<void> sendEmailVerificationForUser(String email, String password) async {}

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  SessionVerificationResult verificationResult = const SessionVerificationResult.valid();

  @override
  Future<SessionVerificationResult> verifySession() async => verificationResult;

  @override
  Future<void> signOut() async {
    setUser(null);
  }
}

class FakeCloudSyncService implements CloudSyncService {
  int syncCallCount = 0;
  final List<String> syncedMediaIds = [];
  Exception? exceptionToThrow;
  Future<void> Function(MediaItem item)? onSync;

  int tombstoneCallCount = 0;
  final List<String> tombstonedMediaIds = [];
  Exception? tombstoneExceptionToThrow;
  Future<void> Function(MediaItem item)? onTombstone;

  @override
  Future<void> syncMediaItem({
    required MediaItem item,
    required String absoluteOriginalPath,
    required String absoluteEvidencePath,
    String? absoluteThumbnailPath,
    required String currentUserId,
  }) async {
    syncCallCount++;
    syncedMediaIds.add(item.id);
    if (onSync != null) {
      await onSync!(item);
    }
    if (exceptionToThrow != null) {
      throw exceptionToThrow!;
    }
  }

  @override
  Future<void> syncTombstone({required MediaItem item, required String currentUserId}) async {
    tombstoneCallCount++;
    tombstonedMediaIds.add(item.id);
    if (onTombstone != null) {
      await onTombstone!(item);
    }
    if (tombstoneExceptionToThrow != null) {
      throw tombstoneExceptionToThrow!;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeEvidenceStorageService implements EvidenceStorageService {
  final Directory testDir;

  FakeEvidenceStorageService(this.testDir);

  @override
  Future<Directory> getMediaDirectory() async {
    return Directory('${testDir.path}/media');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeMediaRepository mockRepo;
  late FakeCloudSyncService mockCloudSync;
  late FakeEvidenceStorageService mockStorage;
  late FakeAuthService fakeAuth;
  late FakeConnectivity fakeConnectivity;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_coord_test_');
    final mediaDir = Directory('${tempDir.path}/media');
    await mediaDir.create(recursive: true);

    mockRepo = FakeMediaRepository();
    mockCloudSync = FakeCloudSyncService();
    mockStorage = FakeEvidenceStorageService(tempDir);
    fakeAuth = FakeAuthService(
      const AuthUser(uid: 'user-123', email: 'eng@sitelens.local'),
    );
    fakeConnectivity = FakeConnectivity();
  });

  tearDown(() async {
    fakeConnectivity.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('1. Crash recovery resets in-flight syncing items (synced=2 -> synced=0)', () async {
    final itemStuck = MediaItem(
      id: 'm-stuck',
      siteId: 'site-1',
      originalUri: 'media/orig_m-stuck.jpg',
      uri: 'media/evid_m-stuck.jpg',
      type: MediaItemType.photo,
      lat: 22.5,
      lon: 88.3,
      capturedAt: DateTime.now(),
      creatorId: 'user-123',
      syncStatus: SyncStatusType.syncing, // Stuck!
    );
    mockRepo.setItems([itemStuck]);

    final coordinator = SyncCoordinator(
      mediaRepo: mockRepo,
      cloudSyncService: mockCloudSync,
      storageService: mockStorage,
      authService: fakeAuth,
      connectivity: fakeConnectivity,
    );

    await Future.delayed(const Duration(milliseconds: 50));
    expect(mockRepo._items.first.syncStatus, equals(SyncStatusType.synced)); // Was reset to pending, then processed to synced
    coordinator.dispose();
  });

  test('2. Concurrent trigger protection: Multiple simultaneous triggers execute sync only once', () async {
    final item = MediaItem(
      id: 'm-concurrent',
      siteId: 'site-1',
      originalUri: 'media/orig_m-concurrent.jpg',
      uri: 'media/evid_m-concurrent.jpg',
      type: MediaItemType.photo,
      lat: 22.5,
      lon: 88.3,
      capturedAt: DateTime.now(),
      creatorId: 'user-123',
      syncStatus: SyncStatusType.pending,
    );
    mockRepo.setItems([item]);

    final coordinator = SyncCoordinator(
      mediaRepo: mockRepo,
      cloudSyncService: mockCloudSync,
      storageService: mockStorage,
      authService: fakeAuth,
      connectivity: fakeConnectivity,
    );

    // Dispatch 5 concurrent triggers simultaneously
    await Future.wait([
      coordinator.triggerSync(),
      coordinator.triggerSync(),
      coordinator.triggerSync(),
      coordinator.triggerSync(),
      coordinator.triggerSync(),
    ]);

    expect(mockCloudSync.syncCallCount, equals(1));
    coordinator.dispose();
  });

  test('3. Creator isolation: Items captured by another user remain dormant', () async {
    final otherUserItem = MediaItem(
      id: 'm-other-user',
      siteId: 'site-1',
      originalUri: 'media/orig_m-other.jpg',
      uri: 'media/evid_m-other.jpg',
      type: MediaItemType.photo,
      lat: 22.5,
      lon: 88.3,
      capturedAt: DateTime.now(),
      creatorId: 'user-OTHER', // Different creator
      syncStatus: SyncStatusType.pending,
    );
    mockRepo.setItems([otherUserItem]);

    final coordinator = SyncCoordinator(
      mediaRepo: mockRepo,
      cloudSyncService: mockCloudSync,
      storageService: mockStorage,
      authService: fakeAuth, // Active session is user-123
      connectivity: fakeConnectivity,
    );

    await coordinator.triggerSync(isManual: true);

    expect(mockCloudSync.syncCallCount, equals(0));
    final items = await mockRepo.getPendingOrFailedMedia();
    expect(items.first.syncStatus, equals(SyncStatusType.pending)); // Remained dormant
    coordinator.dispose();
  });

  test('4. Permanent failure (Integrity Conflict / Revoked Membership) is marked failed and ignored by automatic reconnect', () async {
    final item = MediaItem(
      id: 'm-conflict',
      siteId: 'site-1',
      originalUri: 'media/orig_m-conflict.jpg',
      uri: 'media/evid_m-conflict.jpg',
      type: MediaItemType.photo,
      lat: 22.5,
      lon: 88.3,
      capturedAt: DateTime.now(),
      creatorId: 'user-123',
      syncStatus: SyncStatusType.pending,
    );
    mockRepo.setItems([item]);

    mockCloudSync.exceptionToThrow = PermanentSyncException('Revoked site membership');

    final coordinator = SyncCoordinator(
      mediaRepo: mockRepo,
      cloudSyncService: mockCloudSync,
      storageService: mockStorage,
      authService: fakeAuth,
      connectivity: fakeConnectivity,
    );

    await coordinator.triggerSync();

    expect(coordinator.state.failedCount, equals(1));
    final items = await mockRepo.getPendingOrFailedMedia(creatorId: 'user-123');
    expect(items.first.syncStatus, equals(SyncStatusType.failed));

    // Reset call count and trigger automatic sync (not manual)
    mockCloudSync.syncCallCount = 0;
    await coordinator.triggerSync(isManual: false);

    // Permanent failure should be skipped during automatic sync
    expect(mockCloudSync.syncCallCount, equals(0));

    coordinator.dispose();
  });

  test('5. Manual retry explicitly re-evaluates previously failed items', () async {
    final item = MediaItem(
      id: 'm-retry',
      siteId: 'site-1',
      originalUri: 'media/orig_m-retry.jpg',
      uri: 'media/evid_m-retry.jpg',
      type: MediaItemType.photo,
      lat: 22.5,
      lon: 88.3,
      capturedAt: DateTime.now(),
      creatorId: 'user-123',
      syncStatus: SyncStatusType.failed,
    );
    mockRepo.setItems([item]);

    mockCloudSync.exceptionToThrow = null; // Problem resolved

    final coordinator = SyncCoordinator(
      mediaRepo: mockRepo,
      cloudSyncService: mockCloudSync,
      storageService: mockStorage,
      authService: fakeAuth,
      connectivity: fakeConnectivity,
    );

    // Manual retry tapped
    await coordinator.triggerSync(isManual: true);

    expect(mockCloudSync.syncCallCount, equals(1));
    final items = await mockRepo.getPendingOrFailedMedia(creatorId: 'user-123');
    expect(items, isEmpty); // Item was successfully synced!
    coordinator.dispose();
  });

  group('P1-1 Authentication / User-Switch Race Tests', () {
    test('Test A — Logout during active sync aborts subsequent User A items in the batch', () async {
      final item1 = MediaItem(
        id: 'm-userA-1',
        siteId: 'site-1',
        originalUri: 'media/orig_1.jpg',
        uri: 'media/evid_1.jpg',
        type: MediaItemType.photo,
        lat: 22.5,
        lon: 88.3,
        capturedAt: DateTime.now(),
        creatorId: 'user-123',
        syncStatus: SyncStatusType.pending,
      );
      final item2 = MediaItem(
        id: 'm-userA-2',
        siteId: 'site-1',
        originalUri: 'media/orig_2.jpg',
        uri: 'media/evid_2.jpg',
        type: MediaItemType.photo,
        lat: 22.5,
        lon: 88.3,
        capturedAt: DateTime.now(),
        creatorId: 'user-123',
        syncStatus: SyncStatusType.pending,
      );
      mockRepo.setItems([item1, item2]);

      final coordinator = SyncCoordinator(
        mediaRepo: mockRepo,
        cloudSyncService: mockCloudSync,
        storageService: mockStorage,
        authService: fakeAuth,
        connectivity: fakeConnectivity,
      );

      // When item1 begins syncing, simulate User A logging out
      mockCloudSync.onSync = (item) async {
        if (item.id == 'm-userA-1') {
          fakeAuth.setUser(null); // User logs out mid-sync
        }
      };

      await coordinator.triggerSync();

      // Item 1 completed, but Item 2 must be aborted
      expect(mockCloudSync.syncedMediaIds, equals(['m-userA-1']));
      expect(mockCloudSync.syncedMediaIds.contains('m-userA-2'), isFalse);

      final items = await mockRepo.getPendingOrFailedMedia();
      final remainingItem2 = items.firstWhere((i) => i.id == 'm-userA-2');
      expect(remainingItem2.syncStatus, equals(SyncStatusType.pending)); // Remains pending, not processed under stale session

      coordinator.dispose();
    });

    test('Test B — User A -> User B switch terminates User A batch and executes User B sync', () async {
      final userAItem1 = MediaItem(
        id: 'm-userA-1',
        siteId: 'site-1',
        originalUri: 'media/orig_A1.jpg',
        uri: 'media/evid_A1.jpg',
        type: MediaItemType.photo,
        lat: 22.5,
        lon: 88.3,
        capturedAt: DateTime.now(),
        creatorId: 'user-123',
        syncStatus: SyncStatusType.pending,
      );
      final userAItem2 = MediaItem(
        id: 'm-userA-2',
        siteId: 'site-1',
        originalUri: 'media/orig_A2.jpg',
        uri: 'media/evid_A2.jpg',
        type: MediaItemType.photo,
        lat: 22.5,
        lon: 88.3,
        capturedAt: DateTime.now(),
        creatorId: 'user-123',
        syncStatus: SyncStatusType.pending,
      );
      final userBItem = MediaItem(
        id: 'm-userB-1',
        siteId: 'site-2',
        originalUri: 'media/orig_B1.jpg',
        uri: 'media/evid_B1.jpg',
        type: MediaItemType.photo,
        lat: 22.5,
        lon: 88.3,
        capturedAt: DateTime.now(),
        creatorId: 'user-456',
        syncStatus: SyncStatusType.pending,
      );
      mockRepo.setItems([userAItem1, userAItem2, userBItem]);

      final coordinator = SyncCoordinator(
        mediaRepo: mockRepo,
        cloudSyncService: mockCloudSync,
        storageService: mockStorage,
        authService: fakeAuth,
        connectivity: fakeConnectivity,
      );

      // When User A's item 1 syncs, switch user to User B
      mockCloudSync.onSync = (item) async {
        if (item.id == 'm-userA-1') {
          fakeAuth.setUser(const AuthUser(uid: 'user-456', email: 'userB@sitelens.local'));
        }
      };

      await coordinator.triggerSync();
      await Future.delayed(const Duration(milliseconds: 50)); // Allow follow-up sync to drain

      // Expected: User A item 1 synced, User A item 2 aborted, User B item synced
      expect(mockCloudSync.syncedMediaIds, contains('m-userA-1'));
      expect(mockCloudSync.syncedMediaIds, isNot(contains('m-userA-2')));
      expect(mockCloudSync.syncedMediaIds, contains('m-userB-1'));

      coordinator.dispose();
    });

    test('Test C — Auth change between items is rejected immediately', () async {
      final item1 = MediaItem(
        id: 'm-c1',
        siteId: 'site-1',
        originalUri: 'media/orig_c1.jpg',
        uri: 'media/evid_c1.jpg',
        type: MediaItemType.photo,
        lat: 22.5,
        lon: 88.3,
        capturedAt: DateTime.now(),
        creatorId: 'user-123',
        syncStatus: SyncStatusType.pending,
      );
      final item2 = MediaItem(
        id: 'm-c2',
        siteId: 'site-1',
        originalUri: 'media/orig_c2.jpg',
        uri: 'media/evid_c2.jpg',
        type: MediaItemType.photo,
        lat: 22.5,
        lon: 88.3,
        capturedAt: DateTime.now(),
        creatorId: 'user-123',
        syncStatus: SyncStatusType.pending,
      );
      mockRepo.setItems([item1, item2]);

      final coordinator = SyncCoordinator(
        mediaRepo: mockRepo,
        cloudSyncService: mockCloudSync,
        storageService: mockStorage,
        authService: fakeAuth,
        connectivity: fakeConnectivity,
      );

      mockCloudSync.onSync = (item) async {
        // Change auth identity
        fakeAuth.setUser(null);
      };

      await coordinator.triggerSync();

      expect(mockCloudSync.syncedMediaIds, equals(['m-c1']));
      coordinator.dispose();
    });
  });

  group('P1-2 Manual Retry Queueing Tests', () {
    test('Test D — Manual retry requested during active automatic sync is not lost and executes follow-up', () async {
      final autoItem = MediaItem(
        id: 'm-auto-1',
        siteId: 'site-1',
        originalUri: 'media/orig_auto.jpg',
        uri: 'media/evid_auto.jpg',
        type: MediaItemType.photo,
        lat: 22.5,
        lon: 88.3,
        capturedAt: DateTime.now(),
        creatorId: 'user-123',
        syncStatus: SyncStatusType.pending,
      );
      final failedItem = MediaItem(
        id: 'm-failed-x',
        siteId: 'site-1',
        originalUri: 'media/orig_fail.jpg',
        uri: 'media/evid_fail.jpg',
        type: MediaItemType.photo,
        lat: 22.5,
        lon: 88.3,
        capturedAt: DateTime.now(),
        creatorId: 'user-123',
        syncStatus: SyncStatusType.failed,
      );
      mockRepo.setItems([autoItem, failedItem]);

      final coordinator = SyncCoordinator(
        mediaRepo: mockRepo,
        cloudSyncService: mockCloudSync,
        storageService: mockStorage,
        authService: fakeAuth,
        connectivity: fakeConnectivity,
      );

      // Pre-seed failed item into permanent failure suppression set
      mockCloudSync.onSync = (item) async {
        if (item.id == 'm-failed-x') {
          throw PermanentSyncException('initial failure');
        }
      };
      await coordinator.triggerSync(isManual: true); // Fails item X only
      mockCloudSync.onSync = null; // Issue resolved

      // Reset sync tracking
      mockCloudSync.syncedMediaIds.clear();
      mockCloudSync.syncCallCount = 0;
      mockRepo.setItems([autoItem, failedItem]);

      // When autoItem is syncing, simulate user pressing Manual Retry
      mockCloudSync.onSync = (item) async {
        if (item.id == 'm-auto-1') {
          // Dispatched while automatic sync is in progress
          coordinator.triggerSync(isManual: true);
        }
      };

      await coordinator.triggerSync(isManual: false);
      await Future.delayed(const Duration(milliseconds: 50)); // Allow deferred manual retry to execute

      // Both the automatic item and the manually retried failed item must have synced
      expect(mockCloudSync.syncedMediaIds, contains('m-auto-1'));
      expect(mockCloudSync.syncedMediaIds, contains('m-failed-x'));

      coordinator.dispose();
    });

    test('Test E — No duplicate concurrent executions during queued manual retry', () async {
      final item = MediaItem(
        id: 'm-single',
        siteId: 'site-1',
        originalUri: 'media/orig_s.jpg',
        uri: 'media/evid_s.jpg',
        type: MediaItemType.photo,
        lat: 22.5,
        lon: 88.3,
        capturedAt: DateTime.now(),
        creatorId: 'user-123',
        syncStatus: SyncStatusType.pending,
      );
      mockRepo.setItems([item]);

      final coordinator = SyncCoordinator(
        mediaRepo: mockRepo,
        cloudSyncService: mockCloudSync,
        storageService: mockStorage,
        authService: fakeAuth,
        connectivity: fakeConnectivity,
      );

      int activeConcurrentSyncs = 0;
      int maxConcurrentSyncs = 0;

      mockCloudSync.onSync = (item) async {
        activeConcurrentSyncs++;
        if (activeConcurrentSyncs > maxConcurrentSyncs) {
          maxConcurrentSyncs = activeConcurrentSyncs;
        }
        // Interleave manual retry call
        coordinator.triggerSync(isManual: true);
        await Future.delayed(const Duration(milliseconds: 10));
        activeConcurrentSyncs--;
      };

      await coordinator.triggerSync(isManual: false);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(maxConcurrentSyncs, equals(1)); // Never more than 1 sync concurrently
      coordinator.dispose();
    });

    test('Test F — Multiple manual retry requests during processing are deduplicated gracefully', () async {
      final item = MediaItem(
        id: 'm-multi',
        siteId: 'site-1',
        originalUri: 'media/orig_m.jpg',
        uri: 'media/evid_m.jpg',
        type: MediaItemType.photo,
        lat: 22.5,
        lon: 88.3,
        capturedAt: DateTime.now(),
        creatorId: 'user-123',
        syncStatus: SyncStatusType.pending,
      );
      mockRepo.setItems([item]);

      final coordinator = SyncCoordinator(
        mediaRepo: mockRepo,
        cloudSyncService: mockCloudSync,
        storageService: mockStorage,
        authService: fakeAuth,
        connectivity: fakeConnectivity,
      );

      mockCloudSync.onSync = (item) async {
        // Enqueue 5 manual retry calls in rapid succession
        coordinator.triggerSync(isManual: true);
        coordinator.triggerSync(isManual: true);
        coordinator.triggerSync(isManual: true);
        coordinator.triggerSync(isManual: true);
        coordinator.triggerSync(isManual: true);
      };

      await coordinator.triggerSync(isManual: false);
      await Future.delayed(const Duration(milliseconds: 50));

      // Item should be synced cleanly without redundant infinite loops
      final items = await mockRepo.getPendingOrFailedMedia();
      expect(items, isEmpty);
      coordinator.dispose();
    });

    test('Logout immediately resets pendingCount, failedCount, isSyncing, while SQLite media remain untouched and User B recalculates', () async {
      final userAItem1 = MediaItem(
        id: 'm-userA-1',
        siteId: 'site-1',
        originalUri: 'media/orig_a1.jpg',
        uri: 'media/evid_a1.jpg',
        type: MediaItemType.photo,
        lat: 22.5,
        lon: 88.3,
        capturedAt: DateTime.now(),
        creatorId: 'user-A',
        syncStatus: SyncStatusType.pending,
      );
      final userAItem2 = MediaItem(
        id: 'm-userA-2',
        siteId: 'site-1',
        originalUri: 'media/orig_a2.jpg',
        uri: 'media/evid_a2.jpg',
        type: MediaItemType.photo,
        lat: 22.5,
        lon: 88.3,
        capturedAt: DateTime.now(),
        creatorId: 'user-A',
        syncStatus: SyncStatusType.failed,
      );
      final userBItem = MediaItem(
        id: 'm-userB-1',
        siteId: 'site-1',
        originalUri: 'media/orig_b1.jpg',
        uri: 'media/evid_b1.jpg',
        type: MediaItemType.photo,
        lat: 22.5,
        lon: 88.3,
        capturedAt: DateTime.now(),
        creatorId: 'user-B',
        syncStatus: SyncStatusType.pending,
      );

      mockRepo.setItems([userAItem1, userAItem2, userBItem]);

      // Set offline so items remain pending without auto-syncing during test
      fakeConnectivity.currentResults = [ConnectivityResult.none];
      fakeConnectivity.emit([ConnectivityResult.none]);

      // Login as User A
      fakeAuth.setUser(const AuthUser(uid: 'user-A', email: 'userA@sitelens.local'));

      final coordinator = SyncCoordinator(
        mediaRepo: mockRepo,
        cloudSyncService: mockCloudSync,
        storageService: mockStorage,
        authService: fakeAuth,
        connectivity: fakeConnectivity,
      );

      await Future.delayed(const Duration(milliseconds: 50));

      // Verify User A has 1 pending, 1 failed
      expect(coordinator.state.pendingCount, equals(1));
      expect(coordinator.state.failedCount, equals(1));

      // User A logs out
      fakeAuth.setUser(null);
      await Future.delayed(const Duration(milliseconds: 50));

      // Verify state immediately resets to zero counts
      expect(coordinator.state.pendingCount, equals(0));
      expect(coordinator.state.failedCount, equals(0));
      expect(coordinator.state.isSyncing, equals(false));

      // Verify SQLite records remain completely untouched
      final allDbItems = await mockRepo.getAllMediaEntriesIncludingDeleted();
      expect(allDbItems.length, equals(3));
      expect(allDbItems.where((i) => i.creatorId == 'user-A').length, equals(2));

      // User B logs in
      fakeAuth.setUser(const AuthUser(uid: 'user-B', email: 'userB@sitelens.local'));
      await Future.delayed(const Duration(milliseconds: 50));

      // User B has 1 pending, 0 failed
      expect(coordinator.state.pendingCount, equals(1));
      expect(coordinator.state.failedCount, equals(0));

      coordinator.dispose();
    });
  });

  group('F1 Offline Capture Auto-Sync Tests', () {
    test('New pending evidence while online auto-syncs without manual badge action or connectivity event', () async {
      mockRepo.setItems([]);
      final coordinator = SyncCoordinator(
        mediaRepo: mockRepo,
        cloudSyncService: mockCloudSync,
        storageService: mockStorage,
        authService: fakeAuth,
        connectivity: fakeConnectivity,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Capture completes: a new pending item is committed to the local queue
      final newItem = MediaItem(
        id: 'm-new-online',
        siteId: 'site-1',
        originalUri: 'media/orig_m-new-online.jpg',
        uri: 'media/evid_m-new-online.jpg',
        type: MediaItemType.photo,
        lat: 22.5,
        lon: 88.3,
        capturedAt: DateTime.now(),
        creatorId: 'user-123',
        syncStatus: SyncStatusType.pending,
      );
      mockRepo.setItems([newItem]);

      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Uploaded exactly once, without any manual/connectivity trigger
      expect(mockCloudSync.syncCallCount, equals(1));
      expect(mockCloudSync.syncedMediaIds, equals(['m-new-online']));
      final items = await mockRepo.getPendingOrFailedMedia(creatorId: 'user-123');
      expect(items, isEmpty);

      coordinator.dispose();
    });

    test('Capture while offline stays pending and uploads only after reconnect', () async {
      fakeConnectivity.currentResults = [ConnectivityResult.none];
      mockRepo.setItems([]);
      final coordinator = SyncCoordinator(
        mediaRepo: mockRepo,
        cloudSyncService: mockCloudSync,
        storageService: mockStorage,
        authService: fakeAuth,
        connectivity: fakeConnectivity,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Offline capture commits locally and must remain queued
      final offlineItem = MediaItem(
        id: 'm-offline-cap',
        siteId: 'site-1',
        originalUri: 'media/orig_m-offline-cap.jpg',
        uri: 'media/evid_m-offline-cap.jpg',
        type: MediaItemType.photo,
        lat: 22.5,
        lon: 88.3,
        capturedAt: DateTime.now(),
        creatorId: 'user-123',
        syncStatus: SyncStatusType.pending,
      );
      mockRepo.setItems([offlineItem]);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(mockCloudSync.syncCallCount, equals(0));
      expect(mockRepo._items.first.syncStatus, equals(SyncStatusType.pending));

      // Reconnection drives the existing pipeline
      fakeConnectivity.emit([ConnectivityResult.wifi]);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(mockCloudSync.syncCallCount, equals(1));
      expect(mockRepo._items.first.syncStatus, equals(SyncStatusType.synced));

      coordinator.dispose();
    });
  });

  group('F1 Foreground Resume Sync Tests', () {
    test('Authenticated resume with pending work triggers the existing sync path', () async {
      mockRepo.setItems([]);
      final coordinator = SyncCoordinator(
        mediaRepo: mockRepo,
        cloudSyncService: mockCloudSync,
        storageService: mockStorage,
        authService: fakeAuth,
        connectivity: fakeConnectivity,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(mockCloudSync.syncCallCount, equals(0));

      // Seed a failed (non-suppressed) item: the pending-count edge trigger does
      // not fire for failed items, so only a resume event can drive this sync.
      final failedItem = MediaItem(
        id: 'm-resume-pending',
        siteId: 'site-1',
        originalUri: 'media/orig_m-resume.jpg',
        uri: 'media/evid_m-resume.jpg',
        type: MediaItemType.photo,
        lat: 22.5,
        lon: 88.3,
        capturedAt: DateTime.now(),
        creatorId: 'user-123',
        syncStatus: SyncStatusType.failed,
      );
      mockRepo.setItems([failedItem]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(mockCloudSync.syncCallCount, equals(0));

      // Foreground resume drives the existing triggerSync pipeline
      coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(mockCloudSync.syncCallCount, equals(1));
      expect(mockCloudSync.syncedMediaIds, equals(['m-resume-pending']));
      expect(mockRepo._items.first.syncStatus, equals(SyncStatusType.synced));

      coordinator.dispose();
    });

    test('Unauthenticated resume does not start evidence synchronization', () async {
      final loggedOutAuth = FakeAuthService(null);
      mockRepo.setItems([
        MediaItem(
          id: 'm-logged-out',
          siteId: 'site-1',
          originalUri: 'media/orig_lo.jpg',
          uri: 'media/evid_lo.jpg',
          type: MediaItemType.photo,
          lat: 22.5,
          lon: 88.3,
          capturedAt: DateTime.now(),
          creatorId: 'user-123',
          syncStatus: SyncStatusType.pending,
        ),
      ]);
      final coordinator = SyncCoordinator(
        mediaRepo: mockRepo,
        cloudSyncService: mockCloudSync,
        storageService: mockStorage,
        authService: loggedOutAuth,
        connectivity: fakeConnectivity,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(mockCloudSync.syncCallCount, equals(0));
      expect(mockRepo._items.first.syncStatus, equals(SyncStatusType.pending));

      coordinator.dispose();
    });

    test('Resume during an already-running sync does not create a duplicate concurrent sync', () async {
      mockRepo.setItems([
        MediaItem(
          id: 'm-resume-mid',
          siteId: 'site-1',
          originalUri: 'media/orig_mid.jpg',
          uri: 'media/evid_mid.jpg',
          type: MediaItemType.photo,
          lat: 22.5,
          lon: 88.3,
          capturedAt: DateTime.now(),
          creatorId: 'user-123',
          syncStatus: SyncStatusType.pending,
        ),
      ]);
      final coordinator = SyncCoordinator(
        mediaRepo: mockRepo,
        cloudSyncService: mockCloudSync,
        storageService: mockStorage,
        authService: fakeAuth,
        connectivity: fakeConnectivity,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      mockCloudSync.syncCallCount = 0;
      mockCloudSync.syncedMediaIds.clear();

      int activeConcurrentSyncs = 0;
      int maxConcurrentSyncs = 0;
      mockCloudSync.onSync = (item) async {
        activeConcurrentSyncs++;
        if (activeConcurrentSyncs > maxConcurrentSyncs) {
          maxConcurrentSyncs = activeConcurrentSyncs;
        }
        // Resume event fires mid-flight
        coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        activeConcurrentSyncs--;
      };

      // Re-queue item as pending and drive one cycle
      mockRepo.setItems([
        MediaItem(
          id: 'm-resume-mid',
          siteId: 'site-1',
          originalUri: 'media/orig_mid.jpg',
          uri: 'media/evid_mid.jpg',
          type: MediaItemType.photo,
          lat: 22.5,
          lon: 88.3,
          capturedAt: DateTime.now(),
          creatorId: 'user-123',
          syncStatus: SyncStatusType.pending,
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(maxConcurrentSyncs, equals(1));
      expect(mockCloudSync.syncCallCount, equals(1));
      expect(mockRepo._items.first.syncStatus, equals(SyncStatusType.synced));

      coordinator.dispose();
    });

    test('Session-generation protection still prevents cross-user processing on resume', () async {
      final userAItem1 = MediaItem(
        id: 'm-userA-1',
        siteId: 'site-1',
        originalUri: 'media/orig_A1.jpg',
        uri: 'media/evid_A1.jpg',
        type: MediaItemType.photo,
        lat: 22.5,
        lon: 88.3,
        capturedAt: DateTime.now(),
        creatorId: 'user-123',
        syncStatus: SyncStatusType.pending,
      );
      final userAItem2 = MediaItem(
        id: 'm-userA-2',
        siteId: 'site-1',
        originalUri: 'media/orig_A2.jpg',
        uri: 'media/evid_A2.jpg',
        type: MediaItemType.photo,
        lat: 22.5,
        lon: 88.3,
        capturedAt: DateTime.now(),
        creatorId: 'user-123',
        syncStatus: SyncStatusType.pending,
      );
      mockRepo.setItems([userAItem1, userAItem2]);
      final coordinator = SyncCoordinator(
        mediaRepo: mockRepo,
        cloudSyncService: mockCloudSync,
        storageService: mockStorage,
        authService: fakeAuth,
        connectivity: fakeConnectivity,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      mockCloudSync.syncCallCount = 0;
      mockCloudSync.syncedMediaIds.clear();

      mockCloudSync.onSync = (item) async {
        if (item.id == 'm-userA-1') {
          fakeAuth.setUser(null); // Logout mid-batch
          coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
        }
      };
      mockRepo.setItems([userAItem1, userAItem2]);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Item 1 completed; item 2 must NOT be processed under the stale session
      expect(mockCloudSync.syncedMediaIds, equals(['m-userA-1']));
      final remaining = await mockRepo.getPendingOrFailedMedia();
      expect(remaining.single.id, equals('m-userA-2'));
      expect(remaining.single.syncStatus, equals(SyncStatusType.pending));

      coordinator.dispose();
    });
  });

  group('F2 Unexpected Exception Suppression Tests', () {
    test('Unexpected exception is suppressed from automatic cycles; manual retry re-evaluates', () async {
      final item = MediaItem(
        id: 'm-unexpected',
        siteId: 'site-1',
        originalUri: 'media/orig_unx.jpg',
        uri: 'media/evid_unx.jpg',
        type: MediaItemType.photo,
        lat: 22.5,
        lon: 88.3,
        capturedAt: DateTime.now(),
        creatorId: 'user-123',
        syncStatus: SyncStatusType.pending,
      );
      mockRepo.setItems([item]);
      mockCloudSync.exceptionToThrow = Exception('Unexpected internal failure');

      final coordinator = SyncCoordinator(
        mediaRepo: mockRepo,
        cloudSyncService: mockCloudSync,
        storageService: mockStorage,
        authService: fakeAuth,
        connectivity: fakeConnectivity,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // First automatic cycle processes once, fails, and marks failed honestly
      expect(mockCloudSync.syncCallCount, equals(1));
      expect(mockRepo._items.first.syncStatus, equals(SyncStatusType.failed));

      // Subsequent automatic cycles must NOT repeatedly process the item
      await coordinator.triggerSync(isManual: false);
      await coordinator.triggerSync(isManual: false);
      expect(mockCloudSync.syncCallCount, equals(1));

      // Manual retry explicitly re-evaluates the suppressed item
      mockCloudSync.exceptionToThrow = null;
      await coordinator.triggerSync(isManual: true);
      expect(mockCloudSync.syncCallCount, equals(2));
      expect(mockRepo._items.first.syncStatus, equals(SyncStatusType.synced));

      coordinator.dispose();
    });

    test('Retryable failures retain backoff: automatic cycles skip until manual retry', () async {
      final item = MediaItem(
        id: 'm-retryable',
        siteId: 'site-1',
        originalUri: 'media/orig_rt.jpg',
        uri: 'media/evid_rt.jpg',
        type: MediaItemType.photo,
        lat: 22.5,
        lon: 88.3,
        capturedAt: DateTime.now(),
        creatorId: 'user-123',
        syncStatus: SyncStatusType.pending,
      );
      mockRepo.setItems([item]);
      mockCloudSync.exceptionToThrow = RetryableSyncException('Transient network failure');

      final coordinator = SyncCoordinator(
        mediaRepo: mockRepo,
        cloudSyncService: mockCloudSync,
        storageService: mockStorage,
        authService: fakeAuth,
        connectivity: fakeConnectivity,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Failed once, returned to pending with backoff scheduled
      expect(mockCloudSync.syncCallCount, equals(1));
      expect(mockRepo._items.first.syncStatus, equals(SyncStatusType.pending));

      // An immediate automatic cycle respects backoff and skips the item
      await coordinator.triggerSync(isManual: false);
      expect(mockCloudSync.syncCallCount, equals(1));

      // Manual retry clears backoff and processes the item
      mockCloudSync.exceptionToThrow = null;
      await coordinator.triggerSync(isManual: true);
      expect(mockCloudSync.syncCallCount, equals(2));
      expect(mockRepo._items.first.syncStatus, equals(SyncStatusType.synced));

      coordinator.dispose();
    });
  });

  group('B-1 Tombstone Synchronization Tests', () {
    MediaItem syncedDeletedItem({String creatorId = 'user-123', String id = 'm-tombstone'}) => MediaItem(
          id: id,
          siteId: 'site-1',
          originalUri: 'media/orig_$id.jpg',
          uri: 'media/evid_$id.jpg',
          type: MediaItemType.photo,
          lat: 22.5,
          lon: 88.3,
          capturedAt: DateTime.now(),
          creatorId: creatorId,
          syncStatus: SyncStatusType.synced,
          isDeleted: true,
        );

    SyncCoordinator buildCoordinator() => SyncCoordinator(
          mediaRepo: mockRepo,
          cloudSyncService: mockCloudSync,
          storageService: mockStorage,
          authService: fakeAuth,
          connectivity: fakeConnectivity,
        );

    /// Deterministic B-1 test pattern: construct an idle coordinator first
    /// (settles the constructor's initial cycle), then seed the tombstone —
    /// the tombstone-count edge trigger runs exactly one discovery cycle.
    Future<SyncCoordinator> buildAndSeed(List<MediaItem> items) async {
      final coordinator = buildCoordinator();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      mockRepo.setItems(items);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return coordinator;
    }

    test('Discovers a synced locally-deleted item, routes it to the tombstone path, and never touches artifact sync or its status', () async {
      final coordinator = await buildAndSeed([syncedDeletedItem()]);

      expect(mockCloudSync.tombstoneCallCount, equals(1));
      expect(mockCloudSync.tombstonedMediaIds, contains('m-tombstone'));
      // The artifact pipeline (files, uploads, hashing) is never invoked for a
      // tombstone — the cloud ledger write is the only operation.
      expect(mockCloudSync.syncCallCount, equals(0));

      // The deleted row's artifact-sync status is never written: no false
      // "synced" claim and no failed/pending churn on a tombstoned row.
      final row = mockRepo._items.single;
      expect(row.isDeleted, isTrue);
      expect(row.syncStatus, equals(SyncStatusType.synced));

      coordinator.dispose();
    });

    test('Repeated tombstone synchronization is idempotent and keeps the row state stable', () async {
      final coordinator = await buildAndSeed([syncedDeletedItem()]);
      expect(mockCloudSync.tombstoneCallCount, equals(1));

      // A later manual cycle rediscovers the candidate; the cloud-side
      // reconciliation is a no-op for an already-tombstoned document.
      await coordinator.triggerSync(isManual: true);

      expect(mockCloudSync.tombstoneCallCount, equals(2));
      final row = mockRepo._items.single;
      expect(row.syncStatus, equals(SyncStatusType.synced));
      expect(row.isDeleted, isTrue);

      coordinator.dispose();
    });

    test('Retryable tombstone failure preserves backoff/manual-retry semantics and never mutates the deleted row status', () async {
      mockCloudSync.tombstoneExceptionToThrow = RetryableSyncException('Transient network failure');
      final coordinator = await buildAndSeed([syncedDeletedItem()]);

      expect(mockCloudSync.tombstoneCallCount, equals(1));
      final row = mockRepo._items.single;
      expect(row.syncStatus, equals(SyncStatusType.synced));
      expect(row.isDeleted, isTrue);

      // An immediate automatic cycle respects the scheduled backoff
      mockCloudSync.tombstoneCallCount = 0;
      await coordinator.triggerSync(isManual: false);
      expect(mockCloudSync.tombstoneCallCount, equals(0));

      // Manual retry clears backoff and re-evaluates the tombstone
      mockCloudSync.tombstoneExceptionToThrow = null;
      await coordinator.triggerSync(isManual: true);
      expect(mockCloudSync.tombstoneCallCount, equals(1));

      coordinator.dispose();
    });

    test('Permanent tombstone failure is suppressed from automatic cycles until manual retry', () async {
      mockCloudSync.tombstoneExceptionToThrow = PermanentSyncException('Session revoked');
      final coordinator = await buildAndSeed([syncedDeletedItem()]);

      expect(mockCloudSync.tombstoneCallCount, equals(1));
      expect(coordinator.state.lastError, isNotNull);
      // Deleted rows never enter the pending/failed badge counts.
      expect(coordinator.state.failedCount, equals(0));

      mockCloudSync.tombstoneCallCount = 0;
      await coordinator.triggerSync(isManual: false);
      expect(mockCloudSync.tombstoneCallCount, equals(0)); // Suppressed

      mockCloudSync.tombstoneExceptionToThrow = null;
      await coordinator.triggerSync(isManual: true);
      expect(mockCloudSync.tombstoneCallCount, equals(1)); // Manual re-evaluates

      coordinator.dispose();
    });

    test('Tombstones of another creator remain dormant', () async {
      final coordinator = await buildAndSeed([syncedDeletedItem(creatorId: 'user-OTHER')]);

      expect(mockCloudSync.tombstoneCallCount, equals(0));

      coordinator.dispose();
    });

    test('Logout during a tombstone batch aborts subsequent tombstone processing', () async {
      mockCloudSync.onTombstone = (item) async {
        if (item.id == 'm-t1') {
          fakeAuth.setUser(null);
        }
      };
      final coordinator = await buildAndSeed([
        syncedDeletedItem(id: 'm-t1'),
        syncedDeletedItem(id: 'm-t2'),
      ]);

      // Only the first tombstone was processed before the session terminated.
      expect(mockCloudSync.tombstonedMediaIds, equals(['m-t1']));

      coordinator.dispose();
    });

    test('Soft-deleting a synced item while online edge-triggers a sync cycle', () async {
      final coordinator = buildCoordinator();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(mockCloudSync.tombstoneCallCount, equals(0));

      // Removal from gallery tombstones the row: the tombstone-count stream
      // edge-triggers the existing sync pipeline (B-1 discovery).
      mockRepo.setItems([syncedDeletedItem()]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(mockCloudSync.tombstoneCallCount, equals(1));

      coordinator.dispose();
    });

    test('C-2: permanently deleting a published (failed) evidence item propagates its tombstone', () async {
      final publishedFailedItem = MediaItem(
        id: 'm-failed',
        siteId: 'site-1',
        originalUri: 'media/orig_m-failed.jpg',
        uri: 'media/evid_m-failed.jpg',
        type: MediaItemType.photo,
        lat: 22.5,
        lon: 88.3,
        capturedAt: DateTime.now(),
        creatorId: 'user-123',
        syncStatus: SyncStatusType.failed, // published: site + ledger doc already created
        isDeleted: false,
      );
      mockRepo.setItems([publishedFailedItem]);

      // User permanently deletes the evidence before it ever synced.
      await mockRepo.deletePermanently('m-failed');

      final coordinator = buildCoordinator();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // The tombstone propagated through the existing B-1 path...
      expect(mockCloudSync.tombstoneCallCount, equals(1));
      expect(mockCloudSync.tombstonedMediaIds, contains('m-failed'));
      // ...while the artifact pipeline correctly skipped the deleted row.
      expect(mockCloudSync.syncCallCount, equals(0));

      // The hidden tombstone row retains its state; the cloud ledger is the
      // only thing reconciled (is_deleted: true — proven at service level).
      final row = mockRepo._items.single;
      expect(row.isDeleted, isTrue);
      expect(row.syncStatus, SyncStatusType.failed);

      coordinator.dispose();
    });

    test('C-2: permanently deleting never-published evidence discovers the candidate but the cloud write is a verified no-op', () async {
      final neverPublishedItem = MediaItem(
        id: 'm-never-published',
        siteId: 'site-1',
        originalUri: 'media/orig_m-never.jpg',
        uri: 'media/evid_m-never.jpg',
        type: MediaItemType.photo,
        lat: 22.5,
        lon: 88.3,
        capturedAt: DateTime.now(),
        creatorId: 'user-123',
        syncStatus: SyncStatusType.pending,
        isDeleted: false,
      );
      mockRepo.setItems([neverPublishedItem]);
      await mockRepo.deletePermanently('m-never-published');

      final coordinator = buildCoordinator();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // The candidate rides the same pipeline; CloudSyncService.syncTombstone
      // performs no Firestore write for a nonexistent document (proven at
      // service level: 'No-op for a never-published item'), so no cloud
      // deletion record is created and nothing is claimed.
      expect(mockCloudSync.tombstoneCallCount, equals(1));
      expect(mockCloudSync.syncCallCount, equals(0));

      final row = mockRepo._items.single;
      expect(row.isDeleted, isTrue);
      expect(row.syncStatus, SyncStatusType.pending);

      coordinator.dispose();
    });

    test('C-2: tombstone failure after permanent deletion preserves the recoverable row (deferred propagation)', () async {
      final publishedFailedItem = MediaItem(
        id: 'm-failed-deferred',
        siteId: 'site-1',
        originalUri: 'media/orig_m-failed-deferred.jpg',
        uri: 'media/evid_m-failed-deferred.jpg',
        type: MediaItemType.photo,
        lat: 22.5,
        lon: 88.3,
        capturedAt: DateTime.now(),
        creatorId: 'user-123',
        syncStatus: SyncStatusType.failed,
        isDeleted: false,
      );
      mockRepo.setItems([publishedFailedItem]);
      await mockRepo.deletePermanently('m-failed-deferred');

      mockCloudSync.tombstoneExceptionToThrow = RetryableSyncException('Offline');
      final coordinator = buildCoordinator();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // The propagation failed, but the tombstone row was NOT destroyed: the
      // deferred path remains recoverable.
      expect(mockCloudSync.tombstoneCallCount, equals(1));
      final row = mockRepo._items.single;
      expect(row.isDeleted, isTrue);
      expect(row.syncStatus, SyncStatusType.failed);

      // A later retry succeeds — the ledger is still reconciled eventually.
      mockCloudSync.tombstoneExceptionToThrow = null;
      await coordinator.triggerSync(isManual: true);
      expect(mockCloudSync.tombstoneCallCount, equals(2));

      coordinator.dispose();
    });
  });
}
