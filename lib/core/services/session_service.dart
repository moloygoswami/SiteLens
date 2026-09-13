import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'permission_service.dart';

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
  StreamSubscription<AuthUser?>? _authSubscription;
  static const String _onboardingPrefix = 'sitelens_onboarding_completed_';

  Future<SessionVerificationResult>? _activeVerificationFuture;
  bool _isDisposed = false;

  SessionService(this._authService, this._ref)
      : super(const UserSessionState(status: SessionStatus.loading)) {
    _init();
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
      _evaluateUserState(initial).then((_) {
        if (mounted && !_isDisposed && state.user != null) {
          unawaited(verifySession());
        }
      });
    }

    _authSubscription = _authService.authStateChanges.listen((authUser) async {
      if (!mounted || _isDisposed) return;
      if (authUser == null) {
        state = const UserSessionState(
          status: SessionStatus.unauthenticated,
          user: null,
          isOnboardingCompleted: false,
        );
      } else {
        await _evaluateUserState(authUser);
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

    if (_activeVerificationFuture != null) {
      return await _activeVerificationFuture!;
    }

    final future = _runVerification();
    _activeVerificationFuture = future;
    try {
      return await future;
    } finally {
      _activeVerificationFuture = null;
    }
  }

  Future<SessionVerificationResult> _runVerification() async {
    final result = await _authService.verifySession();
    if (_isDisposed || !mounted) return result;

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

  Future<void> _evaluateUserState(AuthUser authUser) async {
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
  return SessionService(authService, ref);
});
