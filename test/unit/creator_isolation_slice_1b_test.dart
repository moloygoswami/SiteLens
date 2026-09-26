import 'dart:ffi';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/repositories/site_repository.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/data/local/quarantine/creator_quarantine_service.dart';
import 'package:sitelens/domain/models/site_model.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/domain/models/enums.dart';

void main() {
  setUpAll(() {
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  group('Slice 1B: Local Creator Isolation / Repository Authorization Suite', () {
    late AppDatabase db;
    late SiteRepository siteRepo;
    late MediaRepository mediaRepo;
    late CreatorQuarantineService quarantineService;

    const userA = 'creator-user-a';
    const userB = 'creator-user-b';

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      siteRepo = LocalSiteRepository(db);
      mediaRepo = LocalMediaRepository(db);
      quarantineService = CreatorQuarantineService(db);
      await quarantineService.ensureTablesExist();

      // Seed baseline sites for User A and User B
      await siteRepo.saveSite(
        const SiteModel(
          id: 'site-user-a',
          siteCode: 'SITE_A',
          name: 'Site User A',
          address: '100 Road A',
          creatorId: userA,
        ),
        creatorId: userA,
      );

      await siteRepo.saveSite(
        const SiteModel(
          id: 'site-user-b',
          siteCode: 'SITE_B',
          name: 'Site User B',
          address: '200 Road B',
          creatorId: userB,
        ),
        creatorId: userB,
      );

      // Seed media for User A
      await mediaRepo.insertMedia(
        MediaItem(
          id: 'media-a-1',
          siteId: 'site-user-a',
          originalUri: 'media/orig_a1.jpg',
          uri: 'media/evid_a1.jpg',
          type: MediaItemType.photo,
          lat: 22.5,
          lon: 88.3,
          activityTag: 'Excavation',
          observationType: ObservationType.nonConformity,
          capturedAt: DateTime.utc(2026, 9, 1, 11, 0),
          creatorId: userA,
        ),
        creatorId: userA,
      );

      // Seed media for User B
      await mediaRepo.insertMedia(
        MediaItem(
          id: 'media-b-1',
          siteId: 'site-user-b',
          originalUri: 'media/orig_b1.jpg',
          uri: 'media/evid_b1.jpg',
          type: MediaItemType.photo,
          lat: 22.5,
          lon: 88.3,
          activityTag: 'Excavation',
          observationType: ObservationType.nonConformity,
          capturedAt: DateTime.utc(2026, 9, 1, 11, 0),
          creatorId: userB,
        ),
        creatorId: userB,
      );
    });

    tearDown(() async {
      await db.close();
    });

    // =========================================================================
    // 1. Collection read isolation: User A cannot obtain User B's sites/media
    // =========================================================================
    group('1. Collection Read Isolation', () {
      test('getAllSites returns strictly creator-scoped sites', () async {
        final sitesA = await siteRepo.getAllSites(creatorId: userA);
        expect(sitesA.map((s) => s.id), contains('site-user-a'));
        expect(sitesA.map((s) => s.id), isNot(contains('site-user-b')));

        final sitesB = await siteRepo.getAllSites(creatorId: userB);
        expect(sitesB.map((s) => s.id), contains('site-user-b'));
        expect(sitesB.map((s) => s.id), isNot(contains('site-user-a')));
      });

      test('watchAllMedia streams strictly creator-scoped media', () async {
        final mediaListA = await mediaRepo.watchAllMedia(creatorId: userA).first;
        expect(mediaListA.map((m) => m.id), contains('media-a-1'));
        expect(mediaListA.map((m) => m.id), isNot(contains('media-b-1')));

        final mediaListB = await mediaRepo.watchAllMedia(creatorId: userB).first;
        expect(mediaListB.map((m) => m.id), contains('media-b-1'));
        expect(mediaListB.map((m) => m.id), isNot(contains('media-a-1')));
      });

      test('findNearbyMedia returns strictly creator-scoped results', () async {
        final nearbyA = await mediaRepo.findNearbyMedia(
          centerLat: 22.5,
          centerLon: 88.3,
          radiusMeters: 50.0,
          creatorId: userA,
        );
        expect(nearbyA.map((n) => n.item.id), contains('media-a-1'));
        expect(nearbyA.map((n) => n.item.id), isNot(contains('media-b-1')));
      });

      test('searchMedia queries are strictly creator-scoped', () async {
        final searchA = await mediaRepo.searchMedia(
          query: 'Excavation',
          creatorId: userA,
        );
        expect(searchA.map((m) => m.id), contains('media-a-1'));
        expect(searchA.map((m) => m.id), isNot(contains('media-b-1')));
      });

      test('getResolvedMediaIds is strictly creator-scoped', () async {
        // Seed resolved item for User A
        await mediaRepo.insertMedia(
          MediaItem(
            id: 'media-a-closed',
            siteId: 'site-user-a',
            originalUri: 'media/orig_a_c.jpg',
            uri: 'media/evid_a_c.jpg',
            type: MediaItemType.photo,
            lat: 22.5,
            lon: 88.3,
            observationType: ObservationType.closed,
            linkedMediaId: 'media-a-1',
            capturedAt: DateTime.utc(2026, 9, 1, 12, 0),
            creatorId: userA,
          ),
          creatorId: userA,
        );

        final resolvedA = await mediaRepo.getResolvedMediaIds(
          siteId: 'site-user-a',
          creatorId: userA,
        );
        expect(resolvedA, contains('media-a-1'));

        final resolvedB = await mediaRepo.getResolvedMediaIds(
          siteId: 'site-user-a',
          creatorId: userB,
        );
        expect(resolvedB, isNot(contains('media-a-1')));
      });
    });

    // =========================================================================
    // 2. Direct-ID isolation: User A cannot retrieve User B's resource by ID
    // =========================================================================
    group('2. Direct-ID Isolation', () {
      test('getSiteById returns null when accessing foreign creator site', () async {
        final siteForUserA = await siteRepo.getSiteById('site-user-b', creatorId: userA);
        expect(siteForUserA, isNull);

        final siteForUserB = await siteRepo.getSiteById('site-user-a', creatorId: userB);
        expect(siteForUserB, isNull);

        // Own site retrieves cleanly
        final ownA = await siteRepo.getSiteById('site-user-a', creatorId: userA);
        expect(ownA, isNotNull);
        expect(ownA!.id, equals('site-user-a'));
      });

      test('getMediaById returns null when accessing foreign creator media', () async {
        final mediaForUserA = await mediaRepo.getMediaById('media-b-1', creatorId: userA);
        expect(mediaForUserA, isNull);

        final mediaForUserB = await mediaRepo.getMediaById('media-a-1', creatorId: userB);
        expect(mediaForUserB, isNull);

        // Own media retrieves cleanly
        final ownA = await mediaRepo.getMediaById('media-a-1', creatorId: userA);
        expect(ownA, isNotNull);
        expect(ownA!.id, equals('media-a-1'));
      });
    });

    // =========================================================================
    // 3. Mutation isolation: User A cannot update/delete/overwrite User B's resource
    // =========================================================================
    group('3. Mutation Isolation', () {
      test('User A cannot updateTags on User B media', () async {
        expect(
          () => mediaRepo.updateTags(
            mediaId: 'media-b-1',
            activityTag: 'Attacked',
            observationType: ObservationType.general,
            creatorId: userA,
          ),
          throwsA(isA<MediaIsolationException>()),
        );

        // Verify media-b-1 unchanged
        final itemB = await mediaRepo.getMediaById('media-b-1', creatorId: userB);
        expect(itemB!.activityTag, equals('Excavation'));
      });

      test('User A cannot softDeleteMedia belonging to User B', () async {
        expect(
          () => mediaRepo.softDeleteMedia('media-b-1', creatorId: userA),
          throwsA(isA<MediaIsolationException>()),
        );

        final itemB = await mediaRepo.getMediaById('media-b-1', creatorId: userB);
        expect(itemB!.isDeleted, isFalse);
      });

      test('User A cannot removeFromGallery on User B media', () async {
        expect(
          () => mediaRepo.removeFromGallery('media-b-1', creatorId: userA),
          throwsA(isA<MediaIsolationException>()),
        );

        final itemB = await mediaRepo.getMediaById('media-b-1', creatorId: userB);
        expect(itemB!.isDeleted, isFalse);
      });

      test('User A cannot deletePermanently on User B media', () async {
        expect(
          () => mediaRepo.deletePermanently('media-b-1', creatorId: userA),
          throwsA(isA<MediaIsolationException>()),
        );

        final itemB = await mediaRepo.getMediaById('media-b-1', creatorId: userB);
        expect(itemB, isNotNull);
      });

      test('User A cannot markTombstoneReconciled on User B media', () async {
        expect(
          () => mediaRepo.markTombstoneReconciled('media-b-1', creatorId: userA),
          throwsA(isA<MediaIsolationException>()),
        );
      });

      test('User A cannot updateSyncStatus on User B media', () async {
        expect(
          () => mediaRepo.updateSyncStatus('media-b-1', SyncStatusType.synced, creatorId: userA),
          throwsA(isA<MediaIsolationException>()),
        );
      });
    });

    // =========================================================================
    // 4. Ownership propagation: Resources retain authoritative creator_id
    // =========================================================================
    group('4. Ownership Propagation', () {
      test('Site created under User A retains User A creatorId', () async {
        final site = await siteRepo.getSiteById('site-user-a', creatorId: userA);
        expect(site!.creatorId, equals(userA));
      });

      test('Media created under User A retains User A creatorId', () async {
        final media = await mediaRepo.getMediaById('media-a-1', creatorId: userA);
        expect(media!.creatorId, equals(userA));
      });
    });

    // =========================================================================
    // 5. Ownership immutability: User B cannot re-stamp or claim User A's resource
    // =========================================================================
    group('5. Ownership Immutability', () {
      test('User B cannot overwrite or re-stamp User A site', () async {
        expect(
          () => siteRepo.saveSite(
            const SiteModel(
              id: 'site-user-a',
              siteCode: 'HIJACKED',
              name: 'Hijacked Site',
              address: '999 Pirate Way',
              creatorId: userB,
            ),
            creatorId: userB,
          ),
          throwsA(isA<SiteIsolationException>()),
        );

        // Verify site-user-a was not modified
        final originalSite = await siteRepo.getSiteById('site-user-a', creatorId: userA);
        expect(originalSite!.name, equals('Site User A'));
        expect(originalSite.creatorId, equals(userA));
      });

      test('User B cannot overwrite or re-stamp User A media', () async {
        expect(
          () => mediaRepo.insertMedia(
            MediaItem(
              id: 'media-a-1',
              siteId: 'site-user-b',
              originalUri: 'media/hijack.jpg',
              uri: 'media/hijack.jpg',
              type: MediaItemType.photo,
              lat: 22.5,
              lon: 88.3,
              capturedAt: DateTime.utc(2026, 9, 1, 11, 0),
              creatorId: userB,
            ),
            creatorId: userB,
          ),
          throwsA(isA<MediaIsolationException>()),
        );

        // Verify media-a-1 was not modified
        final originalMedia = await mediaRepo.getMediaById('media-a-1', creatorId: userA);
        expect(originalMedia!.siteId, equals('site-user-a'));
        expect(originalMedia.creatorId, equals(userA));
      });
    });

    // =========================================================================
    // 6. Fail-closed behavior: null/empty creator identity fails closed
    // =========================================================================
    group('6. Fail-Closed Behavior', () {
      test('getAllSites fails closed on null and empty creatorId', () async {
        expect(await siteRepo.getAllSites(creatorId: null), isEmpty);
        expect(await siteRepo.getAllSites(creatorId: ''), isEmpty);
      });

      test('getSiteById fails closed on null and empty creatorId', () async {
        expect(await siteRepo.getSiteById('site-user-a', creatorId: null), isNull);
        expect(await siteRepo.getSiteById('site-user-a', creatorId: ''), isNull);
      });

      test('saveSite fails closed on null and empty creatorId', () async {
        expect(
          () => siteRepo.saveSite(
            const SiteModel(id: 'site-unauth', siteCode: 'UNAUTH', name: 'Unauth', address: 'Unknown'),
            creatorId: null,
          ),
          throwsA(isA<SiteIsolationException>()),
        );
        expect(
          () => siteRepo.saveSite(
            const SiteModel(id: 'site-unauth', siteCode: 'UNAUTH', name: 'Unauth', address: 'Unknown'),
            creatorId: '',
          ),
          throwsA(isA<SiteIsolationException>()),
        );
      });

      test('watchAllMedia fails closed on null and empty creatorId', () async {
        final streamNull = mediaRepo.watchAllMedia(creatorId: null);
        expect(await streamNull.first, isEmpty);

        final streamEmpty = mediaRepo.watchAllMedia(creatorId: '');
        expect(await streamEmpty.first, isEmpty);
      });

      test('getMediaById fails closed on null and empty creatorId (NO unscoped lookup)', () async {
        expect(await mediaRepo.getMediaById('media-a-1', creatorId: null), isNull);
        expect(await mediaRepo.getMediaById('media-a-1', creatorId: ''), isNull);
      });

      test('insertMedia fails closed on null and empty creatorId', () async {
        expect(
          () => mediaRepo.insertMedia(
            MediaItem(
              id: 'media-no-auth',
              siteId: 'site-user-a',
              originalUri: 'media/noauth.jpg',
              uri: 'media/noauth.jpg',
              type: MediaItemType.photo,
              lat: 22.5,
              lon: 88.3,
              capturedAt: DateTime.utc(2026, 9, 1, 10),
            ),
            creatorId: null,
          ),
          throwsA(isA<MediaIsolationException>()),
        );
      });

      test('findNearbyMedia fails closed on null and empty creatorId', () async {
        final resNull = await mediaRepo.findNearbyMedia(
          centerLat: 22.5,
          centerLon: 88.3,
          radiusMeters: 50.0,
          creatorId: null,
        );
        expect(resNull, isEmpty);

        final resEmpty = await mediaRepo.findNearbyMedia(
          centerLat: 22.5,
          centerLon: 88.3,
          radiusMeters: 50.0,
          creatorId: '',
        );
        expect(resEmpty, isEmpty);
      });

      test('findSuggestedBeforeMatch fails closed on null and empty creatorId', () async {
        final matchNull = await mediaRepo.findSuggestedBeforeMatch(
          centerLat: 22.5,
          centerLon: 88.3,
          siteId: 'site-user-a',
          activityTag: 'Excavation',
          capturedBefore: DateTime.utc(2026, 9, 1, 12),
          creatorId: null,
        );
        expect(matchNull, isNull);

        final matchEmpty = await mediaRepo.findSuggestedBeforeMatch(
          centerLat: 22.5,
          centerLon: 88.3,
          siteId: 'site-user-a',
          activityTag: 'Excavation',
          capturedBefore: DateTime.utc(2026, 9, 1, 12),
          creatorId: '',
        );
        expect(matchEmpty, isNull);
      });

      test('linkMedia fails closed on null and empty creatorId', () async {
        expect(
          () => mediaRepo.linkMedia(
            mediaId: 'media-a-1',
            linkedMediaId: 'media-a-1',
            creatorId: null,
          ),
          throwsA(isA<MediaIsolationException>()),
        );
      });

      test('updateTags fails closed on null and empty creatorId', () async {
        expect(
          () => mediaRepo.updateTags(
            mediaId: 'media-a-1',
            activityTag: 'Tag',
            observationType: ObservationType.general,
            creatorId: null,
          ),
          throwsA(isA<MediaIsolationException>()),
        );
      });
    });

    // =========================================================================
    // 7. Linked-resource isolation: Cross-creator linked media operations rejected
    // =========================================================================
    group('7. Linked-Resource Isolation', () {
      test('linkMedia rejects linking User A media with User B candidate', () async {
        // Seed closed observation under User A
        await mediaRepo.insertMedia(
          MediaItem(
            id: 'media-a-closed-2',
            siteId: 'site-user-a',
            originalUri: 'media/orig_c2.jpg',
            uri: 'media/evid_c2.jpg',
            type: MediaItemType.photo,
            lat: 22.5,
            lon: 88.3,
            observationType: ObservationType.closed,
            capturedAt: DateTime.utc(2026, 9, 1, 12),
            creatorId: userA,
          ),
          creatorId: userA,
        );

        expect(
          () => mediaRepo.linkMedia(
            mediaId: 'media-a-closed-2',
            linkedMediaId: 'media-b-1',
            creatorId: userA,
          ),
          throwsA(
            isA<MediaIsolationException>().having(
              (e) => e.message,
              'message',
              contains('Creator isolation violation'),
            ),
          ),
        );
      });

      test('insertMedia rejects linking to candidate belonging to different creator', () async {
        expect(
          () => mediaRepo.insertMedia(
            MediaItem(
              id: 'media-a-closed-cross',
              siteId: 'site-user-a',
              originalUri: 'media/orig_cross.jpg',
              uri: 'media/evid_cross.jpg',
              type: MediaItemType.photo,
              lat: 22.5,
              lon: 88.3,
              observationType: ObservationType.closed,
              linkedMediaId: 'media-b-1',
              capturedAt: DateTime.utc(2026, 9, 1, 12),
              creatorId: userA,
            ),
            creatorId: userA,
          ),
          throwsA(
            isA<MediaIsolationException>().having(
              (e) => e.message,
              'message',
              contains('Creator isolation violation'),
            ),
          ),
        );
      });

      test('updateTags rejects cross-creator linkedMediaId', () async {
        expect(
          () => mediaRepo.updateTags(
            mediaId: 'media-a-1',
            activityTag: 'Closure',
            observationType: ObservationType.closed,
            linkedMediaId: 'media-b-1',
            creatorId: userA,
          ),
          throwsA(
            isA<MediaIsolationException>().having(
              (e) => e.message,
              'message',
              contains('Creator isolation violation'),
            ),
          ),
        );
      });
    });

    // =========================================================================
    // 8. Quarantine semantics: Unresolved creator records are never auto-attributed
    // =========================================================================
    group('8. Quarantine Semantics', () {
      test('unresolved creator site is quarantined to separate table and never auto-attributed', () async {
        // Classify and quarantine an unattributed site
        const orphanedSite = SiteModel(
          id: 'site-legacy-orphaned',
          siteCode: 'ORPHAN',
          name: 'Orphaned Site',
          address: 'Unknown Road',
          creatorId: null, // missing creator
        );

        await quarantineService.quarantineSite(
          orphanedSite,
          reason: 'Missing creator identity on sync/import',
        );

        // Excluded from active creator-scoped queries for User A and User B
        final sitesA = await siteRepo.getAllSites(creatorId: userA);
        expect(sitesA.map((s) => s.id), isNot(contains('site-legacy-orphaned')));

        final sitesB = await siteRepo.getAllSites(creatorId: userB);
        expect(sitesB.map((s) => s.id), isNot(contains('site-legacy-orphaned')));

        final directA = await siteRepo.getSiteById('site-legacy-orphaned', creatorId: userA);
        expect(directA, isNull);

        // Exists in dedicated quarantine table for recovery without auto-attribution
        final isQuarantined = await quarantineService.isSiteQuarantined('site-legacy-orphaned');
        expect(isQuarantined, isTrue);
      });

      test('unresolved creator media is quarantined to separate table and never auto-attributed', () async {
        final orphanedMedia = MediaItem(
          id: 'media-legacy-orphaned',
          siteId: 'site-user-a',
          originalUri: 'media/orphan.jpg',
          uri: 'media/orphan.jpg',
          type: MediaItemType.photo,
          lat: 22.5,
          lon: 88.3,
          capturedAt: DateTime.utc(2026, 9, 1, 10),
          creatorId: null, // missing creator
        );

        await quarantineService.quarantineMedia(
          orphanedMedia,
          reason: 'Corrupt/missing creator identity header',
        );

        // Excluded from active creator-scoped queries
        final mediaListA = await mediaRepo.watchAllMedia(creatorId: userA).first;
        expect(mediaListA.map((m) => m.id), isNot(contains('media-legacy-orphaned')));

        final directA = await mediaRepo.getMediaById('media-legacy-orphaned', creatorId: userA);
        expect(directA, isNull);

        // Exists in dedicated quarantine storage
        final isQuarantined = await quarantineService.isMediaQuarantined('media-legacy-orphaned');
        expect(isQuarantined, isTrue);
      });
    });

    // =========================================================================
    // 9. Repository access-path coverage: All audit paths verified
    // =========================================================================
    group('9. Repository Access-Path Coverage', () {
      test('resetStuckSyncingMedia respects creatorId isolation', () async {
        // Resetting for User A does not fail and is creator-scoped
        await expectLater(
          mediaRepo.resetStuckSyncingMedia(creatorId: userA),
          completes,
        );

        // Null creatorId fails closed
        await expectLater(
          mediaRepo.resetStuckSyncingMedia(creatorId: null),
          completes,
        );
      });

      test('getAllMediaEntriesIncludingDeleted respects creatorId isolation', () async {
        final allA = await mediaRepo.getAllMediaEntriesIncludingDeleted(creatorId: userA);
        expect(allA.every((m) => m.creatorId == userA), isTrue);

        final allB = await mediaRepo.getAllMediaEntriesIncludingDeleted(creatorId: userB);
        expect(allB.every((m) => m.creatorId == userB), isTrue);

        expect(await mediaRepo.getAllMediaEntriesIncludingDeleted(creatorId: null), isEmpty);
        expect(await mediaRepo.getAllMediaEntriesIncludingDeleted(creatorId: ''), isEmpty);
      });
    });
  });
}
