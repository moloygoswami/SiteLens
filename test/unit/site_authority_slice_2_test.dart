import 'dart:async';
import 'dart:ffi';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/repositories/site_repository.dart';
import 'package:sitelens/domain/models/site_model.dart';
import 'package:sitelens/features/sites/site_controller.dart';

class FakeConnectivity implements Connectivity {
  final _controller = StreamController<List<ConnectivityResult>>.broadcast();
  List<ConnectivityResult> currentResults;

  FakeConnectivity({this.currentResults = const [ConnectivityResult.wifi]});

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => currentResults;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _controller.stream;

  void emit(List<ConnectivityResult> results) {
    currentResults = results;
    _controller.add(results);
  }

  void dispose() {
    _controller.close();
  }
}

class HydratableMockSiteRepository implements SiteRepository {
  final SiteRepository _inner;
  List<SiteModel> remoteSitesToHydrate;
  bool shouldThrowOnHydrate;

  HydratableMockSiteRepository(
    this._inner, {
    this.remoteSitesToHydrate = const [],
    this.shouldThrowOnHydrate = false,
  });

  @override
  Future<List<SiteModel>> getAllSites({String? creatorId}) =>
      _inner.getAllSites(creatorId: creatorId);

  @override
  Future<SiteModel?> getSiteById(String id, {String? creatorId}) =>
      _inner.getSiteById(id, creatorId: creatorId);

  @override
  Future<void> saveSite(SiteModel site, {String? creatorId}) =>
      _inner.saveSite(site, creatorId: creatorId);

  @override
  Future<void> deleteSite(String id, {String? creatorId}) =>
      _inner.deleteSite(id, creatorId: creatorId);

  @override
  Future<bool> hasMediaForSite(String siteId, {String? creatorId}) =>
      _inner.hasMediaForSite(siteId, creatorId: creatorId);

  @override
  Future<void> seedDefaultSitesIfEmpty() => _inner.seedDefaultSitesIfEmpty();

  @override
  Future<List<SiteModel>> hydrateRemoteSites(String userId) async {
    if (shouldThrowOnHydrate) {
      throw Exception('Remote hydration simulated network failure');
    }
    for (final s in remoteSitesToHydrate) {
      await _inner.saveSite(s, creatorId: userId);
    }
    return remoteSitesToHydrate;
  }
}

