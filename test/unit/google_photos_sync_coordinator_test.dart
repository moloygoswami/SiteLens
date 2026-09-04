import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sitelens/core/services/auth_service.dart';
import 'package:sitelens/core/utils/crypto_utils.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/features/camera/services/evidence_storage_service.dart';
import 'package:sitelens/features/google_photos/controllers/google_photos_settings_controller.dart';
import 'package:sitelens/features/google_photos/models/google_photos_sync_entry.dart';
import 'package:sitelens/features/google_photos/models/google_photos_sync_status.dart';
import 'package:sitelens/features/google_photos/repositories/google_photos_repository.dart';
import 'package:sitelens/features/google_photos/services/google_photos_api_service.dart';
import 'package:sitelens/features/google_photos/services/google_photos_auth_service.dart';
import 'package:sitelens/features/google_photos/services/google_photos_sync_coordinator.dart';

class MockGooglePhotosApiService extends GooglePhotosApiService {
  int uploadBytesCalls = 0;
  int createMediaItemCalls = 0;
  int getOrCreateAlbumCalls = 0;
  String? lastCreatedDescription;
  String? lastCreatedAlbumId;
  bool shouldThrowAuth = false;
  bool shouldThrowRetryable = false;
  bool shouldThrowPermanent = false;
  bool shouldThrowAlbumError = false;
  bool shouldFailMediaCreation = false;
  int invalidateAlbumCalls = 0;
  String currentAlbumId = 'mock_album_old';

  MockGooglePhotosApiService({required super.authService});

  @override
  Future<String> uploadBytes({required Uint8List bytes, required String mimeType}) async {
    uploadBytesCalls++;
    if (shouldThrowAuth) throw GooglePhotosAuthException('Token expired');
    if (shouldThrowRetryable) throw GooglePhotosApiException('503 Service Unavailable', statusCode: 503, isRetryable: true);
    if (shouldThrowPermanent) throw GooglePhotosApiException('400 Bad Request', statusCode: 400);
    return 'mock_upload_token_$uploadBytesCalls';
  }

  @override
  Future<String?> getOrCreateAlbum(String albumTitle) async {
    getOrCreateAlbumCalls++;
    return currentAlbumId;
  }

  @override
  Future<void> invalidateAlbumId() async {
    invalidateAlbumCalls++;
    currentAlbumId = 'mock_album_new';
  }

  @override
  Future<String> createMediaItem({
    required String uploadToken,
    required String fileName,
    required String description,
    String? albumId,
  }) async {
    createMediaItemCalls++;
    lastCreatedDescription = description;
    lastCreatedAlbumId = albumId;
    if (albumId == null) {
      throw GooglePhotosApiException('Uploads outside album are strictly prohibited.');
    }
    if (shouldThrowAlbumError && albumId == 'mock_album_old') {
      throw GooglePhotosApiException('Album not found (404)');
    }
    if (shouldFailMediaCreation) {
      throw GooglePhotosApiException('Media creation error (code: 3): INVALID_ARGUMENT');
    }
    return 'gp_media_id_$createMediaItemCalls';
  }
}

class MockGooglePhotosRepository implements GooglePhotosRepository {
  final Map<String, GooglePhotosSyncEntry> store = {};

  @override
  Future<int> countByStatus(GooglePhotosSyncStatus status) async {
    return store.values.where((e) => e.status == status).length;
  }

  @override
  Future<void> deleteEntry(String mediaId) async {
    store.remove(mediaId);
  }

  @override
  Future<GooglePhotosSyncEntry?> getEntryForMedia(String mediaId) async {
    return store[mediaId];
  }

  @override
  Future<List<GooglePhotosSyncEntry>> getPendingOrFailedEntries() async {
    return store.values.where((e) => e.status == GooglePhotosSyncStatus.pending || e.status == GooglePhotosSyncStatus.failed).toList();
  }

  @override
  Future<void> queueMedia(String mediaId) async {
    store[mediaId] = GooglePhotosSyncEntry(mediaId: mediaId, status: GooglePhotosSyncStatus.pending);
  }

  @override
  Future<void> updateStatus({
    required String mediaId,
    required GooglePhotosSyncStatus status,
    String? googlePhotosMediaId,
    DateTime? uploadedAt,
    String? errorMessage,
    bool incrementRetry = false,
  }) async {
    final existing = store[mediaId] ?? GooglePhotosSyncEntry(mediaId: mediaId, status: status);
    store[mediaId] = existing.copyWith(
      status: status,
      googlePhotosMediaId: googlePhotosMediaId,
      uploadedAt: uploadedAt,
      errorMessage: errorMessage,
      retryCount: incrementRetry ? existing.retryCount + 1 : existing.retryCount,
    );
  }

