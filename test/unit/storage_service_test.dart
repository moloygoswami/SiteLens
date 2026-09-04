import 'dart:io';
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
  });
}
