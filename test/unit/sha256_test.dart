import 'package:flutter_test/flutter_test.dart';
import 'package:sitelens/core/utils/crypto_utils.dart';

void main() {
  group('CryptoUtils SHA-256 Tests', () {
    test('Computes deterministic SHA-256 hex string', () {
      const input = 'SiteLens Evidence Hash Test';
      final hash1 = CryptoUtils.computeSha256String(input);
      final hash2 = CryptoUtils.computeSha256String(input);

      expect(hash1, equals(hash2));
      expect(hash1.length, equals(64)); // SHA-256 produces 64 hex characters
    });
  });
}
