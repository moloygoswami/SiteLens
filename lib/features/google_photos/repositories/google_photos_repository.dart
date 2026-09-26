import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/local/database/app_database.dart';
import '../../../data/local/database/database_provider.dart';
import '../models/google_photos_sync_entry.dart';
import '../models/google_photos_sync_status.dart';

final googlePhotosRepositoryProvider = Provider<GooglePhotosRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return LocalGooglePhotosRepository(db);
});

class GooglePhotosIsolationException implements Exception {
  final String message;
  GooglePhotosIsolationException(this.message);

  @override
  String toString() => 'GooglePhotosIsolationException: $message';
}

abstract class GooglePhotosRepository {
  Future<void> queueMedia(String mediaId, {required String? creatorId});
  Future<List<GooglePhotosSyncEntry>> getPendingOrFailedEntries({required String? creatorId});
  Future<GooglePhotosSyncEntry?> getEntryForMedia(String mediaId, {required String? creatorId});
  Future<void> updateStatus({
    required String mediaId,
    required String? creatorId,
    required GooglePhotosSyncStatus status,
    String? googlePhotosMediaId,
    DateTime? uploadedAt,
    String? errorMessage,
    bool incrementRetry = false,
  });
  Future<void> deleteEntry(String mediaId, {required String? creatorId});
  Stream<List<GooglePhotosSyncEntry>> watchAllEntries({required String? creatorId});
  Future<int> countByStatus(GooglePhotosSyncStatus status, {required String? creatorId});
  Future<void> clearQueueForCreator(String creatorId);
}

class LocalGooglePhotosRepository implements GooglePhotosRepository {
  final AppDatabase _db;

  LocalGooglePhotosRepository(this._db);

  GooglePhotosSyncEntry _toEntry(GooglePhotosSyncTableData data) {
    return GooglePhotosSyncEntry(
      mediaId: data.mediaId,
      status: GooglePhotosSyncStatus.fromString(data.status),
      creatorId: data.creatorId,
      googlePhotosMediaId: data.googlePhotosMediaId,
      uploadedAt: data.uploadedAt != null ? DateTime.tryParse(data.uploadedAt!) : null,
      errorMessage: data.errorMessage,
      retryCount: data.retryCount,
      lastAttemptAt: data.lastAttemptAt != null ? DateTime.tryParse(data.lastAttemptAt!) : null,
    );
  }

  @override
  Future<void> queueMedia(String mediaId, {required String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) {
      throw GooglePhotosIsolationException('Cannot queue Google Photos entry without authoritative creator identity.');
    }
    await _db.into(_db.googlePhotosSyncEntries).insertOnConflictUpdate(
          GooglePhotosSyncEntriesCompanion(
            mediaId: Value(mediaId),
            creatorId: Value(creatorId),
            status: const Value('pending'),
            errorMessage: const Value(null),
            retryCount: const Value(0),
            lastAttemptAt: const Value(null),
          ),
        );
  }

  @override
  Future<List<GooglePhotosSyncEntry>> getPendingOrFailedEntries({required String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) {
      return const [];
    }
    final query = _db.select(_db.googlePhotosSyncEntries)
      ..where((tbl) => tbl.creatorId.equals(creatorId) & tbl.status.isIn(['pending', 'uploading', 'failed']));
    final rows = await query.get();
    return rows.map(_toEntry).toList();
  }

  @override
  Future<GooglePhotosSyncEntry?> getEntryForMedia(String mediaId, {required String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) {
      return null;
    }
    final query = _db.select(_db.googlePhotosSyncEntries)
      ..where((tbl) => tbl.mediaId.equals(mediaId) & tbl.creatorId.equals(creatorId));
    final row = await query.getSingleOrNull();
    return row != null ? _toEntry(row) : null;
  }

  @override
  Future<void> updateStatus({
    required String mediaId,
    required String? creatorId,
    required GooglePhotosSyncStatus status,
    String? googlePhotosMediaId,
    DateTime? uploadedAt,
    String? errorMessage,
    bool incrementRetry = false,
  }) async {
    if (creatorId == null || creatorId.isEmpty) {
      throw GooglePhotosIsolationException('Cannot update Google Photos entry status without authoritative creator identity.');
    }
    final existing = await getEntryForMedia(mediaId, creatorId: creatorId);
    if (existing == null) {
      return;
    }
    final currentRetries = existing.retryCount;
    final nextRetries = incrementRetry ? currentRetries + 1 : currentRetries;

    await (_db.update(_db.googlePhotosSyncEntries)
          ..where((tbl) => tbl.mediaId.equals(mediaId) & tbl.creatorId.equals(creatorId)))
        .write(
      GooglePhotosSyncEntriesCompanion(
        status: Value(status.name),
        googlePhotosMediaId: googlePhotosMediaId != null ? Value(googlePhotosMediaId) : const Value.absent(),
        uploadedAt: uploadedAt != null ? Value(uploadedAt.toIso8601String()) : const Value.absent(),
        errorMessage: Value(errorMessage),
        retryCount: Value(nextRetries),
        lastAttemptAt: Value(DateTime.now().toIso8601String()),
      ),
    );
  }

  @override
  Future<void> deleteEntry(String mediaId, {required String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) {
      return;
    }
    await (_db.delete(_db.googlePhotosSyncEntries)
          ..where((tbl) => tbl.mediaId.equals(mediaId) & tbl.creatorId.equals(creatorId)))
        .go();
  }

  @override
  Stream<List<GooglePhotosSyncEntry>> watchAllEntries({required String? creatorId}) {
    if (creatorId == null || creatorId.isEmpty) {
      return Stream.value(const []);
    }
    return (_db.select(_db.googlePhotosSyncEntries)
          ..where((tbl) => tbl.creatorId.equals(creatorId)))
        .watch()
        .map((rows) => rows.map(_toEntry).toList());
  }

  @override
  Future<int> countByStatus(GooglePhotosSyncStatus status, {required String? creatorId}) async {
    if (creatorId == null || creatorId.isEmpty) {
      return 0;
    }
    final query = _db.select(_db.googlePhotosSyncEntries)
      ..where((tbl) => tbl.creatorId.equals(creatorId) & tbl.status.equals(status.name));
    final rows = await query.get();
    return rows.length;
  }

  @override
  Future<void> clearQueueForCreator(String creatorId) async {
    if (creatorId.isEmpty) return;
    await (_db.delete(_db.googlePhotosSyncEntries)
          ..where((tbl) => tbl.creatorId.equals(creatorId)))
        .go();
  }
}
