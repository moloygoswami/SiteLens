import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/open.dart';

import 'package:sitelens/core/services/auth_service.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/features/camera/services/evidence_storage_service.dart';
import 'package:sitelens/features/google_photos/controllers/google_photos_settings_controller.dart';
import 'package:sitelens/features/google_photos/models/google_photos_sync_status.dart';
import 'package:sitelens/features/google_photos/repositories/google_photos_repository.dart';
import 'package:sitelens/features/google_photos/services/google_photos_api_service.dart';
import 'package:sitelens/features/google_photos/services/google_photos_auth_service.dart';
import 'package:sitelens/features/google_photos/services/google_photos_sync_coordinator.dart';

class FakePhotosAuthService extends GooglePhotosAuthService {}

class FakeAuthService implements AuthService {
  AuthUser? _currentUser;
  final StreamController<AuthUser?> _authController = StreamController<AuthUser?>.broadcast();

  FakeAuthService([this._currentUser]);

  @override
  AuthUser? get currentUser => _currentUser;

  void setCurrentUser(AuthUser? user) {
    _currentUser = user;
    _authController.add(user);
  }

  @override
  Stream<AuthUser?> get authStateChanges => _authController.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeGooglePhotosApiService extends GooglePhotosApiService {
  int uploadCalls = 0;
  bool shouldThrowRetryable = false;

  FakeGooglePhotosApiService() : super(authService: FakePhotosAuthService());

  @override
  Future<String> uploadBytes({required Uint8List bytes, required String mimeType}) async {
    uploadCalls++;
    if (shouldThrowRetryable) {
      throw GooglePhotosApiException('503 Service Unavailable', statusCode: 503, isRetryable: true);
    }
    return 'token_$uploadCalls';
  }

  @override
  Future<String?> getOrCreateAlbum(String albumTitle, {String? ownerUid}) async => 'album_mock';

  @override
  Future<String> createMediaItem({
    required String uploadToken,
    required String fileName,
    required String description,
    String? albumId,
  }) async {
    return 'gp_media_$uploadCalls';
  }
}

class FakeEvidenceStorageService extends EvidenceStorageService {
  final Directory tempDir;
  FakeEvidenceStorageService(this.tempDir);

  @override
  Future<Directory> getMediaDirectory() async {
    final mediaDir = Directory('${tempDir.path}/media');
    if (!mediaDir.existsSync()) {
      mediaDir.createSync(recursive: true);
    }
    return mediaDir;
  }
}

MediaItem _makeMedia(String id, String creatorId, String relativeUri) {
  return MediaItem(
    id: id,
    siteId: 'site-1',
    creatorId: creatorId,
    originalUri: relativeUri,
    uri: relativeUri,
    type: MediaItemType.photo,
    lat: 22.5726,
    lon: 88.3639,
    capturedAt: DateTime.now(),
    syncStatus: SyncStatusType.synced,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    try {
      open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
    } catch (_) {}
  });

  late AppDatabase db;
  late LocalGooglePhotosRepository gpRepo;
  late LocalMediaRepository mediaRepo;
  late Directory tempDir;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    gpRepo = LocalGooglePhotosRepository(db);
    tempDir = await Directory.systemTemp.createTemp('gphotos_isolation_test_');
    mediaRepo = LocalMediaRepository(db, storageService: FakeEvidenceStorageService(tempDir));

