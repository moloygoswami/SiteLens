import 'dart:ffi';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/repositories/media_repository.dart';

/// R26 — Deterministic Gallery Ordering.
///
/// The authoritative gallery order is `captured_at DESC, id ASC`. These tests
/// prove the ordering never depends on wall-clock time, query timing, map
/// iteration or database return order.
void main() {
  late AppDatabase db;
  late LocalMediaRepository repo;
  const uid = 'r26-user';
  const otherUid = 'r26-other-user';
  const gallerySite = 'site-r26';
  const otherSite = 'site-r26-b';

  setUpAll(() {
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = LocalMediaRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insert({
    required String id,
    required String capturedAt,
    String note = 'r26 note',
    String siteId = gallerySite,
    String creatorId = uid,
    int isDeleted = 0,
  }) async {
    await db.into(db.media).insert(
          MediaCompanion.insert(
            id: id,
            uri: 'file:///data/$id.jpg',
            lat: 22.5,
            lon: 88.3,
            capturedAt: capturedAt,
            siteId: drift.Value(siteId),
            creatorId: drift.Value(creatorId),
            note: drift.Value(note),
            isDeleted: drift.Value(isDeleted),
          ),
        );
  }

  List<String> ids(List<dynamic> items) => items.map((i) => i.id as String).toList();

  group('R26: Deterministic Gallery Ordering', () {
    test('1. authoritative ordering is captured_at DESC (newest first)', () async {
      await insert(id: 'a', capturedAt: '2026-08-15T10:00:00.000Z');
      await insert(id: 'c', capturedAt: '2026-08-15T12:00:00.000Z');
      await insert(id: 'b', capturedAt: '2026-08-15T11:00:00.000Z');

      final items = await repo.watchAllMedia(creatorId: uid).first;
      expect(ids(items), equals(['c', 'b', 'a']));
    });

    test('2. identical captured_at values use a deterministic id ASC tie-break', () async {
      const ts = '2026-08-15T10:00:00.000Z';
      await insert(id: 'tie-c', capturedAt: ts);
      await insert(id: 'tie-a', capturedAt: ts);
      await insert(id: 'tie-b', capturedAt: ts);

      final gallery = await repo.watchAllMedia(creatorId: uid).first;
      expect(ids(gallery), equals(['tie-a', 'tie-b', 'tie-c']));

      final searched = await repo.searchMedia(query: 'r26', creatorId: uid);
      expect(ids(searched), equals(['tie-a', 'tie-b', 'tie-c']));
    });

    test('3. malformed captured_at values order deterministically (never DateTime.now())', () async {
      await insert(id: 'good', capturedAt: '2026-08-15T10:00:00.000Z');
      await insert(id: 'bad-z', capturedAt: 'zzz-not-a-timestamp');
      await insert(id: 'bad-n', capturedAt: 'nope');

      final first = await repo.watchAllMedia(creatorId: uid).first;
      final second = await repo.watchAllMedia(creatorId: uid).first;

      // Deterministic across repeated queries.
      expect(ids(first), equals(ids(second)));

      // Deterministic across the two independent implementations (stream vs search).
      final searched = await repo.searchMedia(query: 'r26', creatorId: uid);
      expect(ids(searched), equals(ids(first)));

      // The parsed model fallback is a fixed sentinel (epoch), never the clock.
      final bad = first.firstWhere((i) => i.id == 'bad-n');
      expect(bad.capturedAt.millisecondsSinceEpoch, equals(0));
    });

    test('4. repeated identical queries return identical ordering', () async {
      const ts = '2026-08-15T10:00:00.000Z';
      await insert(id: 'r26-x', capturedAt: ts);
      await insert(id: 'r26-y', capturedAt: ts);
      await insert(id: 'r26-z', capturedAt: '2026-08-16T09:30:00.000Z');

      final search1 = ids(await repo.searchMedia(query: 'r26', creatorId: uid));
      final search2 = ids(await repo.searchMedia(query: 'r26', creatorId: uid));
      final watch1 = ids(await repo.watchAllMedia(creatorId: uid).first);
      final watch2 = ids(await repo.watchAllMedia(creatorId: uid).first);

      expect(search1, equals(search2));
      expect(watch1, equals(watch2));
      expect(search1, equals(watch1));
    });

    test('5. existing gallery filters and creator scoping are preserved', () async {
      await insert(id: 'keep-site-a', capturedAt: '2026-08-15T10:00:00.000Z', siteId: gallerySite);
      await insert(id: 'other-site', capturedAt: '2026-08-15T11:00:00.000Z', siteId: otherSite);
      await insert(id: 'no-match', capturedAt: '2026-08-15T09:00:00.000Z', note: 'unrelated');
      await insert(id: 'foreign-owner', capturedAt: '2026-08-15T12:00:00.000Z', creatorId: otherUid);
      await insert(id: 'soft-deleted', capturedAt: '2026-08-15T13:00:00.000Z', isDeleted: 1);

      // watchAllMedia: creator-scoped, soft-deletes excluded, captured_at DESC.
      final all = ids(await repo.watchAllMedia(creatorId: uid).first);
      expect(all, equals(['other-site', 'keep-site-a', 'no-match']));

      // Site filter honoured.
      final bySite = ids(await repo.watchAllMedia(siteId: gallerySite, creatorId: uid).first);
      expect(bySite, equals(['keep-site-a', 'no-match']));

      // searchMedia: same authoritative order, creator-scoped, note-match only.
      final searched = ids(await repo.searchMedia(query: 'r26', creatorId: uid));
      expect(searched, equals(['other-site', 'keep-site-a']));

      final searchedBySite = ids(await repo.searchMedia(query: 'r26', siteId: gallerySite, creatorId: uid));
      expect(searchedBySite, equals(['keep-site-a']));

      // Fail-closed creator isolation is unchanged.
      expect(await repo.watchAllMedia(creatorId: null).first, isEmpty);
      expect(await repo.searchMedia(query: 'r26', creatorId: ''), isEmpty);
    });
  });
}
