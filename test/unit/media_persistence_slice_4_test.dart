import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sqlite3/open.dart';

import 'package:sitelens/core/utils/crypto_utils.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/features/camera/models/camera_ui_state.dart';
import 'package:sitelens/features/camera/models/evidence_metadata_snapshot.dart';
import 'package:sitelens/features/camera/models/processed_evidence_payload.dart';
import 'package:sitelens/features/camera/services/evidence_processing_service.dart';
import 'package:sitelens/features/camera/services/evidence_storage_service.dart';
import 'package:sitelens/features/camera/services/media_persistence_coordinator.dart';
import 'package:sitelens/features/review/controllers/review_tag_controller.dart';
import 'package:sitelens/features/review/models/pending_capture_payload.dart';

class TestEvidenceStorageService extends EvidenceStorageService {
  final Directory testBaseDir;
  TestEvidenceStorageService(this.testBaseDir);

  @override
  Future<Directory> getBaseDirectory() async => testBaseDir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    open.overrideFor(OperatingSystem.linux, () {
      try {
        return DynamicLibrary.open('libsqlite3.so.0');
      } catch (_) {
        return DynamicLibrary.open('libsqlite3.so');
      }
    });
  });

  group('Slice 4: TM-U-09 / AC-HUD-06 / AC-HUD-08 — Isolate Input & Single-HUD Invariant', () {
    test('EvidenceIsolateInput contains strictly the 3 permitted fields and is pure Dart', () {
      final orig = Uint8List.fromList([1, 2, 3]);
      final hud = Uint8List.fromList([4, 5, 6]);
      const aspect = CameraAspectRatio.ratio4_3;

      final input = EvidenceIsolateInput(
        originalBytes: orig,
        hudPngBytes: hud,
        targetAspectRatio: aspect,
      );

      expect(input.originalBytes, equals(orig));
      expect(input.hudPngBytes, equals(hud));
      expect(input.targetAspectRatio, equals(aspect));
    });

    test('EvidenceProcessingService produces burned canonical evidence without UI dependencies', () async {
      final tempDir = Directory.systemTemp.createTempSync('sitelens_slice4_hud_');
      final storage = TestEvidenceStorageService(tempDir);
      final service = EvidenceProcessingService(storage);

      // Create a test 100x100 base JPEG
      final baseImg = img.Image(width: 100, height: 100);
      img.fill(baseImg, color: img.ColorRgb8(200, 200, 200));
      final baseJpeg = Uint8List.fromList(img.encodeJpg(baseImg));

      final snapshot = EvidenceMetadataSnapshot(
        mediaId: 'media_test_hud_01',
        siteId: 'SITE_001',
        siteCode: 'BLDG-A',
        siteName: 'Main Facility',
        creatorId: 'user_inspect_01',
        capturedAtUtc: DateTime.utc(2026, 3, 10, 12, 0, 0),
        canonicalTimestampUtc: '2026-03-10 12:00:00 UTC',
        latitude: 37.7749,
        longitude: -122.4194,
        accuracyMeters: 2.5,
        lowAccuracy: false,
        resolvedAddress: '100 Main St, City',
      );

      final payload = await service.processCapture(
        originalBytes: baseJpeg,
        snapshot: snapshot,
      );

      expect(payload.isSuccess, isTrue);
      expect(payload.mediaId, equals('media_test_hud_01'));
      expect(payload.originalFilePath, equals('media/orig_media_test_hud_01.jpg'));
      expect(payload.evidenceFilePath, equals('media/evid_media_test_hud_01.jpg'));
      expect(payload.thumbnailFilePath, equals('media/thumb_media_test_hud_01.jpg'));
      expect(payload.evidenceSha256, isNotNull);
      expect(payload.originalSha256, isNotEmpty);
      expect(payload.evidenceSha256, isNot(equals(payload.originalSha256)));

      tempDir.deleteSync(recursive: true);
    });
  });

  group('Slice 4: TM-U-10 / AC-EVID-04 / AC-EVID-05 — EXIF Stripping & Null Telemetry Preservation', () {
    test('EXIF metadata is stripped from canonical evidence and thumbnail artifacts', () async {
      final tempDir = Directory.systemTemp.createTempSync('sitelens_slice4_exif_');
      final storage = TestEvidenceStorageService(tempDir);
      final service = EvidenceProcessingService(storage);

      // Create an image with synthetic EXIF tag
      final testImg = img.Image(width: 80, height: 80);
      img.fill(testImg, color: img.ColorRgb8(120, 150, 180));
      testImg.exif.imageIfd['Make'] = 'Pixel';
      testImg.exif.imageIfd['Model'] = 'Pixel 9 Pro';
      testImg.exif.imageIfd['Software'] = 'CameraApp 1.0';
      final rawJpegWithExif = Uint8List.fromList(img.encodeJpg(testImg));

      final snapshot = EvidenceMetadataSnapshot(
        mediaId: 'media_test_exif_01',
        siteId: 'SITE_001',
        siteCode: 'BLDG-A',
        siteName: 'Main Facility',
        creatorId: 'user_inspect_01',
        capturedAtUtc: DateTime.utc(2026, 3, 10, 12, 0, 0),
        canonicalTimestampUtc: '2026-03-10 12:00:00 UTC',
        latitude: 37.7749,
        longitude: -122.4194,
        accuracyMeters: 2.0,
        lowAccuracy: false,
        resolvedAddress: '100 Main St, City',
      );

      final payload = await service.processCapture(
        originalBytes: rawJpegWithExif,
        snapshot: snapshot,
      );

      expect(payload.isSuccess, isTrue);

      // Read back saved original, evidence, and thumbnail bytes
      final origFile = File(await storage.resolveAbsolutePath(payload.originalFilePath));
      final evidFile = File(await storage.resolveAbsolutePath(payload.evidenceFilePath!));
      final thumbFile = File(await storage.resolveAbsolutePath(payload.thumbnailFilePath!));

      final origDecoded = img.decodeJpg(await origFile.readAsBytes())!;
      final evidDecoded = img.decodeJpg(await evidFile.readAsBytes())!;
      final thumbDecoded = img.decodeJpg(await thumbFile.readAsBytes())!;

      // Original preserves EXIF
      expect(origDecoded.exif.imageIfd.hasMake, isTrue);
      expect(origDecoded.exif.imageIfd.hasModel, isTrue);

      // Evidence and thumbnail have EXIF stripped
      expect(evidDecoded.exif.imageIfd.hasMake, isFalse);
      expect(evidDecoded.exif.imageIfd.hasModel, isFalse);
      expect(thumbDecoded.exif.imageIfd.hasMake, isFalse);
      expect(thumbDecoded.exif.imageIfd.hasModel, isFalse);

      tempDir.deleteSync(recursive: true);
    });

    test('Unavailable telemetry (altitude, heading, satellites) preserved as explicit null', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final repo = LocalMediaRepository(db);
      final tempDir = Directory.systemTemp.createTempSync('sitelens_slice4_null_telem_');
      final storage = TestEvidenceStorageService(tempDir);
      final coordinator = MediaPersistenceCoordinator(db, repo, storage);

      // Seed valid site
      await db.into(db.sites).insert(
        SitesCompanion.insert(
          id: 'SITE_001',
          siteCode: const drift.Value('BLDG-A'),
          name: const drift.Value('Main Facility'),
          address: const drift.Value('100 Main St, City'),
        ),
      );

      // Pre-create disk files so existence verification passes
      final origFile = File('${tempDir.path}/media/orig_media_telem_01.jpg')..createSync(recursive: true);
      origFile.writeAsBytesSync([1, 2, 3]);
      final evidFile = File('${tempDir.path}/media/evid_media_telem_01.jpg')..createSync(recursive: true);
      evidFile.writeAsBytesSync([4, 5, 6]);
      final thumbFile = File('${tempDir.path}/media/thumb_media_telem_01.jpg')..createSync(recursive: true);
      thumbFile.writeAsBytesSync([7, 8, 9]);

      final payload = ProcessedEvidencePayload(
        isSuccess: true,
        mediaId: 'media_telem_01',
        originalFilePath: 'media/orig_media_telem_01.jpg',
        evidenceFilePath: 'media/evid_media_telem_01.jpg',
        thumbnailFilePath: 'media/thumb_media_telem_01.jpg',
        originalSha256: 'orig_hash_123',
        evidenceSha256: 'evid_hash_123',
        originalFileSizeBytes: 3,
        evidenceFileSizeBytes: 3,
        thumbnailFileSizeBytes: 3,
        metadataSnapshot: EvidenceMetadataSnapshot(
          mediaId: 'media_telem_01',
          siteId: 'SITE_001',
          siteCode: 'BLDG-A',
          siteName: 'Main Facility',
          creatorId: 'creator_01',
          capturedAtUtc: DateTime.utc(2026, 3, 10, 12, 0, 0),
          canonicalTimestampUtc: '2026-03-10 12:00:00 UTC',
          latitude: 37.7749,
          longitude: -122.4194,
          accuracyMeters: 3.0,
          lowAccuracy: false,
          resolvedAddress: '100 Main St, City',
          altitudeMeters: null, // explicit null
          headingDegrees: null, // explicit null
          gnssSatelliteCount: null, // explicit null
          gnssSatellitesUsedInFix: null, // explicit null
        ),
      );

      final item = await coordinator.persistCapturedEvidence(payload);

      expect(item.altitude, isNull, reason: 'Altitude must not default to 0.0 or synthetic value');
      expect(item.headingDegrees, isNull, reason: 'Heading must not default to 0.0 or synthetic value');
      expect(item.gnssSatelliteCount, isNull, reason: 'Satellites must not default to 0 or synthetic value');
      expect(item.gnssSatellitesUsedInFix, isNull, reason: 'Satellites used in fix must remain null');

      // Verify directly from SQLite
      final dbRow = await (db.select(db.media)..where((tbl) => tbl.id.equals('media_telem_01'))).getSingle();
      expect(dbRow.altitudeM, isNull);
      expect(dbRow.headingDegrees, isNull);
      expect(dbRow.gnssSatelliteCount, isNull);
      expect(dbRow.gnssSatellitesUsedInFix, isNull);

      await db.close();
      tempDir.deleteSync(recursive: true);
    });
  });

  group('Slice 4: TM-U-11 / AC-EVID-06 / AC-EVID-07 / AC-EVID-08 — SHA-256 Authority & Live Re-hash', () {
    test('Independent SHA-256 hashes for original and evidence; getArtifactHash enforces zero fallback', () {
      final item = MediaItem(
        id: 'media_hash_01',
        siteId: 'SITE_001',
        originalUri: 'media/orig_media_hash_01.jpg',
        uri: 'media/evid_media_hash_01.jpg',
        thumbUri: 'media/thumb_media_hash_01.jpg',
        type: MediaItemType.photo,
        lat: 37.7749,
        lon: -122.4194,
        accuracyM: 2.0,
        capturedAt: DateTime.utc(2026, 3, 10, 12, 0, 0),
        sha256Hash: 'abc123orig',
        evidenceSha256Hash: 'def456evid',
      );

      // Distinct hashes
      expect(item.sha256Hash, isNot(equals(item.evidenceSha256Hash)));

      // Authoritative accessors
      expect(item.getArtifactHash(ArtifactType.original), equals('abc123orig'));
      expect(item.getArtifactHash(ArtifactType.evidence), equals('def456evid'));
      expect(item.getArtifactHash(ArtifactType.thumbnail), isNull);

      // Display accessors with UNAVAILABLE fallback
      expect(item.getDisplayHash(ArtifactType.original), equals('abc123orig'));
      expect(item.getDisplayHash(ArtifactType.evidence), equals('def456evid'));
      expect(item.getDisplayHash(ArtifactType.thumbnail), equals('UNAVAILABLE'));

      // If evidence hash is null, it must NOT fall back to original hash
      final itemNoEvidHash = MediaItem(
        id: 'media_hash_02',
        siteId: 'SITE_001',
        originalUri: 'media/orig_media_hash_02.jpg',
        uri: 'media/evid_media_hash_02.jpg',
        type: MediaItemType.photo,
        lat: 37.7749,
        lon: -122.4194,
        capturedAt: DateTime.utc(2026, 3, 10, 12, 0, 0),
        sha256Hash: 'abc123orig',
        evidenceSha256Hash: null,
      );
      expect(itemNoEvidHash.getArtifactHash(ArtifactType.evidence), isNull);
      expect(itemNoEvidHash.getDisplayHash(ArtifactType.evidence), equals('UNAVAILABLE'));
      expect(itemNoEvidHash.getDisplayHash(ArtifactType.evidence), isNot(equals('abc123orig')));
    });

    test('Live byte re-hash via verifyArtifactIntegrity yields verified, unverified, or unavailable', () async {
      final tempDir = Directory.systemTemp.createTempSync('sitelens_slice4_rehash_');
      final storage = TestEvidenceStorageService(tempDir);

      final fileBytes = Uint8List.fromList([65, 66, 67, 68]); // "ABCD"
      final expectedSha = CryptoUtils.computeSha256(fileBytes);

      final testFile = File('${tempDir.path}/media/evid_sample.jpg')..createSync(recursive: true);
      testFile.writeAsBytesSync(fileBytes);

      // 1. Matching hash -> verified
      final resVerified = await storage.verifyArtifactIntegrity(
        relativePath: 'media/evid_sample.jpg',
        expectedSha256: expectedSha,
      );
      expect(resVerified, equals(IntegrityVerificationResult.verified));

      // 2. Tampered file -> unverified
      testFile.writeAsBytesSync([65, 66, 67, 99]); // Tampered byte
      final resTampered = await storage.verifyArtifactIntegrity(
        relativePath: 'media/evid_sample.jpg',
        expectedSha256: expectedSha,
      );
      expect(resTampered, equals(IntegrityVerificationResult.unverified));

      // 3. Missing file -> unavailable
      final resMissing = await storage.verifyArtifactIntegrity(
        relativePath: 'media/non_existent.jpg',
        expectedSha256: expectedSha,
      );
      expect(resMissing, equals(IntegrityVerificationResult.unavailable));

      // 4. Missing expected hash -> unavailable
      final resNoExpected = await storage.verifyArtifactIntegrity(
        relativePath: 'media/evid_sample.jpg',
        expectedSha256: null,
      );
      expect(resNoExpected, equals(IntegrityVerificationResult.unavailable));

      tempDir.deleteSync(recursive: true);
    });
  });

  group('Slice 4: TM-U-17 / AC-SECB-05 — Path Traversal Hardening', () {
    test('resolveAbsolutePath sanitizes ../, ..\\, ....//, and rejects null bytes', () async {
      final tempDir = Directory.systemTemp.createTempSync('sitelens_slice4_sec_');
      final storage = TestEvidenceStorageService(tempDir);

      // Normal path
      final normal = await storage.resolveAbsolutePath('media/orig_123.jpg');
      expect(normal, equals('${tempDir.path}/media/orig_123.jpg'));

      // Forward slash traversal
      final traversal1 = await storage.resolveAbsolutePath('../../etc/passwd');
      expect(traversal1, equals('${tempDir.path}/etc/passwd'));
      expect(traversal1.contains('..'), isFalse);

      // Backslash traversal
      final traversal2 = await storage.resolveAbsolutePath('..\\..\\windows\\system32');
      expect(traversal2, equals('${tempDir.path}/windows/system32'));
      expect(traversal2.contains('..'), isFalse);

      // Repeated recursive traversal (....//)
      final traversal3 = await storage.resolveAbsolutePath('....//....//hidden/secrets.txt');
      expect(traversal3, equals('${tempDir.path}/hidden/secrets.txt'));
      expect(traversal3.contains('..'), isFalse);

      // Null byte injection must throw ArgumentError
      expect(
        () async => await storage.resolveAbsolutePath('media/file.jpg\x00.exe'),
        throwsA(isA<ArgumentError>()),
      );

      tempDir.deleteSync(recursive: true);
    });
  });

  group('Slice 4: AC-HUD-09 / AC-REVIEW-06 — Atomic Writes, Existence Check & Rollback', () {
    test('MediaPersistenceCoordinator verifies file existence on disk before DB insert', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final repo = LocalMediaRepository(db);
      final tempDir = Directory.systemTemp.createTempSync('sitelens_slice4_atomic_');
      final storage = TestEvidenceStorageService(tempDir);
      final coordinator = MediaPersistenceCoordinator(db, repo, storage);

      await db.into(db.sites).insert(
        SitesCompanion.insert(
          id: 'SITE_001',
          siteCode: const drift.Value('BLDG-A'),
          name: const drift.Value('Main Facility'),
          address: const drift.Value('100 Main St, City'),
        ),
      );

      final payload = ProcessedEvidencePayload(
        isSuccess: true,
        mediaId: 'missing_files_01',
        originalFilePath: 'media/orig_missing.jpg',
        evidenceFilePath: 'media/evid_missing.jpg',
        thumbnailFilePath: 'media/thumb_missing.jpg',
        originalSha256: 'hash_orig',
        evidenceSha256: 'hash_evid',
        originalFileSizeBytes: 100,
        evidenceFileSizeBytes: 100,
        thumbnailFileSizeBytes: 50,
        metadataSnapshot: EvidenceMetadataSnapshot(
          mediaId: 'missing_files_01',
          siteId: 'SITE_001',
          siteCode: 'BLDG-A',
          siteName: 'Main Facility',
          creatorId: 'creator_01',
          capturedAtUtc: DateTime.utc(2026, 3, 10, 12, 0, 0),
          canonicalTimestampUtc: '2026-03-10 12:00:00 UTC',
          latitude: 37.7749,
          longitude: -122.4194,
          accuracyMeters: 2.0,
          lowAccuracy: false,
          resolvedAddress: '100 Main St, City',
        ),
      );

      // Files do not exist on disk -> throws MediaPersistenceException
      expect(
        () async => await coordinator.persistCapturedEvidence(payload),
        throwsA(isA<MediaPersistenceException>()),
      );

      // Ensure 0 DB records inserted
      final allItems = await (db.select(db.media).get());
      expect(allItems, isEmpty);

      await db.close();
      tempDir.deleteSync(recursive: true);
    });

    test('Rollback on failure cleans derived files while preserving original capture', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final repo = LocalMediaRepository(db);
      final tempDir = Directory.systemTemp.createTempSync('sitelens_slice4_rollback_');
      final storage = TestEvidenceStorageService(tempDir);
      final coordinator = MediaPersistenceCoordinator(db, repo, storage);

      // Create original, evidence, and thumbnail on disk
      final origFile = File('${tempDir.path}/media/orig_fail_01.jpg')..createSync(recursive: true);
      origFile.writeAsBytesSync([1, 2, 3]);
      final evidFile = File('${tempDir.path}/media/evid_fail_01.jpg')..createSync(recursive: true);
      evidFile.writeAsBytesSync([4, 5, 6]);
      final thumbFile = File('${tempDir.path}/media/thumb_fail_01.jpg')..createSync(recursive: true);
      thumbFile.writeAsBytesSync([7, 8, 9]);

      // Do NOT insert SITE_001 in DB so persistence fails
      final payload = ProcessedEvidencePayload(
        isSuccess: true,
        mediaId: 'fail_01',
        originalFilePath: 'media/orig_fail_01.jpg',
        evidenceFilePath: 'media/evid_fail_01.jpg',
        thumbnailFilePath: 'media/thumb_fail_01.jpg',
        originalSha256: 'hash_orig',
        evidenceSha256: 'hash_evid',
        originalFileSizeBytes: 3,
        evidenceFileSizeBytes: 3,
        thumbnailFileSizeBytes: 3,
        metadataSnapshot: EvidenceMetadataSnapshot(
          mediaId: 'fail_01',
          siteId: 'NON_EXISTENT_SITE',
          siteCode: 'BLDG-A',
          siteName: 'Main Facility',
          creatorId: 'creator_01',
          capturedAtUtc: DateTime.utc(2026, 3, 10, 12, 0, 0),
          canonicalTimestampUtc: '2026-03-10 12:00:00 UTC',
          latitude: 37.7749,
          longitude: -122.4194,
          accuracyMeters: 2.0,
          lowAccuracy: false,
          resolvedAddress: '100 Main St, City',
        ),
      );

      // Must fail with SiteAssociationException
      expect(
        () async => await coordinator.persistCapturedEvidence(payload),
        throwsA(isA<SiteAssociationException>()),
      );

      // Original must be preserved
      expect(origFile.existsSync(), isTrue, reason: 'Original file must never be destroyed on persistence failure');

      await db.close();
      tempDir.deleteSync(recursive: true);
    });
  });

  group('Slice 4: AC-REVIEW-03 / AC-REVIEW-04 / AC-REVIEW-05 — Retake, Discard & Pending State', () {
    test('Retake action cleans uncommitted files leaving 0 orphaned database records', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final repo = LocalMediaRepository(db);
      final tempDir = Directory.systemTemp.createTempSync('sitelens_slice4_retake_');
      final storage = TestEvidenceStorageService(tempDir);
      final coordinator = MediaPersistenceCoordinator(db, repo, storage);
      final notifier = ReviewTagNotifier(db, repo, storage, persistenceCoordinator: coordinator);

      final origFile = File('${tempDir.path}/media/orig_retake_01.jpg')..createSync(recursive: true);
      origFile.writeAsBytesSync([1, 2, 3]);
      final evidFile = File('${tempDir.path}/media/evid_retake_01.jpg')..createSync(recursive: true);
      evidFile.writeAsBytesSync([4, 5, 6]);
      final thumbFile = File('${tempDir.path}/media/thumb_retake_01.jpg')..createSync(recursive: true);
      thumbFile.writeAsBytesSync([7, 8, 9]);

      final payload = PendingCapturePayload(
        mediaId: 'retake_01',
        originalFilePath: 'media/orig_retake_01.jpg',
        evidenceFilePath: 'media/evid_retake_01.jpg',
        thumbnailFilePath: 'media/thumb_retake_01.jpg',
        metadataSnapshot: EvidenceMetadataSnapshot(
          mediaId: 'retake_01',
          siteId: 'SITE_001',
          siteCode: 'BLDG-A',
          siteName: 'Main Facility',
          creatorId: 'creator_01',
          capturedAtUtc: DateTime.utc(2026, 3, 10, 12, 0, 0),
          canonicalTimestampUtc: '2026-03-10 12:00:00 UTC',
          latitude: 37.7749,
          longitude: -122.4194,
          accuracyMeters: 2.0,
          lowAccuracy: false,
          resolvedAddress: '100 Main St, City',
        ),
        sha256Hash: 'hash_orig',
        mediaType: MediaItemType.photo,
        fileSizeBytes: 3,
      );

      // Execute retake cleanup
      await notifier.retake(payload);

      expect(origFile.existsSync(), isFalse);
      expect(evidFile.existsSync(), isFalse);
      expect(thumbFile.existsSync(), isFalse);

      final allRecords = await (db.select(db.media).get());
      expect(allRecords, isEmpty, reason: 'Zero orphaned records in database after retake');

      await db.close();
      tempDir.deleteSync(recursive: true);
    });

    test('PendingCapturePayload persists with SyncStatusType.pending', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final repo = LocalMediaRepository(db);
      final tempDir = Directory.systemTemp.createTempSync('sitelens_slice4_pending_');
      final storage = TestEvidenceStorageService(tempDir);
      final coordinator = MediaPersistenceCoordinator(db, repo, storage);

      await db.into(db.sites).insert(
        SitesCompanion.insert(
          id: 'SITE_001',
          siteCode: const drift.Value('BLDG-A'),
          name: const drift.Value('Main Facility'),
          address: const drift.Value('100 Main St, City'),
        ),
      );

      final origFile = File('${tempDir.path}/media/orig_pend_01.jpg')..createSync(recursive: true);
      origFile.writeAsBytesSync([1, 2, 3]);
      final evidFile = File('${tempDir.path}/media/evid_pend_01.jpg')..createSync(recursive: true);
      evidFile.writeAsBytesSync([4, 5, 6]);
      final thumbFile = File('${tempDir.path}/media/thumb_pend_01.jpg')..createSync(recursive: true);
      thumbFile.writeAsBytesSync([7, 8, 9]);

      final payload = PendingCapturePayload(
        mediaId: 'pend_01',
        originalFilePath: 'media/orig_pend_01.jpg',
        evidenceFilePath: 'media/evid_pend_01.jpg',
        thumbnailFilePath: 'media/thumb_pend_01.jpg',
        metadataSnapshot: EvidenceMetadataSnapshot(
          mediaId: 'pend_01',
          siteId: 'SITE_001',
          siteCode: 'BLDG-A',
          siteName: 'Main Facility',
          creatorId: 'creator_01',
          capturedAtUtc: DateTime.utc(2026, 3, 10, 12, 0, 0),
          canonicalTimestampUtc: '2026-03-10 12:00:00 UTC',
          latitude: 37.7749,
          longitude: -122.4194,
          accuracyMeters: 2.0,
          lowAccuracy: false,
          resolvedAddress: '100 Main St, City',
        ),
        sha256Hash: 'hash_orig',
        mediaType: MediaItemType.photo,
        fileSizeBytes: 3,
      );

      final item = await coordinator.persistPendingCapture(payload);

      expect(item.id, equals('pend_01'));
      expect(item.syncStatus, equals(SyncStatusType.pending));

      await db.close();
      tempDir.deleteSync(recursive: true);
    });
  });

  group('Slice 4: AC-EVID-02 / AC-EVID-09 — Single-HUD Invariant & Video Artifact Model', () {
    test('AC-EVID-02: Canonical evidence artifact is downstream authority (uri points to burned evidence)', () {
      final item = MediaItem(
        id: 'evid_item_01',
        siteId: 'SITE_001',
        originalUri: 'media/orig_evid_item_01.jpg',
        uri: 'media/evid_evid_item_01.jpg',
        thumbUri: 'media/thumb_evid_item_01.jpg',
        type: MediaItemType.photo,
        lat: 37.7749,
        lon: -122.4194,
        accuracyM: 2.0,
        capturedAt: DateTime.utc(2026, 3, 10, 12, 0, 0),
        sha256Hash: 'hash_orig',
        evidenceSha256Hash: 'hash_evid',
      );

      // Downstream surfaces must consume item.uri (the canonical burned evidence artifact)
      expect(item.uri, equals('media/evid_evid_item_01.jpg'));
      expect(item.originalUri, equals('media/orig_evid_item_01.jpg'));
      expect(item.uri, isNot(equals(item.originalUri)));
    });

    test('AC-EVID-09: Video artifact model preserves raw stream with poster/opening frame poster contract', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final repo = LocalMediaRepository(db);
      final tempDir = Directory.systemTemp.createTempSync('sitelens_slice4_video_');
      final storage = TestEvidenceStorageService(tempDir);
      final coordinator = MediaPersistenceCoordinator(db, repo, storage);

      await db.into(db.sites).insert(
        SitesCompanion.insert(
          id: 'SITE_001',
          siteCode: const drift.Value('BLDG-A'),
          name: const drift.Value('Main Facility'),
          address: const drift.Value('100 Main St, City'),
        ),
      );

      final videoFile = File('${tempDir.path}/media/orig_video_01.mp4')..createSync(recursive: true);
      videoFile.writeAsBytesSync([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70]); // mp4 ftyp header
      final thumbFile = File('${tempDir.path}/media/thumb_video_01.jpg')..createSync(recursive: true);
      thumbFile.writeAsBytesSync([0xFF, 0xD8, 0xFF]); // jpg header

      final videoPayload = PendingCapturePayload(
        mediaId: 'video_01',
        originalFilePath: 'media/orig_video_01.mp4',
        evidenceFilePath: 'media/orig_video_01.mp4', // Video stream is preserved raw/unwatermarked
        thumbnailFilePath: 'media/thumb_video_01.jpg', // Poster frame thumbnail
        metadataSnapshot: EvidenceMetadataSnapshot(
          mediaId: 'video_01',
          siteId: 'SITE_001',
          siteCode: 'BLDG-A',
          siteName: 'Main Facility',
          creatorId: 'creator_01',
          capturedAtUtc: DateTime.utc(2026, 3, 10, 12, 0, 0),
          canonicalTimestampUtc: '2026-03-10 12:00:00 UTC',
          latitude: 37.7749,
          longitude: -122.4194,
          accuracyMeters: 2.0,
          lowAccuracy: false,
          resolvedAddress: '100 Main St, City',
          hasAudioTrack: true,
        ),
        sha256Hash: 'hash_video_stream',
        mediaType: MediaItemType.video,
        fileSizeBytes: 8,
      );

      final videoItem = await coordinator.persistPendingCapture(videoPayload);

      expect(videoItem.type, equals(MediaItemType.video));
      expect(videoItem.originalUri, equals('media/orig_video_01.mp4'));
      expect(videoItem.uri, equals('media/orig_video_01.mp4'), reason: 'Video stream remains unwatermarked raw artifact');
      expect(videoItem.thumbUri, equals('media/thumb_video_01.jpg'), reason: 'Thumbnail holds opening poster frame');
      expect(videoItem.hasAudioTrack, isTrue);

      await db.close();
      tempDir.deleteSync(recursive: true);
    });
  });
}
