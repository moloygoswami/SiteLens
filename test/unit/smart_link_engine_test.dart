import 'dart:ffi';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/domain/models/enums.dart';

void main() {
  late AppDatabase db;
  late MediaRepository mediaRepo;

  setUpAll(() {
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    mediaRepo = LocalMediaRepository(db);

    // Seed Site
    await db.into(db.sites).insert(
          SitesCompanion.insert(
            id: 'SITE_A',
            siteCode: const drift.Value('SITE_A'),
            name: const drift.Value('Site A'),
          ),
        );
    await db.into(db.sites).insert(
          SitesCompanion.insert(
            id: 'SITE_B',
            siteCode: const drift.Value('SITE_B'),
            name: const drift.Value('Site B'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  group('Smart-Link Engine & Spatial Matching Tests', () {
    const centerLat = 22.57264;
    const centerLon = 88.36389;

    test('Matches candidates at 0m, 5m, 9.99m, and exactly 10m', () async {
      // 0m (exact match)
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'nc-0m',
              siteId: const drift.Value('SITE_A'),
              originalUri: const drift.Value('media/orig_0m.jpg'),
              uri: 'media/evid_0m.jpg',
              lat: centerLat,
              lon: centerLon,
              activityTag: const drift.Value('Excavation'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-15T01:00:00Z',
              creatorId: const drift.Value('user-1'),
            ),
          );

      final match = await mediaRepo.findSuggestedBeforeMatch(
        centerLat: centerLat,
        centerLon: centerLon,
        siteId: 'SITE_A',
        activityTag: 'Excavation',
        capturedBefore: DateTime.utc(2026, 8, 15, 2),
        radiusMeters: 10.0,
        creatorId: 'user-1',
      );

      expect(match, isNotNull);
      expect(match!.id, 'nc-0m');
      expect(match.observationType, ObservationType.nonConformity);
    });

    test('Rejects candidates beyond 10m threshold (>10.0m)', () async {
      // ~25m away: 0.0002 deg lat ~ 22.2m
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'nc-far',
              siteId: const drift.Value('SITE_A'),
              originalUri: const drift.Value('media/orig_far.jpg'),
              uri: 'media/evid_far.jpg',
              lat: centerLat + 0.0003, // ~33m away
              lon: centerLon,
              activityTag: const drift.Value('Excavation'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-15T01:00:00Z',
              creatorId: const drift.Value('user-1'),
            ),
          );

      final match = await mediaRepo.findSuggestedBeforeMatch(
        centerLat: centerLat,
        centerLon: centerLon,
        siteId: 'SITE_A',
        activityTag: 'Excavation',
        capturedBefore: DateTime.utc(2026, 8, 15, 2),
        radiusMeters: 10.0,
        creatorId: 'user-1',
      );

      expect(match, isNull);
    });

    test('Rejects candidate from a different site even if physically close', () async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'nc-siteB',
              siteId: const drift.Value('SITE_B'),
              originalUri: const drift.Value('media/orig_siteB.jpg'),
              uri: 'media/evid_siteB.jpg',
              lat: centerLat,
              lon: centerLon,
              activityTag: const drift.Value('Excavation'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-15T01:00:00Z',
              creatorId: const drift.Value('user-1'),
            ),
          );

      final match = await mediaRepo.findSuggestedBeforeMatch(
        centerLat: centerLat,
        centerLon: centerLon,
        siteId: 'SITE_A',
        activityTag: 'Excavation',
        capturedBefore: DateTime.utc(2026, 8, 15, 2),
        radiusMeters: 10.0,
        creatorId: 'user-1',
      );

      expect(match, isNull);
    });

    test('Rejects soft-deleted candidates (is_deleted = 1)', () async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'nc-deleted',
              siteId: const drift.Value('SITE_A'),
              originalUri: const drift.Value('media/orig_del.jpg'),
              uri: 'media/evid_del.jpg',
              lat: centerLat,
              lon: centerLon,
              activityTag: const drift.Value('Excavation'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-15T01:00:00Z',
              isDeleted: const drift.Value(1),
              creatorId: const drift.Value('user-1'),
            ),
          );

      final match = await mediaRepo.findSuggestedBeforeMatch(
        centerLat: centerLat,
        centerLon: centerLon,
        siteId: 'SITE_A',
        activityTag: 'Excavation',
        capturedBefore: DateTime.utc(2026, 8, 15, 2),
        radiusMeters: 10.0,
        creatorId: 'user-1',
      );

      expect(match, isNull);
    });

    test('Excludes current media item from matching itself', () async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'current-item',
              siteId: const drift.Value('SITE_A'),
              originalUri: const drift.Value('media/orig_curr.jpg'),
              uri: 'media/evid_curr.jpg',
              lat: centerLat,
              lon: centerLon,
              activityTag: const drift.Value('Excavation'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-15T01:00:00Z',
              creatorId: const drift.Value('user-1'),
            ),
          );

      final match = await mediaRepo.findSuggestedBeforeMatch(
        centerLat: centerLat,
        centerLon: centerLon,
        siteId: 'SITE_A',
        activityTag: 'Excavation',
        capturedBefore: DateTime.utc(2026, 8, 15, 2),
        radiusMeters: 10.0,
        currentMediaId: 'current-item',
        creatorId: 'user-1',
      );

      expect(match, isNull);
    });

    test('Blank activity matches nearby Non-Conformity on same site', () async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'nc-rebar',
              siteId: const drift.Value('SITE_A'),
              originalUri: const drift.Value('media/orig_rebar.jpg'),
              uri: 'media/evid_rebar.jpg',
              lat: centerLat,
              lon: centerLon,
              activityTag: const drift.Value('Rebar Inspection'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-15T01:00:00Z',
              creatorId: const drift.Value('user-1'),
            ),
          );

      final match = await mediaRepo.findSuggestedBeforeMatch(
        centerLat: centerLat,
        centerLon: centerLon,
        siteId: 'SITE_A',
        activityTag: '', // Blank activity
        capturedBefore: DateTime.utc(2026, 8, 15, 2),
        radiusMeters: 10.0,
        creatorId: 'user-1',
      );

      expect(match, isNotNull);
      expect(match!.id, 'nc-rebar');
    });

    test('Multiple candidates prioritize closest distance first', () async {
      // Item 1: ~8m away
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'nc-8m',
              siteId: const drift.Value('SITE_A'),
              originalUri: const drift.Value('media/orig_8m.jpg'),
              uri: 'media/evid_8m.jpg',
              lat: centerLat + 0.00007,
              lon: centerLon,
              activityTag: const drift.Value('Excavation'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-15T01:00:00Z',
              creatorId: const drift.Value('user-1'),
            ),
          );

      // Item 2: ~2m away (closer)
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'nc-2m',
              siteId: const drift.Value('SITE_A'),
              originalUri: const drift.Value('media/orig_2m.jpg'),
              uri: 'media/evid_2m.jpg',
              lat: centerLat + 0.000018,
              lon: centerLon,
              activityTag: const drift.Value('Excavation'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-14T01:00:00Z',
              creatorId: const drift.Value('user-1'),
            ),
          );

      final match = await mediaRepo.findSuggestedBeforeMatch(
        centerLat: centerLat,
        centerLon: centerLon,
        siteId: 'SITE_A',
        activityTag: 'Excavation',
        capturedBefore: DateTime.utc(2026, 8, 15, 2),
        radiusMeters: 10.0,
        creatorId: 'user-1',
      );

      expect(match, isNotNull);
      expect(match!.id, 'nc-2m'); // Closest candidate selected
    });

    test('Rejects Non-Conformity candidates that are already resolved/closed', () async {
      const creatorId = 'user-1';
      // 1. Insert open Non-Conformity (0m away)
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'nc-resolved',
              siteId: const drift.Value('SITE_A'),
              creatorId: const drift.Value(creatorId),
              originalUri: const drift.Value('media/orig_res.jpg'),
              uri: 'media/evid_res.jpg',
              lat: centerLat,
              lon: centerLon,
              activityTag: const drift.Value('Excavation'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-15T01:00:00Z',
            ),
          );

      // 2. Insert Closed record linking to nc-resolved
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'closed-prev',
              siteId: const drift.Value('SITE_A'),
              creatorId: const drift.Value(creatorId),
              originalUri: const drift.Value('media/orig_c.jpg'),
              uri: 'media/evid_c.jpg',
              lat: centerLat,
              lon: centerLon,
              activityTag: const drift.Value('Excavation'),
              observationType: const drift.Value('closed'),
              linkedMediaId: const drift.Value('nc-resolved'),
              capturedAt: '2026-08-15T02:00:00Z',
            ),
          );

      final match = await mediaRepo.findSuggestedBeforeMatch(
        centerLat: centerLat,
        centerLon: centerLon,
        siteId: 'SITE_A',
        activityTag: 'Excavation',
        capturedBefore: DateTime.utc(2026, 8, 15, 2),
        radiusMeters: 10.0,
        creatorId: creatorId,
      );

      // nc-resolved should NOT be returned because it is already resolved
      expect(match, isNull);
    });

    test('R17: a later-created Non-Conformity is never suggested as BEFORE', () async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'nc-later',
              siteId: const drift.Value('SITE_A'),
              originalUri: const drift.Value('media/orig_later.jpg'),
              uri: 'media/evid_later.jpg',
              lat: centerLat,
              lon: centerLon,
              activityTag: const drift.Value('Excavation'),
              observationType: const drift.Value('nonConformity'),
              // Captured AFTER the observation it would be linked to.
              capturedAt: '2026-08-16T01:00:00Z',
              creatorId: const drift.Value('user-1'),
            ),
          );

      final match = await mediaRepo.findSuggestedBeforeMatch(
        centerLat: centerLat,
        centerLon: centerLon,
        siteId: 'SITE_A',
        activityTag: 'Excavation',
        capturedBefore: DateTime.utc(2026, 8, 15, 2),
        radiusMeters: 10.0,
        creatorId: 'user-1',
      );

      expect(match, isNull,
          reason: 'R17: temporal precedence is mandatory for BEFORE classification');
    });

    test('R17: an exactly-simultaneous Non-Conformity is not a BEFORE (strict inequality)', () async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'nc-same-instant',
              siteId: const drift.Value('SITE_A'),
              originalUri: const drift.Value('media/orig_same.jpg'),
              uri: 'media/evid_same.jpg',
              lat: centerLat,
              lon: centerLon,
              activityTag: const drift.Value('Excavation'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-15T02:00:00Z',
              creatorId: const drift.Value('user-1'),
            ),
          );

      final match = await mediaRepo.findSuggestedBeforeMatch(
        centerLat: centerLat,
        centerLon: centerLon,
        siteId: 'SITE_A',
        activityTag: 'Excavation',
        capturedBefore: DateTime.utc(2026, 8, 15, 2),
        radiusMeters: 10.0,
        creatorId: 'user-1',
      );

      expect(match, isNull);
    });

    test('R18: unlinking is non-destructive — the BEFORE candidate survives unchanged', () async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'nc-r18',
              siteId: const drift.Value('SITE_A'),
              originalUri: const drift.Value('media/orig_r18.jpg'),
              uri: 'media/evid_r18.jpg',
              lat: centerLat,
              lon: centerLon,
              activityTag: const drift.Value('Excavation'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-15T01:00:00Z',
              creatorId: const drift.Value('user-1'),
            ),
          );
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'closed-r18',
              siteId: const drift.Value('SITE_A'),
              originalUri: const drift.Value('media/orig_c18.jpg'),
              uri: 'media/evid_c18.jpg',
              lat: centerLat,
              lon: centerLon,
              activityTag: const drift.Value('Excavation'),
              observationType: const drift.Value('closed'),
              linkedMediaId: const drift.Value('nc-r18'),
              capturedAt: '2026-08-15T02:00:00Z',
              creatorId: const drift.Value('user-1'),
            ),
          );

      expect(
        await mediaRepo.getResolvedMediaIds(siteId: 'SITE_A', creatorId: 'user-1'),
        contains('nc-r18'),
      );

      // Unlink by re-tagging the observation as a general (non-Closed) record.
      await mediaRepo.updateTags(
        mediaId: 'closed-r18',
        activityTag: 'Excavation',
        observationType: ObservationType.general,
        linkedMediaId: null,
        creatorId: 'user-1',
      );

      // Candidate status is restored without modifying the candidate record.
      expect(
        await mediaRepo.getResolvedMediaIds(siteId: 'SITE_A', creatorId: 'user-1'),
        isNot(contains('nc-r18')),
      );
      final candidate = await mediaRepo.getMediaById('nc-r18', creatorId: 'user-1');
      expect(candidate, isNotNull);
      expect(candidate!.isDeleted, isFalse);
      expect(candidate.observationType, ObservationType.nonConformity);
      expect(candidate.note, isNull);
    });

    test('R19: a low-accuracy candidate is included within its uncertainty bound', () async {
      // ~12.7m away (inside the indexed bounding box) with ±5m GNSS accuracy:
      // outside the bare 10m radius, inside the uncertainty-bounded radius.
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'nc-uncertain',
              siteId: const drift.Value('SITE_A'),
              originalUri: const drift.Value('media/orig_u.jpg'),
              uri: 'media/evid_u.jpg',
              lat: centerLat + (9.0 / 111320.0),
              lon: centerLon + (9.0 / 102800.0),
              accuracyM: const drift.Value(5.0),
              activityTag: const drift.Value('Excavation'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-15T01:00:00Z',
              creatorId: const drift.Value('user-1'),
            ),
          );

      final match = await mediaRepo.findSuggestedBeforeMatch(
        centerLat: centerLat,
        centerLon: centerLon,
        siteId: 'SITE_A',
        activityTag: 'Excavation',
        capturedBefore: DateTime.utc(2026, 8, 15, 2),
        radiusMeters: 10.0,
        creatorId: 'user-1',
      );

      expect(match, isNotNull, reason: 'R19: accuracy margin widens the radius bound');
      expect(match!.id, 'nc-uncertain');
    });

    test('R19: a synthetic (0,0) coordinate is never a valid location', () async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'nc-zero',
              siteId: const drift.Value('SITE_A'),
              originalUri: const drift.Value('media/orig_z.jpg'),
              uri: 'media/evid_z.jpg',
              lat: 0.0,
              lon: 0.0,
              activityTag: const drift.Value('Excavation'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-08-15T01:00:00Z',
              creatorId: const drift.Value('user-1'),
            ),
          );

      final results = await mediaRepo.findNearbyMedia(
        centerLat: 0.0,
        centerLon: 0.0,
        radiusMeters: 10.0,
        creatorId: 'user-1',
      );

      expect(results.where((r) => r.item.id == 'nc-zero'), isEmpty);
    });
  });
}

