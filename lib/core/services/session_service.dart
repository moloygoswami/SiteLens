import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'permission_service.dart';
import 'session_end_teardown.dart';

enum SessionStatus {
  loading,
  unauthenticated,
  onboardingRequired,
  authenticatedReady,
}

enum SessionAnomalyResolution {
  sessionInvalidated,
  sitePermissionDenied,
  retryable,
}

class UserSessionState {
  final SessionStatus status;
  final AuthUser? user;
  final bool isOnboardingCompleted;
  final String? errorMessage;
  final SessionTerminationReason? terminationReason;

  const UserSessionState({
    required this.status,
    this.user,
    this.isOnboardingCompleted = false,
    this.errorMessage,
    this.terminationReason,
  });

  UserSessionState copyWith({
    SessionStatus? status,
    AuthUser? user,
    bool? isOnboardingCompleted,
    String? errorMessage,
    SessionTerminationReason? terminationReason,
  }) {
    return UserSessionState(
      status: status ?? this.status,
      user: user ?? this.user,
      isOnboardingCompleted: isOnboardingCompleted ?? this.isOnboardingCompleted,
      errorMessage: errorMessage,
      terminationReason: terminationReason ?? this.terminationReason,
    );
  }
}

class SessionService extends StateNotifier<UserSessionState> with WidgetsBindingObserver {
  final AuthService _authService;
  final Ref _ref;
  final List<SessionEndTeardown> _sessionEndTeardowns;
  StreamSubscription<AuthUser?>? _authSubscription;
  static const String _onboardingPrefix = 'sitelens_onboarding_completed_';

  Future<SessionVerificationResult>? _activeVerificationFuture;
  bool _isDisposed = false;

  /// Monotonic session-generation token (`02_ARCHITECTURE.MD` §6.2,
  /// `04_SECURITY.MD` §9).
  ///
  /// Advanced on every session transition — a new sign-in, a sign-out, or an
  /// authoritative invalidation. Any asynchronous work that began under an
  /// earlier generation is discarded on arrival, so a stale result produced for
  /// a previous session can never become authoritative for the current one.
  int _sessionGeneration = 0;

  /// The current session generation. See [_sessionGeneration].
  int get sessionGeneration => _sessionGeneration;

  /// Whether [generation] is still the active session generation.
  bool isCurrentGeneration(int generation) => generation == _sessionGeneration;

  SessionService(
    this._authService,
    this._ref, {
    List<SessionEndTeardown> sessionEndTeardowns = const [],
  })  : _sessionEndTeardowns = sessionEndTeardowns,
        super(const UserSessionState(status: SessionStatus.loading)) {
    _init();
  }

  /// Awaits every registered [SessionEndTeardown] for [endingUid], logging but
  /// never rethrowing individual teardown failures so that session termination
  /// remains deterministic and the user is never left in a partial state.
  Future<void> _runSessionEndTeardowns(String endingUid) async {
    for (final teardown in _sessionEndTeardowns) {
      try {
        await teardown.onSessionEnded(endingUid);
      } catch (e) {
        debugPrint('SessionEndTeardown error for uid $endingUid: $e');
      }
    }
  }

  /// Opens a new session generation, superseding every in-flight operation that
  /// was tagged with the previous one. Returns the new generation.
  int _beginSessionTransition() {
    _sessionGeneration++;
    // A verification in flight for the previous generation must never be
    // shared with, or awaited by, the new one.
    _activeVerificationFuture = null;
    return _sessionGeneration;
  }

