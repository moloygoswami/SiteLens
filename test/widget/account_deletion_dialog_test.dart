import 'dart:ffi' show DynamicLibrary;
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/open.dart';
import 'package:sitelens/core/services/auth_service.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/local/database/database_provider.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/data/repositories/site_repository.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/domain/models/site_model.dart';
import 'package:sitelens/features/camera/services/evidence_storage_service.dart';
import 'package:sitelens/features/settings/settings_screen.dart';
import 'package:sitelens/features/settings/widgets/account_deletion_dialog.dart';
import 'package:sitelens/features/sites/site_controller.dart';
import 'package:sitelens/features/sync/services/cloud_sync_service.dart';
import 'package:sitelens/features/sync/services/sync_coordinator.dart';

class FakeTestAuthService implements AuthService {
  final AuthUser _user = const AuthUser(
    uid: 'test-deletion-uid-12345',
    email: 'inspector@company.com',
    displayName: 'Lead Inspector',
  );

  bool isPassword = true;
  bool reauthenticateCalled = false;
  bool deleteAccountCalled = false;

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> get authStateChanges => Stream.value(_user);

  @override
  Future<void> signOut() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMediaRepo implements MediaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
  @override
  Stream<int> watchUnsyncedCount({String? creatorId}) => Stream.value(0);
  @override
  Future<List<MediaItem>> getPendingOrFailedMedia({String? creatorId}) async => [];
  @override
  Future<void> resetStuckSyncingMedia() async {}
}

class FakeCloudSync implements CloudSyncService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class FakeStorage implements EvidenceStorageService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class MockSyncCoordinator extends SyncCoordinator {
  MockSyncCoordinator()
      : super(
          mediaRepo: FakeMediaRepo(),
          cloudSyncService: FakeCloudSync(),
          storageService: FakeStorage(),
          authService: FakeTestAuthService(),
        );

  @override
  Future<void> triggerSync({bool isManual = false}) async {}
}

void main() {
  const testSite = SiteModel(
    id: 'site-del-test',
    siteCode: 'SL-DEL',
    name: 'Demolition Zone',
    address: '100 Warning Blvd',
  );

  late AppDatabase db;
  late FakeTestAuthService fakeAuthService;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'sitelens_active_site_id': 'site-del-test'});
    db = AppDatabase(NativeDatabase.memory());
    fakeAuthService = FakeTestAuthService();
  });

  tearDown(() async {
    await db.close();
  });

  Widget buildDialogTestWidget({
    bool? isPasswordOverride,
    Future<Map<String, dynamic>> Function()? onDeleteAccount,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: AccountDeletionDialog(
          authService: fakeAuthService,
          appDatabase: db,
          isPasswordProvider: isPasswordOverride ?? fakeAuthService.isPassword,
          onReauthenticateWithPassword: (pw) async {
            fakeAuthService.reauthenticateCalled = true;
          },
          onReauthenticateWithGoogle: () async {
            fakeAuthService.reauthenticateCalled = true;
          },
          onDeleteAccount: onDeleteAccount ??
              () async {
                fakeAuthService.deleteAccountCalled = true;
                return {'success': true};
              },
        ),
      ),
    );
  }

  Widget buildSettingsTestWidget() {
    return ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(fakeAuthService),
        appDatabaseProvider.overrideWithValue(db),
        siteRepositoryProvider.overrideWithValue(MockSiteRepository(testSite)),
        siteControllerProvider.overrideWith((ref) => SiteController(MockSiteRepository(testSite))),
        syncCoordinatorProvider.overrideWith((ref) => MockSyncCoordinator()),
      ],
      child: const MaterialApp(
        home: SettingsScreen(),
      ),
    );
  }

  group('AccountDeletionDialog Widget Tests', () {
    testWidgets('1. Renders destructive warning, bullet items, and password field for password user', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      fakeAuthService.isPassword = true;

      await tester.pumpWidget(buildDialogTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Delete Account'), findsOneWidget);
      expect(find.text('This action is irreversible. Upon confirmation:'), findsOneWidget);
      expect(find.textContaining('Your authentication credentials and user profile will be permanently deleted.'), findsOneWidget);
      expect(find.textContaining('All sites you own, together with their cloud-stored originals'), findsOneWidget);
      expect(find.text('Confirm your password to proceed:'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('DELETE'), findsOneWidget);
    });

    testWidgets('2. Enforces password entry before deletion proceeds', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      fakeAuthService.isPassword = true;

      await tester.pumpWidget(buildDialogTestWidget());
      await tester.pumpAndSettle();

      // Tap DELETE without entering password
      await tester.tap(find.text('DELETE'));
      await tester.pumpAndSettle();

      // Form validation error should appear
      expect(find.text('Password is required to confirm deletion'), findsOneWidget);
      expect(fakeAuthService.deleteAccountCalled, isFalse);
    });

    testWidgets('3. Displays Google re-auth prompt when isPasswordProvider is false', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      fakeAuthService.isPassword = false;

      await tester.pumpWidget(buildDialogTestWidget(isPasswordOverride: false));
      await tester.pumpAndSettle();

      expect(find.text('You will be prompted to re-authenticate with Google before deletion.'), findsOneWidget);
      expect(find.text('Confirm your password to proceed:'), findsNothing);
    });

    testWidgets('4. SettingsScreen displays DELETE ACCOUNT button in USER section', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildSettingsTestWidget());
      await tester.pumpAndSettle();

      // Verify DELETE ACCOUNT button exists
      final deleteBtn = find.text('DELETE ACCOUNT');
      expect(deleteBtn, findsOneWidget);

      // Tap DELETE ACCOUNT button and ensure modal opens
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      expect(find.text('This action is irreversible. Upon confirmation:'), findsOneWidget);
    });

    testWidgets('5. R23: a failed remote deletion never purges local evidence', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Local evidence that must survive a failed remote deletion.
      await db.into(db.sites).insert(
            SitesCompanion.insert(
              id: 'site-survives',
              siteCode: const drift.Value('SL-SURV'),
              name: const drift.Value('Surviving Site'),
              address: const drift.Value('Nowhere'),
              creatorId: const drift.Value('test-deletion-uid-12345'),
            ),
          );

      fakeAuthService.isPassword = true;

      await tester.pumpWidget(buildDialogTestWidget(
        onDeleteAccount: () async {
          throw Exception('Account deletion incomplete: required remote cleanup failed.');
        },
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'secret-password');
      await tester.tap(find.text('DELETE'));
      await tester.pumpAndSettle();

      // The remote deletion reported failure: no successful local purge may
      // follow, and the failure must be surfaced to the user.
      expect(await db.select(db.sites).get(), isNotEmpty);
      expect(find.textContaining('Account deletion failed'), findsOneWidget);
    });
  });
}

class MockSiteRepository implements SiteRepository {
  final SiteModel site;
  MockSiteRepository(this.site);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  @override
  Future<List<SiteModel>> getAllSites({String? creatorId}) async => [site];

  @override
  Future<SiteModel?> getSiteById(String id, {String? creatorId}) async => site;

  @override
  Future<void> saveSite(SiteModel s) async {}
}
