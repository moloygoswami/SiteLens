import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sitelens/app/app.dart';
import 'package:sitelens/core/services/auth_service.dart';
import 'package:sitelens/core/services/permission_service.dart';
import 'package:sitelens/core/services/session_service.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/features/camera/services/evidence_storage_service.dart';
import 'package:sitelens/features/sync/services/cloud_sync_service.dart';
import 'package:sitelens/features/sync/services/sync_coordinator.dart';

class MockAuthService implements AuthService {
  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? _user;

  MockAuthService([this._user]);

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  void emitUser(AuthUser? user) {
    _user = user;
    _controller.add(user);
  }

  @override
  Future<void> signOut() async => emitUser(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockPermissionService extends PermissionService {
  SiteLensPermissionStatus mockStatus = const SiteLensPermissionStatus(
    camera: PermissionStatus.granted,
    location: PermissionStatus.granted,
  );

  @override
  Future<SiteLensPermissionStatus> checkAllPermissions() async {
    state = mockStatus;
    return mockStatus;
  }
}

class RecordingMediaRepository implements MediaRepository {
  final List<MediaItem> items = [];
  int resetCallCount = 0;
  final _countController = StreamController<int>.broadcast();

  void seed(List<MediaItem> seeded) {
    items
      ..clear()
      ..addAll(seeded);
    _emitCount();
  }

  void _emitCount() {
    if (!_countController.isClosed) {
      _countController.add(
        items.where((i) => !i.isDeleted && i.syncStatus == SyncStatusType.pending).length,
      );
    }
  }

  @override
  Future<void> resetStuckSyncingMedia() async {
    resetCallCount++;
    for (int i = 0; i < items.length; i++) {
      if (items[i].syncStatus == SyncStatusType.syncing) {
        items[i] = items[i].copyWith(syncStatus: SyncStatusType.pending);
      }
    }
    _emitCount();
  }

  @override
  Stream<int> watchUnsyncedCount({String? creatorId}) => _countController.stream;

  @override
  Future<List<MediaItem>> getPendingOrFailedMedia({String? creatorId}) async {
    return items.where((i) {
      if (i.isDeleted) return false;
      if (i.syncStatus == SyncStatusType.synced) return false;
      if (creatorId != null && i.creatorId != null && i.creatorId != creatorId) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<void> updateSyncStatus(String mediaId, SyncStatusType status) async {
    final index = items.indexWhere((i) => i.id == mediaId);
    if (index != -1) {
      items[index] = items[index].copyWith(syncStatus: status);
    }
    _emitCount();
  }

  @override
  Future<List<MediaItem>> getTombstoneSyncCandidates({String? creatorId}) async => const [];

  @override
  Stream<int> watchTombstoneCandidateCount({String? creatorId}) => const Stream<int>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RecordingCloudSyncService implements CloudSyncService {
  int syncCallCount = 0;
  final List<String> syncedMediaIds = [];

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
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeEvidenceStorageService extends EvidenceStorageService {
  final Directory mediaDir;

  FakeEvidenceStorageService(this.mediaDir);

  @override
  Future<Directory> getMediaDirectory() async => mediaDir;

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

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAuthService mockAuth;
  late MockPermissionService mockPermission;
  late RecordingMediaRepository fakeRepo;
  late RecordingCloudSyncService fakeCloud;
  late FakeEvidenceStorageService fakeStorage;
  late FakeConnectivity fakeConnectivity;
  late ProviderContainer container;
  late Directory tempDir;
  int coordinatorInstanceCount = 0;

  const testUser = AuthUser(uid: 'user-123', email: 'eng@sitelens.local');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('sync_bootstrap_test_');
    mockAuth = MockAuthService();
    mockPermission = MockPermissionService();
    fakeRepo = RecordingMediaRepository();
    fakeCloud = RecordingCloudSyncService();
    fakeStorage = FakeEvidenceStorageService(Directory('${tempDir.path}/media'));
    fakeConnectivity = FakeConnectivity();
    coordinatorInstanceCount = 0;

    container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(mockAuth),
        permissionServiceProvider.overrideWith((ref) => mockPermission),
        sessionServiceProvider.overrideWith((ref) => SessionService(mockAuth, ref)),
        mediaRepositoryProvider.overrideWithValue(fakeRepo),
        cloudSyncServiceProvider.overrideWith((ref) => fakeCloud),
        evidenceStorageServiceProvider.overrideWithValue(fakeStorage),
        syncCoordinatorProvider.overrideWith((ref) {
          coordinatorInstanceCount++;
          return SyncCoordinator(
            mediaRepo: fakeRepo,
            cloudSyncService: fakeCloud,
            storageService: fakeStorage,
            authService: mockAuth,
            connectivity: fakeConnectivity,
          );
        }),
      ],
    );
    container.listen(sessionServiceProvider, (_, __) {});
  });

  tearDown(() async {
    container.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget buildBootstrap() {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: SyncLifecycleBootstrap(child: SizedBox()),
      ),
    );
  }

  MediaItem stuckItem(String id) => MediaItem(
        id: id,
        siteId: 'site-1',
        originalUri: 'media/orig_$id.jpg',
        uri: 'media/evid_$id.jpg',
        type: MediaItemType.photo,
        lat: 22.5,
        lon: 88.3,
        capturedAt: DateTime.now(),
        creatorId: 'user-123',
        syncStatus: SyncStatusType.syncing,
      );

  group('F3 Sync Lifecycle Bootstrap Tests', () {
    testWidgets(
        'Authenticated startup initializes sync recovery and resets stuck rows without opening Gallery',
        (tester) async {
      fakeConnectivity.currentResults = [ConnectivityResult.none];
      mockAuth.emitUser(testUser);
      fakeRepo.seed([stuckItem('m-stuck')]);

      await tester.pumpWidget(buildBootstrap());
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      // Exactly one coordinator instance, with the crash-recovery hook executed
      expect(coordinatorInstanceCount, equals(1));
      expect(fakeRepo.resetCallCount, equals(1));

      // The syncing=2 row was normalized to pending and is queue-discoverable
      expect(fakeRepo.items.single.syncStatus, equals(SyncStatusType.pending));
      final queue = await fakeRepo.getPendingOrFailedMedia(creatorId: 'user-123');
      expect(queue.single.id, equals('m-stuck'));

      // Offline: no upload attempt is made
      expect(fakeCloud.syncCallCount, equals(0));
    });

    testWidgets(
        'Unauthenticated startup does not initialize evidence synchronization',
        (tester) async {
      fakeRepo.seed([stuckItem('m-stuck-noauth')]);

      await tester.pumpWidget(buildBootstrap());
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      expect(coordinatorInstanceCount, equals(0));
      expect(fakeRepo.resetCallCount, equals(0));
      // The row is untouched by any synchronization lifecycle
      expect(fakeRepo.items.single.syncStatus, equals(SyncStatusType.syncing));
    });

    testWidgets('Logout prevents further synchronization', (tester) async {
      mockAuth.emitUser(testUser);
      fakeRepo.seed([stuckItem('m-pre-logout')]);

      await tester.pumpWidget(buildBootstrap());
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      // Authenticated startup recovered and uploaded the stuck item
      expect(coordinatorInstanceCount, equals(1));
      expect(fakeCloud.syncCallCount, equals(1));

      await mockAuth.signOut();
      await tester.pumpAndSettle();

      // A new pending capture after logout must not be synchronized
      fakeRepo.seed([
        MediaItem(
          id: 'm-after-logout',
          siteId: 'site-1',
          originalUri: 'media/orig_after.jpg',
          uri: 'media/evid_after.jpg',
          type: MediaItemType.photo,
          lat: 22.5,
          lon: 88.3,
          capturedAt: DateTime.now(),
          creatorId: 'user-123',
          syncStatus: SyncStatusType.pending,
        ),
      ]);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      expect(fakeCloud.syncCallCount, equals(1));
      expect(fakeRepo.items.single.syncStatus, equals(SyncStatusType.pending));
    });

    testWidgets(
        'Repeated session transitions do not create duplicate coordinators or subscriptions',
        (tester) async {
      mockAuth.emitUser(testUser);
      fakeRepo.seed([stuckItem('m-repeated')]);

      await tester.pumpWidget(buildBootstrap());
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      expect(coordinatorInstanceCount, equals(1));

      // Logout then re-authenticate
      await mockAuth.signOut();
      await tester.pumpAndSettle();
      mockAuth.emitUser(testUser);
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      // Same single coordinator instance serves the re-authenticated session
      expect(coordinatorInstanceCount, equals(1));
      // The idempotent recovery hook runs again for the new session
      expect(fakeRepo.resetCallCount, equals(2));
    });
  });
}