    // Seed site
    await db.into(db.sites).insert(
      SitesCompanion.insert(
        id: 'site-1',
        name: const drift.Value('Test Site'),
        creatorId: const drift.Value('user_a'),
      ),
    );
  });

  tearDown(() async {
    await db.close();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('Finding 1 — Google Photos Queue Creator Isolation', () {
    test('User A queue is invisible to User B', () async {
      // 1. Insert media for User A and User B
      await mediaRepo.insertMedia(_makeMedia('media_a', 'user_a', 'media/evid_a.jpg'));
      await mediaRepo.insertMedia(_makeMedia('media_b', 'user_b', 'media/evid_b.jpg'));

      // 2. Queue for User A and User B
      await gpRepo.queueMedia('media_a', creatorId: 'user_a');
      await gpRepo.queueMedia('media_b', creatorId: 'user_b');

      // 3. User B queries
      final bPending = await gpRepo.getPendingOrFailedEntries(creatorId: 'user_b');
      expect(bPending.length, equals(1));
      expect(bPending.first.mediaId, equals('media_b'));
      expect(bPending.first.creatorId, equals('user_b'));

      final bWatchList = await gpRepo.watchAllEntries(creatorId: 'user_b').first;
      expect(bWatchList.length, equals(1));
      expect(bWatchList.first.mediaId, equals('media_b'));

      final bCount = await gpRepo.countByStatus(GooglePhotosSyncStatus.pending, creatorId: 'user_b');
      expect(bCount, equals(1));

      final lookupAAsB = await gpRepo.getEntryForMedia('media_a', creatorId: 'user_b');
      expect(lookupAAsB, isNull);

      // User A sees only A
      final aPending = await gpRepo.getPendingOrFailedEntries(creatorId: 'user_a');
      expect(aPending.length, equals(1));
      expect(aPending.first.mediaId, equals('media_a'));
    });

    test('User B cannot update/delete User A queue entries', () async {
      await mediaRepo.insertMedia(_makeMedia('media_a', 'user_a', 'media/evid_a.jpg'));
      await gpRepo.queueMedia('media_a', creatorId: 'user_a');

      // User B attempts to delete User A's queue entry
      await gpRepo.deleteEntry('media_a', creatorId: 'user_b');

      // User A's entry must survive completely intact
      final entryForA = await gpRepo.getEntryForMedia('media_a', creatorId: 'user_a');
      expect(entryForA, isNotNull);
      expect(entryForA!.status, equals(GooglePhotosSyncStatus.pending));

      // User B attempts to update User A's entry status
      await gpRepo.updateStatus(
        mediaId: 'media_a',
        creatorId: 'user_b',
        status: GooglePhotosSyncStatus.failed,
        errorMessage: 'Malicious attempt to alter User A queue',
      );

      // Status for User A must remain pending, not failed
      final refreshedA = await gpRepo.getEntryForMedia('media_a', creatorId: 'user_a');
      expect(refreshedA!.status, equals(GooglePhotosSyncStatus.pending));
      expect(refreshedA.errorMessage, isNull);
    });

    test('User A sign-out removes/isolation-protects User A local queue state and prevents destructive sync by User B', () async {
      // Create actual file for media_a
      final mediaDir = Directory('${tempDir.path}/media');
      mediaDir.createSync(recursive: true);
      final fileA = File('${tempDir.path}/media/evid_a.jpg');
      fileA.writeAsBytesSync([1, 2, 3, 4]);

      await mediaRepo.insertMedia(_makeMedia('media_a', 'user_a', 'media/evid_a.jpg'));
      await gpRepo.queueMedia('media_a', creatorId: 'user_a');

      // User A signs out -> settings notifier switches to null
      SharedPreferences.setMockInitialValues({
        '${GooglePhotosSettingsNotifier.keyOwnerUid}_user_b': 'user_b',
        '${GooglePhotosSettingsNotifier.keyConnected}_user_b': true,
        '${GooglePhotosSettingsNotifier.keyAutoUpload}_user_b': true,
        '${GooglePhotosSettingsNotifier.keyEmail}_user_b': 'user_b@example.com',
      });

      final authUserB = const AuthUser(uid: 'user_b', email: 'user_b@example.com', isEmailVerified: true);
      final fakeAuth = FakeAuthService(authUserB);

      final settingsNotifier = GooglePhotosSettingsNotifier(
        authService: FakePhotosAuthService(),
        repository: gpRepo,
        currentUserId: 'user_b',
        isEmailVerified: true,
      );
      await settingsNotifier.ready;
      await Future.delayed(const Duration(milliseconds: 50));

      // User B sees 0 pending entries from User A
      expect(settingsNotifier.state.pendingCount, equals(0));

      final coordinator = GooglePhotosSyncCoordinator(
        apiService: FakeGooglePhotosApiService(),
        repository: gpRepo,
        mediaRepo: mediaRepo,
        storageService: FakeEvidenceStorageService(tempDir),
        settingsNotifier: settingsNotifier,
        authService: fakeAuth,
      );

      // User B triggers sync pass
      await coordinator.triggerSync();

      // User A's pending queue entry must NOT be deleted by User B's sync pass!
      final entryA = await gpRepo.getEntryForMedia('media_a', creatorId: 'user_a');
      expect(entryA, isNotNull);
      expect(entryA!.status, equals(GooglePhotosSyncStatus.pending));

      // Disconnecting/signing out resets coordinator state
      fakeAuth.setCurrentUser(null);
      coordinator.resetSessionState();
      await settingsNotifier.switchUser(null);
      await settingsNotifier.ready;
      expect(settingsNotifier.state.isConnected, isFalse);
      expect(settingsNotifier.state.pendingCount, equals(0));

      coordinator.dispose();
      settingsNotifier.dispose();
    });

    test('User B starts with an empty queue unless B has own queued entries', () async {
      await mediaRepo.insertMedia(_makeMedia('media_a', 'user_a', 'media/evid_a.jpg'));
      await gpRepo.queueMedia('media_a', creatorId: 'user_a');

      // User B has no entries queued
      final bPending = await gpRepo.getPendingOrFailedEntries(creatorId: 'user_b');
      expect(bPending, isEmpty);

      final bCount = await gpRepo.countByStatus(GooglePhotosSyncStatus.pending, creatorId: 'user_b');
      expect(bCount, equals(0));

      final bWatch = await gpRepo.watchAllEntries(creatorId: 'user_b').first;
      expect(bWatch, isEmpty);
    });

    test('null/empty creator fails closed across all repository operations', () async {
      await mediaRepo.insertMedia(_makeMedia('media_1', 'user_1', 'media/evid_1.jpg'));

      // Reads return empty / null / 0
      expect(await gpRepo.getPendingOrFailedEntries(creatorId: null), isEmpty);
      expect(await gpRepo.getPendingOrFailedEntries(creatorId: ''), isEmpty);

      expect(await gpRepo.getEntryForMedia('media_1', creatorId: null), isNull);
      expect(await gpRepo.getEntryForMedia('media_1', creatorId: ''), isNull);

      expect(await gpRepo.countByStatus(GooglePhotosSyncStatus.pending, creatorId: null), equals(0));
      expect(await gpRepo.countByStatus(GooglePhotosSyncStatus.pending, creatorId: ''), equals(0));

      expect(await gpRepo.watchAllEntries(creatorId: null).first, isEmpty);
      expect(await gpRepo.watchAllEntries(creatorId: '').first, isEmpty);

      // Writes throw GooglePhotosIsolationException
      expect(
        () => gpRepo.queueMedia('media_1', creatorId: null),
        throwsA(isA<GooglePhotosIsolationException>()),
      );
      expect(
        () => gpRepo.queueMedia('media_1', creatorId: ''),
        throwsA(isA<GooglePhotosIsolationException>()),
      );

      expect(
        () => gpRepo.updateStatus(mediaId: 'media_1', creatorId: null, status: GooglePhotosSyncStatus.failed),
        throwsA(isA<GooglePhotosIsolationException>()),
      );
      expect(
        () => gpRepo.updateStatus(mediaId: 'media_1', creatorId: '', status: GooglePhotosSyncStatus.failed),
        throwsA(isA<GooglePhotosIsolationException>()),
      );

      // Delete with null/empty is a safe no-op
      await gpRepo.deleteEntry('media_1', creatorId: null);
      await gpRepo.deleteEntry('media_1', creatorId: '');
    });

    test('existing retry/backoff behavior remains intact with creator scoping', () async {
      final file = File('${tempDir.path}/media/evid_retry.jpg');
      Directory('${tempDir.path}/media').createSync(recursive: true);
      file.writeAsBytesSync([10, 20, 30]);

      await mediaRepo.insertMedia(_makeMedia('media_retry', 'user_a', 'media/evid_retry.jpg'));
      await gpRepo.queueMedia('media_retry', creatorId: 'user_a');

      SharedPreferences.setMockInitialValues({
        '${GooglePhotosSettingsNotifier.keyOwnerUid}_user_a': 'user_a',
        '${GooglePhotosSettingsNotifier.keyConnected}_user_a': true,
        '${GooglePhotosSettingsNotifier.keyAutoUpload}_user_a': true,
        '${GooglePhotosSettingsNotifier.keyEmail}_user_a': 'user_a@example.com',
      });

      final authUserA = const AuthUser(uid: 'user_a', email: 'user_a@example.com', isEmailVerified: true);
      final fakeAuth = FakeAuthService(authUserA);

      final settingsNotifier = GooglePhotosSettingsNotifier(
        authService: FakePhotosAuthService(),
        repository: gpRepo,
        currentUserId: 'user_a',
        isEmailVerified: true,
      );
      await settingsNotifier.ready;

      final fakeApi = FakeGooglePhotosApiService();
      fakeApi.shouldThrowRetryable = true;

      final coordinator = GooglePhotosSyncCoordinator(
        apiService: fakeApi,
        repository: gpRepo,
        mediaRepo: mediaRepo,
        storageService: FakeEvidenceStorageService(tempDir),
        settingsNotifier: settingsNotifier,
        authService: fakeAuth,
      );

      // Trigger sync which hits 503 retryable
      await coordinator.triggerSync();

      final entry = await gpRepo.getEntryForMedia('media_retry', creatorId: 'user_a');
      expect(entry, isNotNull);
      expect(entry!.status, equals(GooglePhotosSyncStatus.pending));
      expect(entry.retryCount, equals(1));
      expect(entry.errorMessage, contains('503 Service Unavailable'));
      expect(entry.lastAttemptAt, isNotNull);

      coordinator.dispose();
      settingsNotifier.dispose();
    });
  });
}
