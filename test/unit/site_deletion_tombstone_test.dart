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

      expect(await siteRepo.hasMediaForSite(testSiteId, creatorId: testUserId), isTrue);

      expect(
        () => siteRepo.deleteSite(testSiteId, creatorId: testUserId),
        throwsA(isA<SiteReferencedByMediaException>()),
      );

      // Verify site was not deleted
      final site = await siteRepo.getSiteById(testSiteId, creatorId: testUserId);
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

      expect(await siteRepo.hasMediaForSite(testSiteId, creatorId: testUserId), isTrue);

      expect(
        () => siteRepo.deleteSite(testSiteId, creatorId: testUserId),
        throwsA(isA<SiteReferencedByMediaException>()),
      );

      final site = await siteRepo.getSiteById(testSiteId, creatorId: testUserId);
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

      expect(await siteRepo.hasMediaForSite(testSiteId, creatorId: testUserId), isTrue);

      expect(
        () => siteRepo.deleteSite(testSiteId, creatorId: testUserId),
        throwsA(isA<SiteReferencedByMediaException>()),
      );

      final site = await siteRepo.getSiteById(testSiteId, creatorId: testUserId);
      expect(site, isNotNull);
    });

    test('Unreconciled never-published tombstone (synced=0, tombstoneReconciled=0) is retained and blocks site deletion', () async {
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
          tombstoneReconciled: const Value(0), // not yet settled by the no-op
        ),
      );

      // R24: an unreconciled tombstone is retained — deletion is blocked.
      expect(await siteRepo.hasMediaForSite(testSiteId, creatorId: testUserId), isTrue);

      expect(
        () => siteRepo.deleteSite(testSiteId, creatorId: testUserId),
        throwsA(isA<SiteReferencedByMediaException>()),
      );

      // Both the site and the tombstone are retained.
      expect(await siteRepo.getSiteById(testSiteId, creatorId: testUserId), isNotNull);
      final media = await (db.select(db.media)..where((tbl) => tbl.siteId.equals(testSiteId))).get();
      expect(media.single.id, equals('media-never-published'));
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

      expect(await siteRepo.hasMediaForSite(testSiteId, creatorId: testUserId), isFalse);

      await siteRepo.deleteSite(testSiteId, creatorId: testUserId);

      final site = await siteRepo.getSiteById(testSiteId, creatorId: testUserId);
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
          tombstoneReconciled: const Value(1), // reconciled so both rows are purge-eligible
        ),
      );

      expect(await siteRepo.hasMediaForSite(testSiteId, creatorId: testUserId), isFalse);

      // Atomically delete site and eligible tombstones under foreign_keys = ON
      await siteRepo.deleteSite(testSiteId, creatorId: testUserId);

      expect(await siteRepo.getSiteById(testSiteId, creatorId: testUserId), isNull);
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
      expect(await siteRepo.hasMediaForSite(testSiteId, creatorId: testUserId), isTrue);
      expect(
        () => siteRepo.deleteSite(testSiteId, creatorId: testUserId),
        throwsA(isA<SiteReferencedByMediaException>()),
      );

      // 2. User deletes photo (soft delete / tombstone)
      await mediaRepo.softDeleteMedia('photo-lifecycle');

      // Tombstone is published (synced=1) and not reconciled (tombstoneReconciled=0) -> BLOCKS deletion
      expect(await siteRepo.hasMediaForSite(testSiteId, creatorId: testUserId), isTrue);
      expect(
        () => siteRepo.deleteSite(testSiteId, creatorId: testUserId),
        throwsA(isA<SiteReferencedByMediaException>()),
      );

      // 3. Cloud tombstone sync completes successfully
      await mediaRepo.markTombstoneReconciled('photo-lifecycle');

      // Now reconciled -> ALLOWS deletion
      expect(await siteRepo.hasMediaForSite(testSiteId, creatorId: testUserId), isFalse);

      // 4. Delete site
      await siteRepo.deleteSite(testSiteId, creatorId: testUserId);

      expect(await siteRepo.getSiteById(testSiteId, creatorId: testUserId), isNull);
      final remaining = await (db.select(db.media)..where((tbl) => tbl.siteId.equals(testSiteId))).get();
      expect(remaining, isEmpty);
    });
  });

  group('R24: Tombstone Retention & Purge Eligibility', () {
    Future<void> insertTombstone({
      required String id,
      required int synced,
      required int reconciled,
      String creatorId = testUserId,
    }) async {
      await db.into(db.media).insert(
        MediaCompanion.insert(
          id: id,
          uri: 'file:///data/$id.jpg',
          lat: 22.57,
          lon: 88.36,
          capturedAt: DateTime.now().toUtc().toIso8601String(),
          siteId: const Value(testSiteId),
          creatorId: Value(creatorId),
          isDeleted: const Value(1),
          synced: Value(synced),
          tombstoneReconciled: Value(reconciled),
        ),
      );
    }

    test('1. reconciled + eligible -> purged with the site', () async {
      await insertTombstone(id: 'r24-eligible', synced: 1, reconciled: 1);

      expect(await siteRepo.hasMediaForSite(testSiteId, creatorId: testUserId), isFalse);

      await siteRepo.deleteSite(testSiteId, creatorId: testUserId);

      expect(await siteRepo.getSiteById(testSiteId, creatorId: testUserId), isNull);
      expect(await (db.select(db.media)..where((t) => t.siteId.equals(testSiteId))).get(), isEmpty);
    });

    test('2. reconciled + not yet eligible (unreconciled sibling) -> retained', () async {
      await insertTombstone(id: 'r24-reconciled-sibling', synced: 1, reconciled: 1);
      await insertTombstone(id: 'r24-pending-sibling', synced: 1, reconciled: 0);

      // The site is not purge-eligible while any tombstone is unreconciled.
      expect(await siteRepo.hasMediaForSite(testSiteId, creatorId: testUserId), isTrue);
      expect(
        () => siteRepo.deleteSite(testSiteId, creatorId: testUserId),
        throwsA(isA<SiteReferencedByMediaException>()),
      );

      // Nothing is purged — the reconciled tombstone is retained too.
      final rows = await (db.select(db.media)..where((t) => t.siteId.equals(testSiteId))).get();
      expect(rows.map((r) => r.id).toSet(), equals({'r24-reconciled-sibling', 'r24-pending-sibling'}));
    });

    test('3. pending (published, unreconciled) -> retained', () async {
      await insertTombstone(id: 'r24-pending', synced: 1, reconciled: 0);

      expect(await siteRepo.hasMediaForSite(testSiteId, creatorId: testUserId), isTrue);
      expect(
        () => siteRepo.deleteSite(testSiteId, creatorId: testUserId),
        throwsA(isA<SiteReferencedByMediaException>()),
      );

      final rows = await (db.select(db.media)..where((t) => t.siteId.equals(testSiteId))).get();
      expect(rows.single.id, equals('r24-pending'));
    });

    test('4. failed/unresolved -> retained', () async {
      await insertTombstone(id: 'r24-failed', synced: 3, reconciled: 0);

      expect(await siteRepo.hasMediaForSite(testSiteId, creatorId: testUserId), isTrue);
      expect(
        () => siteRepo.deleteSite(testSiteId, creatorId: testUserId),
        throwsA(isA<SiteReferencedByMediaException>()),
      );

      final rows = await (db.select(db.media)..where((t) => t.siteId.equals(testSiteId))).get();
      expect(rows.single.id, equals('r24-failed'));
    });

    test('5. wrong creator -> inaccessible and never purged (fail-closed)', () async {
      await insertTombstone(id: 'r24-foreign', synced: 1, reconciled: 1, creatorId: 'other-user');

      // The site is not purge-eligible while it holds a non-creator-owned row.
      expect(await siteRepo.hasMediaForSite(testSiteId, creatorId: testUserId), isTrue);
      expect(
        () => siteRepo.deleteSite(testSiteId, creatorId: testUserId),
        throwsA(isA<SiteReferencedByMediaException>()),
      );

      // The foreign row is retained (never purged by this creator).
      final rows = await (db.select(db.media)..where((t) => t.siteId.equals(testSiteId))).get();
      expect(rows.single.id, equals('r24-foreign'));

      // Fail-closed for an unscoped caller.
      expect(await siteRepo.hasMediaForSite(testSiteId), isTrue);

      // Another creator cannot delete this site at all (creator-scoped).
      await siteRepo.deleteSite(testSiteId, creatorId: 'other-user');
      expect(await siteRepo.getSiteById(testSiteId, creatorId: testUserId), isNotNull);
    });

    test('6. never-published tombstone -> retained until reconciled, purged once reconciled', () async {
      await insertTombstone(id: 'r24-never-published', synced: 0, reconciled: 0);

      // Unreconciled: retained (not purge-eligible).
      expect(await siteRepo.hasMediaForSite(testSiteId, creatorId: testUserId), isTrue);
      expect(
        () => siteRepo.deleteSite(testSiteId, creatorId: testUserId),
        throwsA(isA<SiteReferencedByMediaException>()),
      );

      // The existing never-published verification no-op settles it locally.
      await mediaRepo.markTombstoneReconciled('r24-never-published');

      expect(await siteRepo.hasMediaForSite(testSiteId, creatorId: testUserId), isFalse);
      await siteRepo.deleteSite(testSiteId, creatorId: testUserId);

      expect(await siteRepo.getSiteById(testSiteId, creatorId: testUserId), isNull);
      expect(await (db.select(db.media)..where((t) => t.siteId.equals(testSiteId))).get(), isEmpty);
    });

    test('7. purge is deterministic and idempotent', () async {
      await insertTombstone(id: 'r24-p1', synced: 1, reconciled: 1);
      await insertTombstone(id: 'r24-p2', synced: 0, reconciled: 1);

      await siteRepo.deleteSite(testSiteId, creatorId: testUserId);

      // Re-running the purge after the site is gone is a safe no-op.
      await siteRepo.deleteSite(testSiteId, creatorId: testUserId);

      expect(await siteRepo.getSiteById(testSiteId, creatorId: testUserId), isNull);
      expect(await (db.select(db.media)..where((t) => t.siteId.equals(testSiteId))).get(), isEmpty);
    });
  });
}
