import 'dart:ffi';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/core/utils/haversine.dart';

void main() {
  late AppDatabase db;

  setUpAll(() {
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  setUp(() {
    // In-memory sqlite database for fast, isolated unit testing
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Drift AppDatabase Tests', () {
    test('Can insert and retrieve site', () async {
      await db.into(db.sites).insert(
            SitesCompanion.insert(
              id: 'site-101',
              siteCode: const drift.Value('SITE-101'),
              name: const drift.Value('Metro Station Line 3'),
              address: const drift.Value('Park Street, Kolkata'),
            ),
          );

      final sites = await db.select(db.sites).get();
      expect(sites.length, equals(1));
      expect(sites.first.id, equals('site-101'));
      expect(sites.first.name, equals('Metro Station Line 3'));
    });

    test('Can insert media and perform bounding box query', () async {
      await db.into(db.sites).insert(
            SitesCompanion.insert(
              id: 'site-101',
              siteCode: const drift.Value('SITE-101'),
              name: const drift.Value('Metro Station Line 3'),
              address: const drift.Value('Park Street, Kolkata'),
            ),
          );

      // Target center point
      const centerLat = 22.5726;
      const centerLon = 88.3639;

      // Item 1: Nearby (~10m away)
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'media-1',
              siteId: const drift.Value('site-101'),
              uri: '/data/user/0/com.sitelens/app_flutter/media/photo_1.jpg',
              lat: 22.57268,
              lon: 88.36392,
              type: const drift.Value('photo'),
              activityTag: const drift.Value('PCC'),
              observationType: const drift.Value('non-conformity'),
              capturedAt: '2026-08-14T10:00:00Z',
              sha256Hash: const drift.Value('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'),
            ),
          );

      // Item 2: Far away (~5 km away)
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'media-2',
              siteId: const drift.Value('site-101'),
              uri: '/data/user/0/com.sitelens/app_flutter/media/photo_2.jpg',
              lat: 22.6100,
              lon: 88.4000,
              type: const drift.Value('photo'),
              activityTag: const drift.Value('PCC'),
              observationType: const drift.Value('non-conformity'),
              capturedAt: '2026-08-14T10:30:00Z',
            ),
          );

      // Search within 25m
      final bbox = SpatialMathUtils.calculateBoundingBox(centerLat, centerLon, 25.0);

      final candidateQuery = db.select(db.media)
        ..where(
          (tbl) =>
              tbl.isDeleted.equals(0) &
              tbl.lat.isBiggerOrEqualValue(bbox.minLat) &
              tbl.lat.isSmallerOrEqualValue(bbox.maxLat) &
              tbl.lon.isBiggerOrEqualValue(bbox.minLon) &
              tbl.lon.isSmallerOrEqualValue(bbox.maxLon),
        );

      final candidates = await candidateQuery.get();
      expect(candidates.length, equals(1));
      expect(candidates.first.id, equals('media-1'));
    });

    test('Soft delete excludes items from standard queries', () async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'media-del',
              uri: '/path/to/test.jpg',
              lat: 22.5726,
              lon: 88.3639,
              capturedAt: '2026-08-14T12:00:00Z',
              isDeleted: const drift.Value(1),
            ),
          );

      final activeMedia = await (db.select(db.media)..where((tbl) => tbl.isDeleted.equals(0))).get();
      expect(activeMedia.isEmpty, isTrue);

      final allMedia = await db.select(db.media).get();
      expect(allMedia.length, equals(1));
    });

    test('Can insert, update and query GooglePhotosSyncEntries', () async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'media-gp-1',
              uri: '/path/to/evidence.jpg',
              lat: 22.5726,
              lon: 88.3639,
              capturedAt: '2026-08-20T12:00:00Z',
              evidenceSha256Hash: const drift.Value('evid_sha_256_mock'),
            ),
          );

      await db.into(db.googlePhotosSyncEntries).insert(
            GooglePhotosSyncEntriesCompanion.insert(
              mediaId: 'media-gp-1',
              status: const drift.Value('pending'),
              creatorId: const drift.Value('test-user-1'),
            ),
          );

      var entries = await db.select(db.googlePhotosSyncEntries).get();
      expect(entries.length, equals(1));
      expect(entries.first.mediaId, equals('media-gp-1'));
      expect(entries.first.status, equals('pending'));
      expect(entries.first.creatorId, equals('test-user-1'));

      // Update to uploaded
      await (db.update(db.googlePhotosSyncEntries)
            ..where((tbl) => tbl.mediaId.equals('media-gp-1')))
          .write(
        const GooglePhotosSyncEntriesCompanion(
          status: drift.Value('uploaded'),
          googlePhotosMediaId: drift.Value('gp_item_999'),
        ),
      );

      entries = await db.select(db.googlePhotosSyncEntries).get();
      expect(entries.first.status, equals('uploaded'));
      expect(entries.first.googlePhotosMediaId, equals('gp_item_999'));
      expect(entries.first.creatorId, equals('test-user-1'));
    });
  });
}
