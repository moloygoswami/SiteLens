import 'dart:ffi';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/data/repositories/site_repository.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/domain/models/site_model.dart';

void main() {
  late AppDatabase db;
  late LocalSiteRepository siteRepo;
  late LocalMediaRepository mediaRepo;
  const testUserId = 'test-user-del-001';
  const testSiteId = 'test-site-001';

  setUpAll(() {
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  setUp(() async {
    // Explicitly enforce SQLite foreign key constraints to ensure no FK violations occur
    db = AppDatabase(NativeDatabase.memory(setup: (rawDb) {
      rawDb.execute('PRAGMA foreign_keys = ON;');
    }));
    siteRepo = LocalSiteRepository(db);
    mediaRepo = LocalMediaRepository(db);

    await siteRepo.saveSite(const SiteModel(
      id: testSiteId,
      siteCode: 'SITE-001',
      name: 'Test Site for Deletion',
      address: 'Test Address',
      creatorId: testUserId,
    ));
  });

  tearDown(() async {
    await db.close();
  });

  group('Site Deletion & Tombstone Status Tests', () {
    test('Active media blocks site deletion', () async {
      await db.into(db.media).insert(
        MediaCompanion.insert(
          id: 'media-active',
          uri: 'file:///data/active.jpg',
          lat: 22.57,
          lon: 88.36,
          capturedAt: DateTime.now().toUtc().toIso8601String(),
          siteId: const Value(testSiteId),
          creatorId: const Value(testUserId),
          isDeleted: const Value(0),
          synced: const Value(0),
          tombstoneReconciled: const Value(0),
        ),
      );

      expect(await siteRepo.hasMediaForSite(testSiteId), isTrue);

      expect(
        () => siteRepo.deleteSite(testSiteId, creatorId: testUserId),
        throwsA(isA<SiteReferencedByMediaException>()),
      );

      // Verify site was not deleted
      final site = await siteRepo.getSiteById(testSiteId);
      expect(site, isNotNull);
    });

    test('Pending published tombstone (synced=1, tombstoneReconciled=0) blocks site deletion', () async {
      await db.into(db.media).insert(
        MediaCompanion.insert(
          id: 'media-pending-tombstone',
          uri: 'file:///data/pending_tombstone.jpg',
          lat: 22.57,
          lon: 88.36,
          capturedAt: DateTime.now().toUtc().toIso8601String(),
          siteId: const Value(testSiteId),
          creatorId: const Value(testUserId),
          isDeleted: const Value(1),
          synced: const Value(1), // published
          tombstoneReconciled: const Value(0), // sync still pending
        ),
      );

      expect(await siteRepo.hasMediaForSite(testSiteId), isTrue);

      expect(
        () => siteRepo.deleteSite(testSiteId, creatorId: testUserId),
        throwsA(isA<SiteReferencedByMediaException>()),
      );

      final site = await siteRepo.getSiteById(testSiteId);
      expect(site, isNotNull);
    });

    test('Pending failed tombstone (synced=3, tombstoneReconciled=0) blocks site deletion', () async {
      await db.into(db.media).insert(
        MediaCompanion.insert(
          id: 'media-failed-tombstone',
          uri: 'file:///data/failed_tombstone.jpg',
          lat: 22.57,
          lon: 88.36,
          capturedAt: DateTime.now().toUtc().toIso8601String(),
          siteId: const Value(testSiteId),
          creatorId: const Value(testUserId),
          isDeleted: const Value(1),
          synced: const Value(3), // partially published / failed sync
          tombstoneReconciled: const Value(0), // sync still pending
        ),
      );

      expect(await siteRepo.hasMediaForSite(testSiteId), isTrue);

      expect(
        () => siteRepo.deleteSite(testSiteId, creatorId: testUserId),
        throwsA(isA<SiteReferencedByMediaException>()),
      );

      final site = await siteRepo.getSiteById(testSiteId);
      expect(site, isNotNull);
    });

    test('Never-published tombstone (synced=0) allows site deletion', () async {
      await db.into(db.media).insert(
        MediaCompanion.insert(
          id: 'media-never-published',
          uri: 'file:///data/never_published.jpg',
          lat: 22.57,
          lon: 88.36,
          capturedAt: DateTime.now().toUtc().toIso8601String(),
          siteId: const Value(testSiteId),
          creatorId: const Value(testUserId),
          isDeleted: const Value(1),
          synced: const Value(0), // never published
          tombstoneReconciled: const Value(0),
        ),
      );

      // Has media check must be false
      expect(await siteRepo.hasMediaForSite(testSiteId), isFalse);

      // Delete site succeeds cleanly
      await siteRepo.deleteSite(testSiteId, creatorId: testUserId);

      // Site is deleted
      final site = await siteRepo.getSiteById(testSiteId);
      expect(site, isNull);

      // Tombstone is atomically removed
      final media = await (db.select(db.media)..where((tbl) => tbl.siteId.equals(testSiteId))).get();
      expect(media, isEmpty);
    });

    test('Fully reconciled tombstone (synced=1, tombstoneReconciled=1) allows site deletion', () async {
      await db.into(db.media).insert(
        MediaCompanion.insert(
          id: 'media-reconciled',
          uri: 'file:///data/reconciled.jpg',
          lat: 22.57,
          lon: 88.36,
          capturedAt: DateTime.now().toUtc().toIso8601String(),
          siteId: const Value(testSiteId),
          creatorId: const Value(testUserId),
          isDeleted: const Value(1),
          synced: const Value(1),
          tombstoneReconciled: const Value(1), // reconciled
        ),
      );

      expect(await siteRepo.hasMediaForSite(testSiteId), isFalse);

      await siteRepo.deleteSite(testSiteId, creatorId: testUserId);

      final site = await siteRepo.getSiteById(testSiteId);
      expect(site, isNull);

      final media = await (db.select(db.media)..where((tbl) => tbl.siteId.equals(testSiteId))).get();
      expect(media, isEmpty);
    });

    test('No SQLite FK violation with linked tombstones on atomic deletion', () async {
      // Create parent tombstone
      await db.into(db.media).insert(
        MediaCompanion.insert(
          id: 'parent-tombstone',
          uri: 'file:///data/parent.jpg',
          lat: 22.57,
          lon: 88.36,
          capturedAt: DateTime.now().toUtc().toIso8601String(),
          siteId: const Value(testSiteId),
          creatorId: const Value(testUserId),
          isDeleted: const Value(1),
          synced: const Value(1),
          tombstoneReconciled: const Value(1),
        ),
      );

      // Create child tombstone referencing parent-tombstone via linked_media_id FK
      await db.into(db.media).insert(
        MediaCompanion.insert(
          id: 'child-tombstone',
          uri: 'file:///data/child.jpg',
          lat: 22.57,
          lon: 88.36,
          capturedAt: DateTime.now().toUtc().toIso8601String(),
          siteId: const Value(testSiteId),
          creatorId: const Value(testUserId),
          linkedMediaId: const Value('parent-tombstone'),
          isDeleted: const Value(1),
          synced: const Value(0),
          tombstoneReconciled: const Value(0),
        ),
      );

      expect(await siteRepo.hasMediaForSite(testSiteId), isFalse);

      // Atomically delete site and eligible tombstones under foreign_keys = ON
      await siteRepo.deleteSite(testSiteId, creatorId: testUserId);

      expect(await siteRepo.getSiteById(testSiteId), isNull);
      final remaining = await (db.select(db.media)..where((tbl) => tbl.siteId.equals(testSiteId))).get();
      expect(remaining, isEmpty);
    });

    test('Full lifecycle: media deletion -> pending blocks site deletion -> mark reconciled -> allows deletion', () async {
      // 1. User captures photo (active, published)
      await mediaRepo.insertMedia(MediaItem(
        id: 'photo-lifecycle',
        siteId: testSiteId,
        originalUri: 'media/orig_life.jpg',
        uri: 'media/evid_life.jpg',
        type: MediaItemType.photo,
        lat: 22.57,
        lon: 88.36,
        capturedAt: DateTime.now(),
        creatorId: testUserId,
        syncStatus: SyncStatusType.synced,
        isDeleted: false,
        tombstoneReconciled: false,
      ));

      // Active media blocks site deletion
      expect(await siteRepo.hasMediaForSite(testSiteId), isTrue);
      expect(
        () => siteRepo.deleteSite(testSiteId, creatorId: testUserId),
        throwsA(isA<SiteReferencedByMediaException>()),
      );

      // 2. User deletes photo (soft delete / tombstone)
      await mediaRepo.softDeleteMedia('photo-lifecycle');

      // Tombstone is published (synced=1) and not reconciled (tombstoneReconciled=0) -> BLOCKS deletion
      expect(await siteRepo.hasMediaForSite(testSiteId), isTrue);
      expect(
        () => siteRepo.deleteSite(testSiteId, creatorId: testUserId),
        throwsA(isA<SiteReferencedByMediaException>()),
      );

      // 3. Cloud tombstone sync completes successfully
      await mediaRepo.markTombstoneReconciled('photo-lifecycle');

      // Now reconciled -> ALLOWS deletion
      expect(await siteRepo.hasMediaForSite(testSiteId), isFalse);

      // 4. Delete site
      await siteRepo.deleteSite(testSiteId, creatorId: testUserId);

      expect(await siteRepo.getSiteById(testSiteId), isNull);
      final remaining = await (db.select(db.media)..where((tbl) => tbl.siteId.equals(testSiteId))).get();
      expect(remaining, isEmpty);
    });
  });
}
