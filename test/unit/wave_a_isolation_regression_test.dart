import 'dart:ffi';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/open.dart';
import 'package:sitelens/core/services/auth_service.dart';
import 'package:sitelens/core/services/session_service.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/data/repositories/site_repository.dart';
import 'package:sitelens/domain/models/site_model.dart';
import 'package:sitelens/features/gallery/controllers/gallery_controller.dart';
import 'package:sitelens/features/sites/site_controller.dart';

class MockWaveASessionService extends StateNotifier<UserSessionState> implements SessionService {
  MockWaveASessionService(super.state);

  void setUser(AuthUser? user) {
    if (user == null) {
      state = const UserSessionState(
        status: SessionStatus.unauthenticated,
        user: null,
      );
    } else {
      state = UserSessionState(
        status: SessionStatus.authenticatedReady,
        user: user,
      );
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  group('Wave A Local & Session Isolation Regression Suite (R01, R04, R05)', () {
    late AppDatabase db;
    late SiteRepository siteRepo;
    late MediaRepository mediaRepo;
    late ProviderContainer container;
    late MockWaveASessionService sessionService;

    const userA = 'user-a-uuid-1111';
    const userB = 'user-b-uuid-2222';

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase(NativeDatabase.memory());
      siteRepo = LocalSiteRepository(db);
      mediaRepo = LocalMediaRepository(db);

      sessionService = MockWaveASessionService(
        const UserSessionState(
          status: SessionStatus.authenticatedReady,
          user: AuthUser(uid: userA, email: 'a@example.com'),
        ),
      );

      container = ProviderContainer(
        overrides: [
          sessionServiceProvider.overrideWith((ref) => sessionService),
          mediaRepositoryProvider.overrideWithValue(mediaRepo),
          siteRepositoryProvider.overrideWithValue(siteRepo),
          siteControllerProvider.overrideWith((ref) {
            final session = ref.watch(sessionServiceProvider);
            final ctrl = SiteController(siteRepo, initialUserId: session.user?.uid);
            ref.listen<UserSessionState>(sessionServiceProvider, (previous, next) {
              if (next.status == SessionStatus.unauthenticated || next.user == null) {
                ctrl.resetSession();
              } else if (previous?.user?.uid != next.user?.uid) {
                ctrl.updateUser(next.user?.uid);
              }
            });
            return ctrl;
          }),
        ],
      );

      container.listen(filteredGalleryMediaProvider, (_, __) {});
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('1. Same physical site metadata (siteCode, name, address, GPS) remains completely isolated between User A and User B', () async {
      // User A creates site with specific metadata
      const siteA = SiteModel(
        id: 'site-a-uuid',
        siteCode: 'SITE-100',
        name: 'Metro Pier 14',
        address: '14 River Road, Kolkata',
        creatorId: userA,
      );
      await siteRepo.saveSite(siteA);

      // User A creates evidence
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'media-a-1',
              siteId: const drift.Value('site-a-uuid'),
              creatorId: const drift.Value(userA),
              type: const drift.Value('photo'),
              uri: 'media/evid_a1.jpg',
              originalUri: const drift.Value('media/orig_a1.jpg'),
              thumbUri: const drift.Value('media/thumb_a1.jpg'),
              capturedAt: '2026-08-15T10:00:00.000Z',
              lat: 22.5726,
              lon: 88.3639,
              accuracyM: const drift.Value(3.5),
              lowAccuracy: const drift.Value(0),
              activityTag: const drift.Value('Excavation'),
              observationType: const drift.Value('progress'),
              note: const drift.Value('User A observation'),
              sha256Hash: const drift.Value('1111111111111111111111111111111111111111111111111111111111111111'),
            ),
          );

      // User B creates a site with the EXACT SAME code, name, and address
      const siteB = SiteModel(
        id: 'site-b-uuid',
        siteCode: 'SITE-100',
        name: 'Metro Pier 14',
        address: '14 River Road, Kolkata',
        creatorId: userB,
      );
      await siteRepo.saveSite(siteB);

      // User B creates evidence with identical coordinates
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'media-b-1',
              siteId: const drift.Value('site-b-uuid'),
              creatorId: const drift.Value(userB),
              type: const drift.Value('photo'),
              uri: 'media/evid_b1.jpg',
              originalUri: const drift.Value('media/orig_b1.jpg'),
              thumbUri: const drift.Value('media/thumb_b1.jpg'),
              capturedAt: '2026-08-15T10:00:00.000Z',
              lat: 22.5726,
              lon: 88.3639,
              accuracyM: const drift.Value(3.5),
              lowAccuracy: const drift.Value(0),
              activityTag: const drift.Value('Excavation'),
              observationType: const drift.Value('progress'),
              note: const drift.Value('User B observation'),
              sha256Hash: const drift.Value('2222222222222222222222222222222222222222222222222222222222222222'),
            ),
          );

      // User A queries
      final sitesA = await siteRepo.getAllSites(creatorId: userA);
      expect(sitesA.length, equals(1));
      expect(sitesA.first.id, equals('site-a-uuid'));

      final mediaA = await mediaRepo.watchAllMedia(creatorId: userA).first;
      expect(mediaA.length, equals(1));
      expect(mediaA.first.id, equals('media-a-1'));

      // User B queries
      final sitesB = await siteRepo.getAllSites(creatorId: userB);
      expect(sitesB.length, equals(1));
      expect(sitesB.first.id, equals('site-b-uuid'));

      final mediaB = await mediaRepo.watchAllMedia(creatorId: userB).first;
      expect(mediaB.length, equals(1));
      expect(mediaB.first.id, equals('media-b-1'));

      // Isolation check: B cannot get A's site by ID with creatorId scoping
      final crossSiteLookup = await siteRepo.getSiteById('site-a-uuid', creatorId: userB);
      expect(crossSiteLookup, isNull);

      // Isolation check: B cannot delete A's site
      await siteRepo.deleteSite('site-a-uuid', creatorId: userB);
      final siteAStillExists = await siteRepo.getSiteById('site-a-uuid', creatorId: userA);
      expect(siteAStillExists, isNotNull);
    });

