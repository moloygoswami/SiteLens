import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sitelens/core/services/auth_service.dart';
import 'package:sitelens/core/services/session_service.dart';
import 'package:sitelens/core/services/permission_service.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/features/camera/services/evidence_storage_service.dart';
import 'package:sitelens/features/sync/services/cloud_sync_service.dart';
import 'package:sitelens/features/sync/services/sync_coordinator.dart';
import 'package:firebase_core/firebase_core.dart';

class MockAuthServiceForInvalidation implements AuthService {
  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? _currentUser;
  SessionVerificationResult verificationResultToReturn = const SessionVerificationResult.valid();
  int verifySessionCallCount = 0;
  int signOutCallCount = 0;

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  @override
  AuthUser? get currentUser => _currentUser;

  void emitUser(AuthUser? user) {
    _currentUser = user;
    _controller.add(user);
  }

  @override
  Future<SessionVerificationResult> verifySession() async {
    verifySessionCallCount++;
    return verificationResultToReturn;
  }

  @override
  Future<void> signOut() async {
    signOutCallCount++;
    emitUser(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockPermissionService extends PermissionService {
  @override
  Future<SiteLensPermissionStatus> checkAllPermissions() async {
    state = const SiteLensPermissionStatus(
      camera: PermissionStatus.granted,
      location: PermissionStatus.granted,
    );
    return state;
  }
}

class FakeMediaRepository implements MediaRepository {
  final List<MediaItem> items = [];

  @override
  Future<void> resetStuckSyncingMedia({String? creatorId}) async {}

  @override
  Stream<int> watchUnsyncedCount({String? creatorId}) => Stream.value(items.length);

  @override
  Future<List<MediaItem>> getPendingOrFailedMedia({String? creatorId}) async => items;

  @override
  Future<void> updateSyncStatus(String mediaId, SyncStatusType status, {String? creatorId}) async {
    final index = items.indexWhere((i) => i.id == mediaId);
    if (index != -1) {
      items[index] = items[index].copyWith(syncStatus: status);
    }
  }


  @override
  Future<List<MediaItem>> getTombstoneSyncCandidates({String? creatorId}) async => const [];

  @override
  Stream<int> watchTombstoneCandidateCount({String? creatorId}) => const Stream<int>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeConnectivity implements Connectivity {
  final _controller = StreamController<List<ConnectivityResult>>.broadcast();
  List<ConnectivityResult> currentResults;

  FakeConnectivity({this.currentResults = const [ConnectivityResult.wifi]});

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => currentResults;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _controller.stream;

  void dispose() {
    _controller.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCloudSyncService implements CloudSyncService {
  Exception? errorToThrow;

  @override
  Future<void> syncMediaItem({
    required MediaItem item,
    required String absoluteOriginalPath,
    required String absoluteEvidencePath,
    String? absoluteThumbnailPath,
    required String currentUserId,
  }) async {
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeEvidenceStorageService implements EvidenceStorageService {
  @override
  Future<Directory> getMediaDirectory() async => Directory.systemTemp;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SiteLens Session Invalidation & Recovery Unit Tests (All 5 Scenarios)', () {
    late MockAuthServiceForInvalidation mockAuth;
    late MockPermissionService mockPermission;
    late ProviderContainer container;

    const testUser = AuthUser(
      uid: 'user-001',
      email: 'inspector@sitelens.local',
      displayName: 'Site Inspector',
      isEmailVerified: true,
    );

    setUp(() {
      SharedPreferences.setMockInitialValues({
        'sitelens_onboarding_completed_user-001': true,
      });
      mockAuth = MockAuthServiceForInvalidation();
      mockPermission = MockPermissionService();

      container = ProviderContainer(
        overrides: [
          authServiceProvider.overrideWithValue(mockAuth),
          permissionServiceProvider.overrideWith((ref) => mockPermission),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('Scenario 1: User disabled by Admin/Console invalidates session and records userDisabled', () async {
      mockAuth.emitUser(testUser);
      final sessionService = container.read(sessionServiceProvider.notifier);
      await pumpEventQueue();

      expect(container.read(sessionServiceProvider).status, equals(SessionStatus.authenticatedReady));

      // Simulate Firebase Admin disabling user
      mockAuth.verificationResultToReturn = const SessionVerificationResult.invalid(
        SessionTerminationReason.userDisabled,
        message: 'The user account has been disabled by an administrator.',
      );

      final result = await sessionService.verifySession();

      expect(result.isValid, isFalse);
      expect(result.reason, equals(SessionTerminationReason.userDisabled));
      expect(mockAuth.signOutCallCount, equals(1));

      final finalState = container.read(sessionServiceProvider);
      expect(finalState.status, equals(SessionStatus.unauthenticated));
      expect(finalState.user, isNull);
      expect(finalState.terminationReason, equals(SessionTerminationReason.userDisabled));
      expect(finalState.errorMessage, contains('disabled'));
    });

    test('Scenario 2: User deleted by Admin/Console on cold start invalidates cached session', () async {
      mockAuth._currentUser = testUser;
      mockAuth.verificationResultToReturn = const SessionVerificationResult.invalid(
        SessionTerminationReason.userNotFound,
        message: 'User not found.',
      );

      // Initialize session service with cached user
      container.read(sessionServiceProvider.notifier);
      await pumpEventQueue();

      final state = container.read(sessionServiceProvider);
      expect(state.status, equals(SessionStatus.unauthenticated));
      expect(state.user, isNull);
      expect(state.terminationReason, equals(SessionTerminationReason.userNotFound));
      expect(mockAuth.signOutCallCount, equals(1));
    });

    test('Scenario 3: Refresh token revoked detected on app resume', () async {
      mockAuth.emitUser(testUser);
      final sessionService = container.read(sessionServiceProvider.notifier);
      await pumpEventQueue();

      expect(container.read(sessionServiceProvider).status, equals(SessionStatus.authenticatedReady));

      // Simulate token revocation
      mockAuth.verificationResultToReturn = const SessionVerificationResult.invalid(
        SessionTerminationReason.sessionRevoked,
        message: 'The user token has expired or been revoked.',
      );

      // Simulate app resumed from background
      sessionService.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();

      final state = container.read(sessionServiceProvider);
      expect(state.status, equals(SessionStatus.unauthenticated));
      expect(state.terminationReason, equals(SessionTerminationReason.sessionRevoked));
      expect(mockAuth.signOutCallCount, equals(1));
    });

    test('Scenario 4A: Firebase unauthenticated in SyncCoordinator triggers session invalidation', () async {
      mockAuth.emitUser(testUser);
      final sessionService = container.read(sessionServiceProvider.notifier);
      await pumpEventQueue();

      final fakeRepo = FakeMediaRepository();
      fakeRepo.items.add(MediaItem(
        id: 'media-001',
        siteId: 'site-001',
        creatorId: 'user-001',
        uri: 'media/evid_001.jpg',
        originalUri: 'media/orig_001.jpg',
        type: MediaItemType.photo,
        lat: 37.422,
        lon: -122.084,
        capturedAt: DateTime.now(),
        syncStatus: SyncStatusType.pending,
      ));

      final fakeCloudSync = FakeCloudSyncService();
      fakeCloudSync.errorToThrow = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unauthenticated',
        message: 'User credentials are no longer valid.',
      );

      mockAuth.verificationResultToReturn = const SessionVerificationResult.invalid(
        SessionTerminationReason.unauthenticated,
      );

      final coordinator = SyncCoordinator(
        mediaRepo: fakeRepo,
        cloudSyncService: fakeCloudSync,
        storageService: FakeEvidenceStorageService(),
        authService: mockAuth,
        sessionService: sessionService,
        connectivity: FakeConnectivity(),
      );
      addTearDown(coordinator.dispose);

      await coordinator.triggerSync(isManual: true);
      await pumpEventQueue();

      // Session must be invalidated
      expect(container.read(sessionServiceProvider).status, equals(SessionStatus.unauthenticated));
      expect(fakeRepo.items.first.syncStatus, equals(SyncStatusType.failed));
    });

    test('Scenario 4B: Legitimate site permission-denied does NOT invalidate session when auth is valid', () async {
      mockAuth.emitUser(testUser);
      final sessionService = container.read(sessionServiceProvider.notifier);
      await pumpEventQueue();

      final fakeRepo = FakeMediaRepository();
      fakeRepo.items.add(MediaItem(
        id: 'media-002',
        siteId: 'site-foreign-002',
        creatorId: 'user-001',
        uri: 'media/evid_002.jpg',
        originalUri: 'media/orig_002.jpg',
        type: MediaItemType.photo,
        lat: 37.422,
        lon: -122.084,
        capturedAt: DateTime.now(),
        syncStatus: SyncStatusType.pending,
      ));

      final fakeCloudSync = FakeCloudSyncService();
      fakeCloudSync.errorToThrow = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Missing or insufficient permissions.',
      );

      // Session verification confirms the user is STILL valid
      mockAuth.verificationResultToReturn = const SessionVerificationResult.valid();

      final coordinator = SyncCoordinator(
        mediaRepo: fakeRepo,
        cloudSyncService: fakeCloudSync,
        storageService: FakeEvidenceStorageService(),
        authService: mockAuth,
        sessionService: sessionService,
        connectivity: FakeConnectivity(),
      );
      addTearDown(coordinator.dispose);

      await coordinator.triggerSync(isManual: true);
      await pumpEventQueue();

      // Session MUST remain authenticatedReady!
      expect(container.read(sessionServiceProvider).status, equals(SessionStatus.authenticatedReady));
      expect(mockAuth.signOutCallCount, equals(0));
      // Media item marked failed due to site membership
      expect(fakeRepo.items.first.syncStatus, equals(SyncStatusType.failed));
      expect(coordinator.state.lastError, contains('Permission denied'));
    });

    test('Scenario 4C: permission-denied with disabled auth session triggers invalidation (contextual)', () async {
      mockAuth.emitUser(testUser);
      final sessionService = container.read(sessionServiceProvider.notifier);
      await pumpEventQueue();

      final fakeRepo = FakeMediaRepository();
      fakeRepo.items.add(MediaItem(
        id: 'media-003',
        siteId: 'site-001',
        creatorId: 'user-001',
        uri: 'media/evid_003.jpg',
        originalUri: 'media/orig_003.jpg',
        type: MediaItemType.photo,
        lat: 37.422,
        lon: -122.084,
        capturedAt: DateTime.now(),
        syncStatus: SyncStatusType.pending,
      ));

      final fakeCloudSync = FakeCloudSyncService();
      fakeCloudSync.errorToThrow = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Permission denied.',
      );

      // Session verification confirms the user was disabled
      mockAuth.verificationResultToReturn = const SessionVerificationResult.invalid(
        SessionTerminationReason.userDisabled,
        message: 'User disabled',
      );

      final coordinator = SyncCoordinator(
        mediaRepo: fakeRepo,
        cloudSyncService: fakeCloudSync,
        storageService: FakeEvidenceStorageService(),
        authService: mockAuth,
        sessionService: sessionService,
        connectivity: FakeConnectivity(),
      );
      addTearDown(coordinator.dispose);

      await coordinator.triggerSync(isManual: true);
      await pumpEventQueue();

      // Session MUST be invalidated because the underlying auth was invalid
      expect(container.read(sessionServiceProvider).status, equals(SessionStatus.unauthenticated));
      expect(container.read(sessionServiceProvider).terminationReason, equals(SessionTerminationReason.userDisabled));
    });

    test('Scenario 5: Network failure fails open and does NOT invalidate session or log user out', () async {
      mockAuth.emitUser(testUser);
      final sessionService = container.read(sessionServiceProvider.notifier);
      await pumpEventQueue();

      expect(container.read(sessionServiceProvider).status, equals(SessionStatus.authenticatedReady));

      // Simulate network outage during verification
      mockAuth.verificationResultToReturn = const SessionVerificationResult.networkUnreachable();

      final result = await sessionService.verifySession();

      expect(result.isNetworkUnreachable, isTrue);
      expect(result.isValid, isFalse);
      expect(mockAuth.signOutCallCount, equals(0));

      // Session MUST remain authenticatedReady
      final state = container.read(sessionServiceProvider);
      expect(state.status, equals(SessionStatus.authenticatedReady));
      expect(state.user?.uid, equals('user-001'));
      expect(state.terminationReason, isNull);
    });

    test('Concurrency & Disposal Safety: Concurrent verifySession calls share single future without races', () async {
      mockAuth.emitUser(testUser);
      final sessionService = container.read(sessionServiceProvider.notifier);
      await pumpEventQueue();

      mockAuth.verificationResultToReturn = const SessionVerificationResult.valid();
      mockAuth.verifySessionCallCount = 0;

      // Launch 5 concurrent verification calls
      final results = await Future.wait([
        sessionService.verifySession(),
        sessionService.verifySession(),
        sessionService.verifySession(),
        sessionService.verifySession(),
        sessionService.verifySession(),
      ]);

      // Only 1 call to auth service was executed
      expect(mockAuth.verifySessionCallCount, equals(1));
      for (final r in results) {
        expect(r.isValid, isTrue);
      }
      expect(container.read(sessionServiceProvider).status, equals(SessionStatus.authenticatedReady));
    });
  });
}
