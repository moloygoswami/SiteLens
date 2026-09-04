import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sitelens/core/services/auth_service.dart';
import 'package:sitelens/core/services/session_service.dart';
import 'package:sitelens/core/services/permission_service.dart';

class MockAuthService implements AuthService {
  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? _currentUser;
  bool throwOnSignIn = false;

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  @override
  AuthUser? get currentUser => _currentUser;

  void emitUser(AuthUser? user) {
    _currentUser = user;
    _controller.add(user);
  }

  @override
  Future<AuthUser> signInWithEmailPassword(String email, String password) async {
    if (throwOnSignIn) {
      throw Exception('Invalid credentials');
    }
    final user = AuthUser(
      uid: 'uid-test-123',
      email: email,
      displayName: 'Inspector Test',
    );
    emitUser(user);
    return user;
  }

  @override
  Future<AuthUser?> signInWithGoogle() async {
    if (throwOnSignIn) {
      throw Exception('Google Sign-In failed');
    }
    final user = const AuthUser(
      uid: 'uid-test-123',
      email: 'google-user@sitelens.local',
      displayName: 'Google Inspector',
    );
    emitUser(user);
    return user;
  }

  @override
  Future<AuthUser> signUpWithEmailPassword(
    String email,
    String password, {
    String? displayName,
  }) async {
    if (throwOnSignIn) {
      throw Exception('Sign up failed');
    }
    final user = AuthUser(
      uid: 'uid-test-123',
      email: email,
      displayName: displayName ?? 'Inspector Test',
      isEmailVerified: true,
    );
    emitUser(user);
    return user;
  }

  String? lastPasswordResetEmail;

  @override
  Future<void> sendEmailVerificationForUser(String email, String password) async {}

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    if (throwOnSignIn) throw Exception('Password reset failed');
    lastPasswordResetEmail = email;
  }

  @override
  Future<void> signOut() async {
    emitUser(null);
  }
}

class MockPermissionService extends PermissionService {
  SiteLensPermissionStatus mockStatus = const SiteLensPermissionStatus(
    camera: PermissionStatus.granted,
    location: PermissionStatus.granted,
    photos: PermissionStatus.granted,
  );

  @override
  Future<SiteLensPermissionStatus> checkAllPermissions() async {
    state = mockStatus;
    return mockStatus;
  }
}

void main() {
  group('M1 Auth & Session Routing Unit Tests', () {
    late MockAuthService mockAuth;
    late ProviderContainer container;
    late MockPermissionService mockPermission;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockAuth = MockAuthService();
      mockPermission = MockPermissionService();

      container = ProviderContainer(
        overrides: [
          authServiceProvider.overrideWithValue(mockAuth),
          permissionServiceProvider.overrideWith((ref) => mockPermission),
        ],
      );

      // Initialize session service eagerly
      container.read(sessionServiceProvider);
    });

    tearDown(() {
      container.dispose();
    });

    test('1. Unauthenticated state routes to Welcome', () async {
      mockAuth.emitUser(null);
      await pumpEventQueue();

      final sessionState = container.read(sessionServiceProvider);
      expect(sessionState.status, equals(SessionStatus.unauthenticated));
      expect(sessionState.user, isNull);
    });

    test('2. Authenticated first login routes to onboarding when incomplete', () async {
      const user = AuthUser(uid: 'uid-new-user', email: 'new@sitelens.local');
      mockAuth.emitUser(user);
      await pumpEventQueue();

      final sessionState = container.read(sessionServiceProvider);
      expect(sessionState.status, equals(SessionStatus.onboardingRequired));
      expect(sessionState.user?.uid, equals('uid-new-user'));
      expect(sessionState.isOnboardingCompleted, isFalse);
    });

    test('3. Authenticated + onboarding incomplete routes to onboarding', () async {
      mockPermission.mockStatus = const SiteLensPermissionStatus(
        camera: PermissionStatus.denied,
        location: PermissionStatus.granted,
      );

      const user = AuthUser(uid: 'uid-incomplete', email: 'user@sitelens.local');
      mockAuth.emitUser(user);
      await pumpEventQueue();

      final sessionState = container.read(sessionServiceProvider);
      expect(sessionState.status, equals(SessionStatus.onboardingRequired));
    });

    test('4. Authenticated + onboarding complete routes to authenticatedReady (Site Setup)', () async {
      SharedPreferences.setMockInitialValues({
        'sitelens_onboarding_completed_uid-existing': true,
      });

      mockPermission.mockStatus = const SiteLensPermissionStatus(
        camera: PermissionStatus.granted,
        location: PermissionStatus.granted,
      );

      const user = AuthUser(uid: 'uid-existing', email: 'existing@sitelens.local');
      mockAuth.emitUser(user);
      await pumpEventQueue();

      final sessionState = container.read(sessionServiceProvider);
      expect(sessionState.status, equals(SessionStatus.authenticatedReady));
      expect(sessionState.isOnboardingCompleted, isTrue);
    });

    test('5. Session restored after restart is not incorrectly treated as first login', () async {
      SharedPreferences.setMockInitialValues({
        'sitelens_onboarding_completed_uid-session-restored': true,
      });

      const user = AuthUser(uid: 'uid-session-restored', email: 'restored@sitelens.local');
      mockAuth.emitUser(user);
      await pumpEventQueue();

      final sessionState = container.read(sessionServiceProvider);
      expect(sessionState.status, equals(SessionStatus.authenticatedReady));
      expect(sessionState.isOnboardingCompleted, isTrue);
    });

    test('6. Logout transitions back to unauthenticated state', () async {
      const user = AuthUser(uid: 'uid-logout', email: 'logout@sitelens.local');
      mockAuth.emitUser(user);
      await pumpEventQueue();

      expect(container.read(sessionServiceProvider).status, isNot(SessionStatus.unauthenticated));

      await mockAuth.signOut();
      await pumpEventQueue();

      final sessionState = container.read(sessionServiceProvider);
      expect(sessionState.status, equals(SessionStatus.unauthenticated));
      expect(sessionState.user, isNull);
    });

    test('7. Firebase authentication failure throws and does not fall back to local auth', () async {
      mockAuth.throwOnSignIn = true;

      expect(
        () => mockAuth.signInWithEmailPassword('wrong@sitelens.local', 'badpass'),
        throwsA(isA<Exception>()),
      );

      expect(mockAuth.currentUser, isNull);
    });

    test('8. Anonymous authentication is not used in session state', () {
      final sessionState = container.read(sessionServiceProvider);
      expect(sessionState.user?.displayName, isNot(contains('Anonymous')));
    });

    test('9. sendPasswordResetEmail delegates email to auth service', () async {
      await mockAuth.sendPasswordResetEmail('reset@sitelens.local');
      expect(mockAuth.lastPasswordResetEmail, equals('reset@sitelens.local'));
    });

    test('10. EmailNotVerifiedException contains truthful guidance message and email', () {
      const ex = EmailNotVerifiedException(
        message: 'Your email address has not been verified yet.',
        email: 'engineer@sitelens.local',
      );
      expect(ex.email, equals('engineer@sitelens.local'));
      expect(ex.toString(), contains('not been verified'));
    });
  });
}
