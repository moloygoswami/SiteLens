import 'dart:async';
import 'dart:ffi';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqlite3/open.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sitelens/app/router.dart';
import 'package:sitelens/core/services/auth_service.dart';
import 'package:sitelens/core/services/permission_service.dart';
import 'package:sitelens/core/services/session_service.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/local/database/database_provider.dart';
import 'package:sitelens/features/auth/session_router.dart';
import 'package:sitelens/features/auth/welcome_screen.dart';
import 'package:sitelens/features/onboarding/permission_onboarding_screen.dart';
import 'package:sitelens/features/onboarding/permission_recovery_screen.dart';
import 'package:sitelens/features/sites/site_setup_screen.dart';

class TestMockAuthService implements AuthService {
  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? _currentUser;

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  @override
  AuthUser? get currentUser => _currentUser;

  void emitUser(AuthUser? user) {
    _currentUser = user;
    _controller.add(user);
  }

  @override
  Future<AuthUser> signInWithEmailPassword(String email, String password) async => throw UnimplementedError();

  @override
  Future<AuthUser?> signInWithGoogle() async => throw UnimplementedError();

  @override
  Future<AuthUser> signUpWithEmailPassword(String email, String password, {String? displayName}) async => throw UnimplementedError();

  @override
  Future<void> sendEmailVerificationForUser(String email, String password) async {}

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<SessionVerificationResult> verifySession() async => const SessionVerificationResult.valid();

  @override
  Future<void> signOut() async {
    _currentUser = null;
    _controller.add(null);
  }
}

class TestMockPermissionService extends PermissionService {
  SiteLensPermissionStatus mockStatus = const SiteLensPermissionStatus(
    camera: PermissionStatus.granted,
    location: PermissionStatus.granted,
    photos: PermissionStatus.granted,
  );
  int checkAllPermissionsCallCount = 0;

  @override
  Future<SiteLensPermissionStatus> checkAllPermissions() async {
    checkAllPermissionsCallCount++;
    state = mockStatus;
    return mockStatus;
  }
}

class TestNavigatorObserver extends NavigatorObserver {
  final List<String?> pushedRouteNames = [];
  final List<String?> replacedRouteNames = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRouteNames.add(route.settings.name);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    replacedRouteNames.add(newRoute?.settings.name);
  }
}

