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
            ),
          );

      final match = await mediaRepo.findSuggestedBeforeMatch(
        centerLat: centerLat,
        centerLon: centerLon,
        siteId: 'SITE_A',
        activityTag: 'Excavation',
        radiusMeters: 10.0,
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
            ),
          );

      final match = await mediaRepo.findSuggestedBeforeMatch(
        centerLat: centerLat,
        centerLon: centerLon,
        siteId: 'SITE_A',
        activityTag: 'Excavation',
        radiusMeters: 10.0,
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
            ),
          );

      final match = await mediaRepo.findSuggestedBeforeMatch(
        centerLat: centerLat,
        centerLon: centerLon,
        siteId: 'SITE_A',
        activityTag: 'Excavation',
        radiusMeters: 10.0,
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
            ),
          );

      final match = await mediaRepo.findSuggestedBeforeMatch(
        centerLat: centerLat,
        centerLon: centerLon,
        siteId: 'SITE_A',
        activityTag: 'Excavation',
        radiusMeters: 10.0,
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
            ),
          );

      final match = await mediaRepo.findSuggestedBeforeMatch(
        centerLat: centerLat,
        centerLon: centerLon,
        siteId: 'SITE_A',
        activityTag: 'Excavation',
        radiusMeters: 10.0,
        currentMediaId: 'current-item',
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
            ),
          );

      final match = await mediaRepo.findSuggestedBeforeMatch(
        centerLat: centerLat,
        centerLon: centerLon,
        siteId: 'SITE_A',
        activityTag: '', // Blank activity
        radiusMeters: 10.0,
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
            ),
          );

      final match = await mediaRepo.findSuggestedBeforeMatch(
        centerLat: centerLat,
        centerLon: centerLon,
        siteId: 'SITE_A',
        activityTag: 'Excavation',
        radiusMeters: 10.0,
      );

      expect(match, isNotNull);
      expect(match!.id, 'nc-2m'); // Closest candidate selected
    });

    test('Rejects Non-Conformity candidates that are already resolved/closed', () async {
      // 1. Insert open Non-Conformity (0m away)
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'nc-resolved',
              siteId: const drift.Value('SITE_A'),
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
        radiusMeters: 10.0,
      );

      // nc-resolved should NOT be returned because it is already resolved
      expect(match, isNull);
    });
  });
}