  void _init() {
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {
      // WidgetsBinding not initialized (e.g. in pure unit tests)
    }

    final initial = _authService.currentUser;
    if (initial == null) {
      state = const UserSessionState(
        status: SessionStatus.unauthenticated,
        user: null,
        isOnboardingCompleted: false,
      );
    } else {
      final generation = _sessionGeneration;
      _evaluateUserState(initial, generation).then((_) {
        if (mounted && !_isDisposed && state.user != null) {
          unawaited(verifySession());
        }
      });
    }

    _authSubscription = _authService.authStateChanges.listen((authUser) async {
      if (!mounted || _isDisposed) return;
      final endingUid = state.user?.uid;
      final generation = _beginSessionTransition();
      if (authUser == null) {
        if (endingUid != null) {
          await _runSessionEndTeardowns(endingUid);
        }
        if (!mounted || _isDisposed) return;
        // A trailing sign-out echo after an authoritative termination
        // (invalidateSession already cleared the user and recorded its
        // reason) must neither re-run teardown nor clobber the reason.
        if (state.user == null && state.status == SessionStatus.unauthenticated) {
          return;
        }
        _applyUnauthenticatedState();
      } else {
        if (endingUid != null && endingUid != authUser.uid) {
          await _runSessionEndTeardowns(endingUid);
        }
        await _evaluateUserState(authUser, generation);
      }
    }, onError: (err) {
      if (!mounted || _isDisposed) return;
      debugPrint('SessionService auth stream error: $err');
      state = UserSessionState(
        status: SessionStatus.unauthenticated,
        user: null,
        errorMessage: err.toString(),
      );
    });
  }

