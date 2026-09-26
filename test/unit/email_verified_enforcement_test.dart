import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sitelens/core/services/auth_service.dart';
import 'package:sitelens/core/services/permission_service.dart';
import 'package:sitelens/core/services/session_service.dart';
import 'package:sitelens/core/utils/auth_error_mapper.dart';

// ---------------------------------------------------------------------------
// Hand-rolled fakes for the Firebase/Google SDK types.
//
// No mocking dependency is available in this project and dependencies are out
// of scope for this remediation, so these use `implements` + `noSuchMethod`.
// Only the members `AuthService` actually touches are overridden.
// ---------------------------------------------------------------------------

class _FakeUser implements User {
  _FakeUser({
    required this.uid,
    required this.emailVerified,
    this.email = 'inspector@sitelens.local',
  });

  @override
  final String uid;

  @override
  final String? email;

  @override
  final String? displayName = 'Site Inspector';

  @override
  bool emailVerified;

  int reloadCalls = 0;

  @override
  Future<void> reload() async {
    reloadCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUserCredential implements UserCredential {
  _FakeUserCredential(this.user);

  @override
  final User? user;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFirebaseAuth implements FirebaseAuth {
  _FakeFirebaseAuth({required this.emailVerified});

  /// The `emailVerified` claim reported by Firebase Auth on the signed-in user.
  bool emailVerified;

  _FakeUser? signedIn;
  int signOutCalls = 0;

  @override
  User? get currentUser => signedIn;

  @override
  Stream<User?> authStateChanges() => const Stream<User?>.empty();

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    signedIn = _FakeUser(
      uid: 'uid-email',
      email: email,
      emailVerified: emailVerified,
    );
    return _FakeUserCredential(signedIn);
  }

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    signedIn = _FakeUser(
      uid: 'uid-google',
      email: 'google@sitelens.local',
      emailVerified: emailVerified,
    );
    return _FakeUserCredential(signedIn);
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    signedIn = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGoogleAuthentication implements GoogleSignInAuthentication {
  @override
  String? get accessToken => 'access-token';

  @override
  String? get idToken => 'id-token';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGoogleAccount implements GoogleSignInAccount {
  @override
  Future<GoogleSignInAuthentication> get authentication async =>
      _FakeGoogleAuthentication();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGoogleSignIn implements GoogleSignIn {
  int signOutCalls = 0;

  @override
  Future<GoogleSignInAccount?> signIn() async => _FakeGoogleAccount();

  @override
  Future<GoogleSignInAccount?> signOut() async {
    signOutCalls++;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// Boundary-level fake AuthService (drives SessionService, the authoritative
// session boundary).
// ---------------------------------------------------------------------------

class _FakeAuthService implements AuthService {
  _FakeAuthService();

  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? _currentUser;
  int signOutCalls = 0;

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  @override
  AuthUser? get currentUser => _currentUser;

  /// Seeds a persisted/current identity without emitting on the stream
  /// (models cold-start restoration from a cached Firebase session).
  void seedPersisted(AuthUser? user) => _currentUser = user;

  /// Emits an identity on the auth state stream (models any sign-in path).
  void emitUser(AuthUser? user) {
    _currentUser = user;
    _controller.add(user);
  }

  @override
  Future<SessionVerificationResult> verifySession() async =>
      const SessionVerificationResult.valid();

  @override
  Future<void> signOut() async {
    signOutCalls++;
    emitUser(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePermissionService extends PermissionService {
  @override
  Future<SiteLensPermissionStatus> checkAllPermissions() async {
    state = const SiteLensPermissionStatus(
      camera: PermissionStatus.granted,
      location: PermissionStatus.granted,
    );
    return state;
  }
}

const AuthUser verifiedUser = AuthUser(
  uid: 'uid-verified',
  email: 'verified@sitelens.local',
  displayName: 'Verified Inspector',
  isEmailVerified: true,
);

const AuthUser unverifiedUser = AuthUser(
  uid: 'uid-unverified',
  email: 'unverified@sitelens.local',
  displayName: 'Unverified Inspector',
  isEmailVerified: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A. AuthService email_verified gates (sign-in + persisted session)', () {
    test('1. Verified email/password user is accepted', () async {
      final auth = AuthService(
        firebaseAuth: _FakeFirebaseAuth(emailVerified: true),
        googleSignIn: _FakeGoogleSignIn(),
      );

      final user = await auth.signInWithEmailPassword('a@b.com', 'pw');

      expect(user.isEmailVerified, isTrue);
      expect(auth.currentUser, isNotNull);
    });

    test('2. Unverified email/password user is rejected with no retained session',
        () async {
      final firebaseAuth = _FakeFirebaseAuth(emailVerified: false);
      final auth = AuthService(
        firebaseAuth: firebaseAuth,
        googleSignIn: _FakeGoogleSignIn(),
      );

      await expectLater(
        auth.signInWithEmailPassword('a@b.com', 'pw'),
        throwsA(isA<EmailNotVerifiedException>()),
      );

      // No partial authenticated state survives the rejection.
      expect(firebaseAuth.signOutCalls, equals(1));
      expect(firebaseAuth.currentUser, isNull);
      expect(auth.currentUser, isNull);
    });

    test('3. Verified Google-authenticated user is accepted', () async {
      final auth = AuthService(
        firebaseAuth: _FakeFirebaseAuth(emailVerified: true),
        googleSignIn: _FakeGoogleSignIn(),
      );

      final user = await auth.signInWithGoogle();

      expect(user, isNotNull);
      expect(user!.isEmailVerified, isTrue);
    });

    test('4. Unverified Google-authenticated user is rejected (never assumed verified)',
        () async {
      final firebaseAuth = _FakeFirebaseAuth(emailVerified: false);
      final googleSignIn = _FakeGoogleSignIn();
      final auth = AuthService(
        firebaseAuth: firebaseAuth,
        googleSignIn: googleSignIn,
      );

      await expectLater(
        auth.signInWithGoogle(),
        throwsA(isA<EmailNotVerifiedException>()),
      );

      // Both identities are torn down: no partial authenticated state.
      expect(firebaseAuth.signOutCalls, equals(1));
      expect(googleSignIn.signOutCalls, equals(1));
      expect(firebaseAuth.currentUser, isNull);
      expect(auth.currentUser, isNull);
    });

    test('5. Verified persisted/cold-start session re-validates as valid', () async {
      final firebaseAuth = _FakeFirebaseAuth(emailVerified: true)
        ..signedIn = _FakeUser(
          uid: 'uid-verified',
          emailVerified: true,
        );
      final auth = AuthService(
        firebaseAuth: firebaseAuth,
        googleSignIn: _FakeGoogleSignIn(),
      );

      final result = await auth.verifySession();

      expect(result.isValid, isTrue);
    });

    test('6. Unverified persisted/cold-start session is rejected at the same boundary',
        () async {
      final firebaseAuth = _FakeFirebaseAuth(emailVerified: false)
        ..signedIn = _FakeUser(
          uid: 'uid-unverified',
          emailVerified: false,
        );
      final auth = AuthService(
        firebaseAuth: firebaseAuth,
        googleSignIn: _FakeGoogleSignIn(),
      );

      final result = await auth.verifySession();

      expect(result.isValid, isFalse);
      expect(result.reason, equals(SessionTerminationReason.emailNotVerified));
    });

    test('verifySession reloads before trusting the persisted emailVerified claim',
        () async {
      final user = _FakeUser(uid: 'uid-x', emailVerified: true);
      final firebaseAuth = _FakeFirebaseAuth(emailVerified: true)..signedIn = user;
      final auth = AuthService(
        firebaseAuth: firebaseAuth,
        googleSignIn: _FakeGoogleSignIn(),
      );

      await auth.verifySession();

      // The authoritative claim must be re-read from Firebase, never trusted
      // from a cached client-side assumption (`04_SECURITY.MD` §2, AC-AUTH-10).
      expect(user.reloadCalls, greaterThan(0));
    });
  });

  group('B. Authoritative session boundary (SessionService)', () {
    late _FakeAuthService fakeAuth;
    late ProviderContainer container;

    UserSessionState readState() => container.read(sessionServiceProvider);

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      fakeAuth = _FakeAuthService();
      container = ProviderContainer(
        overrides: [
          authServiceProvider.overrideWithValue(fakeAuth),
          permissionServiceProvider.overrideWith((ref) => _FakePermissionService()),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('1. Verified email/password identity is accepted by the boundary', () async {
      fakeAuth.emitUser(verifiedUser);
      container.read(sessionServiceProvider.notifier);
      await pumpEventQueue();

      expect(readState().status, equals(SessionStatus.onboardingRequired));
      expect(readState().user?.uid, equals(verifiedUser.uid));
    });

    test('2. Unverified email/password identity is rejected', () async {
      fakeAuth.emitUser(unverifiedUser);
      final notifier = container.read(sessionServiceProvider.notifier);
      await pumpEventQueue();

      expect(notifier.state.status, equals(SessionStatus.unauthenticated));
    });

    test('3. Verified Google identity is accepted', () async {
      const googleVerified = AuthUser(
        uid: 'uid-google',
        email: 'google@sitelens.local',
        displayName: 'Google Inspector',
        isEmailVerified: true,
      );
      fakeAuth.emitUser(googleVerified);
      container.read(sessionServiceProvider.notifier);
      await pumpEventQueue();

      expect(readState().status, isNot(SessionStatus.unauthenticated));
    });

    test('4. Unverified Google identity is rejected', () async {
      const googleUnverified = AuthUser(
        uid: 'uid-google',
        email: 'google@sitelens.local',
        displayName: 'Google Inspector',
        isEmailVerified: false,
      );
      fakeAuth.emitUser(googleUnverified);
      container.read(sessionServiceProvider.notifier);
      await pumpEventQueue();

      expect(readState().status, equals(SessionStatus.unauthenticated));
    });

    test('5. Verified persisted/cold-start session is accepted', () async {
      SharedPreferences.setMockInitialValues({
        'sitelens_onboarding_completed_uid-verified': true,
      });
      fakeAuth.seedPersisted(verifiedUser);
      container.read(sessionServiceProvider.notifier);
      await pumpEventQueue();

      expect(readState().status, equals(SessionStatus.authenticatedReady));
    });

    test('6. Unverified persisted/cold-start session is rejected', () async {
      SharedPreferences.setMockInitialValues({
        'sitelens_onboarding_completed_uid-unverified': true,
      });
      fakeAuth.seedPersisted(unverifiedUser);
      container.read(sessionServiceProvider.notifier);
      await pumpEventQueue();

      expect(readState().status, equals(SessionStatus.unauthenticated));
    });

    test('7. A rejected unverified session retains no authenticated application state',
        () async {
      fakeAuth.seedPersisted(unverifiedUser);
      container.read(sessionServiceProvider.notifier);
      await pumpEventQueue();

      final state = readState();
      expect(state.status, equals(SessionStatus.unauthenticated));
      expect(state.user, isNull);
      expect(state.isOnboardingCompleted, isFalse);
      // Not a partial/accepted session in any form.
      expect(state.status, isNot(SessionStatus.authenticatedReady));
      expect(state.status, isNot(SessionStatus.onboardingRequired));
      // The identity is actively torn down, not merely hidden.
      expect(fakeAuth.signOutCalls, greaterThan(0));
    });

    test('8. Verification-required error semantics are preserved', () {
      const ex = EmailNotVerifiedException(
        email: 'unverified@sitelens.local',
        message: kEmailNotVerifiedExceptionMessage,
      );
      expect(ex.message, equals(kEmailNotVerifiedExceptionMessage));
      expect(ex.toString(), equals(kEmailNotVerifiedExceptionMessage));

      // Session-path reason carries the same verification-required guidance.
      expect(
        SessionTerminationReason.emailNotVerified.defaultMessage,
        equals(kEmailNotVerifiedExceptionMessage),
      );

      // The shared anti-enumeration mapper keeps its verification-required text.
      expect(
        mapAuthErrorToMessage(
          Exception('[firebase_auth/email-not-verified] Not verified.'),
        ),
        equals(kEmailNotVerifiedMessage),
      );
    });

    test('9. Existing verified flows are unchanged (onboarding vs ready preserved)',
        () async {
      // First login, onboarding incomplete -> onboardingRequired.
      SharedPreferences.setMockInitialValues({});
      fakeAuth.emitUser(verifiedUser);
      container.read(sessionServiceProvider.notifier);
      await pumpEventQueue();
      expect(readState().status, equals(SessionStatus.onboardingRequired));
      expect(readState().user?.uid, equals(verifiedUser.uid));
    });
  });
}
