import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitelens/features/camera/services/evidence_storage_service.dart';

class TestEvidenceStorageService extends EvidenceStorageService {
  final Directory testBaseDir;
  TestEvidenceStorageService(this.testBaseDir);

  @override
  Future<Directory> getBaseDirectory() async => testBaseDir;
}

void main() {
  group('EvidenceStorageService Unit Tests', () {
    test('EvidenceStorageService.resolveAbsolutePath sanitizes path traversal attempts (vuln-0002 / CWE-862)', () async {
      final tempDir = Directory.systemTemp.createTempSync('sitelens_storage_test_');
      final service = TestEvidenceStorageService(tempDir);

      // Normal path
      final normal = await service.resolveAbsolutePath('media/orig_123.jpg');
      expect(normal, equals('${tempDir.path}/media/orig_123.jpg'));

      // Path traversal attempts with ../ and ..\
      final traversal1 = await service.resolveAbsolutePath('../../etc/passwd');
      expect(traversal1, equals('${tempDir.path}/etc/passwd'));
      expect(traversal1.contains('..'), isFalse);

      final traversal2 = await service.resolveAbsolutePath('..\\..\\sensitive\\data.txt');
      expect(traversal2, equals('${tempDir.path}/sensitive/data.txt'));
      expect(traversal2.contains('..'), isFalse);

      tempDir.deleteSync(recursive: true);
    });

    test('F2: saveOriginalBytes publishes atomically with no temporary remnants', () async {
      final tempDir = Directory.systemTemp.createTempSync('sitelens_storage_atomic_');
      final service = TestEvidenceStorageService(tempDir);

      final bytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final relPath = await service.saveOriginalBytes(bytes, 'media_001');

      expect(relPath, equals('media/orig_media_001.jpg'));
      final absPath = await service.resolveAbsolutePath(relPath);
      final finalFile = File(absPath);

      expect(await finalFile.exists(), isTrue);
      expect(await finalFile.readAsBytes(), equals(bytes));

      // Check that no .tmp_ files remain in the media directory
      final mediaDir = Directory('${tempDir.path}/media');
      final tmpFiles = (await mediaDir.list().toList())
          .where((e) => e.path.contains('.tmp_'))
          .toList();
      expect(tmpFiles, isEmpty);

      tempDir.deleteSync(recursive: true);
    });

    test('F2: saveEvidenceAndThumbnail publishes both atomically without temporary remnants', () async {
      final tempDir = Directory.systemTemp.createTempSync('sitelens_storage_evid_');
      final service = TestEvidenceStorageService(tempDir);

      final evidBytes = Uint8List.fromList([10, 20, 30, 40]);
      final thumbBytes = Uint8List.fromList([50, 60]);

      final paths = await service.saveEvidenceAndThumbnail(
        mediaId: 'media_002',
        evidenceBytes: evidBytes,
        thumbnailBytes: thumbBytes,
      );

      expect(paths['evidencePath'], equals('media/evid_media_002.jpg'));
      expect(paths['thumbnailPath'], equals('media/thumb_media_002.jpg'));

      final evidFile = File(await service.resolveAbsolutePath(paths['evidencePath']!));
      final thumbFile = File(await service.resolveAbsolutePath(paths['thumbnailPath']!));

      expect(await evidFile.exists(), isTrue);
      expect(await thumbFile.exists(), isTrue);
      expect(await evidFile.readAsBytes(), equals(evidBytes));
      expect(await thumbFile.readAsBytes(), equals(thumbBytes));

      // Verify no temporary files remain
      final mediaDir = Directory('${tempDir.path}/media');
      final tmpFiles = (await mediaDir.list().toList())
          .where((e) => e.path.contains('.tmp_'))
          .toList();
      expect(tmpFiles, isEmpty);

      tempDir.deleteSync(recursive: true);
    });

    test('F2: verifyArtifactsExist rejects missing or 0-byte incomplete artifacts', () async {
      final tempDir = Directory.systemTemp.createTempSync('sitelens_storage_verify_');
      final service = TestEvidenceStorageService(tempDir);

      final mediaDir = await service.getMediaDirectory();
      final origFile = File('${mediaDir.path}/orig_media_003.jpg');
      final evidFile = File('${mediaDir.path}/evid_media_003.jpg');
      final thumbFile = File('${mediaDir.path}/thumb_media_003.jpg');

      // 1. Files do not exist yet -> rejected
      final notExisting = await service.verifyArtifactsExist(
        originalRelativePath: 'media/orig_media_003.jpg',
        evidenceRelativePath: 'media/evid_media_003.jpg',
        thumbnailRelativePath: 'media/thumb_media_003.jpg',
      );
      expect(notExisting, isFalse);

      // 2. Incomplete 0-byte file -> rejected
      await origFile.writeAsBytes([], flush: true);
      await evidFile.writeAsBytes([1, 2, 3], flush: true);
      await thumbFile.writeAsBytes([1], flush: true);

      final zeroByteOrig = await service.verifyArtifactsExist(
        originalRelativePath: 'media/orig_media_003.jpg',
        evidenceRelativePath: 'media/evid_media_003.jpg',
        thumbnailRelativePath: 'media/thumb_media_003.jpg',
      );
      expect(zeroByteOrig, isFalse);

      // 3. 0-byte thumbnail -> rejected
      await origFile.writeAsBytes([1, 2, 3], flush: true);
      await thumbFile.writeAsBytes([], flush: true);

      final zeroByteThumb = await service.verifyArtifactsExist(
        originalRelativePath: 'media/orig_media_003.jpg',
        evidenceRelativePath: 'media/evid_media_003.jpg',
        thumbnailRelativePath: 'media/thumb_media_003.jpg',
      );
      expect(zeroByteThumb, isFalse);

      // 4. All non-zero bytes -> accepted
      await thumbFile.writeAsBytes([1], flush: true);
      final allValid = await service.verifyArtifactsExist(
        originalRelativePath: 'media/orig_media_003.jpg',
        evidenceRelativePath: 'media/evid_media_003.jpg',
        thumbnailRelativePath: 'media/thumb_media_003.jpg',
      );
      expect(allValid, isTrue);

      tempDir.deleteSync(recursive: true);
    });

    test('F2: cleanupPartialArtifacts cleans up derived artifacts and lingering temporary files while preserving original', () async {
      final tempDir = Directory.systemTemp.createTempSync('sitelens_storage_cleanup_');
      final service = TestEvidenceStorageService(tempDir);

      final mediaDir = await service.getMediaDirectory();
      final origFile = File('${mediaDir.path}/orig_media_004.jpg');
      final evidFile = File('${mediaDir.path}/evid_media_004.jpg');
      final thumbFile = File('${mediaDir.path}/thumb_media_004.jpg');
      final tmpFile = File('${mediaDir.path}/evid_media_004.jpg.tmp_12345');

      await origFile.writeAsBytes([1, 2, 3], flush: true);
      await evidFile.writeAsBytes([4, 5, 6], flush: true);
      await thumbFile.writeAsBytes([7, 8], flush: true);
      await tmpFile.writeAsBytes([9, 9], flush: true);

      await service.cleanupPartialArtifacts('media_004');

      // Original MUST be preserved
      expect(await origFile.exists(), isTrue);
      // Derived files MUST be deleted
      expect(await evidFile.exists(), isFalse);
      expect(await thumbFile.exists(), isFalse);
      // Lingering temp file MUST be deleted
      expect(await tmpFile.exists(), isFalse);

      tempDir.deleteSync(recursive: true);
    });
  });
}