  void _applyUnauthenticatedState() {
    if (_isDisposed || !mounted) return;
    state = const UserSessionState(
      status: SessionStatus.unauthenticated,
      user: null,
      isOnboardingCompleted: false,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && !_isDisposed) {
      if (this.state.user != null) {
        unawaited(verifySession());
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    _authSubscription?.cancel();
    super.dispose();
  }

  /// Race/disposal-safe verification of the active session with the auth server.
  /// Deduplicates concurrent verification attempts by sharing a single in-flight future.
  Future<SessionVerificationResult> verifySession() async {
    if (_isDisposed || !mounted) {
      return const SessionVerificationResult.networkUnreachable();
    }

    final existing = _activeVerificationFuture;
    if (existing != null) {
      return await existing;
    }

    final future = _runVerification();
    _activeVerificationFuture = future;
    try {
      return await future;
    } finally {
      // Only clear the slot if it still holds this future; a session transition
      // may already have superseded it.
      if (identical(_activeVerificationFuture, future)) {
        _activeVerificationFuture = null;
      }
    }
  }

  Future<SessionVerificationResult> _runVerification() async {
    final generation = _sessionGeneration;
    final result = await _authService.verifySession();
    if (_isDisposed || !mounted) return result;

    // A result produced for a superseded session generation is not
    // authoritative for the current session and must not drive its state
    // (`02_ARCHITECTURE.MD` §6.2).
    if (!isCurrentGeneration(generation)) return result;

    if (!result.isValid && !result.isNetworkUnreachable) {
      await invalidateSession(
        reason: result.reason ?? SessionTerminationReason.unauthenticated,
        message: result.message,
      );
    }
    return result;
  }

  /// Authoritative policy resolution on an unexpected operation anomaly
  /// (e.g. permission-denied or unauthenticated during Firestore/Storage operations).
  ///
  /// Contextual evidence rule:
  /// - Does NOT automatically equate permission-denied with logout or permanent site denial.
  /// - Verifies the session to establish whether the error is auth-level or resource-level.
  Future<SessionAnomalyResolution> handleOperationAnomaly({
    required String operationErrorCode,
    String? siteId,
    String? details,
  }) async {
    if (_isDisposed || !mounted) return SessionAnomalyResolution.retryable;

    final verification = await verifySession();
    if (_isDisposed || !mounted) return SessionAnomalyResolution.retryable;

    if (!verification.isValid && !verification.isNetworkUnreachable) {
      // Confirmed invalid auth session
      return SessionAnomalyResolution.sessionInvalidated;
    }

    if (verification.isNetworkUnreachable) {
      // Network unreachable: fail-open, treat as retryable
      return SessionAnomalyResolution.retryable;
    }

    // Session is confirmed valid!
    if (operationErrorCode == 'permission-denied') {
      // Resource-level denial (e.g. site membership)
      return SessionAnomalyResolution.sitePermissionDenied;
    }

    // unauthenticated but session verified valid -> token might have just refreshed, retryable
    return SessionAnomalyResolution.retryable;
  }

  /// Authoritatively terminates the session:
  /// Signs out, clears user state, records termination reason, and transitions to unauthenticated.
  Future<void> invalidateSession({
    required SessionTerminationReason reason,
    String? message,
  }) async {
    // Capture the ending identity before it can be superseded, then advance
    // the generation so any in-flight work tagged with the prior generation
    // is discarded on arrival rather than applied on top of this termination
    // (`02_ARCHITECTURE.MD` §6.2, `04_SECURITY.MD` §9).
    final endingUid = state.user?.uid;
    _beginSessionTransition();

    if (endingUid != null) {
      await _runSessionEndTeardowns(endingUid);
    }

    try {
      await _authService.signOut();
    } catch (e) {
      debugPrint('Error signing out during session invalidation: $e');
    }

    if (_isDisposed || !mounted) return;

    state = UserSessionState(
      status: SessionStatus.unauthenticated,
      user: null,
      isOnboardingCompleted: false,
      terminationReason: reason,
      errorMessage: message ?? reason.defaultMessage,
    );
  }

  Future<void> _evaluateUserState(AuthUser authUser, int generation) async {
    // Authoritative session boundary (`04_SECURITY.MD` §2, `05_ACCEPTANCE.MD`
    // AC-AUTH-04/AC-AUTH-05). Every accepted application session — email or
    // Google sign-in, persisted-session restoration, cold start, or any auth
    // state hydration — funnels through here, so gating on the identity's
    // `emailVerified` claim at this single point prevents an unverified user
    // from obtaining an accepted session by bypassing the UI. No partial
    // authenticated state is created: the identity is torn down and the session
    // is rejected.
    if (!authUser.isEmailVerified) {
      await invalidateSession(
        reason: SessionTerminationReason.emailNotVerified,
        message: kEmailNotVerifiedExceptionMessage,
      );
      return;
    }

    bool isCompleted = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      isCompleted = prefs.getBool('$_onboardingPrefix${authUser.uid}') ?? false;

      // Check current hardware permissions
      try {
        await _ref.read(permissionServiceProvider.notifier).checkAllPermissions();
      } catch (permErr) {
        debugPrint('SessionService permission check error: $permErr');
      }

      if (!mounted || _isDisposed) return;
      if (!isCurrentGeneration(generation)) return;
      if (_authService.currentUser?.uid != authUser.uid ||
          state.terminationReason != null) {
        return;
      }

      if (!isCompleted) {
        state = UserSessionState(
          status: SessionStatus.onboardingRequired,
          user: authUser,
          isOnboardingCompleted: false,
        );
      } else {
        state = UserSessionState(
          status: SessionStatus.authenticatedReady,
          user: authUser,
          isOnboardingCompleted: true,
        );
      }
    } catch (e) {
      if (!mounted || _isDisposed) return;
      if (!isCurrentGeneration(generation)) return;
      if (_authService.currentUser?.uid != authUser.uid ||
          state.terminationReason != null) {
        return;
      }
      debugPrint('Error evaluating user session state: $e');
      state = UserSessionState(
        status: isCompleted
            ? SessionStatus.authenticatedReady
            : SessionStatus.onboardingRequired,
        user: authUser,
        isOnboardingCompleted: isCompleted,
      );
    }
  }

  Future<void> completeOnboarding(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_onboardingPrefix$uid', true);

      if (mounted && state.user?.uid == uid) {
        state = state.copyWith(
          status: SessionStatus.authenticatedReady,
          isOnboardingCompleted: true,
        );
      }
    } catch (e) {
      debugPrint('Error completing onboarding: $e');
    }
  }

  Future<void> resetOnboardingForUser(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_onboardingPrefix$uid');

      if (mounted && state.user?.uid == uid) {
        state = state.copyWith(
          status: SessionStatus.onboardingRequired,
          isOnboardingCompleted: false,
        );
      }
    } catch (e) {
      debugPrint('Error resetting onboarding: $e');
    }
  }

  Future<bool> isOnboardingCompletedForUser(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_onboardingPrefix$uid') ?? false;
  }
}

final sessionServiceProvider =
    StateNotifierProvider<SessionService, UserSessionState>((ref) {
  final authService = ref.watch(authServiceProvider);
  final teardowns = ref.watch(sessionEndTeardownsProvider);
  return SessionService(authService, ref, sessionEndTeardowns: teardowns);
});