    test('2. Auth transition (Sign Out A -> Sign In B) resets active-site, invalidates cache, and prevents cross-user exposure', () async {
      // Seed data for User A and User B
      await siteRepo.saveSite(const SiteModel(
        id: 'site-a-active',
        siteCode: 'A01',
        name: 'Alpha Site',
        address: 'Alpha Way',
        creatorId: userA,
      ));
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'media-a-active',
              siteId: const drift.Value('site-a-active'),
              creatorId: const drift.Value(userA),
              type: const drift.Value('photo'),
              uri: 'media/evid_a.jpg',
              originalUri: const drift.Value('media/orig_a.jpg'),
              thumbUri: const drift.Value('media/thumb_a.jpg'),
              capturedAt: '2026-08-15T10:00:00.000Z',
              lat: 22.57,
              lon: 88.36,
              activityTag: const drift.Value('Rebar'),
              observationType: const drift.Value('progress'),
              note: const drift.Value('User A note'),
              sha256Hash: const drift.Value('3333333333333333333333333333333333333333333333333333333333333333'),
            ),
          );

      await siteRepo.saveSite(const SiteModel(
        id: 'site-b-active',
        siteCode: 'B01',
        name: 'Beta Site',
        address: 'Beta Way',
        creatorId: userB,
      ));
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'media-b-active',
              siteId: const drift.Value('site-b-active'),
              creatorId: const drift.Value(userB),
              type: const drift.Value('photo'),
              uri: 'media/evid_b.jpg',
              originalUri: const drift.Value('media/orig_b.jpg'),
              thumbUri: const drift.Value('media/thumb_b.jpg'),
              capturedAt: '2026-08-15T10:00:00.000Z',
              lat: 22.57,
              lon: 88.36,
              activityTag: const drift.Value('Paving'),
              observationType: const drift.Value('progress'),
              note: const drift.Value('User B note'),
              sha256Hash: const drift.Value('4444444444444444444444444444444444444444444444444444444444444444'),
            ),
          );

      // Step 1: User A is authenticated
      final siteCtrl = container.read(siteControllerProvider.notifier);
      await siteCtrl.loadSitesAndActiveContext();
      expect(siteCtrl.state.availableSites.length, equals(1));
      expect(siteCtrl.state.availableSites.first.id, equals('site-a-active'));

      await Future<void>.delayed(const Duration(milliseconds: 50));
      var galleryItems = await container.read(filteredGalleryMediaProvider.future);
      expect(galleryItems.length, equals(1));
      expect(galleryItems.first.id, equals('media-a-active'));

      // Step 2: Sign out User A
      sessionService.setUser(null);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Active site must be reset and available sites empty
      final signedOutState = container.read(siteControllerProvider);
      expect(signedOutState.availableSites, isEmpty);
      expect(signedOutState.activeSite, isNull);

      // Gallery must fail closed immediately
      final signedOutGallery = await container.read(filteredGalleryMediaProvider.future);
      expect(signedOutGallery, isEmpty);

      // Step 3: Sign in User B
      sessionService.setUser(const AuthUser(uid: userB, email: 'b@example.com'));
      await container.read(siteControllerProvider.notifier).loadSitesAndActiveContext();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // User B only sees Beta Site
      final userBState = container.read(siteControllerProvider);
      expect(userBState.availableSites.length, equals(1));
      expect(userBState.availableSites.first.id, equals('site-b-active'));

      // User B only sees User B evidence
      galleryItems = await container.read(filteredGalleryMediaProvider.future);
      expect(galleryItems.length, equals(1));
      expect(galleryItems.first.id, equals('media-b-active'));
      expect(galleryItems.any((m) => m.id == 'media-a-active'), isFalse);
    });

    test('3. Strict fail-closed boundary: null and empty creatorId return empty results across all repository queries', () async {
      // Seed data under User A
      await siteRepo.saveSite(const SiteModel(
        id: 'site-fail-closed',
        siteCode: 'FC01',
        name: 'Fail Closed Site',
        address: 'Fail Closed Way',
        creatorId: userA,
      ));
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'media-fail-closed',
              siteId: const drift.Value('site-fail-closed'),
              creatorId: const drift.Value(userA),
              type: const drift.Value('photo'),
              uri: 'media/evid_fc.jpg',
              originalUri: const drift.Value('media/orig_fc.jpg'),
              thumbUri: const drift.Value('media/thumb_fc.jpg'),
              capturedAt: '2026-08-15T10:00:00.000Z',
              lat: 22.57,
              lon: 88.36,
              activityTag: const drift.Value('Testing'),
              observationType: const drift.Value('progress'),
              sha256Hash: const drift.Value('5555555555555555555555555555555555555555555555555555555555555555'),
            ),
          );

      // Seed a closed observation so the resolved-linked-evidence boundary is
      // exercised with real data rather than passing vacuously.
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'media-closed-a',
              siteId: const drift.Value('site-fail-closed'),
              creatorId: const drift.Value(userA),
              type: const drift.Value('photo'),
              uri: 'media/evid_ca.jpg',
              originalUri: const drift.Value('media/orig_ca.jpg'),
              capturedAt: '2026-08-15T11:00:00.000Z',
              lat: 22.57,
              lon: 88.36,
              observationType: const drift.Value('closed'),
              linkedMediaId: const drift.Value('media-fail-closed'),
              sha256Hash: const drift.Value('8888888888888888888888888888888888888888888888888888888888888888'),
              synced: const drift.Value(1),
            ),
          );

      // Seed real soft-deleted tombstone candidates (is_deleted = 1, not mid-sync)
      // for User A and User B so the tombstone boundary is exercised with actual
      // candidate rows rather than passing vacuously on an empty candidate set.
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'media-tombstone-a',
              siteId: const drift.Value('site-fail-closed'),
              creatorId: const drift.Value(userA),
              type: const drift.Value('photo'),
              uri: 'media/evid_ta.jpg',
              originalUri: const drift.Value('media/orig_ta.jpg'),
              thumbUri: const drift.Value('media/thumb_ta.jpg'),
              capturedAt: '2026-08-15T10:00:00.000Z',
              lat: 22.57,
              lon: 88.36,
              activityTag: const drift.Value('Testing'),
              observationType: const drift.Value('progress'),
              sha256Hash: const drift.Value('6666666666666666666666666666666666666666666666666666666666666666'),
              synced: const drift.Value(0),
              isDeleted: const drift.Value(1),
            ),
          );
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'media-tombstone-b',
              siteId: const drift.Value('site-fail-closed'),
              creatorId: const drift.Value(userB),
              type: const drift.Value('photo'),
              uri: 'media/evid_tb.jpg',
              originalUri: const drift.Value('media/orig_tb.jpg'),
              thumbUri: const drift.Value('media/thumb_tb.jpg'),
              capturedAt: '2026-08-15T10:00:00.000Z',
              lat: 22.57,
              lon: 88.36,
              activityTag: const drift.Value('Testing'),
              observationType: const drift.Value('progress'),
              sha256Hash: const drift.Value('7777777777777777777777777777777777777777777777777777777777777777'),
              synced: const drift.Value(0),
              isDeleted: const drift.Value(1),
            ),
          );

      // Test null creatorId across all SiteRepository queries
      expect(await siteRepo.getAllSites(creatorId: null), isEmpty);
      expect(await siteRepo.getAllSites(creatorId: ''), isEmpty);
      expect(await siteRepo.getSiteById('site-fail-closed', creatorId: null), isNull);
      expect(await siteRepo.getSiteById('site-fail-closed', creatorId: ''), isNull);

      // Test deleteSite with null/empty creatorId
      await siteRepo.deleteSite('site-fail-closed', creatorId: null);
      expect(await siteRepo.getSiteById('site-fail-closed', creatorId: userA), isNotNull);
      await siteRepo.deleteSite('site-fail-closed', creatorId: '');
      expect(await siteRepo.getSiteById('site-fail-closed', creatorId: userA), isNotNull);

      // Test null creatorId across all MediaRepository queries
      expect(await mediaRepo.watchAllMedia(creatorId: null).first, isEmpty);
      expect(await mediaRepo.watchAllMedia(creatorId: '').first, isEmpty);
      expect(await mediaRepo.searchMedia(query: 'Testing', creatorId: null), isEmpty);
      expect(await mediaRepo.searchMedia(query: 'Testing', creatorId: ''), isEmpty);
      expect(await mediaRepo.getUnsyncedMedia(creatorId: null), isEmpty);
      expect(await mediaRepo.getUnsyncedMedia(creatorId: ''), isEmpty);
      expect(await mediaRepo.watchUnsyncedCount(creatorId: null).first, equals(0));
      expect(await mediaRepo.watchUnsyncedCount(creatorId: '').first, equals(0));
      expect(await mediaRepo.watchTombstoneCandidateCount(creatorId: null).first, equals(0));
      expect(await mediaRepo.watchTombstoneCandidateCount(creatorId: '').first, equals(0));
      expect(await mediaRepo.getResolvedMediaIds(siteId: 'site-fail-closed', creatorId: null), isEmpty);
      expect(await mediaRepo.getResolvedMediaIds(siteId: 'site-fail-closed', creatorId: ''), isEmpty);
      expect(await mediaRepo.getPendingOrFailedMedia(creatorId: null), isEmpty);
      expect(await mediaRepo.getPendingOrFailedMedia(creatorId: ''), isEmpty);
      expect(await mediaRepo.getTombstoneSyncCandidates(creatorId: null), isEmpty);
      expect(await mediaRepo.getTombstoneSyncCandidates(creatorId: ''), isEmpty);

      // Valid UID returns only that user's data (cross-user rows are present).
      expect(await mediaRepo.watchUnsyncedCount(creatorId: userA).first, equals(1));
      expect(await mediaRepo.watchUnsyncedCount(creatorId: userB).first, equals(0));
      expect(await mediaRepo.watchTombstoneCandidateCount(creatorId: userA).first, equals(1));
      expect(await mediaRepo.watchTombstoneCandidateCount(creatorId: userB).first, equals(1));

      final tombstoneCandidatesA = await mediaRepo.getTombstoneSyncCandidates(creatorId: userA);
      expect(tombstoneCandidatesA.map((m) => m.id), equals(['media-tombstone-a']));
      final tombstoneCandidatesB = await mediaRepo.getTombstoneSyncCandidates(creatorId: userB);
      expect(tombstoneCandidatesB.map((m) => m.id), equals(['media-tombstone-b']));

      // Resolved-linked-evidence: A sees its own linked evidence; B never does.
      expect(
        await mediaRepo.getResolvedMediaIds(siteId: 'site-fail-closed', creatorId: userA),
        contains('media-fail-closed'),
      );
      expect(
        await mediaRepo.getResolvedMediaIds(siteId: 'site-fail-closed', creatorId: userB),
        isEmpty,
      );
    });
  });
}
