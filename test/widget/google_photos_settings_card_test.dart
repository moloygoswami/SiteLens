import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitelens/features/google_photos/controllers/google_photos_settings_controller.dart';
import 'package:sitelens/features/google_photos/models/google_photos_settings.dart';
import 'package:sitelens/features/google_photos/models/google_photos_sync_entry.dart';
import 'package:sitelens/features/google_photos/models/google_photos_sync_status.dart';
import 'package:sitelens/features/google_photos/repositories/google_photos_repository.dart';
import 'package:sitelens/features/google_photos/services/google_photos_auth_service.dart';
import 'package:sitelens/features/settings/widgets/google_photos_settings_card.dart';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeGooglePhotosAuthService extends GooglePhotosAuthService {
  @override
  Stream<GoogleSignInAccount?> get onCurrentUserChanged => const Stream.empty();
}

class MockGooglePhotosRepository implements GooglePhotosRepository {
  final List<GooglePhotosSyncEntry> entries;
  MockGooglePhotosRepository([this.entries = const []]);

  @override
  Future<int> countByStatus(GooglePhotosSyncStatus status) async =>
      entries.where((e) => e.status == status).length;

  @override
  Future<void> deleteEntry(String mediaId) async {}

  @override
  Future<GooglePhotosSyncEntry?> getEntryForMedia(String mediaId) async => null;

  @override
  Future<List<GooglePhotosSyncEntry>> getPendingOrFailedEntries() async => entries;

  @override
  Future<void> queueMedia(String mediaId) async {}

  @override
  Future<void> updateStatus({
    required String mediaId,
    required GooglePhotosSyncStatus status,
    String? googlePhotosMediaId,
    DateTime? uploadedAt,
    String? errorMessage,
    bool incrementRetry = false,
  }) async {}

  @override
  Stream<List<GooglePhotosSyncEntry>> watchAllEntries() => Stream.value(entries);
}

void main() {
  testWidgets('GooglePhotosSettingsCard renders disconnected state correctly', (tester) async {
    SharedPreferences.setMockInitialValues({
      GooglePhotosSettingsNotifier.keyConnected: false,
      GooglePhotosSettingsNotifier.keyAutoUpload: true,
    });

    final repo = MockGooglePhotosRepository();
    final auth = FakeGooglePhotosAuthService();
    final notifier = GooglePhotosSettingsNotifier(authService: auth, repository: repo);

    notifier.state = const GooglePhotosSettings(
      isConnected: false,
      autoUpload: true,
      overallStatus: GooglePhotosSyncStatus.disabled,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          googlePhotosSettingsProvider.overrideWith((ref) => notifier),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GooglePhotosSettingsCard(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('GOOGLE PHOTOS AUTO-SYNC'), findsOneWidget);
    expect(find.text('Google Photos Disconnected'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Automatically upload captured evidence'), findsNothing);
  });

  testWidgets('GooglePhotosSettingsCard renders connected state with toggle and status', (tester) async {
    SharedPreferences.setMockInitialValues({
      GooglePhotosSettingsNotifier.keyConnected: true,
      GooglePhotosSettingsNotifier.keyEmail: 'inspector@sitelens.io',
      GooglePhotosSettingsNotifier.keyAutoUpload: true,
    });

    final repo = MockGooglePhotosRepository([
      const GooglePhotosSyncEntry(mediaId: 'm1', status: GooglePhotosSyncStatus.pending),
      const GooglePhotosSyncEntry(mediaId: 'm2', status: GooglePhotosSyncStatus.pending),
    ]);
    final auth = FakeGooglePhotosAuthService();
    final notifier = GooglePhotosSettingsNotifier(authService: auth, repository: repo);

    notifier.state = const GooglePhotosSettings(
      isConnected: true,
      accountEmail: 'inspector@sitelens.io',
      autoUpload: true,
      pendingCount: 2,
      overallStatus: GooglePhotosSyncStatus.pending,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          googlePhotosSettingsProvider.overrideWith((ref) => notifier),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GooglePhotosSettingsCard(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connected Google Account'), findsOneWidget);
    expect(find.text('inspector@sitelens.io'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);
    expect(find.text('Automatically upload captured evidence'), findsOneWidget);
    expect(find.text('Target album: SiteLens Evidence'), findsOneWidget);
    expect(find.text('Status: Pending (2 queued)'), findsOneWidget);
    expect(find.text('Sync Now'), findsOneWidget);
  });
}
