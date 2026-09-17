import 'dart:async';
import 'dart:ffi';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/open.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sitelens/core/services/auth_service.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/local/database/database_provider.dart';
import 'package:sitelens/features/auth/welcome_screen.dart';
import 'package:sitelens/features/auth/login_screen.dart';
import 'package:sitelens/features/auth/session_router.dart';
import 'package:sitelens/features/onboarding/permission_onboarding_screen.dart';
import 'package:sitelens/features/onboarding/permission_recovery_screen.dart';
import 'package:sitelens/features/sites/site_setup_screen.dart';
import 'package:sitelens/features/auth/signup_screen.dart';
import 'package:sitelens/shared/widgets/primary_button.dart';

class WidgetMockAuthService implements AuthService {
  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? _currentUser;
  Object? errorToThrow;
  String? lastPasswordResetEmail;
  String? lastResendEmail;

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  @override
  AuthUser? get currentUser => _currentUser;

  @override
  Future<AuthUser> signInWithEmailPassword(String email, String password) async {
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    final user = AuthUser(uid: 'test-uid', email: email);
    _currentUser = user;
    _controller.add(user);
    return user;
  }

  @override
  Future<AuthUser?> signInWithGoogle() async {
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    final user = const AuthUser(uid: 'test-google-uid', email: 'test@sitelens.local');
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
    final user = AuthUser(uid: 'test-signup-uid', email: email, displayName: displayName ?? 'Site Inspector');
    _currentUser = user;
    _controller.add(user);
    return user;
  }

  @override
  Future<void> sendEmailVerificationForUser(String email, String password) async {
    lastResendEmail = email;
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
    _currentUser = null;
    _controller.add(null);
  }
}

