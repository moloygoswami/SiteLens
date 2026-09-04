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

abstract class GooglePhotosRepository {
  Future<void> queueMedia(String mediaId);
  Future<List<GooglePhotosSyncEntry>> getPendingOrFailedEntries();
  Future<GooglePhotosSyncEntry?> getEntryForMedia(String mediaId);
  Future<void> updateStatus({
    required String mediaId,
    required GooglePhotosSyncStatus status,
    String? googlePhotosMediaId,
    DateTime? uploadedAt,
    String? errorMessage,
    bool incrementRetry = false,
  });
  Future<void> deleteEntry(String mediaId);
  Stream<List<GooglePhotosSyncEntry>> watchAllEntries();
  Future<int> countByStatus(GooglePhotosSyncStatus status);
}

class LocalGooglePhotosRepository implements GooglePhotosRepository {
  final AppDatabase _db;

  LocalGooglePhotosRepository(this._db);

  GooglePhotosSyncEntry _toEntry(GooglePhotosSyncTableData data) {
    return GooglePhotosSyncEntry(
      mediaId: data.mediaId,
      status: GooglePhotosSyncStatus.fromString(data.status),
      googlePhotosMediaId: data.googlePhotosMediaId,
      uploadedAt: data.uploadedAt != null ? DateTime.tryParse(data.uploadedAt!) : null,
      errorMessage: data.errorMessage,
      retryCount: data.retryCount,
      lastAttemptAt: data.lastAttemptAt != null ? DateTime.tryParse(data.lastAttemptAt!) : null,
    );
  }

  @override
  Future<void> queueMedia(String mediaId) async {
    await _db.into(_db.googlePhotosSyncEntries).insertOnConflictUpdate(
          GooglePhotosSyncEntriesCompanion(
            mediaId: Value(mediaId),
            status: const Value('pending'),
            errorMessage: const Value(null),
            retryCount: const Value(0),
            lastAttemptAt: const Value(null),
          ),
        );
  }

  @override
  Future<List<GooglePhotosSyncEntry>> getPendingOrFailedEntries() async {
    final query = _db.select(_db.googlePhotosSyncEntries)
      ..where((tbl) => tbl.status.isIn(['pending', 'uploading', 'failed']));
    final rows = await query.get();
    return rows.map(_toEntry).toList();
  }

  @override
  Future<GooglePhotosSyncEntry?> getEntryForMedia(String mediaId) async {
    final query = _db.select(_db.googlePhotosSyncEntries)
      ..where((tbl) => tbl.mediaId.equals(mediaId));
    final row = await query.getSingleOrNull();
    return row != null ? _toEntry(row) : null;
  }

  @override
  Future<void> updateStatus({
    required String mediaId,
    required GooglePhotosSyncStatus status,
    String? googlePhotosMediaId,
    DateTime? uploadedAt,
    String? errorMessage,
    bool incrementRetry = false,
  }) async {
    final existing = await getEntryForMedia(mediaId);
    final currentRetries = existing?.retryCount ?? 0;
    final nextRetries = incrementRetry ? currentRetries + 1 : currentRetries;

    await (_db.update(_db.googlePhotosSyncEntries)
          ..where((tbl) => tbl.mediaId.equals(mediaId)))
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
  Future<void> deleteEntry(String mediaId) async {
    await (_db.delete(_db.googlePhotosSyncEntries)
          ..where((tbl) => tbl.mediaId.equals(mediaId)))
        .go();
  }

  @override
  Stream<List<GooglePhotosSyncEntry>> watchAllEntries() {
    return _db.select(_db.googlePhotosSyncEntries).watch().map((rows) => rows.map(_toEntry).toList());
  }

  @override
  Future<int> countByStatus(GooglePhotosSyncStatus status) async {
    final query = _db.select(_db.googlePhotosSyncEntries)
      ..where((tbl) => tbl.status.equals(status.name));
    final rows = await query.get();
    return rows.length;
  }
}
