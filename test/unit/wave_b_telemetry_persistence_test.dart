import 'dart:ffi';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/features/camera/models/evidence_metadata_snapshot.dart';
import 'package:sitelens/features/camera/models/gps_hardware_state.dart';

/// Wave B (R09 audio disclosure, R10 unknown telemetry semantics) persistence
/// and snapshot coverage.
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  group('Wave B R09/R10 telemetry persistence', () {
    late AppDatabase db;
    late MediaRepository repo;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      repo = LocalMediaRepository(db);
      await db.into(db.sites).insert(
            SitesCompanion.insert(
              id: 'S1',
              siteCode: const drift.Value('SC'),
              name: const drift.Value('Site'),
              creatorId: const drift.Value('user-1'),
            ),
          );
    });

    tearDown(() async {
      await db.close();
    });

    test('R09/R10: audio-track presence and compass heading round-trip through Drift', () async {
      await repo.insertMedia(MediaItem(
        id: 'm-audio-heading',
        siteId: 'S1',
        originalUri: 'media/orig_a.mp4',
        uri: 'media/evid_a.mp4',
        type: MediaItemType.video,
        lat: 22.5,
        lon: 88.3,
        capturedAt: DateTime.utc(2026, 9, 18, 10),
        creatorId: 'user-1',
        hasAudioTrack: true,
        headingDegrees: 123.4,
      ));

      final stored = await repo.getMediaById('m-audio-heading');
      expect(stored, isNotNull);
      expect(stored!.hasAudioTrack, isTrue);
      expect(stored.headingDegrees, 123.4);
    });

    test('R09/R10: unknown audio/heading persist as NULL — never a fabricated default', () async {
      await repo.insertMedia(MediaItem(
        id: 'm-unknown-telemetry',
        siteId: 'S1',
        originalUri: 'media/orig_b.mp4',
        uri: 'media/evid_b.mp4',
        type: MediaItemType.video,
        lat: 22.5,
        lon: 88.3,
        capturedAt: DateTime.utc(2026, 9, 18, 10),
        creatorId: 'user-1',
        // hasAudioTrack / headingDegrees never established by the device
      ));

      final stored = await repo.getMediaById('m-unknown-telemetry');
      expect(stored!.hasAudioTrack, isNull);
      expect(stored.headingDegrees, isNull);

      // The v10 columns are nullable with NO default: a row written without them
      // reads back as unknown rather than 0/false (no unsafe migration default).
      final raw = await (db.select(db.media)
            ..where((t) => t.id.equals('m-unknown-telemetry')))
          .getSingle();
      expect(raw.hasAudioTrack, isNull);
      expect(raw.headingDegrees, isNull);
    });

    test('R09: a video snapshot discloses audio presence; a photo snapshot leaves it unknown', () {
      const gps = GpsHardwareState(
        hasValidFix: true,
        latitude: 22.5,
        longitude: 88.3,
        accuracyMeters: 3.0,
        headingDegrees: 42.0,
      );

      final video = EvidenceMetadataSnapshot.capture(
        gpsState: gps,
        siteId: 'S1',
        siteCode: 'SC',
        siteName: 'Site',
        customCaptureTimeUtc: DateTime.utc(2026, 9, 18, 10),
        hasAudioTrack: false,
      );
      expect(video.hasAudioTrack, isFalse);
      expect(video.headingDegrees, 42.0);

      final photo = EvidenceMetadataSnapshot.capture(
        gpsState: gps,
        siteId: 'S1',
        siteCode: 'SC',
        siteName: 'Site',
        customCaptureTimeUtc: DateTime.utc(2026, 9, 18, 10),
      );
      expect(photo.hasAudioTrack, isNull);
    });

    test('R09/R10: the adopted schema version is 10 (audio + heading columns)', () {
      expect(db.schemaVersion, 10);
    });
  });
}
