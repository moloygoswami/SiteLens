import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

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

  // Resolves any relative path (e.g. "media/orig_xxx.jpg") to its absolute filesystem path
  Future<String> resolveAbsolutePath(String relativePath) async {
    final base = await getBaseDirectory();
    final sanitized = relativePath
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'(\.\./|\.\.)'), '')
        .replaceAll(RegExp(r'^/+'), '');
    return '${base.path}/$sanitized';
  }

  /// Saves raw original camera bytes untouched with OS-level flush.
  /// Returns the relative path contract (e.g. "media/orig_xxx.jpg").
  Future<String> saveOriginalBytes(Uint8List originalBytes, String mediaId) async {
    await getMediaDirectory();
    final relPath = getOriginalRelativePath(mediaId);
    final absPath = await resolveAbsolutePath(relPath);

    final file = File(absPath);
    await file.writeAsBytes(originalBytes, flush: true);
    return relPath;
  }

  /// Saves derived evidence JPEG and thumbnail JPEG with OS-level flush.
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

    await evidenceFile.writeAsBytes(evidenceBytes, flush: true);
    await thumbFile.writeAsBytes(thumbnailBytes, flush: true);

    return {
      'evidencePath': evidRelPath,
      'thumbnailPath': thumbRelPath,
    };
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