void main() {
  late AppDatabase db;
  late SiteRepository siteRepo;
  const userA = 'user-alpha-123';
  const userB = 'user-beta-456';

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

    // Seed initial sites for User A
    await siteRepo.saveSite(
      const SiteModel(
        id: 'site-a1',
        siteCode: 'A100',
        name: 'Metro Section Alpha',
        address: '100 North Rd',
        creatorId: userA,
      ),
      creatorId: userA,
    );
    await siteRepo.saveSite(
      const SiteModel(
        id: 'site-a2',
        siteCode: 'A200',
        name: 'Metro Section Beta',
        address: '200 South Rd',
        creatorId: userA,
      ),
      creatorId: userA,
    );

    // Seed initial site for User B
    await siteRepo.saveSite(
      const SiteModel(
        id: 'site-b1',
        siteCode: 'B100',
        name: 'Airport Pier Alpha',
        address: '500 Airport Way',
        creatorId: userB,
      ),
      creatorId: userB,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('1. Creator Isolation', () {
    test('Queries are strictly scoped by creatorId; null or empty creatorId fails closed', () async {
      // Null creatorId returns empty list / null
      final sitesNull = await siteRepo.getAllSites(creatorId: null);
      expect(sitesNull, isEmpty);

      final siteNull = await siteRepo.getSiteById('site-a1', creatorId: null);
      expect(siteNull, isNull);

      // Empty creatorId returns empty list / null
      final sitesEmpty = await siteRepo.getAllSites(creatorId: '');
      expect(sitesEmpty, isEmpty);

      final siteEmpty = await siteRepo.getSiteById('site-a1', creatorId: '');
      expect(siteEmpty, isNull);

      // Valid creatorId returns only matching creator's sites
      final userASites = await siteRepo.getAllSites(creatorId: userA);
      expect(userASites.length, 2);
      expect(userASites.every((s) => s.creatorId == userA), isTrue);

      final userBSites = await siteRepo.getAllSites(creatorId: userB);
      expect(userBSites.length, 1);
      expect(userBSites.first.id, 'site-b1');
    });

    test('User B cannot read or discover User A site by ID (strict fail-closed isolation)', () async {
      final site = await siteRepo.getSiteById('site-a1', creatorId: userB);
      expect(site, isNull);
    });

    test('User B cannot delete User A site even when site ID is known', () async {
      await siteRepo.deleteSite('site-a1', creatorId: userB);

      // Site A1 must still exist for User A
      final siteA1 = await siteRepo.getSiteById('site-a1', creatorId: userA);
      expect(siteA1, isNotNull);
      expect(siteA1!.name, 'Metro Section Alpha');
    });
  });

  group('2. Ownership-Transfer Prevention', () {
    test('Cannot overwrite or mutate an existing site belonging to a different creator', () async {
      expect(
        () => siteRepo.saveSite(
          const SiteModel(
            id: 'site-a1',
            siteCode: 'A100-STEAL',
            name: 'Hijacked Site',
            address: 'Hijack Rd',
            creatorId: userB,
          ),
          creatorId: userB,
        ),
        throwsA(isA<SiteIsolationException>()),
      );

      // Original record for User A remains intact
      final original = await siteRepo.getSiteById('site-a1', creatorId: userA);
      expect(original!.name, 'Metro Section Alpha');
      expect(original.creatorId, userA);
    });

    test('saveSite fails closed if caller creatorId does not match site.creatorId', () async {
      expect(
        () => siteRepo.saveSite(
          const SiteModel(
            id: 'site-new',
            siteCode: 'NEW1',
            name: 'New Site',
            address: 'New Rd',
            creatorId: userA,
          ),
          creatorId: userB,
        ),
        throwsA(isA<SiteIsolationException>()),
      );
    });

    test('saveSite fails closed if creatorId is null or empty', () async {
      expect(
        () => siteRepo.saveSite(
          const SiteModel(
            id: 'site-no-creator',
            siteCode: 'NOC1',
            name: 'No Creator Site',
            address: 'No Creator Rd',
          ),
          creatorId: null,
        ),
        throwsA(isA<SiteIsolationException>()),
      );
    });
  });

  group('3. Active-Site Selection, Persistence, and Restoration', () {
    test('setActiveSite persists selection with per-user key and updates state', () async {
      final controller = SiteController(siteRepo, initialUserId: userA);
      await pumpEventQueue();

      final target = controller.state.availableSites.firstWhere((s) => s.id == 'site-a2');
      await controller.setActiveSite(target, currentUserId: userA);

      expect(controller.state.activeSite?.id, 'site-a2');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sitelens_active_site_id_$userA'), 'site-a2');

      controller.dispose();
    });

    test('New controller instance for the same user restores persisted active site', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sitelens_active_site_id_$userA', 'site-a2');

      final controller = SiteController(siteRepo, initialUserId: userA);
      await pumpEventQueue();

      expect(controller.state.activeSite?.id, 'site-a2');
      expect(controller.state.activeSite?.name, 'Metro Section Beta');

      controller.dispose();
    });

    test('Explicit site selection updates active site and changes persisted preference', () async {
      final controller = SiteController(siteRepo, initialUserId: userA);
      await pumpEventQueue();

      final siteA1 = controller.state.availableSites.firstWhere((s) => s.id == 'site-a1');
      await controller.setActiveSite(siteA1, currentUserId: userA);
      expect(controller.state.activeSite?.id, 'site-a1');

      final siteA2 = controller.state.availableSites.firstWhere((s) => s.id == 'site-a2');
      await controller.setActiveSite(siteA2, currentUserId: userA);
      expect(controller.state.activeSite?.id, 'site-a2');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sitelens_active_site_id_$userA'), 'site-a2');

      controller.dispose();
    });
  });

  group('4. Online ↔ Offline Continuity', () {
    test('Active site identity remains identical across network drops and restorations', () async {
      final fakeConn = FakeConnectivity(currentResults: [ConnectivityResult.wifi]);
      final controller = SiteController(
        siteRepo,
        initialUserId: userA,
        connectivity: fakeConn,
      );
      await pumpEventQueue();

      // Explicitly select site-a2 while online
      final target = controller.state.availableSites.firstWhere((s) => s.id == 'site-a2');
      await controller.setActiveSite(target, currentUserId: userA);
      expect(controller.state.activeSite?.id, 'site-a2');
      expect(controller.state.isOnline, isTrue);

      // Transition to Offline
      fakeConn.emit([ConnectivityResult.none]);
      await pumpEventQueue();

      expect(controller.state.isOnline, isFalse);
      expect(controller.state.activeSite?.id, 'site-a2'); // INVARIANT: active site unchanged

      // Transition back to Online
      fakeConn.emit([ConnectivityResult.wifi]);
      await pumpEventQueue();

      expect(controller.state.isOnline, isTrue);
      expect(controller.state.activeSite?.id, 'site-a2'); // INVARIANT: active site unchanged

      controller.dispose();
      fakeConn.dispose();
    });
  });

  group('5. App Lifecycle Continuity', () {
    test('Simulating app restart restores last active site from local database and prefs', () async {
      // Session 1: User selects site-a2 and app closes
      final controller1 = SiteController(siteRepo, initialUserId: userA);
      await pumpEventQueue();
      final siteA2 = controller1.state.availableSites.firstWhere((s) => s.id == 'site-a2');
      await controller1.setActiveSite(siteA2, currentUserId: userA);
      controller1.dispose();

      // Session 2: App cold start
      final controller2 = SiteController(siteRepo, initialUserId: userA);
      await pumpEventQueue();

      expect(controller2.state.activeSite, isNotNull);
      expect(controller2.state.activeSite!.id, 'site-a2');
      expect(controller2.state.activeSite!.siteCode, 'A200');

      controller2.dispose();
    });

    test('Deleting the active site clears selection and preference without auto-selecting another site', () async {
      final controller = SiteController(siteRepo, initialUserId: userA);
      await pumpEventQueue();

      final siteA1 = controller.state.availableSites.firstWhere((s) => s.id == 'site-a1');
      await controller.setActiveSite(siteA1, currentUserId: userA);
      expect(controller.state.activeSite?.id, 'site-a1');

      // Delete the active site
      await controller.deleteSite('site-a1', currentUserId: userA);

      // Invariant: active site becomes null, no silent auto-selection of remaining site-a2
      expect(controller.state.activeSite, isNull);
      expect(controller.state.availableSites.length, 1);
      expect(controller.state.availableSites.first.id, 'site-a2');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sitelens_active_site_id_$userA'), isNull);

      controller.dispose();
    });
  });

  group('6. Non-Displacing Remote Hydration', () {
    test('Remote hydration merges new sites without displacing an already valid active site', () async {
      final remoteSite = const SiteModel(
        id: 'site-a3-remote',
        siteCode: 'A300',
        name: 'Remote High Speed Rail',
        address: 'Central Station',
        creatorId: userA,
      );

      final hydratableRepo = HydratableMockSiteRepository(
        siteRepo,
        remoteSitesToHydrate: [remoteSite],
      );

      final controller = SiteController(hydratableRepo, initialUserId: userA);
      await pumpEventQueue();

      // Select site-a1
      final siteA1 = controller.state.availableSites.firstWhere((s) => s.id == 'site-a1');
      await controller.setActiveSite(siteA1, currentUserId: userA);
      expect(controller.state.activeSite?.id, 'site-a1');

      // Trigger hydration
      await controller.hydrateSites(currentUserId: userA);
      await pumpEventQueue();

      // Invariant: valid active site is preserved untouched
      expect(controller.state.activeSite?.id, 'site-a1');
      // Invariant: newly hydrated site is now available in list
      expect(controller.state.availableSites.any((s) => s.id == 'site-a3-remote'), isTrue);
      expect(controller.state.availableSites.length, 3);

      controller.dispose();
    });
  });

  group('7. Four Hydration / Site States (AC-SITE-07 / TM-U-04)', () {
    test('State 1: Online + local sites present -> idle then hydrated with sites', () async {
      final hydratableRepo = HydratableMockSiteRepository(siteRepo);
      final controller = SiteController(hydratableRepo, initialUserId: userA);
      await pumpEventQueue();

      expect(controller.state.isOnline, isTrue);
      expect(controller.state.availableSites.isNotEmpty, isTrue);
      expect(controller.state.hydrationStatus, SiteHydrationStatus.hydrated);

      controller.dispose();
    });

    test('State 2: Online + zero local sites + successful remote hydration returning sites', () async {
      const userEmpty = 'user-zero-local-1';
      final remoteSite = const SiteModel(
        id: 'site-remote-only',
        siteCode: 'R101',
        name: 'Remote Pier',
        address: 'Coast Way',
        creatorId: userEmpty,
      );

      final hydratableRepo = HydratableMockSiteRepository(
        siteRepo,
        remoteSitesToHydrate: [remoteSite],
      );

      final controller = SiteController(hydratableRepo, initialUserId: userEmpty);
      await pumpEventQueue();

      expect(controller.state.isOnline, isTrue);
      expect(controller.state.availableSites.length, 1);
      expect(controller.state.availableSites.first.id, 'site-remote-only');
      expect(controller.state.hydrationStatus, SiteHydrationStatus.hydrated);

      controller.dispose();
    });

    test('State 3: Online + zero local sites + successful remote hydration returning 0 sites (genuine empty)', () async {
      const userEmpty = 'user-genuine-empty';
      final hydratableRepo = HydratableMockSiteRepository(siteRepo, remoteSitesToHydrate: []);

      final controller = SiteController(hydratableRepo, initialUserId: userEmpty);
      await pumpEventQueue();

      expect(controller.state.isOnline, isTrue);
      expect(controller.state.availableSites, isEmpty);
      expect(controller.state.hydrationStatus, SiteHydrationStatus.hydrated);
      expect(controller.state.errorMessage, isNull);

      controller.dispose();
    });

    test('State 4: Online + zero local sites + remote fetch failure -> failed status, never conflated with empty', () async {
      const userFail = 'user-hydration-failure';
      final hydratableRepo = HydratableMockSiteRepository(
        siteRepo,
        shouldThrowOnHydrate: true,
      );

      final controller = SiteController(hydratableRepo, initialUserId: userFail);
      await pumpEventQueue();

      expect(controller.state.isOnline, isTrue);
      expect(controller.state.availableSites, isEmpty);
      // Invariant: failure is explicitly recorded, NEVER reported as genuine empty
      expect(controller.state.hydrationStatus, SiteHydrationStatus.failed);

      controller.dispose();
    });

    test('State 5: Offline + zero local sites -> idle hydration, offline status', () async {
      const userOffline = 'user-offline-initial';
      final fakeConn = FakeConnectivity(currentResults: [ConnectivityResult.none]);
      final hydratableRepo = HydratableMockSiteRepository(siteRepo);

      final controller = SiteController(
        hydratableRepo,
        initialUserId: userOffline,
        connectivity: fakeConn,
      );
      await pumpEventQueue();

      expect(controller.state.isOnline, isFalse);
      expect(controller.state.availableSites, isEmpty);
      expect(controller.state.hydrationStatus, SiteHydrationStatus.idle);

      controller.dispose();
      fakeConn.dispose();
    });
  });

  group('8. Invalid / Unauthorized Restoration', () {
    test('Persisted active-site ID belonging to a different user fails closed', () async {
      final prefs = await SharedPreferences.getInstance();
      // Tamper/inject User B's site ID into User A's preference key
      await prefs.setString('sitelens_active_site_id_$userA', 'site-b1');

      final controller = SiteController(siteRepo, initialUserId: userA);
      await pumpEventQueue();

      // Invariant: User A cannot activate User B's site
      expect(controller.state.activeSite?.id, isNot('site-b1'));
      // Defaults safely to User A's first site
      expect(controller.state.activeSite?.creatorId, userA);

      controller.dispose();
    });

    test('Non-existent/corrupted persisted site ID fails closed without crash', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sitelens_active_site_id_$userA', 'site-non-existent-999');

      final controller = SiteController(siteRepo, initialUserId: userA);
      await pumpEventQueue();

      expect(controller.state.activeSite?.id, isNot('site-non-existent-999'));
      expect(controller.state.activeSite?.creatorId, userA);

      controller.dispose();
    });

    test('setActiveSite throws SiteIsolationException when passed a foreign creator site', () async {
      final controller = SiteController(siteRepo, initialUserId: userA);
      await pumpEventQueue();

      const foreignSite = SiteModel(
        id: 'site-b1',
        siteCode: 'B100',
        name: 'Airport Pier Alpha',
        address: '500 Airport Way',
        creatorId: userB,
      );

      expect(
        () => controller.setActiveSite(foreignSite, currentUserId: userA),
        throwsA(isA<SiteIsolationException>()),
      );

      controller.dispose();
    });
  });

  group('9. Session Isolation', () {
    test('resetSession clears in-memory state completely on sign-out', () async {
      final controller = SiteController(siteRepo, initialUserId: userA);
      await pumpEventQueue();

      expect(controller.state.availableSites.isNotEmpty, isTrue);
      expect(controller.state.activeSite, isNotNull);

      // Sign-out trigger
      controller.resetSession();

      expect(controller.currentUserId, isNull);
      expect(controller.state.activeSite, isNull);
      expect(controller.state.availableSites, isEmpty);

      controller.dispose();
    });

    test('updateUser synchronously isolates prior user state before new load', () async {
      final controller = SiteController(siteRepo, initialUserId: userA);
      await pumpEventQueue();
      expect(controller.state.availableSites.length, 2);

      // Switch session to User B
      controller.updateUser(userB);
      await pumpEventQueue();

      expect(controller.currentUserId, userB);
      expect(controller.state.availableSites.length, 1);
      expect(controller.state.availableSites.first.id, 'site-b1');
      expect(controller.state.activeSite?.creatorId, userB);

      controller.dispose();
    });
  });

  group('10. Normative Deletion Behavior (AC-SITE-09 / AC-SITE-10)', () {
    test('Active media blocks site deletion', () async {
      // Insert active media for site-a1
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'photo-active',
              siteId: const Value('site-a1'),
              creatorId: const Value(userA),
              uri: 'file:///app/photos/p1.jpg',
              lat: 22.57,
              lon: 88.36,
              capturedAt: DateTime.now().toUtc().toIso8601String(),
              isDeleted: const Value(0),
              tombstoneReconciled: const Value(0),
            ),
          );

      expect(await siteRepo.hasMediaForSite('site-a1', creatorId: userA), isTrue);
      expect(
        () => siteRepo.deleteSite('site-a1', creatorId: userA),
        throwsA(isA<SiteReferencedByMediaException>()),
      );
    });

    test('Pending published tombstone blocks site deletion', () async {
      // Insert soft-deleted but not yet reconciled media (synced=1, tombstoneReconciled=0)
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'photo-tombstone-pending',
              siteId: const Value('site-a1'),
              creatorId: const Value(userA),
              uri: 'file:///app/photos/p2.jpg',
              lat: 22.57,
              lon: 88.36,
              capturedAt: DateTime.now().toUtc().toIso8601String(),
              isDeleted: const Value(1),
              synced: const Value(1),
              tombstoneReconciled: const Value(0),
            ),
          );

      expect(await siteRepo.hasMediaForSite('site-a1', creatorId: userA), isTrue);
      expect(
        () => siteRepo.deleteSite('site-a1', creatorId: userA),
        throwsA(isA<SiteReferencedByMediaException>()),
      );
    });

    test('Reconciled tombstone allows site deletion and purges site + tombstones atomically', () async {
      // Insert reconciled tombstone (isDeleted=1, tombstoneReconciled=1)
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'photo-reconciled',
              siteId: const Value('site-a1'),
              creatorId: const Value(userA),
              uri: 'file:///app/photos/p3.jpg',
              lat: 22.57,
              lon: 88.36,
              capturedAt: DateTime.now().toUtc().toIso8601String(),
              isDeleted: const Value(1),
              synced: const Value(1),
              tombstoneReconciled: const Value(1),
            ),
          );

      expect(await siteRepo.hasMediaForSite('site-a1', creatorId: userA), isFalse);

      // Deletion succeeds without SQLite foreign key violation
      await siteRepo.deleteSite('site-a1', creatorId: userA);

      // Both site and media are purged atomically
      final siteCheck = await siteRepo.getSiteById('site-a1', creatorId: userA);
      expect(siteCheck, isNull);

      final mediaCheck = await (db.select(db.media)..where((tbl) => tbl.id.equals('photo-reconciled'))).getSingleOrNull();
      expect(mediaCheck, isNull);
    });
  });
}
