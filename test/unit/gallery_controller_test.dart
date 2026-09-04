import 'dart:ffi';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/open.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/data/repositories/site_repository.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/site_model.dart';
import 'package:sitelens/features/gallery/controllers/gallery_controller.dart';
import 'package:sitelens/features/sites/site_controller.dart';

void main() {
  late AppDatabase db;
  late MediaRepository mediaRepo;
  late ProviderContainer container;

  const testSite = SiteModel(
    id: 'site-alpha',
    siteCode: 'SL-001',
    name: 'Sector Alpha',
    address: '100 Construction Way',
  );

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'sitelens_active_site_id': 'site-alpha'});
    db = AppDatabase(NativeDatabase.memory());
    mediaRepo = LocalMediaRepository(db);

    container = ProviderContainer(
      overrides: [
        mediaRepositoryProvider.overrideWithValue(mediaRepo),
        siteControllerProvider.overrideWith(
          (ref) => SiteController(MockSiteRepository(testSite)),
        ),
      ],
    );
    // Keep listener alive
    container.listen(filteredGalleryMediaProvider, (_, __) {});
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> seedTestMedia() async {
    // 1. Photo - Progress
    await db.into(db.media).insert(
          MediaCompanion.insert(
            id: 'm1',
            siteId: const drift.Value('site-alpha'),
            type: const drift.Value('photo'),
            uri: 'media/evid_m1.jpg',
            originalUri: const drift.Value('media/orig_m1.jpg'),
            thumbUri: const drift.Value('media/thumb_m1.jpg'),
            capturedAt: '2026-08-15T10:00:00.000Z',
            lat: 22.56298,
            lon: 88.30085,
            accuracyM: const drift.Value(3.5),
            lowAccuracy: const drift.Value(0),
            activityTag: const drift.Value('Excavation'),
            observationType: const drift.Value('progress'),
            note: const drift.Value('Foundation trench excavation'),
            sha256Hash: const drift.Value('a1b2c3d4e5f60000000000000000000000000000000000000000000000000001'),
          ),
        );

    // 2. Photo - NonConformity (Before)
    await db.into(db.media).insert(
          MediaCompanion.insert(
            id: 'm2',
            siteId: const drift.Value('site-alpha'),
            type: const drift.Value('photo'),
            uri: 'media/evid_m2.jpg',
            originalUri: const drift.Value('media/orig_m2.jpg'),
            thumbUri: const drift.Value('media/thumb_m2.jpg'),
            capturedAt: '2026-08-15T11:00:00.000Z',
            lat: 22.56298,
            lon: 88.30085,
            accuracyM: const drift.Value(4.0),
            lowAccuracy: const drift.Value(0),
            activityTag: const drift.Value('Rebar'),
            observationType: const drift.Value('nonConformity'),
            note: const drift.Value('Missing tie wire at intersection'),
            sha256Hash: const drift.Value('a1b2c3d4e5f60000000000000000000000000000000000000000000000000002'),
          ),
        );

    // 3. Video - Material
    await db.into(db.media).insert(
          MediaCompanion.insert(
            id: 'm3',
            siteId: const drift.Value('site-alpha'),
            type: const drift.Value('video'),
            uri: 'media/evid_m3.jpg',
            originalUri: const drift.Value('media/orig_m3.mp4'),
            thumbUri: const drift.Value('media/thumb_m3.jpg'),
            capturedAt: '2026-08-14T15:00:00.000Z',
            lat: 22.56298,
            lon: 88.30085,
            accuracyM: const drift.Value(25.0),
            lowAccuracy: const drift.Value(1),
            activityTag: const drift.Value('Batching'),
            observationType: const drift.Value('material'),
            note: const drift.Value('Cement slump test recording'),
            sha256Hash: const drift.Value('a1b2c3d4e5f60000000000000000000000000000000000000000000000000003'),
          ),
        );

    // 4. Deleted Photo (Should be excluded)
    await db.into(db.media).insert(
          MediaCompanion.insert(
            id: 'm4_deleted',
            siteId: const drift.Value('site-alpha'),
            type: const drift.Value('photo'),
            uri: 'media/evid_m4.jpg',
            originalUri: const drift.Value('media/orig_m4.jpg'),
            thumbUri: const drift.Value('media/thumb_m4.jpg'),
            capturedAt: '2026-08-15T12:00:00.000Z',
            lat: 22.56298,
            lon: 88.30085,
            accuracyM: const drift.Value(2.0),
            lowAccuracy: const drift.Value(0),
            activityTag: const drift.Value('PCC'),
            observationType: const drift.Value('general'),
            note: const drift.Value('Should not show up'),
            isDeleted: const drift.Value(1),
            sha256Hash: const drift.Value('a1b2c3d4e5f60000000000000000000000000000000000000000000000000004'),
          ),
        );
  }

  group('GalleryController Unit Tests', () {
    test('Empty dataset returns 0 items', () async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final items = await container.read(filteredGalleryMediaProvider.future);
      expect(items, isEmpty);
    });

    test('Loads active items and strictly excludes is_deleted = 1 items', () async {
      await seedTestMedia();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final items = await container.read(filteredGalleryMediaProvider.future);
      expect(items.length, equals(3));
      expect(items.any((i) => i.id == 'm4_deleted'), isFalse);
    });

    test('Filters by Observation Type', () async {
      await seedTestMedia();
      container.read(galleryFilterProvider.notifier).setObservationType(ObservationType.nonConformity);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      
      final items = await container.read(filteredGalleryMediaProvider.future);
      expect(items.length, equals(1));
      expect(items.first.id, equals('m2'));
      expect(items.first.observationType, equals(ObservationType.nonConformity));
    });

    test('Filters by Activity / Work Stage', () async {
      await seedTestMedia();
      container.read(galleryFilterProvider.notifier).setActivityTag('Batching');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      
      final items = await container.read(filteredGalleryMediaProvider.future);
      expect(items.length, equals(1));
      expect(items.first.id, equals('m3'));
      expect(items.first.activityTag, equals('Batching'));
    });

    test('Filters by Low GPS Accuracy (>20m)', () async {
      await seedTestMedia();
      container.read(galleryFilterProvider.notifier).toggleLowAccuracyOnly();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      
      final items = await container.read(filteredGalleryMediaProvider.future);
      expect(items.length, equals(1));
      expect(items.first.id, equals('m3'));
      expect(items.first.lowAccuracy, isTrue);
    });

    test('Filters by Metadata Search (matching notes, tag, or id)', () async {
      await seedTestMedia();
      container.read(galleryFilterProvider.notifier).setSearchQuery('tie wire');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      
      final items = await container.read(filteredGalleryMediaProvider.future);
      expect(items.length, equals(1));
      expect(items.first.id, equals('m2'));
      expect(items.first.note, contains('tie wire'));
    });

    test('Filters by Date Range', () async {
      await seedTestMedia();
      container.read(galleryFilterProvider.notifier).setDateRange(
            DateTimeRange(
              start: DateTime(2026, 8, 14),
              end: DateTime(2026, 8, 14),
            ),
          );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      
      final items = await container.read(filteredGalleryMediaProvider.future);
      expect(items.length, equals(1));
      expect(items.first.id, equals('m3'));
    });

    test('Combined multi-facet filter returns intersection', () async {
      await seedTestMedia();
      final notifier = container.read(galleryFilterProvider.notifier);
      notifier.setObservationType(ObservationType.progress);
      notifier.setActivityTag('Excavation');
      notifier.setSearchQuery('trench');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      
      final items = await container.read(filteredGalleryMediaProvider.future);
      expect(items.length, equals(1));
      expect(items.first.id, equals('m1'));
    });

    test('Soft delete operation updates is_deleted and hides from gallery', () async {
      await seedTestMedia();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      var items = await container.read(filteredGalleryMediaProvider.future);
      expect(items.length, equals(3));

      // Soft delete m1
      await mediaRepo.softDeleteMedia('m1');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      
      items = await container.read(filteredGalleryMediaProvider.future);
      expect(items.length, equals(2));
      expect(items.any((i) => i.id == 'm1'), isFalse);

      // Verify Drift DB record directly: row exists with is_deleted = 1
      final rawMedia = await (db.select(db.media)..where((t) => t.id.equals('m1'))).getSingle();
      expect(rawMedia.isDeleted, equals(1));
    });
  });
}

class MockSiteRepository implements SiteRepository {
  final SiteModel site;
  MockSiteRepository(this.site);

  @override
  Future<List<SiteModel>> getAllSites({String? creatorId}) async => [site];

  @override
  Future<SiteModel?> getSiteById(String id) async => site.id == id ? site : null;

  @override
  Future<void> saveSite(SiteModel site) async {}

  @override
  Future<void> deleteSite(String id) async {}

  @override
  Future<void> seedDefaultSitesIfEmpty() async {}
}
