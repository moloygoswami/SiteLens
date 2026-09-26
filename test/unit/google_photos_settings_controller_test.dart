import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sitelens/features/google_photos/controllers/google_photos_settings_controller.dart';
import 'package:sitelens/features/google_photos/models/google_photos_sync_entry.dart';
import 'package:sitelens/features/google_photos/models/google_photos_sync_status.dart';
import 'package:sitelens/features/google_photos/repositories/google_photos_repository.dart';
import 'package:sitelens/features/google_photos/services/google_photos_auth_service.dart';

class FakeGooglePhotosAuthService extends GooglePhotosAuthService {
  GoogleSignInAccount? mockAccount;
  bool shouldFailConnect = false;

  @override
  Future<GoogleSignInAccount?> connect() async {
    if (shouldFailConnect) throw Exception('OAuth user cancelled');
    return mockAccount;
  }

  @override
  Future<void> disconnect() async {
    mockAccount = null;
  }
}

class FakeGooglePhotosRepository implements GooglePhotosRepository {
  final List<GooglePhotosSyncEntry> entries = [];

  @override
  Future<int> countByStatus(GooglePhotosSyncStatus status, {required String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) return 0;
    return entries.where((e) => e.creatorId == creatorId && e.status == status).length;
  }

  @override
  Future<void> deleteEntry(String mediaId, {required String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) return;
    entries.removeWhere((e) => e.mediaId == mediaId && e.creatorId == creatorId);
  }

  @override
  Future<GooglePhotosSyncEntry?> getEntryForMedia(String mediaId, {required String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) return null;
    return entries.where((e) => e.mediaId == mediaId && e.creatorId == creatorId).firstOrNull;
  }

  @override
  Future<List<GooglePhotosSyncEntry>> getPendingOrFailedEntries({required String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) return [];
    return entries.where((e) => e.creatorId == creatorId && (e.status == GooglePhotosSyncStatus.pending || e.status == GooglePhotosSyncStatus.failed)).toList();
  }

  @override
  Future<void> queueMedia(String mediaId, {required String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) {
      throw GooglePhotosIsolationException('creatorId required');
    }
    entries.add(GooglePhotosSyncEntry(mediaId: mediaId, creatorId: creatorId, status: GooglePhotosSyncStatus.pending));
  }

  @override
  Future<void> updateStatus({
    required String mediaId,
    required String? creatorId,
    required GooglePhotosSyncStatus status,
    String? googlePhotosMediaId,
    DateTime? uploadedAt,
    String? errorMessage,
    bool incrementRetry = false,
  }) async {
    if (creatorId == null || creatorId.isEmpty) {
      throw GooglePhotosIsolationException('creatorId required');
    }
    final idx = entries.indexWhere((e) => e.mediaId == mediaId && e.creatorId == creatorId);
    if (idx != -1) {
      entries[idx] = entries[idx].copyWith(
        status: status,
        googlePhotosMediaId: googlePhotosMediaId,
        uploadedAt: uploadedAt,
        errorMessage: errorMessage,
      );
    }
  }

  @override
  Stream<List<GooglePhotosSyncEntry>> watchAllEntries({required String? creatorId}) {
    if (creatorId == null || creatorId.isEmpty) return Stream.value(const []);
    return Stream.value(entries.where((e) => e.creatorId == creatorId).toList());
  }

  @override
  Future<void> clearQueueForCreator(String creatorId) async {
    entries.removeWhere((e) => e.creatorId == creatorId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeGooglePhotosAuthService fakeAuth;
  late FakeGooglePhotosRepository fakeRepo;
  late GooglePhotosSettingsNotifier notifier;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeAuth = FakeGooglePhotosAuthService();
    fakeRepo = FakeGooglePhotosRepository();
    notifier = GooglePhotosSettingsNotifier(
      authService: fakeAuth,
      repository: fakeRepo,
      currentUserId: 'user_a',
      isEmailVerified: true,
    );
  });

  tearDown(() {
    notifier.dispose();
  });

