import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class CryptoUtils {
  static const String _autoIdChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  static final Random _secureRandom = Random.secure();

  /// Generates a cryptographically secure 20-character base62 Firestore-compatible document ID.
  static String generateFirestoreId() {
    return List.generate(20, (index) => _autoIdChars[_secureRandom.nextInt(_autoIdChars.length)]).join();
  }

  /// Computes the SHA-256 hash of the given raw bytes and returns it as a lowercase hex string.
  static String computeSha256(Uint8List bytes) {
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Computes the SHA-256 hash of a string (UTF-8).
  static String computeSha256String(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
