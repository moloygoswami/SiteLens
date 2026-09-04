import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitelens/app/app.dart';
import 'package:sitelens/core/services/auth_service.dart';

class SmokeTestMockAuthService implements AuthService {
  final _controller = StreamController<AuthUser?>.broadcast();

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  @override
  AuthUser? get currentUser => null;

  @override
  Future<AuthUser> signInWithEmailPassword(String email, String password) async {
    return AuthUser(uid: 'smoke-test-uid', email: email);
  }

  @override
  Future<AuthUser?> signInWithGoogle() async {
    return const AuthUser(uid: 'smoke-test-uid', email: 'google@sitelens.local');
  }

  @override
  Future<AuthUser> signUpWithEmailPassword(
    String email,
    String password, {
    String? displayName,
  }) async {
    return AuthUser(uid: 'smoke-test-uid', email: email);
  }

  @override
  Future<void> sendEmailVerificationForUser(String email, String password) async {}

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<void> signOut() async {}
}

void main() {
  testWidgets('SiteLensApp loads root widget smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(SmokeTestMockAuthService()),
        ],
        child: const SiteLensApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('SiteLens'), findsOneWidget);
  });
}
