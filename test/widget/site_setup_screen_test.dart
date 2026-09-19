import 'dart:ffi';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/open.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sitelens/core/services/auth_service.dart';
import 'package:sitelens/core/services/session_service.dart';
import 'package:sitelens/data/repositories/site_repository.dart';
import 'package:sitelens/domain/models/site_model.dart';
import 'package:sitelens/features/sites/site_controller.dart';
import 'package:sitelens/features/sites/site_setup_screen.dart';

class WidgetTestSiteRepository implements SiteRepository {
  final Map<String, List<SiteModel>> userSites = {};
  bool shouldThrowOnLoad = false;
  bool shouldThrowOnSave = false;
  bool shouldThrowOnDelete = false;
  String deleteErrorMessage = 'Cannot delete site because captured media references this site.';
  int loadCount = 0;

  @override
  Future<List<SiteModel>> getAllSites({String? creatorId}) async {
    loadCount++;
    if (shouldThrowOnLoad) {
      throw Exception('Database read error');
    }
    if (creatorId == null || creatorId.isEmpty) return [];
    return List.from(userSites[creatorId] ?? []);
  }

  @override
  Future<SiteModel?> getSiteById(String id, {String? creatorId}) async {
    for (final list in userSites.values) {
      final match = list.where((s) => s.id == id).firstOrNull;
      if (match != null) return match;
    }
    return null;
  }

  @override
  Future<void> saveSite(SiteModel site) async {
    if (shouldThrowOnSave) {
      throw Exception('Database write failure');
    }
    final creator = site.creatorId ?? '';
    userSites.putIfAbsent(creator, () => []);
    userSites[creator]!.add(site);
  }

  @override
  Future<void> deleteSite(String id, {String? creatorId}) async {
    if (shouldThrowOnDelete) {
      throw SiteReferencedByMediaException(deleteErrorMessage);
    }
    final creator = creatorId ?? '';
    userSites[creator]?.removeWhere((s) => s.id == id);
  }

  @override
  Future<bool> hasMediaForSite(String siteId, {String? creatorId}) async => shouldThrowOnDelete;

  @override
  Future<void> seedDefaultSitesIfEmpty() async {}

  @override
  Future<List<SiteModel>> hydrateRemoteSites(String userId) async => [];
}

class SimpleMockAuthService implements AuthService {
  AuthUser? _user;

  SimpleMockAuthService([this._user]);

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> get authStateChanges => Stream.value(_user);

  @override
  Future<AuthUser> signInWithEmailPassword(String email, String password) async => _user!;

  @override
  Future<AuthUser?> signInWithGoogle() async => _user;

  @override
  Future<AuthUser> signUpWithEmailPassword(String email, String password, {String? displayName}) async => _user!;

  @override
  Future<void> sendEmailVerificationForUser(String email, String password) async {}

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<SessionVerificationResult> verifySession() async => const SessionVerificationResult.valid();

  @override
  Future<void> signOut() async {
    _user = null;
  }
}

