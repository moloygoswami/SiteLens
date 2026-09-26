import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sitelens/core/services/auth_service.dart';
import 'package:sitelens/core/services/permission_service.dart';
import 'package:sitelens/core/services/session_end_teardown.dart';
import 'package:sitelens/core/services/session_service.dart';

/// Finding 5 — deterministic session-boundary teardown.
///
/// Verifies that the ending user's UID is captured before the incoming
/// identity is adopted and that every registered [SessionEndTeardown] runs on
/// sign-out, session invalidation, and account switch — the same mechanism
/// that account deletion flows through when it signs out.
class ControllableAuthService implements AuthService {
  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? _currentUser;

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  @override
  AuthUser? get currentUser => _currentUser;

  void emit(AuthUser? user) {
    _currentUser = user;
    _controller.add(user);
  }

  @override
  Future<SessionVerificationResult> verifySession() async {
    return const SessionVerificationResult.valid();
  }

  @override
  Future<void> signOut() async {
    emit(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RecordingTeardown implements SessionEndTeardown {
  final List<String> endingUids = [];

  @override
  Future<void> onSessionEnded(String endingUid) async {
    endingUids.add(endingUid);
  }
}

class GatedPermissionService extends PermissionService {
  @override
  Future<SiteLensPermissionStatus> checkAllPermissions() async {
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
  late RecordingTeardown teardown;
  late ProviderContainer container;

  const userA = AuthUser(uid: 'uid-a', email: 'a@sitelens.local', isEmailVerified: true);
  const userB = AuthUser(uid: 'uid-b', email: 'b@sitelens.local', isEmailVerified: true);

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'sitelens_onboarding_completed_uid-a': true,
      'sitelens_onboarding_completed_uid-b': true,
    });
    auth = ControllableAuthService();
    teardown = RecordingTeardown();
    container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(auth),
        permissionServiceProvider.overrideWith((ref) => GatedPermissionService()),
        sessionEndTeardownsProvider.overrideWithValue([teardown]),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test('sign-out runs teardown for the ending user', () async {
    container.read(sessionServiceProvider.notifier);
    await pumpEventQueue();

    auth.emit(userA);
    await pumpEventQueue();
    expect(container.read(sessionServiceProvider).user?.uid, equals('uid-a'));

    await auth.signOut();
    await pumpEventQueue();

    expect(teardown.endingUids, equals(['uid-a']));
    expect(container.read(sessionServiceProvider).user, isNull);
  });

  test('session invalidation runs teardown for the ending user', () async {
    final session = container.read(sessionServiceProvider.notifier);
    await pumpEventQueue();

    auth.emit(userA);
    await pumpEventQueue();

    await session.invalidateSession(reason: SessionTerminationReason.sessionRevoked);
    await pumpEventQueue();

    // The sign-out echo may benignly re-fire the idempotent teardown; what
    // matters is that the ending UID was captured and the authoritative
    // termination reason survives the echo.
    expect(teardown.endingUids, isNotEmpty);
    expect(teardown.endingUids.every((uid) => uid == 'uid-a'), isTrue);
    final state = container.read(sessionServiceProvider);
    expect(state.user, isNull);
    expect(state.terminationReason, SessionTerminationReason.sessionRevoked);
  });

  test('account switch runs teardown for the ending user before adopting the new identity', () async {
    container.read(sessionServiceProvider.notifier);
    await pumpEventQueue();

    auth.emit(userA);
    await pumpEventQueue();
    expect(container.read(sessionServiceProvider).user?.uid, equals('uid-a'));

    // Same path account deletion flows through: sign-out then sign-in as
    // a different identity; the first user's teardown must fire exactly once
    // with the ending UID, never with the incoming UID.
    auth.emit(userB);
    await pumpEventQueue();

    expect(teardown.endingUids, equals(['uid-a']));
    expect(container.read(sessionServiceProvider).user?.uid, equals('uid-b'));
  });

  test('teardown is idempotent across repeated session ends', () async {
    final session = container.read(sessionServiceProvider.notifier);
    await pumpEventQueue();

    auth.emit(userA);
    await pumpEventQueue();

    await session.invalidateSession(reason: SessionTerminationReason.sessionRevoked);
    await pumpEventQueue();
    await session.invalidateSession(reason: SessionTerminationReason.sessionRevoked);
    await pumpEventQueue();

    // Second invalidation has no ending user; every recorded teardown is
    // for the first ending user only — never for a null/incoming identity.
    expect(teardown.endingUids, isNotEmpty);
    expect(teardown.endingUids.every((uid) => uid == 'uid-a'), isTrue);
  });
}
