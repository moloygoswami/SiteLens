import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/crypto_utils.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/media_item.dart';
import '../../camera/services/evidence_storage_service.dart';
import 'cloud_sync_service.dart';

final cloudMediaRecoveryServiceProvider = Provider<CloudMediaRecoveryService>((ref) {
  final storageService = ref.watch(evidenceStorageServiceProvider);
  return CloudMediaRecoveryService(
    storage: FirebaseStorage.instance,
    storageService: storageService,
  );
});

class CloudMediaRecoveryService {
  final FirebaseStorage _storage;
  final EvidenceStorageService _storageService;

  CloudMediaRecoveryService({
    required FirebaseStorage storage,
    required EvidenceStorageService storageService,
  })  : _storage = storage,
        _storageService = storageService;

  /// Recovers and forensically verifies a deleted local original photo or video artifact
  /// from Firebase Cloud Storage.
  Future<File> recoverOriginal({
    required MediaItem item,
    void Function(double progress)? onProgress,
  }) async {
    final expectedSha = item.sha256Hash;
    if (expectedSha == null || expectedSha.isEmpty) {
      throw PermanentSyncException(
        'Cannot recover media item ${item.id}: Missing authoritative sha256Hash in local record.',
      );
    }

    // 1. Resolve destination relative & absolute paths
    final String relativePath;
    if (item.originalUri.isNotEmpty) {
      relativePath = item.originalUri;
    } else {
      final ext = item.type == MediaItemType.photo ? 'jpg' : 'mp4';
      relativePath = 'media/orig_${item.id}.$ext';
    }

    final destinationAbsolutePath = await _storageService.resolveAbsolutePath(relativePath);
    final destinationFile = File(destinationAbsolutePath);

    // 2. Check if valid local original already exists
    if (await destinationFile.exists()) {
      final existingBytes = await destinationFile.readAsBytes();
      final existingSha = CryptoUtils.computeSha256(existingBytes);
      if (existingSha == expectedSha) {
        // Already valid and present locally -> Reuse existing file
        return destinationFile;
      } else {
        // Corrupted local file exists -> Fail safely without silent overwrite
        throw IntegrityConflictException(
          'Existing local file at $destinationAbsolutePath has conflicting SHA-256 ($existingSha != $expectedSha).',
        );
      }
    }

    // 3. Ensure media directory exists
    await _storageService.getMediaDirectory();

    // 4. Create unique atomic temporary download target
    final tempRelativePath = 'media/tmp_recov_${item.id}_${DateTime.now().microsecondsSinceEpoch}.tmp';
    final tempAbsolutePath = await _storageService.resolveAbsolutePath(tempRelativePath);
    final tempFile = File(tempAbsolutePath);

    final storageRef = _storage.ref('sites/${item.siteId}/media/${item.id}/original');

    try {
      // 5. Download cloud original artifact to temporary file
      final downloadTask = storageRef.writeToFile(tempFile);

      if (onProgress != null) {
        downloadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
          final totalBytes = snapshot.totalBytes;
          final transferred = snapshot.bytesTransferred;
          if (totalBytes > 0) {
            onProgress(transferred / totalBytes);
          }
        });
      }

      await downloadTask;

      // 6. Forensic Integrity Verification: Calculate SHA-256 of downloaded temporary file
      final downloadedBytes = await tempFile.readAsBytes();
      final computedSha = CryptoUtils.computeSha256(downloadedBytes);

      if (computedSha != expectedSha) {
        // SHA-256 mismatch -> Delete temporary file and reject
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        throw IntegrityConflictException(
          'Downloaded original SHA-256 ($computedSha) conflicts with authoritative expected hash ($expectedSha).',
        );
      }

      // 7. Atomic Promotion: Rename temporary file to final destination path
      final finalFile = await tempFile.rename(destinationAbsolutePath);
      return finalFile;
    } on FirebaseException catch (e) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      if (e.code == 'object-not-found') {
        throw PermanentSyncException(
          'Cloud original artifact not found in storage at sites/${item.siteId}/media/${item.id}/original.',
        );
      } else if (e.code == 'permission-denied') {
        throw PermanentSyncException(
          'Permission denied reading cloud original for site ${item.siteId}.',
        );
      } else {
        throw RetryableSyncException('Firebase storage error (${e.code}): ${e.message}');
      }
    } on SocketException catch (e) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      throw RetryableSyncException('Network connection failed during recovery: ${e.message}');
    } catch (e) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      if (e is PermanentSyncException || e is RetryableSyncException || e is IntegrityConflictException) {
        rethrow;
      }
      throw RetryableSyncException('Unexpected recovery failure: $e');
    }
  }
}
