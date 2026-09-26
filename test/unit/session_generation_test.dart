import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sitelens/core/services/auth_service.dart';
import 'package:sitelens/core/services/permission_service.dart';
import 'package:sitelens/core/services/session_service.dart';

/// Slice 1A — monotonic session-generation authority and stale-work discard.
///
/// Verifies the session-transition requirements of `02_ARCHITECTURE.MD` §6.2
/// and `04_SECURITY.MD` §9 against `05_ACCEPTANCE.MD` AC-SECB-14 / AC-SYNC-09:
/// a monotonic counter is incremented at each session boundary so that any
/// in-flight asynchronous work tagged with a prior generation is discarded on
/// arrival rather than becoming authoritative for the new session.
class ControllableAuthService implements AuthService {
  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? _currentUser;
  Completer<SessionVerificationResult>? _pendingVerification;
  int signOutCount = 0;

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  @override
  AuthUser? get currentUser => _currentUser;

  void emit(AuthUser? user) {
    _currentUser = user;
    _controller.add(user);
  }

  /// Makes the next [verifySession] return an unresolved future that the test
  /// completes explicitly.
  void beginPendingVerification() {
    _pendingVerification = Completer<SessionVerificationResult>();
  }

  void completePendingVerification(SessionVerificationResult result) {
    final pending = _pendingVerification;
    _pendingVerification = null;
    pending?.complete(result);
  }

  @override
  Future<SessionVerificationResult> verifySession() async {
    final pending = _pendingVerification;
    if (pending != null) return pending.future;
    return const SessionVerificationResult.valid();
  }

  @override
  Future<void> signOut() async {
    signOutCount++;
    emit(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class GatedPermissionService extends PermissionService {
  Completer<void>? gate;

  @override
  Future<SiteLensPermissionStatus> checkAllPermissions() async {
    final pending = gate;
    if (pending != null) {
      await pending.future;
    }
    state = const SiteLensPermissionStatus(
      camera: PermissionStatus.granted,
      location: PermissionStatus.granted,
    );
    return state;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ControllableAuthService auth;
  late GatedPermissionService permissions;
  late ProviderContainer container;

  const userA = AuthUser(uid: 'uid-a', email: 'a@sitelens.local', isEmailVerified: true);
  const userB = AuthUser(uid: 'uid-b', email: 'b@sitelens.local', isEmailVerified: true);

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'sitelens_onboarding_completed_uid-a': true,
      'sitelens_onboarding_completed_uid-b': true,
    });
    auth = ControllableAuthService();
    permissions = GatedPermissionService();
    container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(auth),
        permissionServiceProvider.overrideWith((ref) => permissions),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test('sessionGeneration advances monotonically across a sign-out transition', () async {
    final session = container.read(sessionServiceProvider.notifier);
    await pumpEventQueue();

    auth.emit(userA);
    await pumpEventQueue();
    expect(container.read(sessionServiceProvider).status, SessionStatus.authenticatedReady);

    final generationBeforeSignOut = session.sessionGeneration;

    await auth.signOut();
    await pumpEventQueue();

    expect(session.sessionGeneration, greaterThan(generationBeforeSignOut));
    expect(session.isCurrentGeneration(generationBeforeSignOut), isFalse);
    expect(session.isCurrentGeneration(session.sessionGeneration), isTrue);
    expect(container.read(sessionServiceProvider).status, SessionStatus.unauthenticated);
  });

  test('invalidateSession advances the generation and terminates the session', () async {
    final session = container.read(sessionServiceProvider.notifier);
    await pumpEventQueue();

    auth.emit(userA);
    await pumpEventQueue();
    final generationBeforeInvalidation = session.sessionGeneration;

    await session.invalidateSession(reason: SessionTerminationReason.sessionRevoked);
    await pumpEventQueue();

    expect(session.sessionGeneration, greaterThan(generationBeforeInvalidation));

    final state = container.read(sessionServiceProvider);
    expect(state.status, SessionStatus.unauthenticated);
    expect(state.user, isNull);
    expect(state.terminationReason, SessionTerminationReason.sessionRevoked);
  });

  test('a verification result from a superseded generation never invalidates the current session', () async {
    final session = container.read(sessionServiceProvider.notifier);
    await pumpEventQueue();

    auth.emit(userA);
    await pumpEventQueue();
    expect(container.read(sessionServiceProvider).status, SessionStatus.authenticatedReady);

    // Begin a verification for identity A that stays in flight.
    auth.beginPendingVerification();
    final pending = session.verifySession();

    // A different identity signs in while A's verification has not resolved.
    auth.emit(userB);
    await pumpEventQueue();
    expect(container.read(sessionServiceProvider).user?.uid, equals(userB.uid));

    // A's verification now resolves as invalid; it must be discarded.
    auth.completePendingVerification(
      const SessionVerificationResult.invalid(SessionTerminationReason.userDisabled),
    );
    await pending;
    await pumpEventQueue();

    final state = container.read(sessionServiceProvider);
    expect(state.status, SessionStatus.authenticatedReady);
    expect(state.user?.uid, equals(userB.uid));
    expect(state.terminationReason, isNull);
    expect(auth.signOutCount, equals(0));
  });

  test('an onboarding evaluation belonging to a signed-out session is discarded', () async {
    container.read(sessionServiceProvider.notifier);
    await pumpEventQueue();

    // Block the permission lookup so A's evaluation cannot complete immediately.
    permissions.gate = Completer<void>();
    auth.emit(userA);
    await pumpEventQueue();

    // Sign out before A's evaluation resolves.
    await auth.signOut();
    await pumpEventQueue();
    expect(container.read(sessionServiceProvider).status, SessionStatus.unauthenticated);

    // Release the stale evaluation; it must not resurrect authenticated state.
    permissions.gate?.complete();
    permissions.gate = null;
    await pumpEventQueue();

    final state = container.read(sessionServiceProvider);
    expect(state.status, SessionStatus.unauthenticated);
    expect(state.user, isNull);
  });

  test('concurrent verifications share one passing generation and do not advance it', () async {
    final session = container.read(sessionServiceProvider.notifier);
    await pumpEventQueue();

    auth.emit(userA);
    await pumpEventQueue();
    final generationBefore = session.sessionGeneration;

    final results = await Future.wait([
      session.verifySession(),
      session.verifySession(),
      session.verifySession(),
    ]);
    await pumpEventQueue();

    expect(results.every((r) => r.isValid), isTrue);
    expect(session.sessionGeneration, equals(generationBefore));
    expect(container.read(sessionServiceProvider).status, SessionStatus.authenticatedReady);
  });
}
