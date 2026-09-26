import 'dart:async';
import 'dart:ffi';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/open.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sitelens/app/router.dart';
import 'package:sitelens/core/services/auth_service.dart';
import 'package:sitelens/core/utils/auth_error_mapper.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/local/database/database_provider.dart';
import 'package:sitelens/features/auth/login_screen.dart';
import 'package:sitelens/features/auth/signup_screen.dart';
import 'package:sitelens/shared/widgets/primary_button.dart';

class Slice1CMockAuthService implements AuthService {
  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? _currentUser;
  Object? errorToThrow;
  Completer<AuthUser>? signInCompleter;
  String? lastPasswordResetEmail;
  String? lastResendEmail;
  String? lastResendPassword;
  int signOutCallCount = 0;

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  @override
  AuthUser? get currentUser => _currentUser;

  @override
  Future<AuthUser> signInWithEmailPassword(String email, String password) async {
    if (signInCompleter != null) {
      return await signInCompleter!.future;
    }
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    final user = AuthUser(uid: 'test-user-123', email: email);
    _currentUser = user;
    _controller.add(user);
    return user;
  }

  @override
  Future<AuthUser?> signInWithGoogle() async {
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    final user = const AuthUser(uid: 'test-google-123', email: 'test@sitelens.local');
    _currentUser = user;
    _controller.add(user);
    return user;
  }

  @override
  Future<AuthUser> signUpWithEmailPassword(
    String email,
    String password, {
    String? displayName,
  }) async {
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    final user = AuthUser(uid: 'test-signup-123', email: email, displayName: displayName ?? '');
    _currentUser = user;
    _controller.add(user);
    return user;
  }

  @override
  Future<void> sendEmailVerificationForUser(String email, String password) async {
    lastResendEmail = email;
    lastResendPassword = password;
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    lastPasswordResetEmail = email;
  }

  @override
  Future<SessionVerificationResult> verifySession() async => const SessionVerificationResult.valid();

  @override
  Future<void> signOut() async {
    signOutCallCount++;
    _currentUser = null;
    _controller.add(null);
  }
}