void main() {
  late WidgetTestSiteRepository testRepo;
  const userA = 'user-alpha';
  const userB = 'user-beta';

  setUpAll(() {
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    testRepo = WidgetTestSiteRepository();
    testRepo.userSites[userA] = [
      const SiteModel(
        id: 'site-a1',
        siteCode: '101',
        name: 'Metro Section 1',
        address: 'Park St',
        creatorId: userA,
      ),
      const SiteModel(
        id: 'site-a2',
        siteCode: '102',
        name: 'Metro Section 2',
        address: 'Salt Lake',
        creatorId: userA,
      ),
    ];
    testRepo.userSites[userB] = [
      const SiteModel(
        id: 'site-b1',
        siteCode: '901',
        name: 'Airport Viaduct',
        address: 'Airport Rd',
        creatorId: userB,
      ),
    ];
  });

  Widget buildTestWidget({
    required AuthService authService,
    required SiteRepository siteRepo,
    String? initialUserId,
  }) {
    return ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(authService),
        siteRepositoryProvider.overrideWithValue(siteRepo),
        sessionServiceProvider.overrideWith((ref) => SessionService(authService, ref)),
        siteControllerProvider.overrideWith(
          (ref) => SiteController(siteRepo, initialUserId: initialUserId),
        ),
      ],
      child: const MaterialApp(
        home: SiteSetupScreen(),
      ),
    );
  }

  group('SiteSetupScreen Widget Tests', () {
    testWidgets('Renders User A sites and ensures User B sites are not displayed', (tester) async {
      final authService = SimpleMockAuthService(const AuthUser(uid: userA, email: 'a@sitelens.local'));
      await tester.pumpWidget(buildTestWidget(
        authService: authService,
        siteRepo: testRepo,
        initialUserId: userA,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Metro Section 1'), findsOneWidget);
      expect(find.text('Metro Section 2'), findsOneWidget);
      expect(find.text('Airport Viaduct'), findsNothing);
      expect(find.textContaining('2 Sites cached locally'), findsOneWidget);
    });

    testWidgets('Renders User B sites and ensures User A sites are not displayed', (tester) async {
      final authService = SimpleMockAuthService(const AuthUser(uid: userB, email: 'b@sitelens.local'));
      await tester.pumpWidget(buildTestWidget(
        authService: authService,
        siteRepo: testRepo,
        initialUserId: userB,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Airport Viaduct'), findsOneWidget);
      expect(find.text('Metro Section 1'), findsNothing);
      expect(find.text('Metro Section 2'), findsNothing);
      expect(find.textContaining('1 Sites cached locally'), findsOneWidget);
    });

    testWidgets('Renders explicit error banner and retry button on load failure (not "No cached sites found")', (tester) async {
      testRepo.shouldThrowOnLoad = true;
      final authService = SimpleMockAuthService(const AuthUser(uid: userA, email: 'a@sitelens.local'));

      await tester.pumpWidget(buildTestWidget(
        authService: authService,
        siteRepo: testRepo,
        initialUserId: userA,
      ));
      await tester.pumpAndSettle();

      // Error must be surfaced explicitly
      expect(find.text('Failed to load sites'), findsOneWidget);
      expect(find.textContaining('Database read error'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Retry'), findsOneWidget);

      // Must NOT falsely show "No cached sites found"
      expect(find.text('No cached sites found'), findsNothing);

      // Tap Retry after fixing error
      testRepo.shouldThrowOnLoad = false;
      await tester.tap(find.widgetWithText(ElevatedButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Failed to load sites'), findsNothing);
      expect(find.text('Metro Section 1'), findsOneWidget);
    });

    testWidgets('Renders "No cached sites found" only when loading succeeds with empty list', (tester) async {
      const userEmpty = 'user-empty';
      final authService = SimpleMockAuthService(const AuthUser(uid: userEmpty, email: 'empty@sitelens.local'));

      await tester.pumpWidget(buildTestWidget(
        authService: authService,
        siteRepo: testRepo,
        initialUserId: userEmpty,
      ));
      await tester.pumpAndSettle();

      expect(find.text('No cached sites found'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Add Offline Site'), findsOneWidget);
      expect(find.text('Failed to load sites'), findsNothing);
    });

    testWidgets('Add site dialog validates empty fields and duplicate site code with visible errors', (tester) async {
      final authService = SimpleMockAuthService(const AuthUser(uid: userA, email: 'a@sitelens.local'));

      await tester.pumpWidget(buildTestWidget(
        authService: authService,
        siteRepo: testRepo,
        initialUserId: userA,
      ));
      await tester.pumpAndSettle();

      // Open Add Site dialog
      await tester.tap(find.text('+ Add Site'));
      await tester.pumpAndSettle();

      expect(find.text('Add Offline Site / Address'), findsOneWidget);

      // Tap Add & Select with empty fields -> triggers validation
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add & Select'));
      await tester.pumpAndSettle();

      // Dialog remains open and visible error texts appear
      expect(find.text('Site code is required'), findsOneWidget);
      expect(find.text('Site name is required'), findsOneWidget);

      // Enter duplicate site code ('101' already belongs to userA)
      final codeField = find.widgetWithText(TextField, 'Site Code / ID (e.g. 5012)');
      final nameField = find.widgetWithText(TextField, 'Site / Structure Name');

      await tester.enterText(codeField, '101');
      await tester.enterText(nameField, 'Duplicate Pier');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Add & Select'));
      await tester.pumpAndSettle();

      expect(find.text('Site code "101" already exists'), findsOneWidget);
      expect(find.text('Site name is required'), findsNothing);

      // Now enter valid unique site code and submit
      await tester.enterText(codeField, '103');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Add & Select'));
      await tester.pumpAndSettle();

      // Dialog closes and new site appears
      expect(find.text('Add Offline Site / Address'), findsNothing);
      expect(find.text('Duplicate Pier'), findsOneWidget);
      expect(find.textContaining('3 Sites cached locally'), findsOneWidget);
    });

    testWidgets('Add site dialog displays error banner and keeps dialog open on DB failure', (tester) async {
      testRepo.shouldThrowOnSave = true;
      final authService = SimpleMockAuthService(const AuthUser(uid: userA, email: 'a@sitelens.local'));

      await tester.pumpWidget(buildTestWidget(
        authService: authService,
        siteRepo: testRepo,
        initialUserId: userA,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('+ Add Site'));
      await tester.pumpAndSettle();

      final codeField = find.widgetWithText(TextField, 'Site Code / ID (e.g. 5012)');
      final nameField = find.widgetWithText(TextField, 'Site / Structure Name');

      await tester.enterText(codeField, '777');
      await tester.enterText(nameField, 'Lucky Structure');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Add & Select'));
      await tester.pumpAndSettle();

      // Dialog must NOT close on error; displays error banner inside dialog
      expect(find.text('Add Offline Site / Address'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Database write failure'),
        ),
        findsOneWidget,
      );

      // Cancel closes dialog
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Add Offline Site / Address'), findsNothing);
    });

    testWidgets('Delete site dialog displays error banner and does not silently close when media references site', (tester) async {
      testRepo.shouldThrowOnDelete = true;
      final authService = SimpleMockAuthService(const AuthUser(uid: userA, email: 'a@sitelens.local'));

      await tester.pumpWidget(buildTestWidget(
        authService: authService,
        siteRepo: testRepo,
        initialUserId: userA,
      ));
      await tester.pumpAndSettle();

      // Tap delete icon on first site card
      await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
      await tester.pumpAndSettle();

      expect(find.text('Delete Site'), findsOneWidget);
      expect(find.textContaining('Are you sure you want to remove "Metro Section 1"'), findsOneWidget);

      // Tap Delete in dialog
      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
      await tester.pumpAndSettle();

      // Dialog must NOT silently close; must display error banner inside dialog
      expect(find.text('Delete Site'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Cannot delete site because captured media references this site.'),
        ),
        findsOneWidget,
      );

      // Tap Cancel to dismiss
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Site'), findsNothing);

      // Site was NOT removed
      expect(find.text('Metro Section 1'), findsOneWidget);
    });

    testWidgets('Delete site dialog succeeds and closes when site has no media references', (tester) async {
      testRepo.shouldThrowOnDelete = false;
      final authService = SimpleMockAuthService(const AuthUser(uid: userA, email: 'a@sitelens.local'));

      await tester.pumpWidget(buildTestWidget(
        authService: authService,
        siteRepo: testRepo,
        initialUserId: userA,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Metro Section 1'), findsOneWidget);

      // Tap delete icon on first site card
      await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
      await tester.pumpAndSettle();

      // Tap Delete in dialog
      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
      await tester.pumpAndSettle();

      // Dialog closed and site removed
      expect(find.text('Delete Site'), findsNothing);
      expect(find.text('Metro Section 1'), findsNothing);
      expect(find.textContaining('1 Sites cached locally'), findsOneWidget);
    });
  });
}
