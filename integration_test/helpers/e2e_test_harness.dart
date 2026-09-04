import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sitelens/firebase_options.dart';
import 'package:sitelens/app/app.dart';
import 'package:sitelens/core/services/auth_service.dart';
import 'package:sitelens/core/services/permission_service.dart';
import 'package:sitelens/data/repositories/site_repository.dart';
import 'package:sitelens/domain/models/site_model.dart';
import 'package:sitelens/features/sync/services/sync_coordinator.dart';
import 'fake_auth_service.dart';
import 'fake_permission_service.dart';
import 'fake_site_repository.dart';
import 'fake_sync_coordinator.dart';

class E2ETestHarness {
  static const defaultTestUser = AuthUser(
    uid: 'test-user-001',
    email: 'inspector.e2e@sitelens.local',
    displayName: 'Lead E2E Inspector',
  );

  static const defaultTestSite = SiteModel(
    id: 'test-site-001',
    siteCode: 'E2E',
    name: 'E2E Test Inspection Site',
    address: '100 Test Avenue, Metro City',
  );

  late FakeAuthService fakeAuthService;
  late FakePermissionService fakePermissionService;
  late FakeSiteRepository fakeSiteRepository;
  late ProviderContainer container;

  static Future<void> initializeFirebaseIfNeeded() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (_) {
      // Already initialized
    }
  }

  Future<void> bootstrapAuthenticatedApp(
    WidgetTester tester, {
    AuthUser user = defaultTestUser,
    SiteModel activeSite = defaultTestSite,
    List<SiteModel> additionalSites = const [],
  }) async {
    await initializeFirebaseIfNeeded();

    // 1. Establish deterministic SharedPreferences state
    SharedPreferences.setMockInitialValues({
      'sitelens_onboarding_completed_${user.uid}': true,
      'sitelens_active_site_id': activeSite.id,
    });

    // 2. Initialize test doubles
    fakeAuthService = FakeAuthService(user);
    fakePermissionService = FakePermissionService();
    fakeSiteRepository = FakeSiteRepository(initialSites: [activeSite, ...additionalSites]);

    // 3. Create isolated ProviderContainer with explicit overrides
    container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(fakeAuthService),
        permissionServiceProvider.overrideWith((ref) => fakePermissionService),
        siteRepositoryProvider.overrideWithValue(fakeSiteRepository),
        syncCoordinatorProvider.overrideWith((ref) => FakeSyncCoordinator()),
      ],
    );

    // 4. Pump root application
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const SiteLensApp(),
      ),
    );

    await tester.pumpAndSettle();
  }

  Future<void> bootstrapUnauthenticatedApp(WidgetTester tester) async {
    await initializeFirebaseIfNeeded();

    // 1. Clear SharedPreferences
    SharedPreferences.setMockInitialValues({});

    // 2. Initialize unauthenticated doubles
    fakeAuthService = FakeAuthService(null);
    fakePermissionService = FakePermissionService();
    fakeSiteRepository = FakeSiteRepository();

    // 3. Create isolated ProviderContainer
    container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(fakeAuthService),
        permissionServiceProvider.overrideWith((ref) => fakePermissionService),
        siteRepositoryProvider.overrideWithValue(fakeSiteRepository),
      ],
    );

    // 4. Pump root application
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const SiteLensApp(),
      ),
    );

    await tester.pumpAndSettle();
  }

  void dispose() {
    try {
      fakeAuthService.dispose();
    } catch (_) {}
    try {
      container.dispose();
    } catch (_) {}
  }
}
