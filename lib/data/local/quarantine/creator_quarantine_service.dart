import 'package:drift/drift.dart' as drift;
import '../../../domain/models/media_item.dart';
import '../../../domain/models/site_model.dart';
import '../database/app_database.dart';

enum QuarantineStatus {
  active,
  quarantined,
}

class CreatorQuarantineClassification {
  final QuarantineStatus status;
  final String? reason;

  const CreatorQuarantineClassification.active()
      : status = QuarantineStatus.active,
        reason = null;

  const CreatorQuarantineClassification.quarantined(this.reason)
      : status = QuarantineStatus.quarantined;

  bool get isQuarantined => status == QuarantineStatus.quarantined;
  bool get isActive => status == QuarantineStatus.active;
}

/// Manages fail-closed creator quarantine semantics conforming to:
/// - 02_ARCHITECTURE.MD §11.2 & §11.3
/// - 04_SECURITY.MD §3
/// - 05_ACCEPTANCE.MD AC-OWN-05
/// - 06_TESTING.MD TM-U-02
class CreatorQuarantineService {
  final AppDatabase _db;

  CreatorQuarantineService(this._db);

  /// Deterministically classifies any record based on its creator identity.
  /// A record whose creator cannot be resolved MUST be classified as quarantined
  /// and must NEVER be auto-attributed to a current user identity.
  static CreatorQuarantineClassification classifyRecord({String? creatorId}) {
    if (creatorId == null || creatorId.trim().isEmpty) {
      return const CreatorQuarantineClassification.quarantined(
        'Unattributed record: creator_id is missing or empty',
      );
    }
    return const CreatorQuarantineClassification.active();
  }

  /// Ensures that quarantine storage exists in the SQLite database.
  Future<void> ensureTablesExist() async {
    await _db.ensureQuarantineTablesExist();
  }

  /// Quarantines an unattributed or legacy site into the separate, non-queried
  /// `quarantined_sites` table, preserving the option of recovery without
  /// exposing it to creator-scoped queries.
  Future<void> quarantineSite(SiteModel site, {String? reason}) async {
    final classification = classifyRecord(creatorId: site.creatorId);
    if (!classification.isQuarantined) {
      throw ArgumentError('Cannot quarantine site with valid creator_id: ${site.creatorId}');
    }

    await ensureTablesExist();

    await _db.transaction(() async {
      await _db.customStatement(
        'INSERT OR REPLACE INTO quarantined_sites (id, site_code, name, address, quarantined_at, reason) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        [
          site.id,
          site.siteCode,
          site.name,
          site.address,
          DateTime.now().toUtc().toIso8601String(),
          reason ?? classification.reason ?? 'Missing creator_id',
        ],
      );

      // Remove from active sites table so it is never returned by active queries
      await (_db.delete(_db.sites)..where((tbl) => tbl.id.equals(site.id))).go();
    });
  }

  /// Quarantines an unattributed or legacy media record into the separate,
  /// non-queried `quarantined_media` table.
  Future<void> quarantineMedia(MediaItem media, {String? reason}) async {
    final classification = classifyRecord(creatorId: media.creatorId);
    if (!classification.isQuarantined) {
      throw ArgumentError('Cannot quarantine media with valid creator_id: ${media.creatorId}');
    }

    await ensureTablesExist();

    await _db.transaction(() async {
      await _db.customStatement(
        'INSERT OR REPLACE INTO quarantined_media (id, site_id, uri, captured_at, quarantined_at, reason) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        [
          media.id,
          media.siteId,
          media.uri,
          media.capturedAt.toUtc().toIso8601String(),
          DateTime.now().toUtc().toIso8601String(),
          reason ?? classification.reason ?? 'Missing creator_id',
        ],
      );

      // Remove from active media table so it is never returned by active queries
      await (_db.delete(_db.media)..where((tbl) => tbl.id.equals(media.id))).go();
    });
  }

  /// Verifies whether a site with [id] is in the quarantine table.
  Future<bool> isSiteQuarantined(String id) async {
    await ensureTablesExist();
    final result = await _db.customSelect(
      'SELECT id FROM quarantined_sites WHERE id = ?',
      variables: [drift.Variable.withString(id)],
    ).getSingleOrNull();
    return result != null;
  }

  /// Verifies whether a media item with [id] is in the quarantine table.
  Future<bool> isMediaQuarantined(String id) async {
    await ensureTablesExist();
    final result = await _db.customSelect(
      'SELECT id FROM quarantined_media WHERE id = ?',
      variables: [drift.Variable.withString(id)],
    ).getSingleOrNull();
    return result != null;
  }

  /// Sweeps all un-attributed rows (`creator_id IS NULL OR creator_id = ''`) from
  /// active tables into quarantine tables.
  Future<int> sweepUnattributedRecords() async {
    await ensureTablesExist();
    int count = 0;

    await _db.transaction(() async {
      // 1. Unattributed sites
      final siteRows = await _db.customSelect(
        'SELECT id, site_code, name, address FROM sites WHERE creator_id IS NULL OR creator_id = ""',
      ).get();

      for (final row in siteRows) {
        final id = row.read<String>('id');
        final siteCode = row.readNullable<String>('site_code') ?? '';
        final name = row.readNullable<String>('name') ?? '';
        final address = row.readNullable<String>('address') ?? '';

        await _db.customStatement(
          'INSERT OR REPLACE INTO quarantined_sites (id, site_code, name, address, quarantined_at, reason) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          [
            id,
            siteCode,
            name,
            address,
            DateTime.now().toUtc().toIso8601String(),
            'Sweep: Legacy or unattributed site record',
          ],
        );
        await (_db.delete(_db.sites)..where((tbl) => tbl.id.equals(id))).go();
        count++;
      }

      // 2. Unattributed media
      final mediaRows = await _db.customSelect(
        'SELECT id, site_id, uri, captured_at FROM media WHERE creator_id IS NULL OR creator_id = ""',
      ).get();

      for (final row in mediaRows) {
        final id = row.read<String>('id');
        final siteId = row.readNullable<String>('site_id') ?? '';
        final uri = row.read<String>('uri');
        final capturedAt = row.readNullable<String>('captured_at') ?? DateTime.now().toUtc().toIso8601String();

        await _db.customStatement(
          'INSERT OR REPLACE INTO quarantined_media (id, site_id, uri, captured_at, quarantined_at, reason) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          [
            id,
            siteId,
            uri,
            capturedAt,
            DateTime.now().toUtc().toIso8601String(),
            'Sweep: Legacy or unattributed media record',
          ],
        );
        await (_db.delete(_db.media)..where((tbl) => tbl.id.equals(id))).go();
        count++;
      }
    });

    return count;
  }
}