void main() {
  late AppDatabase db;
  late TestMockAuthService mockAuth;
  late TestMockPermissionService mockPermission;

  setUpAll(() {
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    mockAuth = TestMockAuthService();
    mockPermission = TestMockPermissionService();
  });

  tearDown(() async {
    await db.close();
  });

  Widget createTestWidget({
    required Widget home,
    TestNavigatorObserver? observer,
    List<Override> overrides = const [],
  }) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        authServiceProvider.overrideWithValue(mockAuth),
        permissionServiceProvider.overrideWith((ref) => mockPermission),
        ...overrides,
      ],
      child: MaterialApp(
        home: home,
        onGenerateRoute: AppRoutes.onGenerateRoute,
        navigatorObservers: observer != null ? [observer] : [],
      ),
    );
  }

  group('Permission Resume & Navigation Regression Tests', () {
    testWidgets('1. Incomplete onboarding routes to PermissionOnboardingScreen', (tester) async {
      SharedPreferences.setMockInitialValues({
        'sitelens_onboarding_completed_test-uid': false,
      });

      const user = AuthUser(uid: 'test-uid', email: 'inspector@sitelens.local');
      mockAuth.emitUser(user);

      await tester.pumpWidget(createTestWidget(home: const SessionRouter()));
      await tester.pumpAndSettle();

      expect(find.byType(PermissionOnboardingScreen), findsOneWidget);
      expect(find.byType(SiteSetupScreen), findsNothing);
    });

    testWidgets('2. Completed onboarding + granted permissions routes to normal route (SiteSetupScreen)', (tester) async {
      SharedPreferences.setMockInitialValues({
        'sitelens_onboarding_completed_test-uid': true,
      });
      mockPermission.mockStatus = const SiteLensPermissionStatus(
        camera: PermissionStatus.granted,
        location: PermissionStatus.granted,
        photos: PermissionStatus.granted,
      );

      const user = AuthUser(uid: 'test-uid', email: 'inspector@sitelens.local');
      mockAuth.emitUser(user);

      await tester.pumpWidget(createTestWidget(home: const SessionRouter()));
      await tester.pumpAndSettle();

      expect(find.byType(SiteSetupScreen), findsOneWidget);
      expect(find.byType(PermissionOnboardingScreen), findsNothing);
    });

    testWidgets('3. Completed onboarding + revoked permissions routes to normal/recovery path, NOT PermissionOnboardingScreen', (tester) async {
      SharedPreferences.setMockInitialValues({
        'sitelens_onboarding_completed_test-uid': true,
      });
      // Revoke permissions
      mockPermission.mockStatus = const SiteLensPermissionStatus(
        camera: PermissionStatus.denied,
        location: PermissionStatus.denied,
        photos: PermissionStatus.denied,
      );

      const user = AuthUser(uid: 'test-uid', email: 'inspector@sitelens.local');
      mockAuth.emitUser(user);

      await tester.pumpWidget(createTestWidget(home: const SessionRouter()));
      await tester.pumpAndSettle();

      // Must stay in authenticatedReady (SiteSetupScreen), never regressing to PermissionOnboardingScreen
      expect(find.byType(SiteSetupScreen), findsOneWidget);
      expect(find.byType(PermissionOnboardingScreen), findsNothing);
    });

    testWidgets('3b. Recovery screen on permission restoration routes to SiteSetupScreen, NOT PermissionOnboardingScreen', (tester) async {
      SharedPreferences.setMockInitialValues({
        'sitelens_onboarding_completed_test-uid': true,
      });
      mockPermission.mockStatus = const SiteLensPermissionStatus(
        camera: PermissionStatus.denied,
        location: PermissionStatus.denied,
        photos: PermissionStatus.denied,
      );

      const user = AuthUser(uid: 'test-uid', email: 'inspector@sitelens.local');
      mockAuth.emitUser(user);

      await tester.pumpWidget(createTestWidget(home: const PermissionRecoveryScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(PermissionRecoveryScreen), findsOneWidget);

      // Now restore permissions and trigger resume
      mockPermission.mockStatus = const SiteLensPermissionStatus(
        camera: PermissionStatus.granted,
        location: PermissionStatus.granted,
        photos: PermissionStatus.granted,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // Successfully recovers directly to SiteSetupScreen without visiting PermissionOnboardingScreen
      expect(find.byType(SiteSetupScreen), findsOneWidget);
      expect(find.byType(PermissionOnboardingScreen), findsNothing);
    });

    testWidgets('4. Minimize/resume after onboarding: no return to PermissionOnboardingScreen and no duplicate navigation', (tester) async {
      SharedPreferences.setMockInitialValues({
        'sitelens_onboarding_completed_test-uid': false,
      });
      mockPermission.mockStatus = const SiteLensPermissionStatus(
        camera: PermissionStatus.granted,
        location: PermissionStatus.granted,
        photos: PermissionStatus.granted,
      );

      const user = AuthUser(uid: 'test-uid', email: 'inspector@sitelens.local');
      mockAuth.emitUser(user);

      final navObserver = TestNavigatorObserver();

      await tester.pumpWidget(createTestWidget(
        home: const PermissionOnboardingScreen(),
        observer: navObserver,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(PermissionOnboardingScreen), findsOneWidget);

      // Simulate AppLifecycleState.resumed (app minimized and resumed)
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // Navigation occurred directly to siteSetup
      expect(find.byType(SiteSetupScreen), findsOneWidget);
      expect(find.byType(PermissionOnboardingScreen), findsNothing);
      expect(navObserver.replacedRouteNames.length, equals(1));
      // No extra push of root/SessionRouter occurred
      expect(navObserver.pushedRouteNames.length, equals(1));

      // Simulate a second resumed lifecycle event immediately (rapid resume / duplicate event)
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // Guard must prevent duplicate navigation
      expect(navObserver.replacedRouteNames.length, equals(1));

      // Verify onboarding completion flag was persisted
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('sitelens_onboarding_completed_test-uid'), isTrue);
    });

    testWidgets('5. Defect 1: First-launch user recovers from permanent denial, persists onboarding state, cleans back-stack, and preserves state on subsequent launch', (tester) async {
      SharedPreferences.setMockInitialValues({
        'sitelens_onboarding_completed_test-uid': false,
      });
      // Permanently denied initial permissions
      mockPermission.mockStatus = const SiteLensPermissionStatus(
        camera: PermissionStatus.permanentlyDenied,
        location: PermissionStatus.permanentlyDenied,
        photos: PermissionStatus.permanentlyDenied,
      );

      const user = AuthUser(uid: 'test-uid', email: 'inspector@sitelens.local');
      mockAuth.emitUser(user);

      final navObserver = TestNavigatorObserver();

      await tester.pumpWidget(createTestWidget(
        home: const SessionRouter(),
        observer: navObserver,
      ));
      await tester.pumpAndSettle();

      // Starts on PermissionOnboardingScreen
      expect(find.byType(PermissionOnboardingScreen), findsOneWidget);

      // Tap "Resolve Blocked Permissions" -> pushes PermissionRecoveryScreen
      expect(find.text('Resolve Blocked Permissions'), findsOneWidget);
      await tester.tap(find.text('Resolve Blocked Permissions'));
      await tester.pumpAndSettle();

      expect(find.byType(PermissionRecoveryScreen), findsOneWidget);
      expect(navObserver.pushedRouteNames.length, equals(2));

      // Verify the recovery route is currently on top of the navigator stack and can pop
      final recoveryContext = tester.element(find.byType(PermissionRecoveryScreen));
      expect(Navigator.of(recoveryContext).canPop(), isTrue);

      // Simulate permissions restored in device settings
      mockPermission.mockStatus = const SiteLensPermissionStatus(
        camera: PermissionStatus.granted,
        location: PermissionStatus.granted,
        photos: PermissionStatus.granted,
      );

      // App resumed from settings
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // 1. PermissionRecoveryScreen popped cleanly, SessionRouter now displays SiteSetupScreen
      expect(find.byType(SiteSetupScreen), findsOneWidget);
      expect(find.byType(PermissionRecoveryScreen), findsNothing);
      expect(find.byType(PermissionOnboardingScreen), findsNothing);

      // 2. Back-stack is clean: canPop() is strictly false
      final siteSetupContext = tester.element(find.byType(SiteSetupScreen));
      expect(Navigator.of(siteSetupContext).canPop(), isFalse);

      // 3. Onboarding completion flag was persisted in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('sitelens_onboarding_completed_test-uid'), isTrue);

      // 4. Invariant across minimize/reopen: resumed lifecycle does not regress to onboarding
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(SiteSetupScreen), findsOneWidget);
      expect(find.byType(PermissionOnboardingScreen), findsNothing);

      // 5. Invariant on subsequent app launch: fresh SessionRouter starts directly in SiteSetupScreen
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      mockPermission = TestMockPermissionService();
      await tester.pumpWidget(createTestWidget(home: const SessionRouter()));
      await tester.pumpAndSettle();

      expect(find.byType(SiteSetupScreen), findsOneWidget);
      expect(find.byType(PermissionOnboardingScreen), findsNothing);
    });

    testWidgets('6. Defect 2: Declarative SessionRouter onboarding completion eliminates duplicate imperative route replacement', (tester) async {
      SharedPreferences.setMockInitialValues({
        'sitelens_onboarding_completed_test-uid': false,
      });
      mockPermission.mockStatus = const SiteLensPermissionStatus(
        camera: PermissionStatus.granted,
        location: PermissionStatus.granted,
        photos: PermissionStatus.granted,
      );

      const user = AuthUser(uid: 'test-uid', email: 'inspector@sitelens.local');
      mockAuth.emitUser(user);

      final navObserver = TestNavigatorObserver();

      await tester.pumpWidget(createTestWidget(
        home: const SessionRouter(),
        observer: navObserver,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(PermissionOnboardingScreen), findsOneWidget);

      // Tap "Continue to Site Setup"
      final continueBtn = find.text('Continue to Site Setup');
      expect(continueBtn, findsOneWidget);
      await tester.tap(continueBtn);
      await tester.pumpAndSettle();

      // Displays SiteSetupScreen via SessionRouter
      expect(find.byType(SiteSetupScreen), findsOneWidget);
      expect(find.byType(PermissionOnboardingScreen), findsNothing);

      // Single authoritative navigation: declarative SessionRouter did not perform pushReplacementNamed
      expect(navObserver.replacedRouteNames, isEmpty);
      expect(navObserver.pushedRouteNames.length, equals(1));

      // Clean back stack
      final siteSetupContext = tester.element(find.byType(SiteSetupScreen));
      expect(Navigator.of(siteSetupContext).canPop(), isFalse);

      // Onboarding persisted
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('sitelens_onboarding_completed_test-uid'), isTrue);
    });

    testWidgets('7. Defect 2: App-level authoritative sign-out navigation clears pushed route stack without duplicate screen-level navigation', (tester) async {
      SharedPreferences.setMockInitialValues({
        'sitelens_onboarding_completed_test-uid': true,
      });
      mockPermission.mockStatus = const SiteLensPermissionStatus(
        camera: PermissionStatus.granted,
        location: PermissionStatus.granted,
        photos: PermissionStatus.granted,
      );

      const user = AuthUser(uid: 'test-uid', email: 'inspector@sitelens.local');
      mockAuth.emitUser(user);

      final navObserver = TestNavigatorObserver();

      await tester.pumpWidget(ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          authServiceProvider.overrideWithValue(mockAuth),
          permissionServiceProvider.overrideWith((ref) => mockPermission),
        ],
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: const SessionRouter(),
          onGenerateRoute: AppRoutes.onGenerateRoute,
          navigatorObservers: [navObserver],
          builder: (context, child) {
            return Consumer(
              builder: (context, ref, _) {
                ref.listen<UserSessionState>(sessionServiceProvider, (previous, next) {
                  if (next.status == SessionStatus.unauthenticated &&
                      previous != null &&
                      previous.status != SessionStatus.unauthenticated) {
                    rootNavigatorKey.currentState?.pushNamedAndRemoveUntil(
                      AppRoutes.root,
                      (route) => false,
                    );
                  }
                });
                return child ?? const SizedBox();
              },
            );
          },
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(SiteSetupScreen), findsOneWidget);

      // Push a screen onto navigator to create deep stack
      rootNavigatorKey.currentState?.pushNamed(AppRoutes.recovery);
      await tester.pumpAndSettle();
      expect(find.byType(PermissionRecoveryScreen), findsOneWidget);
      expect(rootNavigatorKey.currentState?.canPop(), isTrue);

      // Trigger sign out
      await mockAuth.signOut();
      await tester.pumpAndSettle();

      // Unauthenticated WelcomeScreen reached at root
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(PermissionRecoveryScreen), findsNothing);
      expect(find.byType(SiteSetupScreen), findsNothing);

      // Navigator stack is clean: cannot pop
      expect(rootNavigatorKey.currentState?.canPop(), isFalse);
    });
  });
}