  group('GooglePhotosSettingsNotifier Tests', () {
    test('Initializes with disconnected defaults (opt-in autoUpload false)', () {
      expect(notifier.state.isConnected, isFalse);
      expect(notifier.state.autoUpload, isFalse);
      expect(notifier.state.albumName, equals('SiteLens Evidence'));
      expect(notifier.state.overallStatus, equals(GooglePhotosSyncStatus.disabled));
    });

    test('Can toggle autoUpload setting and persist for user_a', () async {
      await notifier.setAutoUpload(false);
      expect(notifier.state.autoUpload, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('${GooglePhotosSettingsNotifier.keyAutoUpload}_user_a'), isFalse);

      await notifier.setAutoUpload(true);
      expect(notifier.state.autoUpload, isTrue);
    });

    test('Disconnect updates state and clears persisted email for current user', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${GooglePhotosSettingsNotifier.keyOwnerUid}_user_a', 'user_a');
      await prefs.setBool('${GooglePhotosSettingsNotifier.keyConnected}_user_a', true);
      await prefs.setString('${GooglePhotosSettingsNotifier.keyEmail}_user_a', 'inspector@example.com');

      await notifier.disconnect();

      expect(notifier.state.isConnected, isFalse);
      expect(notifier.state.accountEmail, isNull);
      expect(prefs.getBool('${GooglePhotosSettingsNotifier.keyConnected}_user_a'), isFalse);
      expect(prefs.getString('${GooglePhotosSettingsNotifier.keyEmail}_user_a'), isNull);
      expect(prefs.getString('${GooglePhotosSettingsNotifier.keyOwnerUid}_user_a'), isNull);
    });

    test('Unauthenticated user fails closed (disabled, cannot connect)', () async {
      final unauthNotifier = GooglePhotosSettingsNotifier(
        authService: fakeAuth,
        repository: fakeRepo,
        currentUserId: null,
        isEmailVerified: false,
      );

      await unauthNotifier.ready;
      expect(unauthNotifier.state.isConnected, isFalse);
      expect(unauthNotifier.state.overallStatus, equals(GooglePhotosSyncStatus.disabled));

      await unauthNotifier.connect();
      expect(unauthNotifier.state.isConnected, isFalse);
      expect(unauthNotifier.state.lastError, contains('Authentication and email verification required'));

      unauthNotifier.dispose();
    });

    test('Unverified email user fails closed (disabled, cannot connect)', () async {
      final unverifiedNotifier = GooglePhotosSettingsNotifier(
        authService: fakeAuth,
        repository: fakeRepo,
        currentUserId: 'user_unverified',
        isEmailVerified: false,
      );

      await unverifiedNotifier.ready;
      expect(unverifiedNotifier.state.isConnected, isFalse);
      expect(unverifiedNotifier.state.overallStatus, equals(GooglePhotosSyncStatus.disabled));

      await unverifiedNotifier.connect();
      expect(unverifiedNotifier.state.isConnected, isFalse);
      expect(unverifiedNotifier.state.lastError, contains('Authentication and email verification required'));

      unverifiedNotifier.dispose();
    });

    test('Legacy global SharedPreferences keys cannot reconnect a new user', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(GooglePhotosSettingsNotifier.keyConnected, true);
      await prefs.setString(GooglePhotosSettingsNotifier.keyEmail, 'legacy@example.com');

      final newNotifier = GooglePhotosSettingsNotifier(
        authService: fakeAuth,
        repository: fakeRepo,
        currentUserId: 'user_new',
        isEmailVerified: true,
      );

      await newNotifier.ready;
      expect(newNotifier.state.isConnected, isFalse);
      expect(newNotifier.state.accountEmail, isNull);

      newNotifier.dispose();
    });

    test('Account switching: User A -> User B revokes A; B inherits nothing; A must reconnect', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${GooglePhotosSettingsNotifier.keyOwnerUid}_user_a', 'user_a');
      await prefs.setBool('${GooglePhotosSettingsNotifier.keyConnected}_user_a', true);
      await prefs.setString('${GooglePhotosSettingsNotifier.keyEmail}_user_a', 'user_a@gmail.com');
      await prefs.setBool('${GooglePhotosSettingsNotifier.keyAutoUpload}_user_a', true);

      // Load User A
      await notifier.switchUser('user_a', isEmailVerified: true);
      await notifier.ready;
      expect(notifier.state.isConnected, isTrue);
      expect(notifier.state.accountEmail, equals('user_a@gmail.com'));

      // Switch to User B (unconnected): A's grant is revoked and cleared,
      // and B inherits none of A's connection state.
      await notifier.switchUser('user_b', isEmailVerified: true);
      await notifier.ready;
      expect(notifier.state.isConnected, isFalse);
      expect(notifier.state.accountEmail, isNull);
      expect(prefs.getBool('${GooglePhotosSettingsNotifier.keyConnected}_user_a'), isFalse);
      expect(prefs.getString('${GooglePhotosSettingsNotifier.keyEmail}_user_a'), isNull);

      // Switch back to User A: the revoked grant is NOT silently restored;
      // A must explicitly reconnect.
      await notifier.switchUser('user_a', isEmailVerified: true);
      await notifier.ready;
      expect(notifier.state.isConnected, isFalse);
      expect(notifier.state.accountEmail, isNull);
    });

    test('updateOverallStatus updates status and timestamps', () {
      notifier.updateOverallStatus(GooglePhotosSyncStatus.uploaded);
      expect(notifier.state.overallStatus, equals(GooglePhotosSyncStatus.uploaded));
      expect(notifier.state.lastSyncTime, isNotNull);
      expect(notifier.state.lastError, isNull);

      notifier.updateOverallStatus(GooglePhotosSyncStatus.failed, error: 'Network timeout');
      expect(notifier.state.overallStatus, equals(GooglePhotosSyncStatus.failed));
      expect(notifier.state.lastError, equals('Network timeout'));
    });
  });
}