void main() {
  late AppDatabase db;
  late WidgetMockAuthService mockAuth;

  setUpAll(() {
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    mockAuth = WidgetMockAuthService();
  });

  tearDown(() async {
    await db.close();
  });

  Widget buildTestableWidget(Widget child, {List<Override> overrides = const []}) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        authServiceProvider.overrideWithValue(mockAuth),
        ...overrides,
      ],
      child: MaterialApp(
        home: child,
      ),
    );
  }

  group('Milestone M1 Screens Rendering Tests', () {
    testWidgets('WelcomeScreen renders hero and actions', (tester) async {
      await tester.pumpWidget(buildTestableWidget(const WelcomeScreen()));
      await tester.pumpAndSettle();

      expect(find.text('SiteLens'), findsOneWidget);
      expect(find.text('GPS-Verified Construction Evidence'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
      expect(find.text('Burned-in Geotagging'), findsOneWidget);
    });

    testWidgets('LoginScreen renders inputs and actions', (tester) async {
      await tester.pumpWidget(buildTestableWidget(const LoginScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Sign In'), findsNWidgets(2)); // Heading & Button
      expect(find.text('WORK EMAIL'), findsOneWidget);
      expect(find.text('PASSWORD'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Protected by Firebase Authentication & SHA-256 evidence chain'), findsOneWidget);
    });

    testWidgets('LoginScreen prevents user enumeration by returning uniform message for all auth errors', (tester) async {
      // 1. user-not-found error
      mockAuth.errorToThrow = Exception('[firebase_auth/user-not-found] There is no user record.');
      await tester.pumpWidget(buildTestableWidget(const LoginScreen()));
      await tester.pumpAndSettle();

      final emailField = find.byType(TextFormField).at(0);
      final passField = find.byType(TextFormField).at(1);
      final termsCheckbox = find.byType(Checkbox);

      await tester.enterText(emailField, 'nonexistent@company.com');
      await tester.enterText(passField, 'Secret123!');

      // Attempt Sign In without agreeing to terms -> blocked
      await tester.ensureVisible(find.widgetWithText(PrimaryButton, 'Sign In'));
      await tester.tap(find.widgetWithText(PrimaryButton, 'Sign In'));
      await tester.pumpAndSettle();
      expect(find.text('Please agree to the Terms of Service and Privacy Policy to proceed.'), findsOneWidget);

      // Attempt Google Sign In without agreeing to terms -> blocked
      await tester.ensureVisible(find.text('Continue with Google'));
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(find.text('Please agree to the Terms of Service and Privacy Policy before proceeding.'), findsOneWidget);

      // Agree to terms & retry
      await tester.ensureVisible(termsCheckbox);
      await tester.tap(termsCheckbox);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.widgetWithText(PrimaryButton, 'Sign In'));
      await tester.tap(find.widgetWithText(PrimaryButton, 'Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid email or password. Please verify your credentials.'), findsOneWidget);
      expect(find.textContaining('No inspector account found'), findsNothing);
      expect(find.textContaining('sitelens-prod-80e7b'), findsNothing);

      // 2. wrong-password error
      mockAuth.errorToThrow = Exception('[firebase_auth/wrong-password] The password is invalid.');
      await tester.tap(find.widgetWithText(PrimaryButton, 'Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid email or password. Please verify your credentials.'), findsOneWidget);

      // 3. user-disabled error
      mockAuth.errorToThrow = Exception('[firebase_auth/user-disabled] User account disabled.');
      await tester.tap(find.widgetWithText(PrimaryButton, 'Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid email or password. Please verify your credentials.'), findsOneWidget);
      expect(find.textContaining('disabled by administrator'), findsNothing);

      // 4. network-request-failed error
      mockAuth.errorToThrow = Exception('[firebase_auth/network-request-failed] Network error.');
      await tester.tap(find.widgetWithText(PrimaryButton, 'Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('Network connection failed. Please check your internet connection.'), findsOneWidget);
    });

    testWidgets('PermissionOnboardingScreen renders permissions list', (tester) async {
      await tester.pumpWidget(buildTestableWidget(const PermissionOnboardingScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Device Permissions'), findsOneWidget);
      expect(find.text('Camera Access'), findsOneWidget);
      expect(find.text('Precise Location / GPS'), findsOneWidget);
      // Unused device media-library access was removed: no Photos & Storage tile.
      expect(find.text('Photos & Storage'), findsNothing);
    });

    testWidgets('PermissionRecoveryScreen renders instructions and actions', (tester) async {
      await tester.pumpWidget(buildTestableWidget(const PermissionRecoveryScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Permissions Blocked'), findsOneWidget);
      expect(find.text('Open Device Settings'), findsOneWidget);
      expect(find.text('Re-check Permission Status'), findsOneWidget);
    });

    testWidgets('SiteSetupScreen renders project context and site list without offline text, and sign out dialog has no icon', (tester) async {
      await tester.pumpWidget(buildTestableWidget(const SiteSetupScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Project & Site Context'), findsOneWidget);
      expect(find.text('Select Active Site'), findsOneWidget);
      expect(find.text('+ Add Site'), findsOneWidget);
      expect(find.text('Confirm Site & Open Camera'), findsOneWidget);

      // Verify offline availability text is NOT rendered
      expect(find.textContaining('available locally for offline capture'), findsNothing);

      // Tap Sign Out icon in AppBar
      await tester.tap(find.byIcon(Icons.logout_rounded));
      await tester.pumpAndSettle();

      // Verify Sign Out confirmation dialog without icon
      expect(find.text('Sign Out'), findsNWidgets(2)); // Dialog Title & Confirm Button
      expect(find.text('Are you sure you want to sign out from SiteLens?'), findsOneWidget);
      expect(find.descendant(of: find.byType(Dialog), matching: find.byIcon(Icons.logout_rounded)), findsNothing);

      // Tap Cancel -> closes modal
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('SessionRouter displays WelcomeScreen for unauthenticated users', (tester) async {
      await tester.pumpWidget(buildTestableWidget(const SessionRouter()));
      await tester.pumpAndSettle();

      expect(find.text('SiteLens'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
    });

    testWidgets('LoginScreen renders Forgot Password button and opens password reset dialog, sending email', (tester) async {
      await tester.pumpWidget(buildTestableWidget(const LoginScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Forgot Password?'), findsOneWidget);

      // Pre-fill email
      final emailField = find.byType(TextFormField).at(0);
      await tester.enterText(emailField, 'engineer@sitelens.local');

      // Tap Forgot Password
      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();

      // Verify dialog is shown
      expect(find.text('Reset Password'), findsOneWidget);
      expect(find.text('Enter your registered work email address. We will send you a secure link to create a new password.'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Send Reset Link'), findsOneWidget);

      // Submit reset link
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send Reset Link'));
      await tester.pumpAndSettle();

      expect(mockAuth.lastPasswordResetEmail, equals('engineer@sitelens.local'));
      expect(find.text('Password reset link sent to engineer@sitelens.local. Please check your inbox.'), findsOneWidget);
    });

    testWidgets('LoginScreen renders email verification warning and handles resend verification trigger', (tester) async {
      mockAuth.errorToThrow = const EmailNotVerifiedException(
        message: 'Your email address has not been verified yet. Please check your inbox for the verification link.',
        email: 'unverified@sitelens.local',
      );

      await tester.pumpWidget(buildTestableWidget(const LoginScreen()));
      await tester.pumpAndSettle();

      final emailField = find.byType(TextFormField).at(0);
      final passField = find.byType(TextFormField).at(1);
      final termsCheckbox = find.byType(Checkbox);

      await tester.enterText(emailField, 'unverified@sitelens.local');
      await tester.enterText(passField, 'ValidPass123!');
      await tester.tap(termsCheckbox);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.widgetWithText(PrimaryButton, 'Sign In'));
      await tester.tap(find.widgetWithText(PrimaryButton, 'Sign In'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Your email address has not been verified yet'), findsOneWidget);
      expect(find.text('Resend Verification Email'), findsOneWidget);

      // Tap Resend Verification Email
      await tester.tap(find.text('Resend Verification Email'));
      await tester.pumpAndSettle();

      expect(mockAuth.lastResendEmail, equals('unverified@sitelens.local'));
      expect(find.text('Verification email resent to unverified@sitelens.local. Please check your inbox.'), findsOneWidget);
    });

    testWidgets('SignupScreen renders form and switches to verification instructions view upon sign up', (tester) async {
      await tester.pumpWidget(buildTestableWidget(const SignupScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Create Account'), findsNWidgets(2)); // Heading & Button
      expect(find.text('FULL NAME'), findsOneWidget);
      expect(find.text('WORK EMAIL'), findsOneWidget);

      final nameField = find.byType(TextFormField).at(0);
      final emailField = find.byType(TextFormField).at(1);
      final passField = find.byType(TextFormField).at(2);
      final confirmPassField = find.byType(TextFormField).at(3);
      final termsCheckbox = find.byType(Checkbox);

      await tester.enterText(nameField, 'Jane Doe');
      await tester.enterText(emailField, 'jane.doe@sitelens.local');
      await tester.enterText(passField, 'SecurePassword123!');
      await tester.enterText(confirmPassField, 'SecurePassword123!');
      await tester.tap(termsCheckbox);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.widgetWithText(PrimaryButton, 'Create Account'));
      await tester.tap(find.widgetWithText(PrimaryButton, 'Create Account'));
      await tester.pumpAndSettle();

      // Verify success email verification screen
      expect(find.text('Verify Your Email'), findsOneWidget);
      expect(find.textContaining('jane.doe@sitelens.local'), findsOneWidget);
      expect(find.text('Please open your inbox and click the verification link before signing in.'), findsOneWidget);
      expect(find.text('Back to Sign In'), findsOneWidget);
    });
  });
}
