import 'dart:ffi';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/repositories/site_repository.dart';
import 'package:sitelens/features/sites/site_controller.dart';
import 'package:sitelens/domain/models/site_model.dart';

class FailingSiteRepository implements SiteRepository {
  bool shouldFailLoad = false;
  bool shouldFailSave = false;

  @override
  Future<List<SiteModel>> getAllSites({String? creatorId}) async {
    if (shouldFailLoad) {
      throw Exception('Database disk I/O failure');
    }
    return [];
  }

  @override
  Future<SiteModel?> getSiteById(String id, {String? creatorId}) async => null;

  @override
  Future<void> saveSite(SiteModel site, {String? creatorId}) async {
    if (shouldFailSave) {
      throw Exception('Disk full error');
    }
  }

  @override
  Future<void> deleteSite(String id, {String? creatorId}) async {}

  @override
  Future<bool> hasMediaForSite(String siteId, {String? creatorId}) async => false;

  @override
  Future<void> seedDefaultSitesIfEmpty() async {}

  @override
  Future<List<SiteModel>> hydrateRemoteSites(String userId) async => [];
}

class HydratableMockSiteRepository implements SiteRepository {
  final SiteRepository _inner;
  List<SiteModel> remoteSitesToHydrate;

  HydratableMockSiteRepository(this._inner, {this.remoteSitesToHydrate = const []});

  @override
  Future<List<SiteModel>> getAllSites({String? creatorId}) => _inner.getAllSites(creatorId: creatorId);

  @override
  Future<SiteModel?> getSiteById(String id, {String? creatorId}) => _inner.getSiteById(id, creatorId: creatorId);

  @override
  Future<void> saveSite(SiteModel site, {String? creatorId}) => _inner.saveSite(site, creatorId: creatorId);

  @override
  Future<void> deleteSite(String id, {String? creatorId}) => _inner.deleteSite(id, creatorId: creatorId);

  @override
  Future<bool> hasMediaForSite(String siteId, {String? creatorId}) => _inner.hasMediaForSite(siteId, creatorId: creatorId);

  @override
  Future<void> seedDefaultSitesIfEmpty() => _inner.seedDefaultSitesIfEmpty();

  @override
  Future<List<SiteModel>> hydrateRemoteSites(String userId) async {
    for (final s in remoteSitesToHydrate) {
      await _inner.saveSite(s, creatorId: userId);
    }

    return remoteSitesToHydrate;
  }
}

