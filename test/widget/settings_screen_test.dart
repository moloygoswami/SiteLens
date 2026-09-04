import 'dart:ffi' show DynamicLibrary;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/open.dart';
import 'package:sitelens/core/services/auth_service.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/data/repositories/site_repository.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/domain/models/site_model.dart';
import 'package:sitelens/features/camera/services/evidence_storage_service.dart';
import 'package:sitelens/features/camera/widgets/gps_settings_modal.dart';
import 'package:sitelens/features/camera/widgets/timestamp_settings_modal.dart';
import 'package:sitelens/features/settings/settings_screen.dart';
import 'package:sitelens/features/settings/widgets/storage_settings_modal.dart';
import 'package:sitelens/features/sites/site_controller.dart';
import 'package:sitelens/features/sync/services/cloud_sync_service.dart';
import 'package:sitelens/features/sync/services/sync_coordinator.dart';

class FakeSyncCoordinator extends SyncCoordinator {
  int syncTriggeredCount = 0;

  FakeSyncCoordinator({
    required super.mediaRepo,
    required super.cloudSyncService,
    required super.storageService,
    required super.authService,
  }) : super();

  @override
  Future<void> triggerSync({bool isManual = false}) async {
    syncTriggeredCount++;
  }
}

void main() {
  const testSite = SiteModel(
    id: 'site-alpha',
    siteCode: 'SL-001',
    name: 'Sector Alpha',
    address: '100 Construction Way',
  );

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'sitelens_active_site_id': 'site-alpha'});
  });

  Widget createWidgetUnderTest({FakeSyncCoordinator? customCoordinator}) {
    final coordinator = customCoordinator ??
        FakeSyncCoordinator(
          mediaRepo: FakeMediaRepository(),
          cloudSyncService: FakeCloudSyncService(),
          storageService: FakeEvidenceStorageService(),
          authService: MockAuthService(),
        );

    return ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(MockAuthService()),
        siteRepositoryProvider.overrideWithValue(MockSiteRepository(testSite)),
        siteControllerProvider.overrideWith(
          (ref) => SiteController(MockSiteRepository(testSite)),
        ),
        syncCoordinatorProvider.overrideWith(
          (ref) => coordinator,
        ),
      ],
      child: const MaterialApp(
        home: SettingsScreen(),
      ),
    );
  }

  group('SettingsScreen Widget Tests', () {
    testWidgets('1. Renders all 5 primary settings sections', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('SETTINGS'), findsOneWidget);
      expect(find.text('CLOUD SYNC & QUEUE'), findsNothing);
      expect(find.text('GPS & GEOLOCATION'), findsOneWidget);
      expect(find.text('WATERMARK & STAMP'), findsOneWidget);
      expect(find.text('CAMERA & DISPLAY ORIENTATION'), findsNothing);
      expect(find.text('NEARBY SEARCH DEFAULTS'), findsOneWidget);
      expect(find.text('STORAGE & LOCAL MEDIA'), findsOneWidget);
      expect(find.text('USER'), findsNWidgets(2));

      expect(find.text('SL-001 • Sector Alpha'), findsOneWidget);
      expect(find.text('inspector@company.com'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('2. Tapping Configure GPS Threshold opens GpsSettingsModal', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.text('CONFIGURE GPS THRESHOLD'));
      await tester.pumpAndSettle();

      expect(find.byType(GpsSettingsModal), findsOneWidget);
      expect(find.text('GPS Accuracy Threshold'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('3. Tapping Timestamp Edit button opens TimestampSettingsModal', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_calendar_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(TimestampSettingsModal), findsOneWidget);
      expect(find.text('Overlay Timestamp Settings'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('4. Tapping Manage Local Storage opens StorageSettingsModal', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.text('MANAGE LOCAL STORAGE'));
      await tester.pumpAndSettle();

      expect(find.byType(StorageSettingsModal), findsOneWidget);
      expect(find.text('Storage Management'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('5. Tapping Nearby Radius chip updates selected radius', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.text('25m'));
      await tester.pumpAndSettle();

      final chipFinder = find.widgetWithText(ChoiceChip, '25m');
      expect(tester.widget<ChoiceChip>(chipFinder).selected, isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('6. Tapping Sign Out button presents confirmation dialog', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('SIGN OUT'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('SIGN OUT'));
      await tester.pumpAndSettle();

      expect(find.text('Sign Out'), findsNWidgets(2));
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Sign Out'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('7. Verifies orientation settings and landscape options are absent from Settings', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('CAMERA & DISPLAY ORIENTATION'), findsNothing);
      expect(find.text('ORIENTATION & AUTO-ROTATE'), findsNothing);
      expect(find.text('Camera Orientation'), findsNothing);
      expect(find.text('Display Orientation'), findsNothing);
      expect(find.text('Auto-Rotate (Default)'), findsNothing);
      expect(find.text('Auto-Rotate'), findsNothing);
      expect(find.text('Portrait (Default)'), findsNothing);
      expect(find.text('Landscape'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}

class MockSiteRepository implements SiteRepository {
  final SiteModel site;
  MockSiteRepository(this.site);

  @override
  Future<List<SiteModel>> getAllSites({String? creatorId}) async => [site];

  @override
  Future<SiteModel?> getSiteById(String id) async => site.id == id ? site : null;

  @override
  Future<void> saveSite(SiteModel site) async {}

  @override
  Future<void> deleteSite(String id) async {}

  @override
  Future<void> seedDefaultSitesIfEmpty() async {}
}

class MockAuthService implements AuthService {
  final AuthUser _user = const AuthUser(
    uid: 'test-inspector-uid-12345678',
    email: 'inspector@company.com',
    displayName: 'Test Inspector',
  );

  @override
  Stream<AuthUser?> get authStateChanges => Stream.value(_user);

  @override
  AuthUser? get currentUser => _user;

  @override
  Future<AuthUser> signInWithEmailPassword(String email, String password) async => _user;

  @override
  Future<AuthUser?> signInWithGoogle() async => _user;

  @override
  Future<AuthUser> signUpWithEmailPassword(
    String email,
    String password, {
    String? displayName,
  }) async => _user;

  @override
  Future<void> sendEmailVerificationForUser(String email, String password) async {}

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<void> signOut() async {}
}

class FakeMediaRepository implements MediaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  @override
  Stream<int> watchUnsyncedCount({String? creatorId}) => Stream.value(0);

  @override
  Future<List<MediaItem>> getPendingOrFailedMedia({String? creatorId}) async => [];

  @override
  Future<void> resetStuckSyncingMedia() async {}
}

class FakeCloudSyncService implements CloudSyncService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class FakeEvidenceStorageService implements EvidenceStorageService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