  @override
  Stream<List<GooglePhotosSyncEntry>> watchAllEntries() {
    return Stream.value(store.values.toList());
  }
}

class MockMediaRepository implements MediaRepository {
  final Map<String, MediaItem> mediaMap = {};

  @override
  Future<MediaItem?> getMediaById(String id) async => mediaMap[id];

  @override
  Future<List<MediaItem>> getAllMediaEntriesIncludingDeleted({String? creatorId}) async {
    if (creatorId != null && creatorId.isNotEmpty) {
      return mediaMap.values.where((m) => m.creatorId == creatorId).toList();
    }
    return mediaMap.values.toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeGooglePhotosAuthService extends GooglePhotosAuthService {
  GoogleSignInAccount? mockAccount;

  @override
  Future<GoogleSignInAccount?> connect() async => mockAccount;

  @override
  Future<void> disconnect() async {
    mockAccount = null;
  }
}

class FakeAuthService implements AuthService {
  AuthUser? mockUser;

  FakeAuthService({this.mockUser});

  @override
  AuthUser? get currentUser => mockUser;

  @override
  Stream<AuthUser?> get authStateChanges => Stream.value(mockUser);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockEvidenceStorageService extends EvidenceStorageService {
  late Directory tempDir;

  MockEvidenceStorageService(this.tempDir);

  @override
  Future<Directory> getMediaDirectory() async {
    final mediaDir = Directory('${tempDir.path}/media');
    if (!mediaDir.existsSync()) mediaDir.createSync(recursive: true);
    return mediaDir;
  }
}

/// Test-only notifier that can simulate the account becoming connected
/// without going through the real Google Sign-In flow.
class TestGooglePhotosSettingsNotifier extends GooglePhotosSettingsNotifier {
  TestGooglePhotosSettingsNotifier({
    required super.authService,
    required super.repository,
    super.currentUserId = 'user_a',
    super.isEmailVerified = true,
  });

  void simulateConnect() {
    state = state.copyWith(
      isConnected: true,
      autoUpload: true,
      accountEmail: 'inspector@sitelens.io',
      overallStatus: GooglePhotosSyncStatus.pending,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MockGooglePhotosApiService fakeApi;
  late MockGooglePhotosRepository fakeRepo;
  late MockMediaRepository fakeMediaRepo;
  late MockEvidenceStorageService fakeStorage;
  late FakeGooglePhotosAuthService fakePhotosAuth;
  late FakeAuthService fakeAuth;
  late GooglePhotosSettingsNotifier settingsNotifier;
  late GooglePhotosSyncCoordinator coordinator;

  final testEvidenceBytes = Uint8List.fromList([10, 20, 30, 40, 50]);
  final testEvidenceSha = CryptoUtils.computeSha256(testEvidenceBytes);

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      '${GooglePhotosSettingsNotifier.keyOwnerUid}_user_a': 'user_a',
      '${GooglePhotosSettingsNotifier.keyConnected}_user_a': true,
      '${GooglePhotosSettingsNotifier.keyAutoUpload}_user_a': true,
      '${GooglePhotosSettingsNotifier.keyEmail}_user_a': 'inspector@sitelens.io',
    });

    tempDir = await Directory.systemTemp.createTemp('gphotos_test_');
    final mediaDir = Directory('${tempDir.path}/media');
    await mediaDir.create(recursive: true);

    final evidFile = File('${mediaDir.path}/evid_m1.jpg');
    await evidFile.writeAsBytes(testEvidenceBytes);

    fakePhotosAuth = FakeGooglePhotosAuthService();
    fakeApi = MockGooglePhotosApiService(authService: fakePhotosAuth);
    fakeRepo = MockGooglePhotosRepository();
    fakeMediaRepo = MockMediaRepository();
    fakeStorage = MockEvidenceStorageService(tempDir);
    fakeAuth = FakeAuthService()
      ..mockUser = const AuthUser(
        uid: 'user_a',
        email: 'inspector@sitelens.io',
        isEmailVerified: true,
      );

    fakeMediaRepo.mediaMap['m1'] = MediaItem(
      id: 'm1',
      siteId: 'site-1',
      creatorId: 'user_a',
      originalUri: 'media/orig_m1.jpg',
      uri: 'media/evid_m1.jpg',
      thumbUri: 'media/thumb_m1.jpg',
      type: MediaItemType.photo,
      lat: 22.5,
      lon: 88.3,
      capturedAt: DateTime.utc(2026, 8, 20),
      sha256Hash: 'orig_hash',
      evidenceSha256Hash: testEvidenceSha,
      syncStatus: SyncStatusType.pending,
      isDeleted: false,
    );

    settingsNotifier = GooglePhotosSettingsNotifier(
      authService: fakePhotosAuth,
      repository: fakeRepo,
      currentUserId: 'user_a',
      isEmailVerified: true,
    );
    await Future.delayed(Duration.zero);

    coordinator = GooglePhotosSyncCoordinator(
      apiService: fakeApi,
      repository: fakeRepo,
      mediaRepo: fakeMediaRepo,
      storageService: fakeStorage,
      settingsNotifier: settingsNotifier,
      authService: fakeAuth,
    );
  });

  tearDown(() async {
    coordinator.dispose();
    settingsNotifier.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('GooglePhotosSyncCoordinator Tests', () {
    test('Queues media and performs upload when online and connected', () async {
      await coordinator.onMediaCaptured('m1');

      expect(fakeRepo.store.containsKey('m1'), isTrue);
      expect(fakeApi.uploadBytesCalls, equals(1));
      expect(fakeApi.createMediaItemCalls, equals(1));
      expect(fakeRepo.store['m1']?.status, equals(GooglePhotosSyncStatus.uploaded));
      expect(fakeRepo.store['m1']?.googlePhotosMediaId, equals('gp_media_id_1'));
    });

    test('Transitions to authRequired on 401/403 token expiration', () async {
      fakeApi.shouldThrowAuth = true;

      await coordinator.onMediaCaptured('m1');

      expect(fakeRepo.store['m1']?.status, equals(GooglePhotosSyncStatus.authRequired));
      expect(settingsNotifier.state.overallStatus, equals(GooglePhotosSyncStatus.authRequired));
    });

    test('Exponential backoff for retryable 503 errors and transitions to pending', () async {
      fakeApi.shouldThrowRetryable = true;

      await coordinator.onMediaCaptured('m1');

      expect(fakeRepo.store['m1']?.status, equals(GooglePhotosSyncStatus.pending));
      expect(fakeRepo.store['m1']?.retryCount, equals(1));
      expect(fakeRepo.store['m1']?.errorMessage, contains('503 Service Unavailable'));
    });

    test('Permanent failure on 400 Bad Request', () async {
      fakeApi.shouldThrowPermanent = true;

      await coordinator.onMediaCaptured('m1');

      expect(fakeRepo.store['m1']?.status, equals(GooglePhotosSyncStatus.failed));
      expect(fakeRepo.store['m1']?.errorMessage, contains('400 Bad Request'));
      expect(settingsNotifier.state.overallStatus, equals(GooglePhotosSyncStatus.failed));
    });

    test('Recovers from deleted album by invalidating cached ID and re-uploading', () async {
      fakeApi.shouldThrowAlbumError = true;

      await coordinator.onMediaCaptured('m1');

      expect(fakeApi.invalidateAlbumCalls, equals(1));
      expect(fakeApi.createMediaItemCalls, equals(2));
      expect(fakeRepo.store['m1']?.status, equals(GooglePhotosSyncStatus.uploaded));
    });

    test('Rejects upload on evidence SHA-256 hash mismatch and marks entry failed', () async {
      fakeMediaRepo.mediaMap['m1'] = fakeMediaRepo.mediaMap['m1']!.copyWith(
        evidenceSha256Hash: 'corrupted_tampered_hash',
      );

      await coordinator.onMediaCaptured('m1');

      expect(fakeApi.uploadBytesCalls, equals(0));
      expect(fakeRepo.store['m1']?.status, equals(GooglePhotosSyncStatus.failed));
      expect(fakeRepo.store['m1']?.errorMessage, equals('Evidence SHA-256 hash mismatch.'));
    });

    test('User author note is passed as description and no GPS/technical data is leaked', () async {
      fakeMediaRepo.mediaMap['m1'] = fakeMediaRepo.mediaMap['m1']!.copyWith(
        note: 'Rebar placement verified at Column 4B',
      );

      await coordinator.onMediaCaptured('m1');

      expect(fakeApi.lastCreatedDescription, equals('Rebar placement verified at Column 4B'));
    });

    test('Safe fail-closed: If account is disconnected during queue execution, uploads abort', () async {
      await settingsNotifier.disconnect();

      await coordinator.onMediaCaptured('m1');

      expect(fakeApi.uploadBytesCalls, equals(0));
      expect(fakeApi.createMediaItemCalls, equals(0));
    });

    test('onMediaCaptured awaits settings resolution before deciding whether to upload', () async {
      SharedPreferences.setMockInitialValues({
        '${GooglePhotosSettingsNotifier.keyOwnerUid}_user_a': 'user_a',
        '${GooglePhotosSettingsNotifier.keyConnected}_user_a': true,
        '${GooglePhotosSettingsNotifier.keyAutoUpload}_user_a': true,
        '${GooglePhotosSettingsNotifier.keyEmail}_user_a': 'inspector@sitelens.io',
      });

      final notifier = GooglePhotosSettingsNotifier(
        authService: GooglePhotosAuthService(),
        repository: fakeRepo,
        currentUserId: 'user_a',
        isEmailVerified: true,
      );
      final coordinator = GooglePhotosSyncCoordinator(
        apiService: fakeApi,
        repository: fakeRepo,
        mediaRepo: fakeMediaRepo,
        storageService: fakeStorage,
        settingsNotifier: notifier,
        authService: fakeAuth,
      );

      await coordinator.onMediaCaptured('m1');

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(fakeRepo.store.containsKey('m1'), isTrue);
      expect(fakeApi.uploadBytesCalls, equals(1));
      expect(fakeApi.createMediaItemCalls, equals(1));

      coordinator.dispose();
      notifier.dispose();
    });

    test('Catch-up sync uploads media captured before the account was connected', () async {
      SharedPreferences.setMockInitialValues({});

      final notifier = TestGooglePhotosSettingsNotifier(
        authService: GooglePhotosAuthService(),
        repository: fakeRepo,
        currentUserId: 'user_a',
        isEmailVerified: true,
      );
      await Future.delayed(Duration.zero);
      final coordinator = GooglePhotosSyncCoordinator(
        apiService: fakeApi,
        repository: fakeRepo,
        mediaRepo: fakeMediaRepo,
        storageService: fakeStorage,
        settingsNotifier: notifier,
        authService: fakeAuth,
      );

      expect(fakeRepo.store.containsKey('m1'), isFalse);

      notifier.simulateConnect();

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(fakeRepo.store.containsKey('m1'), isTrue);
      expect(fakeApi.uploadBytesCalls, equals(1));
      expect(fakeRepo.store['m1']?.status, equals(GooglePhotosSyncStatus.uploaded));

      coordinator.dispose();
      notifier.dispose();
    });

    test('Multi-User Isolation: User B cannot upload User A media, and User A cannot upload User B media', () async {
      fakeMediaRepo.mediaMap['m2_user_b'] = MediaItem(
        id: 'm2_user_b',
        siteId: 'site-1',
        creatorId: 'user_b',
        originalUri: 'media/orig_m2.jpg',
        uri: 'media/evid_m2.jpg',
        thumbUri: 'media/thumb_m2.jpg',
        type: MediaItemType.photo,
        lat: 22.5,
        lon: 88.3,
        capturedAt: DateTime.utc(2026, 8, 21),
        sha256Hash: 'orig_hash_2',
        evidenceSha256Hash: testEvidenceSha,
        syncStatus: SyncStatusType.pending,
        isDeleted: false,
      );

      await coordinator.triggerSync();

      expect(fakeRepo.store.containsKey('m1'), isTrue);
      expect(fakeRepo.store.containsKey('m2_user_b'), isFalse);
    });

    test('Unauthenticated user cannot trigger sync or upload evidence', () async {
      fakeAuth.mockUser = null;

      await coordinator.triggerSync();

      expect(fakeApi.uploadBytesCalls, equals(0));
    });

    test('Unverified email user cannot trigger sync or upload evidence', () async {
      fakeAuth.mockUser = const AuthUser(
        uid: 'user_unverified',
        email: 'unverified@example.com',
        isEmailVerified: false,
      );

      await coordinator.triggerSync();

      expect(fakeApi.uploadBytesCalls, equals(0));
    });
  });
}
