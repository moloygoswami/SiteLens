import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'app_database.g.dart';

// Table 1: Sites (architecture.md Section 11)
@DataClassName('SiteEntry')
class Sites extends Table {
  TextColumn get id => text()();
  TextColumn get siteCode => text().nullable().named('site_code')();
  TextColumn get name => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get creatorId => text().nullable().named('creator_id')(); // Creator user UID for per-user site scoping — Added in v7

  @override
  Set<Column> get primaryKey => {id};
}

// Table 2: Media (architecture.md Section 11 & Milestone M2.6)
@DataClassName('MediaEntry')
class Media extends Table {
  TextColumn get id => text()();
  TextColumn get siteId => text().nullable().named('site_id').references(Sites, #id)();
  TextColumn get originalUri => text().withDefault(const Constant('')).named('original_uri')(); // Added in v2
  TextColumn get uri => text()();
  TextColumn get thumbUri => text().nullable().named('thumb_uri')();
  TextColumn get type => text().nullable()(); // 'photo' or 'video'
  RealColumn get lat => real()();
  RealColumn get lon => real()();
  RealColumn get accuracyM => real().nullable().named('accuracy_m')();
  IntColumn get lowAccuracy => integer().withDefault(const Constant(0)).named('low_accuracy')();
  RealColumn get altitudeM => real().nullable().named('altitude_m')(); // Real capture elevation — Added in v7 (vuln-0002)
  TextColumn get activityTag => text().nullable().named('activity_tag')();
  TextColumn get observationType => text().nullable().named('observation_type')();
  TextColumn get linkedMediaId => text().nullable().named('linked_media_id').references(Media, #id)();
  TextColumn get note => text().nullable()();
  TextColumn get capturedAt => text().named('captured_at')();
  TextColumn get sha256Hash => text().nullable().named('sha256_hash')(); // SHA-256 of orig_<id> (immutable original)
  TextColumn get evidenceSha256Hash => text().nullable().named('evidence_sha256_hash')(); // SHA-256 of evid_<id> (watermarked evidence) — Added in v3
  TextColumn get capturedAddress => text().nullable().named('captured_address')(); // Reverse-geocoded physical address at capture time — Added in v4
  TextColumn get creatorId => text().nullable().named('creator_id')(); // Creator user ID — Added in v5
  IntColumn get synced => integer().withDefault(const Constant(0))();
  IntColumn get isDeleted => integer().withDefault(const Constant(0)).named('is_deleted')(); // soft delete

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [];

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (site_id) REFERENCES sites(id)',
    'FOREIGN KEY (linked_media_id) REFERENCES media(id)',
  ];
}

// Table 3: GooglePhotosSyncEntries (Google Photos Auto-Sync Subsystem)
@DataClassName('GooglePhotosSyncTableData')
class GooglePhotosSyncEntries extends Table {
  TextColumn get mediaId => text().named('media_id').references(Media, #id)();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get googlePhotosMediaId => text().nullable().named('google_photos_media_id')();
  TextColumn get uploadedAt => text().nullable().named('uploaded_at')();
  TextColumn get errorMessage => text().nullable().named('error_message')();
  IntColumn get retryCount => integer().withDefault(const Constant(0)).named('retry_count')();
  TextColumn get lastAttemptAt => text().nullable().named('last_attempt_at')();

  @override
  Set<Column> get primaryKey => {mediaId};

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (media_id) REFERENCES media(id) ON DELETE CASCADE',
  ];
}

@DriftDatabase(tables: [Sites, Media, GooglePhotosSyncEntries])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      // Add custom indexes defined in frozen architecture v1.0
      await customStatement('CREATE INDEX IF NOT EXISTS idx_media_lat ON media(lat);');
      await customStatement('CREATE INDEX IF NOT EXISTS idx_media_lon ON media(lon);');
      await customStatement('CREATE INDEX IF NOT EXISTS idx_media_site ON media(site_id);');
      await customStatement('CREATE INDEX IF NOT EXISTS idx_media_obs ON media(observation_type);');
      await customStatement('CREATE INDEX IF NOT EXISTS idx_media_captured ON media(captured_at);');
      await customStatement('CREATE INDEX IF NOT EXISTS idx_gphotos_status ON google_photos_sync_entries(status);');
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await m.addColumn(media, media.originalUri);
      }
      if (from < 3) {
        // v3: persist evidence (watermarked) SHA-256 independently of original hash
        await m.addColumn(media, media.evidenceSha256Hash);
      }
      if (from < 4) {
        // v4: persist reverse-geocoded physical address at capture time
        await m.addColumn(media, media.capturedAddress);
      }
      if (from < 5) {
        // v5: persist creator UID for multi-user sync authorization
        await m.addColumn(media, media.creatorId);
      }
      if (from < 6) {
        // v6: Google Photos Sync Table & Index
        await m.createTable(googlePhotosSyncEntries);
        await customStatement('CREATE INDEX IF NOT EXISTS idx_gphotos_status ON google_photos_sync_entries(status);');
      }
      if (from < 7) {
        // v7: persist real capture elevation and site creator UID (remediates vuln-0002 & vuln-0003)
        await m.addColumn(media, media.altitudeM);
        await m.addColumn(sites, sites.creatorId);
      }
    },
  );

  /// Purges all local user data across all tables during account deletion.
  Future<void> clearAllUserData() async {
    await transaction(() async {
      await delete(googlePhotosSyncEntries).go();
      await delete(media).go();
      await delete(sites).go();
    });
  }

  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      final dbFolder = await getApplicationDocumentsDirectory();
      final file = File(p.join(dbFolder.path, 'sitelens_local.db'));
      return NativeDatabase.createInBackground(file);
    });
  }
}
