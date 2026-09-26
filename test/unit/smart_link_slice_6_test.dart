import 'dart:ffi';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sitelens/core/utils/gps_utils.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/features/nearby/models/nearby_search_state.dart';

void main() {
  late AppDatabase db;
  late MediaRepository mediaRepo;

  setUpAll(() {
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    mediaRepo = LocalMediaRepository(db);

    // Seed Site Alpha and Beta
    await db.into(db.sites).insert(
          SitesCompanion.insert(
            id: 'site-alpha-uuid',
            siteCode: const drift.Value('SITE-ALPHA'),
            name: const drift.Value('Site Alpha North'),
          ),
        );
    await db.into(db.sites).insert(
          SitesCompanion.insert(
            id: 'site-beta-uuid',
            siteCode: const drift.Value('SITE-BETA'),
            name: const drift.Value('Site Beta South'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  const centerLat = 22.57264;
  const centerLon = 88.36389;

  group('TM-U-12 [AC-LINK-01, AC-LINK-05, AC-LINK-06, AC-LINK-07]: Smart-Link Candidate Query', () {
    test('Candidate filtering: radius (>10m rejected), site, activity, creator, and temporal precedence', () async {
      final captureTime = DateTime.utc(2026, 9, 21, 10, 0, 0);

      // 1. Valid matching candidate
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'candidate-valid',
              siteId: const drift.Value('site-alpha-uuid'),
              originalUri: const drift.Value('media/orig_val.jpg'),
              uri: 'media/evid_val.jpg',
              lat: centerLat + 0.00003, // ~3.3m
              lon: centerLon,
              activityTag: const drift.Value('Trenching'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-09-21T09:00:00Z', // 1 hr before
              creatorId: const drift.Value('user-alice'),
            ),
          );

      // 2. Candidate outside 10m radius (>10m rejected)
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'candidate-too-far',
              siteId: const drift.Value('site-alpha-uuid'),
              originalUri: const drift.Value('media/orig_far.jpg'),
              uri: 'media/evid_far.jpg',
              lat: centerLat + 0.0003, // ~33m
              lon: centerLon,
              activityTag: const drift.Value('Trenching'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-09-21T09:00:00Z',
              creatorId: const drift.Value('user-alice'),
            ),
          );

      // 3. Candidate on different site rejected
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'candidate-diff-site',
              siteId: const drift.Value('site-beta-uuid'),
              originalUri: const drift.Value('media/orig_site.jpg'),
              uri: 'media/evid_site.jpg',
              lat: centerLat + 0.00002, // ~2.2m
              lon: centerLon,
              activityTag: const drift.Value('Trenching'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-09-21T09:00:00Z',
              creatorId: const drift.Value('user-alice'),
            ),
          );

      // 4. Candidate with different activity rejected (when activity is non-empty)
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'candidate-diff-activity',
              siteId: const drift.Value('site-alpha-uuid'),
              originalUri: const drift.Value('media/orig_act.jpg'),
              uri: 'media/evid_act.jpg',
              lat: centerLat + 0.00002,
              lon: centerLon,
              activityTag: const drift.Value('Concrete Pouring'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-09-21T09:00:00Z',
              creatorId: const drift.Value('user-alice'),
            ),
          );

      // 5. Candidate created by User B rejected when querying as User Alice
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'candidate-diff-creator',
              siteId: const drift.Value('site-alpha-uuid'),
              originalUri: const drift.Value('media/orig_bob.jpg'),
              uri: 'media/evid_bob.jpg',
              lat: centerLat + 0.00001,
              lon: centerLon,
              activityTag: const drift.Value('Trenching'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-09-21T09:00:00Z',
              creatorId: const drift.Value('user-bob'),
            ),
          );

      // 6. Candidate captured later than current item is never returned
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'candidate-future',
              siteId: const drift.Value('site-alpha-uuid'),
              originalUri: const drift.Value('media/orig_fut.jpg'),
              uri: 'media/evid_fut.jpg',
              lat: centerLat + 0.00001,
              lon: centerLon,
              activityTag: const drift.Value('Trenching'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-09-21T11:00:00Z', // 1 hr after
              creatorId: const drift.Value('user-alice'),
            ),
          );

      // 7. Candidate captured at the exact same second is rejected (must be strictly earlier)
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'candidate-simultaneous',
              siteId: const drift.Value('site-alpha-uuid'),
              originalUri: const drift.Value('media/orig_sim.jpg'),
              uri: 'media/evid_sim.jpg',
              lat: centerLat + 0.00001,
              lon: centerLon,
              activityTag: const drift.Value('Trenching'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-09-21T10:00:00Z',
              creatorId: const drift.Value('user-alice'),
            ),
          );

      final match = await mediaRepo.findSuggestedBeforeMatch(
        centerLat: centerLat,
        centerLon: centerLon,
        siteId: 'site-alpha-uuid',
        activityTag: 'Trenching',
        capturedBefore: captureTime,
        radiusMeters: 10.0,
        creatorId: 'user-alice',
      );

      expect(match, isNotNull);
      expect(match!.id, 'candidate-valid');
    });

    test('Unlinking a fixture pair restores candidate status without mutating other fields', () async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'nc-defect-1',
              siteId: const drift.Value('site-alpha-uuid'),
              originalUri: const drift.Value('media/orig_nc1.jpg'),
              uri: 'media/evid_nc1.jpg',
              lat: centerLat,
              lon: centerLon,
              activityTag: const drift.Value('Paving'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-09-21T08:00:00Z',
              creatorId: const drift.Value('user-alice'),
              sha256Hash: const drift.Value('sha-orig-nc1'),
              evidenceSha256Hash: const drift.Value('sha-evid-nc1'),
              note: const drift.Value('Paving crack defect'),
            ),
          );

      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'closed-res-1',
              siteId: const drift.Value('site-alpha-uuid'),
              originalUri: const drift.Value('media/orig_cl1.jpg'),
              uri: 'media/evid_cl1.jpg',
              lat: centerLat,
              lon: centerLon,
              activityTag: const drift.Value('Paving'),
              observationType: const drift.Value('closed'),
              linkedMediaId: const drift.Value('nc-defect-1'),
              capturedAt: '2026-09-21T09:00:00Z',
              creatorId: const drift.Value('user-alice'),
              sha256Hash: const drift.Value('sha-orig-cl1'),
              evidenceSha256Hash: const drift.Value('sha-evid-cl1'),
              note: const drift.Value('Resurfaced pavement [Evid_ID: nc-defect-1]'),
            ),
          );

      // Verify nc-defect-1 is marked as resolved
      var resolved = await mediaRepo.getResolvedMediaIds(siteId: 'site-alpha-uuid', creatorId: 'user-alice');
      expect(resolved, contains('nc-defect-1'));

      // Unlink: update closed-res-1 to have null linkedMediaId and switch observationType to progress
      await mediaRepo.updateTags(
        mediaId: 'closed-res-1',
        activityTag: 'Paving',
        observationType: ObservationType.progress,
        linkedMediaId: null,
        note: 'Resurfaced pavement',
        creatorId: 'user-alice',
      );

      // Verify nc-defect-1 is no longer resolved
      resolved = await mediaRepo.getResolvedMediaIds(siteId: 'site-alpha-uuid', creatorId: 'user-alice');
      expect(resolved, isNot(contains('nc-defect-1')));

      // Verify candidate status restored and all fields of nc-defect-1 remain unmutated
      final restored = await mediaRepo.getMediaById('nc-defect-1', creatorId: 'user-alice');
      expect(restored, isNotNull);
      expect(restored!.id, 'nc-defect-1');
      expect(restored.observationType, ObservationType.nonConformity);
      expect(restored.activityTag, 'Paving');
      expect(restored.note, 'Paving crack defect');
      expect(restored.sha256Hash, 'sha-orig-nc1');
      expect(restored.evidenceSha256Hash, 'sha-evid-nc1');
      expect(restored.isDeleted, isFalse);
    });
  });

  group('TM-U-14 [AC-NEARBY-03, AC-NEARBY-04, AC-NEARBY-05, AC-NEARBY-06]: Spatial Refinement & Formatting', () {
    test('Zero cross-creator results at identical coordinates', () async {
      // Alice item at center
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'alice-photo',
              siteId: const drift.Value('site-alpha-uuid'),
              originalUri: const drift.Value('media/alice.jpg'),
              uri: 'media/alice_evid.jpg',
              lat: centerLat,
              lon: centerLon,
              capturedAt: '2026-09-21T09:00:00Z',
              creatorId: const drift.Value('user-alice'),
            ),
          );

      // Bob item at the EXACT SAME physical coordinates
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'bob-photo',
              siteId: const drift.Value('site-alpha-uuid'),
              originalUri: const drift.Value('media/bob.jpg'),
              uri: 'media/bob_evid.jpg',
              lat: centerLat,
              lon: centerLon,
              capturedAt: '2026-09-21T09:00:00Z',
              creatorId: const drift.Value('user-bob'),
            ),
          );

      // Search as Alice
      final aliceResults = await mediaRepo.findNearbyMedia(
        centerLat: centerLat,
        centerLon: centerLon,
        radiusMeters: 50.0,
        creatorId: 'user-alice',
      );
      expect(aliceResults.every((r) => r.item.creatorId == 'user-alice'), isTrue);
      expect(aliceResults.any((r) => r.item.id == 'bob-photo'), isFalse);

      // Search as Bob
      final bobResults = await mediaRepo.findNearbyMedia(
        centerLat: centerLat,
        centerLon: centerLon,
        radiusMeters: 50.0,
        creatorId: 'user-bob',
      );
      expect(bobResults.every((r) => r.item.creatorId == 'user-bob'), isTrue);
      expect(bobResults.any((r) => r.item.id == 'alice-photo'), isFalse);
    });

    test('Distance-filter bound incorporates candidate accuracy margin (R19)', () async {
      // Item is ~12.0m away (8.5m lat, 8.5m lon) - inside the 10m bounding box diagonal (~14.1m),
      // exceeding nominal 10m radius, but within 10m + 4m candidate accuracy uncertainty bound.
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'uncertain-cand',
              siteId: const drift.Value('site-alpha-uuid'),
              originalUri: const drift.Value('media/orig_unc.jpg'),
              uri: 'media/evid_unc.jpg',
              lat: centerLat + (8.5 / 111320.0),
              lon: centerLon + (8.5 / 102800.0),
              accuracyM: const drift.Value(4.0),
              capturedAt: '2026-09-21T09:00:00Z',
              creatorId: const drift.Value('user-alice'),
            ),
          );

      final results = await mediaRepo.findNearbyMedia(
        centerLat: centerLat,
        centerLon: centerLon,
        radiusMeters: 10.0,
        creatorId: 'user-alice',
      );

      expect(results.any((r) => r.item.id == 'uncertain-cand'), isTrue);
    });

    test('Deterministic sort order: distance ascending -> recency descending -> id ascending', () async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'item-b',
              siteId: const drift.Value('site-alpha-uuid'),
              originalUri: const drift.Value('media/b.jpg'),
              uri: 'media/b_e.jpg',
              lat: centerLat + (5.0 / 111320.0),
              lon: centerLon,
              capturedAt: '2026-09-21T09:00:00Z',
              creatorId: const drift.Value('user-alice'),
            ),
          );
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'item-a',
              siteId: const drift.Value('site-alpha-uuid'),
              originalUri: const drift.Value('media/a.jpg'),
              uri: 'media/a_e.jpg',
              lat: centerLat + (5.0 / 111320.0),
              lon: centerLon,
              capturedAt: '2026-09-21T09:00:00Z',
              creatorId: const drift.Value('user-alice'),
            ),
          );
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'item-c',
              siteId: const drift.Value('site-alpha-uuid'),
              originalUri: const drift.Value('media/c.jpg'),
              uri: 'media/c_e.jpg',
              lat: centerLat + (5.0 / 111320.0),
              lon: centerLon,
              capturedAt: '2026-09-21T09:30:00Z',
              creatorId: const drift.Value('user-alice'),
            ),
          );
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'item-d',
              siteId: const drift.Value('site-alpha-uuid'),
              originalUri: const drift.Value('media/d.jpg'),
              uri: 'media/d_e.jpg',
              lat: centerLat + (2.0 / 111320.0),
              lon: centerLon,
              capturedAt: '2026-09-21T08:00:00Z',
              creatorId: const drift.Value('user-alice'),
            ),
          );

      final results = await mediaRepo.findNearbyMedia(
        centerLat: centerLat,
        centerLon: centerLon,
        radiusMeters: 10.0,
        creatorId: 'user-alice',
      );

      final ids = results.map((r) => r.item.id).toList();
      expect(ids, ['item-d', 'item-c', 'item-a', 'item-b']);
    });

    test('Distance-display formatter includes accuracy uncertainty suffix and never bare sub-meter precision', () {
      final formattedWithAcc = GPSUtils.formatDistanceWithUncertainty(12.345, accuracyMeters: 4.2);
      expect(formattedWithAcc, '12.3m (±4.2m)');

      final formattedNull = GPSUtils.formatDistanceWithUncertainty(8.765, accuracyMeters: null);
      expect(formattedNull, '8.8m (±—)');

      final formattedZero = GPSUtils.formatDistanceWithUncertainty(0.0, accuracyMeters: 1.5);
      expect(formattedZero, '0.0m (±1.5m)');
    });

    test('Grouping classifies results into Before, After, Progress, and Other', () {
      final mockState = NearbySearchState(
        centerLat: centerLat,
        centerLon: centerLon,
        results: [
          NearbyMediaResult(
            item: MediaItem(
              id: 'nc-1',
              siteId: 'site-alpha-uuid',
              originalUri: 'a',
              uri: 'b',
              thumbUri: 'c',
              type: MediaItemType.photo,
              lat: centerLat,
              lon: centerLon,
              observationType: ObservationType.nonConformity,
              capturedAt: DateTime.utc(2026, 9, 21),
              creatorId: 'user-alice',
              syncStatus: SyncStatusType.pending,
            ),
            distanceMeters: 3.0,
          ),
          NearbyMediaResult(
            item: MediaItem(
              id: 'cl-1',
              siteId: 'site-alpha-uuid',
              originalUri: 'a',
              uri: 'b',
              thumbUri: 'c',
              type: MediaItemType.photo,
              lat: centerLat,
              lon: centerLon,
              observationType: ObservationType.closed,
              capturedAt: DateTime.utc(2026, 9, 21),
              creatorId: 'user-alice',
              syncStatus: SyncStatusType.pending,
            ),
            distanceMeters: 5.0,
          ),
          NearbyMediaResult(
            item: MediaItem(
              id: 'pr-1',
              siteId: 'site-alpha-uuid',
              originalUri: 'a',
              uri: 'b',
              thumbUri: 'c',
              type: MediaItemType.photo,
              lat: centerLat,
              lon: centerLon,
              observationType: ObservationType.progress,
              capturedAt: DateTime.utc(2026, 9, 21),
              creatorId: 'user-alice',
              syncStatus: SyncStatusType.pending,
            ),
            distanceMeters: 7.0,
          ),
          NearbyMediaResult(
            item: MediaItem(
              id: 'gen-1',
              siteId: 'site-alpha-uuid',
              originalUri: 'a',
              uri: 'b',
              thumbUri: 'c',
              type: MediaItemType.photo,
              lat: centerLat,
              lon: centerLon,
              observationType: ObservationType.general,
              capturedAt: DateTime.utc(2026, 9, 21),
              creatorId: 'user-alice',
              syncStatus: SyncStatusType.pending,
            ),
            distanceMeters: 9.0,
          ),
        ],
      );

      expect(mockState.beforeResults.map((r) => r.item.id), ['nc-1']);
      expect(mockState.afterResults.map((r) => r.item.id), ['cl-1']);
      expect(mockState.progressResults.map((r) => r.item.id), ['pr-1']);
      expect(mockState.otherResults.map((r) => r.item.id), ['gen-1']);
    });
  });

  group('TM-U-16 [AC-PERF-03]: Bounding-Box Pre-Filter', () {
    test('Bounding box pre-filter isolates spatial candidates prior to exact Haversine calculation', () async {
      for (int i = 0; i < 50; i++) {
        await db.into(db.media).insert(
              MediaCompanion.insert(
                id: 'far-item-$i',
                siteId: const drift.Value('site-alpha-uuid'),
                originalUri: drift.Value('media/far_$i.jpg'),
                uri: 'media/far_evid_$i.jpg',
                lat: centerLat + 10.0 + (i * 0.01),
                lon: centerLon,
                capturedAt: '2026-09-21T09:00:00Z',
                creatorId: const drift.Value('user-alice'),
              ),
            );
      }

      for (int i = 1; i <= 3; i++) {
        await db.into(db.media).insert(
              MediaCompanion.insert(
                id: 'near-item-$i',
                siteId: const drift.Value('site-alpha-uuid'),
                originalUri: drift.Value('media/near_$i.jpg'),
                uri: 'media/near_evid_$i.jpg',
                lat: centerLat + (i * 4.0 / 111320.0),
                lon: centerLon,
                capturedAt: '2026-09-21T09:00:00Z',
                creatorId: const drift.Value('user-alice'),
              ),
            );
      }

      final results = await mediaRepo.findNearbyMedia(
        centerLat: centerLat,
        centerLon: centerLon,
        radiusMeters: 25.0,
        creatorId: 'user-alice',
      );

      expect(results.length, 3);
      expect(results.map((r) => r.item.id).toSet(), {'near-item-1', 'near-item-2', 'near-item-3'});
    });
  });
}
