import 'dart:async';
import 'package:sitelens/core/services/auth_service.dart';

class FakeAuthService implements AuthService {
  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? _user;

  FakeAuthService(this._user);

  void setUser(AuthUser? user) {
    _user = user;
    _controller.add(user);
  }

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  void dispose() {
    _controller.close();
  }

  @override
  Future<AuthUser> signInWithEmailPassword(String email, String password) async {
    return _user ??
        AuthUser(
          uid: 'test-user-001',
          email: email,
          displayName: 'Test Inspector',
        );
  }

  @override
  Future<AuthUser?> signInWithGoogle() async {
    return _user;
  }

  @override
  Future<AuthUser> signUpWithEmailPassword(
    String email,
    String password, {
    String? displayName,
  }) async {
    final newUser = AuthUser(
      uid: 'test-user-new',
      email: email,
      displayName: displayName ?? email.split('@').first,
      isEmailVerified: false,
    );
    setUser(newUser);
    return newUser;
  }

  @override
  Future<void> sendEmailVerificationForUser(String email, String password) async {}

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<void> signOut() async {
    setUser(null);
  }
}