void main() {
  late AppDatabase db;
  late Slice1CMockAuthService mockAuth;

  setUpAll(() {
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    mockAuth = Slice1CMockAuthService();
  });

  tearDown(() async {
    await db.close();
  });

  Widget buildTestApp({Widget? home, String? initialRoute}) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        authServiceProvider.overrideWithValue(mockAuth),
      ],
      child: MaterialApp(
        navigatorKey: rootNavigatorKey,
        navigatorObservers: [appRouteObserver],
        onGenerateRoute: AppRoutes.onGenerateRoute,
        initialRoute: initialRoute,
        home: home,
      ),
    );
  }

  group('Slice 1C: Authentication UI Conformance', () {
    // 1. Welcome Screen Behavior
    testWidgets('1. Welcome screen renders brand, highlights, and navigates to Login', (tester) async {
      await tester.pumpWidget(buildTestApp(initialRoute: AppRoutes.welcome));
      await tester.pumpAndSettle();

      expect(find.text('SiteLens'), findsOneWidget);
      expect(find.text('GPS-Verified Construction Evidence'), findsOneWidget);
      expect(find.text('Burned-in Geotagging'), findsOneWidget);
      expect(find.text('Before/After Smart-Link'), findsOneWidget);
      expect(find.text('100% Offline-First'), findsOneWidget);

      final getStartedBtn = find.widgetWithText(PrimaryButton, 'Get Started');
      expect(getStartedBtn, findsOneWidget);

      await tester.ensureVisible(getStartedBtn);
      await tester.tap(getStartedBtn);
      await tester.pumpAndSettle();

      // Verify transitioned to LoginScreen
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Sign In'), findsNWidgets(2)); // Title & Button
    });

    // 2. Login Validation
    testWidgets('2. Login validation rejects empty email and empty password', (tester) async {
      await tester.pumpWidget(buildTestApp(home: const LoginScreen()));
      await tester.pumpAndSettle();

      final signInBtn = find.widgetWithText(PrimaryButton, 'Sign In');
      await tester.ensureVisible(signInBtn);
      await tester.tap(signInBtn);
      await tester.pumpAndSettle();

      expect(find.text('Please enter your work email'), findsOneWidget);

      // Enter email but leave password empty
      final emailField = find.byType(TextFormField).at(0);
      await tester.enterText(emailField, 'inspector@company.com');
      await tester.tap(signInBtn);
      await tester.pumpAndSettle();

      expect(find.text('Please enter your password'), findsOneWidget);
    });

    // 3. Uniform Credential-Error Presentation (Anti-Enumeration)
    testWidgets('3. Uniform credential failure presentation masks account existence (AC-AUTH-08)', (tester) async {
      await tester.pumpWidget(buildTestApp(home: const LoginScreen()));
      await tester.pumpAndSettle();

      final emailField = find.byType(TextFormField).at(0);
      final passField = find.byType(TextFormField).at(1);
      final termsBox = find.byType(Checkbox);
      final signInBtn = find.widgetWithText(PrimaryButton, 'Sign In');

      await tester.enterText(emailField, 'unknown@company.com');
      await tester.enterText(passField, 'Secret123!');
      await tester.ensureVisible(termsBox);
      await tester.tap(termsBox);
      await tester.pumpAndSettle();

      // Case A: user-not-found
      mockAuth.errorToThrow = Exception('[firebase_auth/user-not-found] No user record.');
      await tester.ensureVisible(signInBtn);
      await tester.tap(signInBtn);
      await tester.pumpAndSettle();

      expect(find.text(kUniformCredentialFailureMessage), findsOneWidget);
      expect(find.textContaining('user-not-found'), findsNothing);
      expect(find.textContaining('No user record'), findsNothing);

      // Case B: wrong-password
      mockAuth.errorToThrow = Exception('[firebase_auth/wrong-password] Invalid password.');
      await tester.tap(signInBtn);
      await tester.pumpAndSettle();

      expect(find.text(kUniformCredentialFailureMessage), findsOneWidget);
      expect(find.textContaining('wrong-password'), findsNothing);

      // Case C: user-disabled
      mockAuth.errorToThrow = Exception('[firebase_auth/user-disabled] Account disabled.');
      await tester.tap(signInBtn);
      await tester.pumpAndSettle();

      expect(find.text(kUniformCredentialFailureMessage), findsOneWidget);
      expect(find.textContaining('user-disabled'), findsNothing);

      // Case D: invalid-credential
      mockAuth.errorToThrow = Exception('[firebase_auth/invalid-credential] Invalid credential.');
      await tester.tap(signInBtn);
      await tester.pumpAndSettle();

      expect(find.text(kUniformCredentialFailureMessage), findsOneWidget);
    });

    // 4. Loading-State Behavior
    testWidgets('4. Loading state disables form inputs and displays progress indicator', (tester) async {
      mockAuth.signInCompleter = Completer<AuthUser>();

      await tester.pumpWidget(buildTestApp(home: const LoginScreen()));
      await tester.pumpAndSettle();

      final emailField = find.byType(TextFormField).at(0);
      final passField = find.byType(TextFormField).at(1);
      final termsBox = find.byType(Checkbox);
      final signInBtn = find.widgetWithText(PrimaryButton, 'Sign In');

      await tester.enterText(emailField, 'inspector@company.com');
      await tester.enterText(passField, 'Secret123!');
      await tester.ensureVisible(termsBox);
      await tester.tap(termsBox);
      await tester.pumpAndSettle();

      await tester.ensureVisible(signInBtn);
      await tester.tap(signInBtn);
      // Pump once so state updates to _isLoading = true
      await tester.pump();

      // Verify PrimaryButton has CircularProgressIndicator
      expect(find.descendant(of: find.byType(PrimaryButton), matching: find.byType(CircularProgressIndicator)), findsOneWidget);

      // Verify form fields are disabled
      final emailWidget = tester.widget<TextFormField>(find.byType(TextFormField).at(0));
      final passWidget = tester.widget<TextFormField>(find.byType(TextFormField).at(1));
      expect(emailWidget.enabled, isFalse);
      expect(passWidget.enabled, isFalse);

      // Complete async sign-in
      mockAuth.signInCompleter!.complete(const AuthUser(uid: 'u1', email: 'inspector@company.com'));
      await tester.pumpAndSettle();
    });

    // 5. Unverified-Account Behavior and Resend Action
    testWidgets('5. Unverified account surfaces warning banner and triggers resend action', (tester) async {
      mockAuth.errorToThrow = const EmailNotVerifiedException(
        message: 'Your email address has not been verified yet. Please check your inbox for the verification link.',
        email: 'unverified@sitelens.local',
      );

      await tester.pumpWidget(buildTestApp(home: const LoginScreen()));
      await tester.pumpAndSettle();

      final emailField = find.byType(TextFormField).at(0);
      final passField = find.byType(TextFormField).at(1);
      final termsBox = find.byType(Checkbox);
      final signInBtn = find.widgetWithText(PrimaryButton, 'Sign In');

      await tester.enterText(emailField, 'unverified@sitelens.local');
      await tester.enterText(passField, 'Password123!');
      await tester.ensureVisible(termsBox);
      await tester.tap(termsBox);
      await tester.pumpAndSettle();

      await tester.ensureVisible(signInBtn);
      await tester.tap(signInBtn);
      await tester.pumpAndSettle();

      // Warning banner is displayed
      expect(find.textContaining('Your email address has not been verified yet'), findsOneWidget);

      // Inline Resend Verification Email button is present
      final resendBtn = find.widgetWithText(OutlinedButton, 'Resend Verification Email');
      expect(resendBtn, findsOneWidget);

      // Tap Resend
      await tester.tap(resendBtn);
      await tester.pumpAndSettle();

      expect(mockAuth.lastResendEmail, equals('unverified@sitelens.local'));
      expect(find.textContaining('Verification email resent to unverified@sitelens.local'), findsOneWidget);
    });

    // 6. Forgot-Password Behavior
    testWidgets('6. Forgot-password pre-fills email, validates, and dispatches reset email', (tester) async {
      await tester.pumpWidget(buildTestApp(home: const LoginScreen()));
      await tester.pumpAndSettle();

      final emailField = find.byType(TextFormField).at(0);
      await tester.enterText(emailField, 'engineer@site.com');

      final forgotPassBtn = find.text('Forgot Password?');
      expect(forgotPassBtn, findsOneWidget);
      await tester.tap(forgotPassBtn);
      await tester.pumpAndSettle();

      // Reset Password dialog appears
      expect(find.text('Reset Password'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Send Reset Link'), findsOneWidget);

      // Verify email was pre-filled in dialog
      final dialogEmailField = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField));
      expect(dialogEmailField, findsOneWidget);
      final dialogEmailWidget = tester.widget<TextFormField>(dialogEmailField);
      expect(dialogEmailWidget.controller?.text, equals('engineer@site.com'));

      // Tap Send Reset Link
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send Reset Link'));
      await tester.pumpAndSettle();

      expect(mockAuth.lastPasswordResetEmail, equals('engineer@site.com'));
      expect(find.textContaining('Password reset link sent to engineer@site.com'), findsOneWidget);
    });

    // 7. Sign-Up Validation
    testWidgets('7. Sign-up validation enforces required fields, email format, and password length/match', (tester) async {
      await tester.pumpWidget(buildTestApp(home: const SignupScreen()));
      await tester.pumpAndSettle();

      final createBtn = find.widgetWithText(PrimaryButton, 'Create Account');
      final nameField = find.byType(TextFormField).at(0);
      final emailField = find.byType(TextFormField).at(1);
      final passField = find.byType(TextFormField).at(2);
      final confirmPassField = find.byType(TextFormField).at(3);
      final termsBox = find.byType(Checkbox);

      // A: Empty Name
      await tester.ensureVisible(createBtn);
      await tester.tap(createBtn);
      await tester.pumpAndSettle();
      expect(find.text('Please enter your full name'), findsOneWidget);

      // B: Invalid Email
      await tester.enterText(nameField, 'Alice Engineer');
      await tester.enterText(emailField, 'notanemail');
      await tester.ensureVisible(createBtn);
      await tester.tap(createBtn);
      await tester.pumpAndSettle();
      expect(find.text('Please enter a valid email address'), findsOneWidget);

      // C: Short Password (< 6 chars)
      await tester.enterText(emailField, 'alice@company.com');
      await tester.enterText(passField, '123');
      await tester.ensureVisible(createBtn);
      await tester.tap(createBtn);
      await tester.pumpAndSettle();
      expect(find.text('Password must be at least 6 characters'), findsOneWidget);

      // D: Mismatched Password
      await tester.enterText(passField, 'Secret123!');
      await tester.enterText(confirmPassField, 'Different123!');
      await tester.ensureVisible(createBtn);
      await tester.tap(createBtn);
      await tester.pumpAndSettle();
      expect(find.text('Passwords do not match'), findsOneWidget);

      // E: Passwords match but Terms unchecked
      await tester.enterText(confirmPassField, 'Secret123!');
      await tester.ensureVisible(createBtn);
      await tester.tap(createBtn);
      await tester.pumpAndSettle();
      expect(find.text('Please agree to the Terms of Service and Privacy Policy to create an account.'), findsOneWidget);

      // F: Check Terms and successfully submit
      await tester.ensureVisible(termsBox);
      await tester.tap(termsBox);
      await tester.pumpAndSettle();
      await tester.ensureVisible(createBtn);
      await tester.tap(createBtn);
      await tester.pumpAndSettle();

      // Verify sign-up succeeded and moved to verification screen
      expect(find.text('Verify Your Email'), findsOneWidget);
    });

    // 8. Required Terms/Privacy Agreement
    testWidgets('8. Terms/Privacy agreement is required for email login and Google login', (tester) async {
      await tester.pumpWidget(buildTestApp(home: const LoginScreen()));
      await tester.pumpAndSettle();

      final emailField = find.byType(TextFormField).at(0);
      final passField = find.byType(TextFormField).at(1);
      final signInBtn = find.widgetWithText(PrimaryButton, 'Sign In');
      final googleBtn = find.text('Continue with Google');

      await tester.enterText(emailField, 'test@company.com');
      await tester.enterText(passField, 'ValidPass123!');

      // Attempt Email Sign In without terms
      await tester.ensureVisible(signInBtn);
      await tester.tap(signInBtn);
      await tester.pumpAndSettle();
      expect(find.text('Please agree to the Terms of Service and Privacy Policy to proceed.'), findsOneWidget);

      // Attempt Google Sign In without terms
      await tester.ensureVisible(googleBtn);
      await tester.tap(googleBtn);
      await tester.pumpAndSettle();
      expect(find.text('Please agree to the Terms of Service and Privacy Policy before proceeding.'), findsOneWidget);
    });

    // 9. Verification-Gate Behavior After Registration
    testWidgets('9. Post-signup signs out unverified user and enforces verification gate', (tester) async {
      await tester.pumpWidget(buildTestApp(home: const SignupScreen()));
      await tester.pumpAndSettle();

      final nameField = find.byType(TextFormField).at(0);
      final emailField = find.byType(TextFormField).at(1);
      final passField = find.byType(TextFormField).at(2);
      final confirmPassField = find.byType(TextFormField).at(3);
      final termsBox = find.byType(Checkbox);
      final createBtn = find.widgetWithText(PrimaryButton, 'Create Account');

      await tester.enterText(nameField, 'Bob Builder');
      await tester.enterText(emailField, 'bob@construction.local');
      await tester.enterText(passField, 'BuildSafe123!');
      await tester.enterText(confirmPassField, 'BuildSafe123!');
      await tester.ensureVisible(termsBox);
      await tester.tap(termsBox);
      await tester.pumpAndSettle();

      await tester.ensureVisible(createBtn);
      await tester.tap(createBtn);
      await tester.pumpAndSettle();

      // Normative check: user is immediately signed out so unverified session is never authoritative
      expect(mockAuth.signOutCallCount, equals(1));

      // Normative check: verification gate UI displays registered email
      expect(find.text('Verify Your Email'), findsOneWidget);
      expect(find.textContaining('bob@construction.local'), findsOneWidget);
      expect(find.text('Back to Sign In'), findsOneWidget);
    });

    // 10. Required Accessibility Behavior
    testWidgets('10. Accessibility conforms to minimum touch targets, live regions, and semantics', (tester) async {
      await tester.pumpWidget(buildTestApp(home: const LoginScreen()));
      await tester.pumpAndSettle();

      // A: Password obscurity toggle has accessibility tooltip
      final obscureToggle = find.byTooltip('Show password');
      expect(obscureToggle, findsOneWidget);

      // B: Touch targets for PrimaryButton and Google button are at least 48dp
      final signInBtnFinder = find.widgetWithText(PrimaryButton, 'Sign In');
      final signInSize = tester.getSize(signInBtnFinder);
      expect(signInSize.height, greaterThanOrEqualTo(48.0));

      final googleBtnFinder = find.widgetWithText(OutlinedButton, 'Continue with Google');
      final googleSize = tester.getSize(googleBtnFinder);
      expect(googleSize.height, greaterThanOrEqualTo(48.0));

      // C: Trigger error banner to verify live region semantics
      final emailField = find.byType(TextFormField).at(0);
      final passField = find.byType(TextFormField).at(1);
      final termsBox = find.byType(Checkbox);

      await tester.enterText(emailField, 'test@company.com');
      await tester.enterText(passField, 'WrongPass123!');
      await tester.ensureVisible(termsBox);
      await tester.tap(termsBox);
      await tester.pumpAndSettle();

      mockAuth.errorToThrow = Exception('[firebase_auth/wrong-password] Invalid password.');
      await tester.ensureVisible(signInBtnFinder);
      await tester.tap(signInBtnFinder);
      await tester.pumpAndSettle();

      // Error container is wrapped in a liveRegion Semantics node
      final liveRegionSemantics = find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.liveRegion == true,
      );
      expect(liveRegionSemantics, findsOneWidget);
    });
  });
}
