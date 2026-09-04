import 'dart:async';
import 'package:flutter/foundation.dart';
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

class UserSessionState {
  final SessionStatus status;
  final AuthUser? user;
  final bool isOnboardingCompleted;
  final String? errorMessage;

  const UserSessionState({
    required this.status,
    this.user,
    this.isOnboardingCompleted = false,
    this.errorMessage,
  });

  UserSessionState copyWith({
    SessionStatus? status,
    AuthUser? user,
    bool? isOnboardingCompleted,
    String? errorMessage,
  }) {
    return UserSessionState(
      status: status ?? this.status,
      user: user ?? this.user,
      isOnboardingCompleted: isOnboardingCompleted ?? this.isOnboardingCompleted,
      errorMessage: errorMessage,
    );
  }
}

class SessionService extends StateNotifier<UserSessionState> {
  final AuthService _authService;
  final Ref _ref;
  StreamSubscription<AuthUser?>? _authSubscription;
  static const String _onboardingPrefix = 'sitelens_onboarding_completed_';

  SessionService(this._authService, this._ref)
      : super(const UserSessionState(status: SessionStatus.loading)) {
    _init();
  }

  void _init() {
    final initial = _authService.currentUser;
    if (initial == null) {
      state = const UserSessionState(
        status: SessionStatus.unauthenticated,
        user: null,
        isOnboardingCompleted: false,
      );
    } else {
      _evaluateUserState(initial);
    }

    _authSubscription = _authService.authStateChanges.listen((authUser) async {
      if (!mounted) return;
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
      if (!mounted) return;
      debugPrint('SessionService auth stream error: $err');
      state = UserSessionState(
        status: SessionStatus.unauthenticated,
        user: null,
        errorMessage: err.toString(),
      );
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _evaluateUserState(AuthUser authUser) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isCompleted = prefs.getBool('$_onboardingPrefix${authUser.uid}') ?? false;

      // Check current hardware permissions
      final permStatus = await _ref.read(permissionServiceProvider.notifier).checkAllPermissions();

      if (!mounted) return;

      if (!isCompleted || !permStatus.areCorePermissionsGranted) {
        state = UserSessionState(
          status: SessionStatus.onboardingRequired,
          user: authUser,
          isOnboardingCompleted: isCompleted,
        );
      } else {
        state = UserSessionState(
          status: SessionStatus.authenticatedReady,
          user: authUser,
          isOnboardingCompleted: true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('Error evaluating user session state: $e');
      state = UserSessionState(
        status: SessionStatus.onboardingRequired,
        user: authUser,
        isOnboardingCompleted: false,
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
