import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/utils/crypto_utils.dart';
import '../../../domain/models/enums.dart';

final evidenceStorageServiceProvider = Provider<EvidenceStorageService>((ref) {
  return EvidenceStorageService();
});

class EvidenceStorageService {
  Directory? _baseDir;

  Future<Directory> getBaseDirectory() async {
    if (_baseDir != null && await _baseDir!.exists()) {
      return _baseDir!;
    }
    final appDir = await getApplicationDocumentsDirectory();
    _baseDir = appDir;
    return appDir;
  }

  Future<Directory> getMediaDirectory() async {
    final base = await getBaseDirectory();
    final mediaDir = Directory('${base.path}/media');
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }
    return mediaDir;
  }

  // Relative path contracts for Drift SQLite persistence
  String getOriginalRelativePath(String mediaId) => 'media/orig_$mediaId.jpg';
  String getEvidenceRelativePath(String mediaId) => 'media/evid_$mediaId.jpg';
  String getThumbnailRelativePath(String mediaId) => 'media/thumb_$mediaId.jpg';

  /// Resolves any relative path (e.g. "media/orig_xxx.jpg") to its absolute filesystem path.
  /// Rejects null bytes and normalizes traversal sequences so the resolved target
  /// resides strictly within the application-private base directory (AC-SECB-05, TM-U-17).
  Future<String> resolveAbsolutePath(String relativePath) async {
    if (relativePath.contains('\x00')) {
      throw ArgumentError('Path traversal rejected: null byte detected in path');
    }
    final base = await getBaseDirectory();
    var sanitized = relativePath.replaceAll('\\', '/');
    sanitized = sanitized.replaceAll(RegExp(r'^/+'), '');
    while (sanitized.contains('..')) {
      sanitized = sanitized.replaceAll('..', '');
    }
    sanitized = sanitized.replaceAll(RegExp(r'/+'), '/');
    if (sanitized.startsWith('/')) {
      sanitized = sanitized.substring(1);
    }
    final target = '${base.path}/$sanitized';
    if (!target.startsWith(base.path)) {
      throw ArgumentError('Path traversal rejected: target path escapes base directory');
    }
    return target;
  }

  /// Forensically verifies an on-disk artifact against an expected SHA-256 hash (AC-EVID-08, TM-U-11).
  /// Reads physical on-disk bytes, computes SHA-256, and compares with expected.
  /// Returns [IntegrityVerificationResult]:
  /// - verified: on-disk file exists, is read, and computed SHA-256 matches expected.
  /// - unverified: on-disk file exists, but computed SHA-256 does NOT match expected.
  /// - unavailable: on-disk file does not exist, or expected hash is null/empty.
  Future<IntegrityVerificationResult> verifyArtifactIntegrity({
    required String relativePath,
    required String? expectedSha256,
  }) async {
    if (expectedSha256 == null || expectedSha256.trim().isEmpty) {
      return IntegrityVerificationResult.unavailable;
    }
    try {
      final absPath = await resolveAbsolutePath(relativePath);
      final file = File(absPath);
      if (!file.existsSync() || file.lengthSync() == 0) {
        return IntegrityVerificationResult.unavailable;
      }
      final bytes = file.readAsBytesSync();
      final computed = CryptoUtils.computeSha256(bytes);
      if (computed.toLowerCase() == expectedSha256.trim().toLowerCase()) {
        return IntegrityVerificationResult.verified;
      } else {
        return IntegrityVerificationResult.unverified;
      }
    } catch (_) {
      return IntegrityVerificationResult.unavailable;
    }
  }

  /// Atomically writes bytes to [targetFile] by first writing to a temporary file in the same directory,
  /// flushing to OS storage, and renaming the temporary file to [targetFile.path].
  /// If an error occurs, the temporary file is deleted before rethrowing.
  Future<void> _atomicWriteFile(File targetFile, Uint8List bytes) async {
    final tempFile = File('${targetFile.path}.tmp_${DateTime.now().microsecondsSinceEpoch}');
    try {
      await tempFile.writeAsBytes(bytes, flush: true);
      await tempFile.rename(targetFile.path);
    } catch (e) {
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
      rethrow;
    }
  }

  /// R15: re-reads a just-published artifact and asserts its SHA-256 equals the
  /// digest of the exact bytes that were written, so a committed or published
  /// digest always describes what is physically on disk. Returns false when the
  /// file is missing, unreadable, or byte-divergent.
  @visibleForTesting
  Future<bool> verifyPublishedBytes(File file, Uint8List expectedBytes) async {
    try {
      if (!await file.exists()) return false;
      final persisted = await file.readAsBytes();
      return CryptoUtils.computeSha256(persisted) ==
          CryptoUtils.computeSha256(expectedBytes);
    } catch (_) {
      return false;
    }
  }

  /// Saves raw original camera bytes untouched with OS-level flush and atomic publication.
  /// Returns the relative path contract (e.g. "media/orig_xxx.jpg").
  Future<String> saveOriginalBytes(Uint8List originalBytes, String mediaId) async {
    await getMediaDirectory();
    final relPath = getOriginalRelativePath(mediaId);
    final absPath = await resolveAbsolutePath(relPath);

    final file = File(absPath);
    await _atomicWriteFile(file, originalBytes);

    // R15: the published bytes must satisfy the recorded digest before the hash
    // can be committed. Never delete the original here — a mismatch aborts so
    // the caller reports truthfully and the bytes remain available for retry.
    if (!await verifyPublishedBytes(file, originalBytes)) {
      throw const FileSystemException(
        'Original artifact failed SHA-256 verification after write.',
      );
    }
    return relPath;
  }

  /// Saves derived evidence JPEG and thumbnail JPEG atomically with OS-level flush.
  /// Returns the relative path contracts.
  Future<Map<String, String>> saveEvidenceAndThumbnail({
    required String mediaId,
    required Uint8List evidenceBytes,
    required Uint8List thumbnailBytes,
  }) async {
    await getMediaDirectory();
    final evidRelPath = getEvidenceRelativePath(mediaId);
    final thumbRelPath = getThumbnailRelativePath(mediaId);

    final evidAbsPath = await resolveAbsolutePath(evidRelPath);
    final thumbAbsPath = await resolveAbsolutePath(thumbRelPath);

    final evidenceFile = File(evidAbsPath);
    final thumbFile = File(thumbAbsPath);

    final evidTemp = File('$evidAbsPath.tmp_${DateTime.now().microsecondsSinceEpoch}');
    final thumbTemp = File('$thumbAbsPath.tmp_${DateTime.now().microsecondsSinceEpoch}');

    try {
      await evidTemp.writeAsBytes(evidenceBytes, flush: true);
      await thumbTemp.writeAsBytes(thumbnailBytes, flush: true);

      await evidTemp.rename(evidAbsPath);
      await thumbTemp.rename(thumbAbsPath);

      // R15: re-verify the final published bytes before their digests can be
      // committed. A mismatch throws inside the try so the derived artifacts and
      // any temporary remnants are removed while the original is never touched.
      if (!await verifyPublishedBytes(evidenceFile, evidenceBytes) ||
          !await verifyPublishedBytes(thumbFile, thumbnailBytes)) {
        throw const FileSystemException(
          'Published evidence artifacts failed SHA-256 verification.',
        );
      }

      return {
        'evidencePath': evidRelPath,
        'thumbnailPath': thumbRelPath,
      };
    } catch (e) {
      try {
        if (await evidTemp.exists()) await evidTemp.delete();
      } catch (_) {}
      try {
        if (await thumbTemp.exists()) await thumbTemp.delete();
      } catch (_) {}
      try {
        if (await evidenceFile.exists()) await evidenceFile.delete();
      } catch (_) {}
      try {
        if (await thumbFile.exists()) await thumbFile.delete();
      } catch (_) {}
      rethrow;
    }
  }

  /// Verifies that original and evidence (and optional thumbnail) artifacts physically exist and have non-zero size.
  Future<bool> verifyArtifactsExist({
    required String originalRelativePath,
    required String evidenceRelativePath,
    String? thumbnailRelativePath,
  }) async {
    try {
      final origFile = File(await resolveAbsolutePath(originalRelativePath));
      final evidFile = File(await resolveAbsolutePath(evidenceRelativePath));

      if (!await origFile.exists() || await origFile.length() == 0) return false;
      if (!await evidFile.exists() || await evidFile.length() == 0) return false;
      if (thumbnailRelativePath != null && thumbnailRelativePath.isNotEmpty) {
        final thumbFile = File(await resolveAbsolutePath(thumbnailRelativePath));
        if (!await thumbFile.exists() || await thumbFile.length() == 0) return false;
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Cleans up partial derived files on failure while ALWAYS preserving original camera bytes.
  Future<void> cleanupPartialArtifacts(String mediaId) async {
    try {
      final evidAbsPath = await resolveAbsolutePath(getEvidenceRelativePath(mediaId));
      final thumbAbsPath = await resolveAbsolutePath(getThumbnailRelativePath(mediaId));

      final evidenceFile = File(evidAbsPath);
      final thumbFile = File(thumbAbsPath);

      if (await evidenceFile.exists()) {
        await evidenceFile.delete();
      }
      if (await thumbFile.exists()) {
        await thumbFile.delete();
      }

      // Also clean up any lingering temporary files from interrupted writes
      final dir = await getMediaDirectory();
      if (await dir.exists()) {
        final entities = await dir.list().toList();
        for (final entity in entities) {
          if (entity is File && entity.path.contains(mediaId) && entity.path.contains('.tmp_')) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  /// Cleans up the temporary XFile produced by CameraController.
  Future<void> deleteTempCameraFile(String tempPath) async {
    try {
      final file = File(tempPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// Deletes the original captured media file at the given relative path.
  Future<void> deleteOriginalMedia(String relativePath) async {
    try {
      final absPath = await resolveAbsolutePath(relativePath);
      final file = File(absPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// Deletes all local physical media files (original, evidence, thumbnail) for a given media item.
  Future<void> deleteLocalMediaFiles({
    required String mediaId,
    String? originalUri,
    String? uri,
    String? thumbUri,
    String? type,
  }) async {
    final relPaths = <String>{
      if (originalUri != null && originalUri.isNotEmpty) originalUri else getOriginalRelativePath(mediaId),
      if (uri != null && uri.isNotEmpty) uri else getEvidenceRelativePath(mediaId),
      if (thumbUri != null && thumbUri.isNotEmpty) thumbUri else getThumbnailRelativePath(mediaId),
    };

    for (final relPath in relPaths) {
      if (relPath.isEmpty) continue;
      try {
        final absPath = await resolveAbsolutePath(relPath);
        final file = File(absPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }
}