void main() {
  late AppDatabase db;
  late SiteRepository siteRepo;
  late SiteController siteController;
  const testUserId = 'test-user-001';

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory(setup: (rawDb) {
      rawDb.execute('PRAGMA foreign_keys = ON;');
    }));
    siteRepo = LocalSiteRepository(db);

    // Test fixtures scoped to testUserId
    await siteRepo.saveSite(const SiteModel(
      id: 'site-4092',
      siteCode: '4092',
      name: 'Metro Line 3 Pier 42 Construction',
      address: 'Park Street Crossway, Sector 5, Kolkata',
      creatorId: testUserId,
    ));
    await siteRepo.saveSite(const SiteModel(
      id: 'site-1088',
      siteCode: '1088',
      name: 'Flyover Viaduct Segment B',
      address: 'EM Bypass Junction, Kolkata',
      creatorId: testUserId,
    ));
    await siteRepo.saveSite(const SiteModel(
      id: 'site-7721',
      siteCode: '7721',
      name: 'High-Rise Tower Block A Foundation',
      address: 'Rajarhat Main Blvd, New Town',
      creatorId: testUserId,
    ));
    siteController = SiteController(siteRepo, initialUserId: testUserId);
  });

  tearDown(() async {
    await db.close();
  });

  group('SiteController & SiteRepository Core Tests', () {
    test('Loads available test sites successfully for authenticated user', () async {
      await siteController.loadSitesAndActiveContext();

      expect(siteController.state.availableSites.length, equals(3));
      expect(siteController.state.activeSite, isNotNull);
      expect(siteController.state.activeSite?.siteCode, equals('4092'));
      expect(siteController.state.errorMessage, isNull);
    });

    test('Can switch active site and persist with user-scoped key', () async {
      await siteController.loadSitesAndActiveContext();

      const newSite = SiteModel(
        id: 'site-1088',
        siteCode: '1088',
        name: 'Flyover Viaduct Segment B',
        address: 'EM Bypass Junction, Kolkata',
        creatorId: testUserId,
      );

      await siteController.setActiveSite(newSite);
      expect(siteController.state.activeSite?.id, equals('site-1088'));

      // Verify persistence in SharedPreferences with user-scoped key
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sitelens_active_site_id_$testUserId'), equals('site-1088'));
    });

    test('Can add and select custom offline site with 20-character Firestore-compatible auto-ID', () async {
      await siteController.addCustomOfflineSite(
        siteCode: '9901',
        name: 'Underground Tunnel Segment C',
        address: 'Howrah Station Approach, Kolkata',
      );

      final active = siteController.state.activeSite;
      expect(active?.siteCode, equals('9901'));
      expect(active?.creatorId, equals(testUserId));
      expect(active?.id.length, equals(20));
      expect(RegExp(r'^[a-zA-Z0-9]{20}$').hasMatch(active!.id), isTrue);
      expect(siteController.state.availableSites.length, equals(4));
    });

    test('Can delete cached site scoped to user', () async {
      await siteController.loadSitesAndActiveContext();
      expect(siteController.state.availableSites.length, equals(3));

      await siteController.deleteSite('site-4092');
      expect(siteController.state.availableSites.length, equals(2));
      expect(siteController.state.availableSites.any((s) => s.id == 'site-4092'), isFalse);
    });
  });

  group('Per-User Site Isolation Tests', () {
    test('User A sites are never visible to User B (strict fail-closed isolation)', () async {
      const userA = 'user-alpha';
      const userB = 'user-beta';

      // Insert sites for User A
      await siteRepo.saveSite(const SiteModel(
        id: 'site-alpha-1',
        siteCode: 'A100',
        name: 'Alpha Pier 1',
        address: 'Alpha St',
        creatorId: userA,
      ));
      await siteRepo.saveSite(const SiteModel(
        id: 'site-alpha-2',
        siteCode: 'A200',
        name: 'Alpha Pier 2',
        address: 'Alpha Rd',
        creatorId: userA,
      ));

      // Insert site for User B
      await siteRepo.saveSite(const SiteModel(
        id: 'site-beta-1',
        siteCode: 'B100',
        name: 'Beta Bridge',
        address: 'Beta Blvd',
        creatorId: userB,
      ));

      // Controller for User A
      final controllerA = SiteController(siteRepo, initialUserId: userA);
      await controllerA.loadSitesAndActiveContext();
      expect(controllerA.state.availableSites.length, equals(2));
      expect(controllerA.state.availableSites.every((s) => s.creatorId == userA), isTrue);
      expect(controllerA.state.availableSites.any((s) => s.id == 'site-beta-1'), isFalse);

      // Controller for User B
      final controllerB = SiteController(siteRepo, initialUserId: userB);
      await controllerB.loadSitesAndActiveContext();
      expect(controllerB.state.availableSites.length, equals(1));
      expect(controllerB.state.availableSites.first.id, equals('site-beta-1'));
      expect(controllerB.state.availableSites.first.creatorId, equals(userB));
      // User A's sites are completely invisible to User B
      expect(controllerB.state.availableSites.any((s) => s.id == 'site-alpha-1'), isFalse);
      expect(controllerB.state.availableSites.any((s) => s.id == 'site-alpha-2'), isFalse);

      // Unauthenticated / null creatorId strictly returns empty list (no unrestricted all-sites fallback)
      final unauthenticatedSites = await siteRepo.getAllSites(creatorId: null);
      expect(unauthenticatedSites, isEmpty);

      final emptyCreatorSites = await siteRepo.getAllSites(creatorId: '');
      expect(emptyCreatorSites, isEmpty);
    });

    test('User B cannot delete User A site even if site ID is known', () async {
      const userA = 'user-alpha';
      const userB = 'user-beta';

      await siteRepo.saveSite(const SiteModel(
        id: 'site-alpha-protected',
        siteCode: 'PROT1',
        name: 'Protected Site',
        address: 'Protected Way',
        creatorId: userA,
      ));

      final controllerB = SiteController(siteRepo, initialUserId: userB);
      // User B attempts to delete site-alpha-protected
      await controllerB.deleteSite('site-alpha-protected');

      // Verify site-alpha-protected still exists in DB for User A
      final sitesA = await siteRepo.getAllSites(creatorId: userA);
      expect(sitesA.any((s) => s.id == 'site-alpha-protected'), isTrue);
    });

    test('resetSession clears state completely on sign-out', () async {
      await siteController.loadSitesAndActiveContext();
      expect(siteController.state.availableSites.length, equals(3));
      expect(siteController.state.activeSite, isNotNull);

      siteController.resetSession();

      expect(siteController.state.availableSites, isEmpty);
      expect(siteController.state.activeSite, isNull);
      expect(siteController.state.isLoading, isFalse);
      expect(siteController.currentUserId, isNull);
    });

    test('updateUser switches context to new user and reloads sites', () async {
      const newUser = 'user-new-002';
      await siteRepo.saveSite(const SiteModel(
        id: 'site-new-1',
        siteCode: 'NEW1',
        name: 'New Site',
        address: 'New St',
        creatorId: newUser,
      ));

      siteController.updateUser(newUser);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(siteController.currentUserId, equals(newUser));
      expect(siteController.state.availableSites.length, equals(1));
      expect(siteController.state.availableSites.first.id, equals('site-new-1'));
    });
  });

  group('Load Error Handling & Retry Tests', () {
    test('Surface load error explicitly and support functional retry path', () async {
      final failingRepo = FailingSiteRepository();
      final controller = SiteController(failingRepo, initialUserId: 'user-retry');

      // Trigger failure
      failingRepo.shouldFailLoad = true;
      await controller.loadSitesAndActiveContext();

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.errorMessage, contains('Failed to load sites'));
      expect(controller.state.errorMessage, contains('Database disk I/O failure'));
      expect(controller.state.availableSites, isEmpty);
      expect(controller.state.activeSite, isNull);

      // Now resolve failure and retry
      failingRepo.shouldFailLoad = false;
      await controller.loadSitesAndActiveContext();

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.errorMessage, isNull);
    });
  });

  group('Create-Site Error & Validation Tests', () {
    test('Rejects empty site code or empty site name', () async {
      expect(
        () => siteController.addCustomOfflineSite(
          siteCode: '',
          name: 'Valid Name',
          address: 'Valid Address',
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => siteController.addCustomOfflineSite(
          siteCode: '   ',
          name: 'Valid Name',
          address: 'Valid Address',
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => siteController.addCustomOfflineSite(
          siteCode: '5012',
          name: '',
          address: 'Valid Address',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Prevents duplicate site code within same user scope', () async {
      // 4092 already exists in setUp for testUserId
      expect(
        () => siteController.addCustomOfflineSite(
          siteCode: '4092',
          name: 'Another Pier',
          address: 'Another Address',
        ),
        throwsA(isA<DuplicateSiteCodeException>()),
      );

      // Case insensitive check
      expect(
        () => siteController.addCustomOfflineSite(
          siteCode: ' 4092 ',
          name: 'Another Pier',
          address: 'Another Address',
        ),
        throwsA(isA<DuplicateSiteCodeException>()),
      );
    });

    test('Allows identical site code across different users', () async {
      const otherUser = 'user-other';
      final otherController = SiteController(siteRepo, initialUserId: otherUser);

      // otherUser can create 4092 without collision
      final created = await otherController.addCustomOfflineSite(
        siteCode: '4092',
        name: 'Other User Pier 42',
        address: 'Other Address',
      );

      expect(created.siteCode, equals('4092'));
      expect(created.creatorId, equals(otherUser));
    });

    test('Handles DB save failure gracefully by updating state and rethrowing', () async {
      final failingRepo = FailingSiteRepository();
      failingRepo.shouldFailSave = true;
      final controller = SiteController(failingRepo, initialUserId: 'user-save-fail');

      await expectLater(
        () => controller.addCustomOfflineSite(
          siteCode: '9999',
          name: 'Failing Site',
          address: 'Failing Address',
        ),
        throwsA(isA<Exception>()),
      );

      expect(controller.state.errorMessage, contains('Failed to add site'));
    });
  });

  group('Delete-Site Media Foreign Key Integrity Tests', () {
    test('Cannot delete site referenced by active media in database', () async {
      // Active media (isDeleted = 0) referencing site-4092
      await db.into(db.media).insert(
        MediaCompanion.insert(
          id: 'media-active-001',
          uri: 'file:///data/orig_001.jpg',
          lat: 22.57,
          lon: 88.36,
          capturedAt: DateTime.now().toUtc().toIso8601String(),
          siteId: const Value('site-4092'),
          creatorId: const Value(testUserId),
          isDeleted: const Value(0),
          synced: const Value(0),
          tombstoneReconciled: const Value(0),
        ),
      );

      // Verify hasMediaForSite returns true
      expect(await siteRepo.hasMediaForSite('site-4092', creatorId: testUserId), isTrue);

      // Attempting to delete site-4092 must throw SiteReferencedByMediaException
      expect(
        () => siteController.deleteSite('site-4092'),
        throwsA(isA<SiteReferencedByMediaException>()),
      );

      // Verify site-4092 is preserved in DB and still in controller
      await siteController.loadSitesAndActiveContext();
      expect(siteController.state.availableSites.any((s) => s.id == 'site-4092'), isTrue);
    });

    test('Cannot delete site referenced by pending tombstone (published but sync pending)', () async {
      // Published tombstone (isDeleted = 1, synced = 1, tombstoneReconciled = 0)
      await db.into(db.media).insert(
        MediaCompanion.insert(
          id: 'media-pending-tombstone',
          uri: 'file:///data/orig_002.jpg',
          lat: 22.57,
          lon: 88.36,
          capturedAt: DateTime.now().toUtc().toIso8601String(),
          siteId: const Value('site-4092'),
          creatorId: const Value(testUserId),
          isDeleted: const Value(1),
          synced: const Value(1), // Published before deletion
          tombstoneReconciled: const Value(0), // Not yet synced to Firestore
        ),
      );

      // Pending tombstone blocks deletion
      expect(await siteRepo.hasMediaForSite('site-4092', creatorId: testUserId), isTrue);

      expect(
        () => siteController.deleteSite('site-4092'),
        throwsA(isA<SiteReferencedByMediaException>()),
      );

      await siteController.loadSitesAndActiveContext();
      expect(siteController.state.availableSites.any((s) => s.id == 'site-4092'), isTrue);
    });

    test('Cannot delete site while an unreconciled never-published tombstone remains (R24)', () async {
      // Never-published tombstone (isDeleted = 1, synced = 0, tombstoneReconciled = 0)
      await db.into(db.media).insert(
        MediaCompanion.insert(
          id: 'media-never-published-tombstone',
          uri: 'file:///data/orig_003.jpg',
          lat: 22.57,
          lon: 88.36,
          capturedAt: DateTime.now().toUtc().toIso8601String(),
          siteId: const Value('site-4092'),
          creatorId: const Value(testUserId),
          isDeleted: const Value(1),
          synced: const Value(0), // Never published
          tombstoneReconciled: const Value(0), // Not yet settled
        ),
      );

      // R24: an unreconciled tombstone is retained -> deletion is blocked.
      expect(await siteRepo.hasMediaForSite('site-4092', creatorId: testUserId), isTrue);

      expect(
        () => siteController.deleteSite('site-4092'),
        throwsA(isA<SiteReferencedByMediaException>()),
      );

      await siteController.loadSitesAndActiveContext();
      expect(siteController.state.availableSites.any((s) => s.id == 'site-4092'), isTrue);

      // Tombstone row is retained (never purged).
      final remainingMedia = await (db.select(db.media)..where((tbl) => tbl.siteId.equals('site-4092'))).get();
      expect(remainingMedia.single.id, equals('media-never-published-tombstone'));
    });

    test('Can delete site when only fully reconciled tombstones remain', () async {
      // Reconciled tombstone (isDeleted = 1, synced = 1, tombstoneReconciled = 1)
      await db.into(db.media).insert(
        MediaCompanion.insert(
          id: 'media-reconciled-tombstone',
          uri: 'file:///data/orig_004.jpg',
          lat: 22.57,
          lon: 88.36,
          capturedAt: DateTime.now().toUtc().toIso8601String(),
          siteId: const Value('site-4092'),
          creatorId: const Value(testUserId),
          isDeleted: const Value(1),
          synced: const Value(1),
          tombstoneReconciled: const Value(1), // Fully reconciled with cloud
        ),
      );

      // Fully reconciled tombstone does NOT block deletion
      expect(await siteRepo.hasMediaForSite('site-4092', creatorId: testUserId), isFalse);

      // Deletion succeeds without FK violation
      await siteController.deleteSite('site-4092');

      await siteController.loadSitesAndActiveContext();
      expect(siteController.state.availableSites.any((s) => s.id == 'site-4092'), isFalse);

      // Tombstone row was atomically removed from DB
      final remainingMedia = await (db.select(db.media)..where((tbl) => tbl.siteId.equals('site-4092'))).get();
      expect(remainingMedia, isEmpty);
    });

    test('No SQLite FK violation when atomically deleting site with multiple and linked tombstones', () async {
      // Parent tombstone
      await db.into(db.media).insert(
        MediaCompanion.insert(
          id: 'tombstone-parent',
          uri: 'file:///data/orig_parent.jpg',
          lat: 22.57,
          lon: 88.36,
          capturedAt: DateTime.now().toUtc().toIso8601String(),
          siteId: const Value('site-4092'),
          creatorId: const Value(testUserId),
          isDeleted: const Value(1),
          synced: const Value(1),
          tombstoneReconciled: const Value(1),
        ),
      );

      // Child tombstone linked to parent tombstone
      await db.into(db.media).insert(
        MediaCompanion.insert(
          id: 'tombstone-child',
          uri: 'file:///data/orig_child.jpg',
          lat: 22.57,
          lon: 88.36,
          capturedAt: DateTime.now().toUtc().toIso8601String(),
          siteId: const Value('site-4092'),
          creatorId: const Value(testUserId),
          linkedMediaId: const Value('tombstone-parent'),
          isDeleted: const Value(1),
          synced: const Value(0), // never published
          tombstoneReconciled: const Value(1), // reconciled so both rows are purge-eligible
        ),
      );

      // Has media check must allow deletion
      expect(await siteRepo.hasMediaForSite('site-4092', creatorId: testUserId), isFalse);

      // Must delete cleanly under strict PRAGMA foreign_keys = ON
      await siteRepo.deleteSite('site-4092', creatorId: testUserId);

      // Both site and tombstones must be cleanly removed
      final siteInDb = await (db.select(db.sites)..where((tbl) => tbl.id.equals('site-4092'))).getSingleOrNull();
      expect(siteInDb, isNull);

      final mediaInDb = await (db.select(db.media)..where((tbl) => tbl.siteId.equals('site-4092'))).get();
      expect(mediaInDb, isEmpty);
    });

    test('Can delete site when no media references it', () async {
      // site-7721 has no media references
      await siteController.deleteSite('site-7721');

      await siteController.loadSitesAndActiveContext();
      expect(siteController.state.availableSites.any((s) => s.id == 'site-7721'), isFalse);
    });
  });

  group('Site Context Requirements & Firestore → Drift Hydration', () {
    test(
      'Site A selected → online capture → network unavailable → offline capture → network restored → online capture (all reference SAME Site A stable ID)',
      () async {
        await siteController.loadSitesAndActiveContext();

        final siteA = siteController.state.availableSites.firstWhere((s) => s.id == 'site-4092');
        await siteController.setActiveSite(siteA);
        expect(siteController.state.activeSite?.id, equals('site-4092'));

        // 1. Online capture
        // Evidence is captured with activeSite's ID
        final onlineCapture1SiteId = siteController.state.activeSite?.id;
        expect(onlineCapture1SiteId, equals('site-4092'));

        // 2. Network loss / offline transition
        // Invariant: Network loss must NOT clear, replace, or duplicate active site
        // (Active-site continuity invariant)
        expect(siteController.state.activeSite?.id, equals('site-4092'));

        // 3. Offline capture
        // Evidence captured offline uses the exact same stable site ID
        final offlineCaptureSiteId = siteController.state.activeSite?.id;
        expect(offlineCaptureSiteId, equals('site-4092'));

        // 4. Network restored / online transition
        // Remote hydration runs in background
        await siteController.hydrateSites();

        // Invariant: Network restoration must NOT change or displace the active site
        expect(siteController.state.activeSite?.id, equals('site-4092'));

        // 5. Online capture after restoration
        final onlineCapture2SiteId = siteController.state.activeSite?.id;
        expect(onlineCapture2SiteId, equals('site-4092'));

        // All captures across online -> offline -> online transitions reference the exact same Site A stable ID
        expect(onlineCapture1SiteId, equals(offlineCaptureSiteId));
        expect(offlineCaptureSiteId, equals(onlineCapture2SiteId));
        expect(onlineCapture1SiteId, equals('site-4092'));
      },
    );

    test(
      'Fresh device → authenticated online → existing authorized Firestore Site A → Site A hydrated into local Drift → Site A appears in site selection',
      () async {
        final freshDb = AppDatabase(NativeDatabase.memory(setup: (rawDb) {
          rawDb.execute('PRAGMA foreign_keys = ON;');
        }));
        addTearDown(() => freshDb.close());

        const freshUserId = 'fresh-user-777';
        final baseRepo = LocalSiteRepository(freshDb);

        // Before hydration, local Drift has 0 sites for fresh user
        expect(await baseRepo.getAllSites(creatorId: freshUserId), isEmpty);

        const remoteAuthorizedSiteA = SiteModel(
          id: 'firestore-site-alpha-1',
          siteCode: 'FA01',
          name: 'Authorized Remote Pier Alpha',
          address: 'Metro Corridor Pier 12, Kolkata',
          creatorId: freshUserId,
        );

        final hydratingRepo = HydratableMockSiteRepository(
          baseRepo,
          remoteSitesToHydrate: [remoteAuthorizedSiteA],
        );

        final freshController = SiteController(hydratingRepo, initialUserId: freshUserId);

        // Load sites (triggers local Drift load, then remote hydration)
        await freshController.loadSitesAndActiveContext();
        await freshController.hydrateSites();

        // Site A has been hydrated into local Drift
        final dbSites = await baseRepo.getAllSites(creatorId: freshUserId);
        expect(dbSites.length, equals(1));
        expect(dbSites.first.id, equals('firestore-site-alpha-1'));
        expect(dbSites.first.siteCode, equals('FA01'));

        // Site A appears in site selection and is set as active
        expect(freshController.state.availableSites.length, equals(1));
        expect(freshController.state.availableSites.first.id, equals('firestore-site-alpha-1'));
        expect(freshController.state.activeSite?.id, equals('firestore-site-alpha-1'));
      },
    );

    test('Hydration does NOT replace a valid currently active site', () async {
      await siteController.loadSitesAndActiveContext();

      // Explicitly set Site B ('site-1088') as active
      final siteB = siteController.state.availableSites.firstWhere((s) => s.id == 'site-1088');
      await siteController.setActiveSite(siteB);
      expect(siteController.state.activeSite?.id, equals('site-1088'));

      // Remote hydration returns Site A and a newly discovered Site C
      const remoteSiteC = SiteModel(
        id: 'site-remote-pier-c',
        siteCode: 'RC99',
        name: 'Remote Pier C Station',
        address: 'Harbour Approach Road',
        creatorId: testUserId,
      );

      final hydratableRepo = HydratableMockSiteRepository(
        siteRepo,
        remoteSitesToHydrate: [remoteSiteC],
      );

      final testController = SiteController(hydratableRepo, initialUserId: testUserId);
      await testController.loadSitesAndActiveContext();
      await testController.setActiveSite(siteB);
      expect(testController.state.activeSite?.id, equals('site-1088'));

      // Run hydration
      await testController.hydrateSites();

      // Available sites now includes the newly hydrated Site C
      expect(testController.state.availableSites.any((s) => s.id == 'site-remote-pier-c'), isTrue);

      // Active site is STILL Site B ('site-1088'), NOT replaced by Site A or Site C
      expect(testController.state.activeSite?.id, equals('site-1088'));
    });

    test('Only an explicit user selection can change the active site', () async {
      await siteController.loadSitesAndActiveContext();

      final site1 = siteController.state.availableSites.firstWhere((s) => s.id == 'site-4092');
      final site2 = siteController.state.availableSites.firstWhere((s) => s.id == 'site-7721');

      await siteController.setActiveSite(site1);
      expect(siteController.state.activeSite?.id, equals('site-4092'));

      // Hydration runs -> active site does not change
      await siteController.hydrateSites();
      expect(siteController.state.activeSite?.id, equals('site-4092'));

      // Reloading sites -> active site does not change
      await siteController.loadSitesAndActiveContext();
      expect(siteController.state.activeSite?.id, equals('site-4092'));

      // Explicit user selection changes the active site
      await siteController.setActiveSite(site2);
      expect(siteController.state.activeSite?.id, equals('site-7721'));
    });

    test('Local cached sites remain immediately usable without waiting for remote hydration', () async {
      final hydratableRepo = HydratableMockSiteRepository(siteRepo);
      final testController = SiteController(hydratableRepo, initialUserId: testUserId);

      // Local sites load immediately
      await testController.loadSitesAndActiveContext();
      expect(testController.state.availableSites.length, equals(3));
      expect(testController.state.activeSite, isNotNull);
      expect(testController.state.isLoading, isFalse);
    });
  });
}
