import 'dart:ffi';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sitelens/core/utils/closed_evidence_integrity.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/domain/models/enums.dart';

void main() {
  setUpAll(() {
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  group('F3: ClosedEvidenceIntegrity Pure Logic Tests', () {
    test('1. Closed -> General clears link and Evid_ID from note', () {
      const initialNote = 'Evid_ID: before-item-123\nConcrete curing verified by inspector';
      final result = ClosedEvidenceIntegrity.enforceIntegrity(
        observationType: ObservationType.general,
        linkedMediaId: 'before-item-123',
        note: initialNote,
      );

      expect(result.linkedMediaId, isNull);
      expect(result.note, equals('Concrete curing verified by inspector'));
      expect(result.note!.contains('Evid_ID'), isFalse);
    });

    test('2. Explicit link removal clears both link and Evid_ID', () {
      const initialNote = 'Evid_ID: before-item-456\nBackfill compaction done';
      // When user dismisses link, linkedMediaId is null
      final result = ClosedEvidenceIntegrity.enforceIntegrity(
        observationType: ObservationType.closed,
        linkedMediaId: null,
        note: initialNote,
      );

      expect(result.linkedMediaId, isNull);
      expect(result.note, equals('Backfill compaction done'));
      expect(result.note!.contains('Evid_ID'), isFalse);
    });

    test('3. Closed -> Closed with valid link preserves both link and Evid_ID', () {
      const initialNote = 'Subbase inspection complete';
      final result = ClosedEvidenceIntegrity.enforceIntegrity(
        observationType: ObservationType.closed,
        linkedMediaId: 'before-item-789',
        note: initialNote,
      );

      expect(result.linkedMediaId, equals('before-item-789'));
      expect(result.note, equals('Evid_ID: before-item-789\nSubbase inspection complete'));
    });

    test('3b. Closed -> Closed with already-formatted Evid_ID does not duplicate', () {
      const initialNote = 'Evid_ID: before-item-789\nSubbase inspection complete';
      final result = ClosedEvidenceIntegrity.enforceIntegrity(
        observationType: ObservationType.closed,
        linkedMediaId: 'before-item-789',
        note: initialNote,
      );

      expect(result.linkedMediaId, equals('before-item-789'));
      expect(result.note, equals('Evid_ID: before-item-789\nSubbase inspection complete'));
      expect('Evid_ID'.allMatches(result.note!).length, equals(1));
    });

    test('removeAllEvidIdsFromNote strips multiple stale Evid_ID lines cleanly', () {
      const messyNote = 'Evid_ID: old-1\nEvid_ID: old-2\nActual inspector note\nSecond line';
      final cleaned = ClosedEvidenceIntegrity.removeAllEvidIdsFromNote(messyNote);
      expect(cleaned, equals('Actual inspector note\nSecond line'));
    });
  });

  group('F3: Repository Database updateTags & Persistence Invariant Tests', () {
    late AppDatabase db;
    late MediaRepository mediaRepo;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      mediaRepo = LocalMediaRepository(db);

      // Seed active site
      await db.into(db.sites).insert(
            SitesCompanion.insert(
              id: 'SITE_F3',
              siteCode: const drift.Value('F3_CODE'),
              name: const drift.Value('F3 Test Site'),
            ),
          );

      // Seed a Before photo and a Closed photo
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'before_photo_1',
              siteId: const drift.Value('SITE_F3'),
              type: const drift.Value('photo'),
              uri: 'media/evid_before.jpg',
              capturedAt: DateTime.utc(2026, 8, 1, 10, 0, 0).toIso8601String(),
              lat: 22.5,
              lon: 88.3,
              observationType: const drift.Value('issue'),
              synced: const drift.Value(0),
              creatorId: const drift.Value('user-1'),
            ),
          );

      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'closed_photo_1',
              siteId: const drift.Value('SITE_F3'),
              type: const drift.Value('photo'),
              uri: 'media/evid_closed.jpg',
              capturedAt: DateTime.utc(2026, 8, 2, 10, 0, 0).toIso8601String(),
              lat: 22.5,
              lon: 88.3,
              observationType: const drift.Value('closed'),
              linkedMediaId: const drift.Value('before_photo_1'),
              note: const drift.Value('Evid_ID: before_photo_1\nDefect resolved'),
              synced: const drift.Value(0),
              creatorId: const drift.Value('user-1'),
            ),
          );
    });

    tearDown(() async {
      await db.close();
    });

    test('4. Reload preserves the corrected state: changing Closed -> General in DB clears link and Evid_ID', () async {
      // Pre-check: closed_photo_1 has linkedMediaId and Evid_ID note
      final preCheck = await mediaRepo.getMediaById('closed_photo_1', creatorId: 'user-1');
      expect(preCheck, isNotNull);
      expect(preCheck!.observationType, equals(ObservationType.closed));
      expect(preCheck.linkedMediaId, equals('before_photo_1'));
      expect(preCheck.note, contains('Evid_ID: before_photo_1'));

      // Perform updateTags to General observation
      await mediaRepo.updateTags(
        mediaId: 'closed_photo_1',
        activityTag: 'General Inspection',
        observationType: ObservationType.general,
        note: 'Evid_ID: before_photo_1\nDefect resolved',
        creatorId: 'user-1',
      );

      // Reload from DB
      final reloaded = await mediaRepo.getMediaById('closed_photo_1', creatorId: 'user-1');
      expect(reloaded, isNotNull);
      expect(reloaded!.observationType, equals(ObservationType.general));
      // linkedMediaId MUST be cleared (null) in database
      expect(reloaded.linkedMediaId, isNull);
      // Evid_ID MUST be stripped from note
      expect(reloaded.note, equals('Defect resolved'));
      expect(reloaded.note!.contains('Evid_ID'), isFalse);
    });

    test('updateTags cannot leave an invalid Closed-only relationship when observation is non-Closed', () async {
      // Attempting to pass a linkedMediaId with a non-closed observation is strictly neutralized
      await mediaRepo.updateTags(
        mediaId: 'closed_photo_1',
        activityTag: 'Material Audit',
        observationType: ObservationType.material,
        note: 'Some note with Evid_ID: before_photo_1',
        linkedMediaId: 'before_photo_1',
        creatorId: 'user-1',
      );

      final reloaded = await mediaRepo.getMediaById('closed_photo_1', creatorId: 'user-1');
      expect(reloaded!.observationType, equals(ObservationType.material));
      expect(reloaded.linkedMediaId, isNull);
      expect(reloaded.note, equals('Some note with'));
    });

    test('linkMedia prohibits linking for non-Closed observation', () async {
      // Set to general first
      await mediaRepo.updateTags(
        mediaId: 'closed_photo_1',
        activityTag: 'General',
        observationType: ObservationType.general,
        note: 'Note',
        creatorId: 'user-1',
      );

      // Attempt to link
      await mediaRepo.linkMedia(
        mediaId: 'closed_photo_1',
        linkedMediaId: 'before_photo_1',
        creatorId: 'user-1',
      );

      final reloaded = await mediaRepo.getMediaById('closed_photo_1', creatorId: 'user-1');
      expect(reloaded!.linkedMediaId, isNull);
    });

    test('Closed -> Closed with valid link updates and preserves relationship on reload', () async {
      await mediaRepo.updateTags(
        mediaId: 'closed_photo_1',
        activityTag: 'Closure',
        observationType: ObservationType.closed,
        note: 'Re-inspection passed',
        linkedMediaId: 'before_photo_1',
        creatorId: 'user-1',
      );

      final reloaded = await mediaRepo.getMediaById('closed_photo_1', creatorId: 'user-1');
      expect(reloaded!.observationType, equals(ObservationType.closed));
      expect(reloaded.linkedMediaId, equals('before_photo_1'));
      expect(reloaded.note, equals('Evid_ID: before_photo_1\nRe-inspection passed'));
    });
  });
}
