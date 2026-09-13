import 'dart:ffi';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sitelens/core/utils/haversine.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/features/nearby/controllers/nearby_search_controller.dart';
import 'package:sitelens/features/nearby/models/nearby_search_state.dart';

void main() {
  late AppDatabase db;
  late MediaRepository mediaRepo;

  final testSiteA = 'site-101';
  final testSiteB = 'site-202';
  final centerLat = 22.56400;
  final centerLon = 88.30000;

  setUpAll(() {
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  final sourceItem = MediaItem(
    id: 'source-1',
    siteId: testSiteA,
    originalUri: 'media/orig_source1.jpg',
    uri: 'media/evid_source1.jpg',
    thumbUri: 'media/thumb_source1.jpg',
    type: MediaItemType.photo,
    lat: centerLat,
    lon: centerLon,
    accuracyM: 2.5,
    lowAccuracy: false,
    activityTag: 'Excavation',
    observationType: ObservationType.nonConformity,
    linkedMediaId: null,
    note: 'Open trench hazard',
    capturedAt: DateTime.utc(2026, 8, 15, 10, 0, 0),
    sha256Hash: 'hash-source-1',
    evidenceSha256Hash: 'evid-hash-source-1',
    capturedAddress: 'Shibpur, Howrah',
    creatorId: 'user-A',
    syncStatus: SyncStatusType.pending,
    isDeleted: false,
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    mediaRepo = LocalMediaRepository(db);

    // Seed test sites
    await db.into(db.sites).insert(
          SitesCompanion.insert(
            id: testSiteA,
            siteCode: const drift.Value('101'),
            name: const drift.Value('Test Site Alpha'),
            address: const drift.Value('123 Main Road'),
          ),
        );
    await db.into(db.sites).insert(
          SitesCompanion.insert(
            id: testSiteB,
            siteCode: const drift.Value('202'),
            name: const drift.Value('Test Site Beta'),
            address: const drift.Value('456 Cross Street'),
          ),
        );

    // Seed source item
    await mediaRepo.insertMedia(sourceItem);
  });

  tearDown(() async {
    await db.close();
  });

  group('M5.1 Spatial Query & Search Controller Unit Tests', () {
    // 1. Exact center point (0m distance)
    test('1. Exact center point returns 0.0m distance correctly', () async {
      await mediaRepo.insertMedia(MediaItem(
        id: 'item-exact-center',
        siteId: testSiteA,
        originalUri: 'media/orig_center.jpg',
        uri: 'media/evid_center.jpg',
        thumbUri: 'media/thumb_center.jpg',
        type: MediaItemType.photo,
        lat: centerLat,
        lon: centerLon,
        accuracyM: 1.0,
        lowAccuracy: false,
        activityTag: 'Survey',
        observationType: ObservationType.general,
        linkedMediaId: null,
        note: 'Center point monument',
        capturedAt: DateTime.utc(2026, 8, 15, 10, 30, 0),
        creatorId: 'user-A',
        sha256Hash: 'hash-center',
        evidenceSha256Hash: 'evid-hash-center',
        capturedAddress: 'Shibpur, Howrah',
        syncStatus: SyncStatusType.pending,
        isDeleted: false,
      ));

      final controller = NearbySearchNotifier(
        mediaRepo,
        sourceMedia: sourceItem,
        initialRadiusMeters: 10.0,
      );

      await Future.delayed(const Duration(milliseconds: 50));
      final results = controller.state.results;

      expect(results.length, equals(1));
      expect(results.first.item.id, equals('item-exact-center'));
      expect(results.first.distanceMeters, closeTo(0.0, 0.01));
    });

    // 2. Media inside radius
    test('2. Media inside radius is included in search results', () async {
      // 5 meters north offset
      await mediaRepo.insertMedia(MediaItem(
        id: 'item-inside-5m',
        siteId: testSiteA,
        originalUri: 'media/orig_5m.jpg',
        uri: 'media/evid_5m.jpg',
        thumbUri: 'media/thumb_5m.jpg',
        type: MediaItemType.photo,
        lat: centerLat + (5.0 / 111320.0),
        lon: centerLon,
        accuracyM: 2.0,
        lowAccuracy: false,
        activityTag: 'Excavation',
        observationType: ObservationType.progress,
        linkedMediaId: null,
        note: 'Trench north side',
        capturedAt: DateTime.utc(2026, 8, 15, 11, 0, 0),
        creatorId: 'user-A',
        sha256Hash: 'hash-5m',
        evidenceSha256Hash: 'evid-hash-5m',
        capturedAddress: 'Shibpur, Howrah',
        syncStatus: SyncStatusType.pending,
        isDeleted: false,
      ));

      final controller = NearbySearchNotifier(
        mediaRepo,
        sourceMedia: sourceItem,
        initialRadiusMeters: 10.0,
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(controller.state.results.length, equals(1));
      expect(controller.state.results.first.item.id, equals('item-inside-5m'));
      expect(controller.state.results.first.distanceMeters, closeTo(5.0, 0.2));
    });

    // 3. Media outside radius
    test('3. Media outside radius is excluded from search results', () async {
      // 15 meters north offset (outside 10m radius)
      await mediaRepo.insertMedia(MediaItem(
        id: 'item-outside-15m',
        siteId: testSiteA,
        originalUri: 'media/orig_15m.jpg',
        uri: 'media/evid_15m.jpg',
        thumbUri: 'media/thumb_15m.jpg',
        type: MediaItemType.photo,
        lat: centerLat + (15.0 / 111320.0),
        lon: centerLon,
        accuracyM: 2.0,
        lowAccuracy: false,
        activityTag: 'Excavation',
        observationType: ObservationType.progress,
        linkedMediaId: null,
        note: 'Far trench section',
        capturedAt: DateTime.utc(2026, 8, 15, 11, 0, 0),
        creatorId: 'user-A',
        sha256Hash: 'hash-15m',
        evidenceSha256Hash: 'evid-hash-15m',
        capturedAddress: 'Shibpur, Howrah',
        syncStatus: SyncStatusType.pending,
        isDeleted: false,
      ));

      final controller = NearbySearchNotifier(
        mediaRepo,
        sourceMedia: sourceItem,
        initialRadiusMeters: 10.0,
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(controller.state.results, isEmpty);
    });

    // 4. Bounding-box corner candidate rejected by exact Haversine distance
    test('4. Bounding-box corner candidate is rejected by exact Haversine refinement', () async {
      final bbox = SpatialMathUtils.calculateBoundingBox(centerLat, centerLon, 10.0);
      final deltaLat = (bbox.maxLat - centerLat) * 0.80; // 8.0m north
      final deltaLon = (bbox.maxLon - centerLon) * 0.80; // 8.0m east

      final cornerLat = centerLat + deltaLat;
      final cornerLon = centerLon + deltaLon;

      expect(bbox.contains(cornerLat, cornerLon), isTrue);

      final trueDistance = SpatialMathUtils.haversineDistanceMeters(centerLat, centerLon, cornerLat, cornerLon);
      expect(trueDistance, greaterThan(10.0));

      await mediaRepo.insertMedia(MediaItem(
        id: 'corner-candidate',
        siteId: testSiteA,
        originalUri: 'media/orig_corner.jpg',
        uri: 'media/evid_corner.jpg',
        thumbUri: 'media/thumb_corner.jpg',
        type: MediaItemType.photo,
        lat: cornerLat,
        lon: cornerLon,
        accuracyM: 1.0,
        lowAccuracy: false,
        activityTag: 'CornerTest',
        observationType: ObservationType.progress,
        linkedMediaId: null,
        note: 'Corner candidate in bounding box',
        capturedAt: DateTime.utc(2026, 8, 15, 12, 0, 0),
        creatorId: 'user-A',
        sha256Hash: 'hash-corner',
        evidenceSha256Hash: 'evid-hash-corner',
        capturedAddress: 'Shibpur, Howrah',
        syncStatus: SyncStatusType.pending,
        isDeleted: false,
      ));

      final controller = NearbySearchNotifier(
        mediaRepo,
        sourceMedia: sourceItem,
        initialRadiusMeters: 10.0,
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(controller.state.results, isEmpty);
    });

    // 5. Soft-deleted media excluded
    test('5. Soft-deleted media (is_deleted = 1) is strictly excluded', () async {
      await mediaRepo.insertMedia(MediaItem(
        id: 'deleted-item-2m',
        siteId: testSiteA,
        originalUri: 'media/orig_del.jpg',
        uri: 'media/evid_del.jpg',
        thumbUri: 'media/thumb_del.jpg',
        type: MediaItemType.photo,
        lat: centerLat + (2.0 / 111320.0),
        lon: centerLon,
        accuracyM: 1.0,
        lowAccuracy: false,
        activityTag: 'Excavation',
        observationType: ObservationType.progress,
        linkedMediaId: null,
        note: 'Deleted item 2m away',
        capturedAt: DateTime.utc(2026, 8, 15, 11, 0, 0),
        creatorId: 'user-A',
        sha256Hash: 'hash-del',
        evidenceSha256Hash: 'evid-hash-del',
        capturedAddress: 'Shibpur, Howrah',
        syncStatus: SyncStatusType.pending,
        isDeleted: true, // Marked as soft-deleted
      ));

      final controller = NearbySearchNotifier(
        mediaRepo,
        sourceMedia: sourceItem,
        initialRadiusMeters: 25.0,
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(controller.state.results.any((r) => r.item.id == 'deleted-item-2m'), isFalse);
    });

    // 6. Capture-time coordinates used instead of current GPS
    test('6. Search strictly uses historical capture-time coordinates of source media', () async {
      final historicalSource = MediaItem(
        id: 'historical-capture',
        siteId: testSiteA,
        originalUri: 'media/orig_hist.jpg',
        uri: 'media/evid_hist.jpg',
        thumbUri: 'media/thumb_hist.jpg',
        type: MediaItemType.photo,
        lat: 22.60000, // Different historical location (~4km away from centerLat)
        lon: 88.35000,
        accuracyM: 2.0,
        lowAccuracy: false,
        activityTag: 'Survey',
        observationType: ObservationType.general,
        linkedMediaId: null,
        note: 'Historical site inspection',
        capturedAt: DateTime.utc(2026, 8, 10, 10, 0, 0),
        creatorId: 'user-A',
        sha256Hash: 'hash-hist',
        evidenceSha256Hash: 'evid-hash-hist',
        capturedAddress: 'Rajarhat, Kolkata',
        syncStatus: SyncStatusType.pending,
        isDeleted: false,
      );

      final controller = NearbySearchNotifier(
        mediaRepo,
        sourceMedia: historicalSource,
        initialRadiusMeters: 25.0,
      );

      expect(controller.state.centerLat, equals(22.60000));
      expect(controller.state.centerLon, equals(88.35000));
    });

    // 7. Ascending distance sorting
    test('7. Results are sorted in ascending order of spatial distance', () async {
      // Item A: 8m away
      await mediaRepo.insertMedia(MediaItem(
        id: 'item-8m',
        siteId: testSiteA,
        originalUri: 'media/orig_8m.jpg',
        uri: 'media/evid_8m.jpg',
        thumbUri: 'media/thumb_8m.jpg',
        type: MediaItemType.photo,
        lat: centerLat + (8.0 / 111320.0),
        lon: centerLon,
        accuracyM: 2.0,
        lowAccuracy: false,
        activityTag: 'TagA',
        observationType: ObservationType.progress,
        linkedMediaId: null,
        note: '8m away',
        capturedAt: DateTime.utc(2026, 8, 15, 12, 0, 0),
        creatorId: 'user-A',
        sha256Hash: 'hash-8m',
        evidenceSha256Hash: 'evid-hash-8m',
        capturedAddress: 'Shibpur, Howrah',
        syncStatus: SyncStatusType.pending,
        isDeleted: false,
      ));

      // Item B: 3m away
      await mediaRepo.insertMedia(MediaItem(
        id: 'item-3m',
        siteId: testSiteA,
        originalUri: 'media/orig_3m.jpg',
        uri: 'media/evid_3m.jpg',
        thumbUri: 'media/thumb_3m.jpg',
        type: MediaItemType.photo,
        lat: centerLat + (3.0 / 111320.0),
        lon: centerLon,
        accuracyM: 2.0,
        lowAccuracy: false,
        activityTag: 'TagB',
        observationType: ObservationType.progress,
        linkedMediaId: null,
        note: '3m away',
        capturedAt: DateTime.utc(2026, 8, 15, 11, 0, 0),
        creatorId: 'user-A',
        sha256Hash: 'hash-3m',
        evidenceSha256Hash: 'evid-hash-3m',
        capturedAddress: 'Shibpur, Howrah',
        syncStatus: SyncStatusType.pending,
        isDeleted: false,
      ));

      final controller = NearbySearchNotifier(
        mediaRepo,
        sourceMedia: sourceItem,
        initialRadiusMeters: 25.0,
      );

      await Future.delayed(const Duration(milliseconds: 50));
      final results = controller.state.results;

      expect(results.length, equals(2));
      expect(results[0].item.id, equals('item-3m'));
      expect(results[1].item.id, equals('item-8m'));
      expect(results[0].distanceMeters, lessThan(results[1].distanceMeters));
    });

    // 8. Equal-distance secondary sorting by capturedAt (recency)
    test('8. Equal-distance items are sorted by capture time (recency) as secondary sort', () async {
      // Older item at 5m (10:00 UTC)
      await mediaRepo.insertMedia(MediaItem(
        id: 'item-5m-older',
        siteId: testSiteA,
        originalUri: 'media/orig_older.jpg',
        uri: 'media/evid_older.jpg',
        thumbUri: 'media/thumb_older.jpg',
        type: MediaItemType.photo,
        lat: centerLat + (5.0 / 111320.0),
        lon: centerLon,
        accuracyM: 1.0,
        lowAccuracy: false,
        activityTag: 'TagX',
        observationType: ObservationType.progress,
        linkedMediaId: null,
        note: 'Older 5m item',
        capturedAt: DateTime.utc(2026, 8, 15, 10, 0, 0),
        creatorId: 'user-A',
        sha256Hash: 'hash-older',
        evidenceSha256Hash: 'evid-hash-older',
        capturedAddress: 'Shibpur, Howrah',
        syncStatus: SyncStatusType.pending,
        isDeleted: false,
      ));

      // Newer item at same 5m (14:00 UTC)
      await mediaRepo.insertMedia(MediaItem(
        id: 'item-5m-newer',
        siteId: testSiteA,
        originalUri: 'media/orig_newer.jpg',
        uri: 'media/evid_newer.jpg',
        thumbUri: 'media/thumb_newer.jpg',
        type: MediaItemType.photo,
        lat: centerLat + (5.0 / 111320.0),
        lon: centerLon,
        accuracyM: 1.0,
        lowAccuracy: false,
        activityTag: 'TagX',
        observationType: ObservationType.progress,
        linkedMediaId: null,
        note: 'Newer 5m item',
        capturedAt: DateTime.utc(2026, 8, 15, 14, 0, 0),
        creatorId: 'user-A',
        sha256Hash: 'hash-newer',
        evidenceSha256Hash: 'evid-hash-newer',
        capturedAddress: 'Shibpur, Howrah',
        syncStatus: SyncStatusType.pending,
        isDeleted: false,
      ));

      final controller = NearbySearchNotifier(
        mediaRepo,
        sourceMedia: sourceItem,
        initialRadiusMeters: 25.0,
      );

      await Future.delayed(const Duration(milliseconds: 50));
      final results = controller.state.results;

      expect(results.length, equals(2));
      // Same distance, so newer item (14:00) precedes older item (10:00)
      expect(results[0].item.id, equals('item-5m-newer'));
      expect(results[1].item.id, equals('item-5m-older'));
    });

    // 9. Zero-result search
    test('9. Search with no nearby candidates returns clean empty result list without errors', () async {
      final controller = NearbySearchNotifier(
        mediaRepo,
        sourceMedia: sourceItem,
        initialRadiusMeters: 5.0, // No items seeded within 5m
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(controller.state.results, isEmpty);
      expect(controller.state.totalCount, equals(0));
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.errorMessage, isNull);
    });

    // 10. Invalid/unavailable coordinates
    test('10. Custom center coordinates update gracefully', () async {
      final controller = NearbySearchNotifier(
        mediaRepo,
        sourceMedia: null,
        defaultLat: 0.0,
        defaultLon: 0.0,
        initialRadiusMeters: 25.0,
        creatorId: 'user-A',
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(controller.state.results, isEmpty);

      // Shift to test site location
      controller.setCenter(centerLat, centerLon);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(controller.state.centerLat, equals(centerLat));
      expect(controller.state.centerLon, equals(centerLon));
    });

    // 11. Same-site filter
    test('11. Same-site filter isolates items by site ID when enabled vs disabled', () async {
      // Item on Site B at 4m away
      await mediaRepo.insertMedia(MediaItem(
        id: 'item-site-b-4m',
        siteId: testSiteB, // Different site
        originalUri: 'media/orig_siteb.jpg',
        uri: 'media/evid_siteb.jpg',
        thumbUri: 'media/thumb_siteb.jpg',
        type: MediaItemType.photo,
        lat: centerLat + (4.0 / 111320.0),
        lon: centerLon,
        accuracyM: 2.0,
        lowAccuracy: false,
        activityTag: 'Excavation',
        observationType: ObservationType.progress,
        linkedMediaId: null,
        note: 'Site B progress',
        capturedAt: DateTime.utc(2026, 8, 15, 11, 0, 0),
        creatorId: 'user-A',
        sha256Hash: 'hash-siteb',
        evidenceSha256Hash: 'evid-hash-siteb',
        capturedAddress: 'Shibpur, Howrah',
        syncStatus: SyncStatusType.pending,
        isDeleted: false,
      ));

      // Item on Site A at 4m away
      await mediaRepo.insertMedia(MediaItem(
        id: 'item-site-a-4m',
        siteId: testSiteA, // Same site as sourceItem
        originalUri: 'media/orig_sitea.jpg',
        uri: 'media/evid_sitea.jpg',
        thumbUri: 'media/thumb_sitea.jpg',
        type: MediaItemType.photo,
        lat: centerLat + (4.0 / 111320.0),
        lon: centerLon,
        accuracyM: 2.0,
        lowAccuracy: false,
        activityTag: 'Excavation',
        observationType: ObservationType.progress,
        linkedMediaId: null,
        note: 'Site A progress',
        capturedAt: DateTime.utc(2026, 8, 15, 11, 0, 0),
        creatorId: 'user-A',
        sha256Hash: 'hash-sitea',
        evidenceSha256Hash: 'evid-hash-sitea',
        capturedAddress: 'Shibpur, Howrah',
        syncStatus: SyncStatusType.pending,
        isDeleted: false,
      ));

      // With sameSiteOnly = true (default)
      final controller = NearbySearchNotifier(
        mediaRepo,
        sourceMedia: sourceItem, // siteId: site-101
        initialRadiusMeters: 25.0,
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(controller.state.results.length, equals(1));
      expect(controller.state.results.first.item.id, equals('item-site-a-4m'));

      // Toggling sameSiteOnly = false should return both Site A and Site B
      controller.setFilters(const NearbySearchFilters(sameSiteOnly: false));
      await Future.delayed(const Duration(milliseconds: 50));

      expect(controller.state.results.length, equals(2));
      expect(controller.state.results.map((r) => r.item.id), containsAll(['item-site-a-4m', 'item-site-b-4m']));
    });

    // 12. Existing M3 smart-link behavior remains unchanged
    test('12. Existing M3 smart-link search operates authoritatively via repository', () async {
      // Seed a candidate for M3 linking
      await mediaRepo.insertMedia(MediaItem(
        id: 'm3-candidate-nonconformity',
        siteId: testSiteA,
        originalUri: 'media/orig_nc.jpg',
        uri: 'media/evid_nc.jpg',
        thumbUri: 'media/thumb_nc.jpg',
        type: MediaItemType.photo,
        lat: centerLat + (3.0 / 111320.0),
        lon: centerLon,
        accuracyM: 2.0,
        lowAccuracy: false,
        activityTag: 'Excavation',
        observationType: ObservationType.nonConformity,
        linkedMediaId: null,
        note: 'Open trench',
        capturedAt: DateTime.utc(2026, 8, 15, 9, 0, 0),
        creatorId: 'user-A',
        sha256Hash: 'hash-nc',
        evidenceSha256Hash: 'evid-hash-nc',
        capturedAddress: 'Shibpur, Howrah',
        syncStatus: SyncStatusType.pending,
        isDeleted: false,
      ));

      final match = await mediaRepo.findSuggestedBeforeMatch(
        centerLat: centerLat,
        centerLon: centerLon,
        siteId: testSiteA,
        activityTag: 'Excavation',
        radiusMeters: 10.0,
        currentMediaId: sourceItem.id, // Exclude sourceItem itself
        creatorId: 'user-A',
      );

      expect(match, isNotNull);
      expect(match!.id, equals('m3-candidate-nonconformity'));
    });

    // 13. M5.5 Active Filter Count & Individual Setters / Clearers
    test('13. Active filter count correctly counts active non-default filters', () async {
      final controller = NearbySearchNotifier(
        mediaRepo,
        sourceMedia: sourceItem,
        initialRadiusMeters: 50.0,
      );

      // Default state: sameSiteOnly=true -> 0 active filters
      expect(controller.state.filters.activeFilterCount, equals(0));
      expect(controller.state.filters.hasActiveFilters, isFalse);

      // 1. Observation filter (+1)
      controller.setObservationType(ObservationType.closed);
      expect(controller.state.filters.activeFilterCount, equals(1));
      expect(controller.state.filters.hasActiveFilters, isTrue);

      // 2. Activity filter (+1 -> total 2)
      controller.setActivityTag('Excavation');
      expect(controller.state.filters.activeFilterCount, equals(2));

      // 3. Date range filter (+1 -> total 3)
      controller.setDateRange(DateTime(2026, 8, 1), DateTime(2026, 8, 30));
      expect(controller.state.filters.activeFilterCount, equals(3));

      // 4. Disabling sameSiteOnly (+1 -> total 4)
      controller.setSameSiteOnly(false);
      expect(controller.state.filters.activeFilterCount, equals(4));

      // Clearing individual filters decrements active count
      controller.clearActivityFilter();
      expect(controller.state.filters.activeFilterCount, equals(3));
      expect(controller.state.filters.activityTag, isNull);

      controller.clearObservationTypeFilter();
      expect(controller.state.filters.activeFilterCount, equals(2));
      expect(controller.state.filters.observationType, isNull);

      controller.clearDateRangeFilter();
      expect(controller.state.filters.activeFilterCount, equals(1));
      expect(controller.state.filters.startDate, isNull);

      controller.setSameSiteOnly(true);
      expect(controller.state.filters.activeFilterCount, equals(0));
      expect(controller.state.filters.hasActiveFilters, isFalse);
    });

    // 14. M5.5 Reset Filters preserves selected spatial radius
    test('14. Resetting filters restores default filters while preserving selected spatial radius', () async {
      final controller = NearbySearchNotifier(
        mediaRepo,
        sourceMedia: sourceItem,
        initialRadiusMeters: 50.0,
      );

      // Change radius to 10m and apply multiple filters
      controller.setRadius(10.0);
      controller.setObservationType(ObservationType.nonConformity);
      controller.setActivityTag('Rebar');
      controller.setSameSiteOnly(false);

      expect(controller.state.radiusMeters, equals(10.0));
      expect(controller.state.filters.activeFilterCount, equals(3));

      // Reset all filters
      controller.resetFilters();

      expect(controller.state.filters.sameSiteOnly, isTrue);
      expect(controller.state.filters.observationType, isNull);
      expect(controller.state.filters.activityTag, isNull);
      expect(controller.state.filters.startDate, isNull);
      expect(controller.state.filters.activeFilterCount, equals(0));

      // CRITICAL PRD CONTRACT: Radius must NOT be reset!
      expect(controller.state.radiusMeters, equals(10.0));
    });

    // 15. M5.5 Date range filter handles inclusive end-of-day queries
    test('15. Date range filter includes all captures on the selected end date', () async {
      final itemOnDay = MediaItem(
        id: 'item-captured-late-evening',
        siteId: testSiteA,
        originalUri: 'media/orig_late.jpg',
        uri: 'media/evid_late.jpg',
        thumbUri: 'media/thumb_late.jpg',
        type: MediaItemType.photo,
        lat: centerLat + (2.0 / 111320.0),
        lon: centerLon,
        accuracyM: 1.0,
        lowAccuracy: false,
        activityTag: 'Finishing',
        observationType: ObservationType.progress,
        linkedMediaId: null,
        note: 'End of day progress',
        capturedAt: DateTime(2026, 8, 15, 18, 0, 0), // 6:00 PM on same calendar day
        creatorId: 'user-A',
        sha256Hash: 'hash-late',
        evidenceSha256Hash: 'evid-hash-late',
        capturedAddress: 'Shibpur, Howrah',
        syncStatus: SyncStatusType.pending,
        isDeleted: false,
      );
      await mediaRepo.insertMedia(itemOnDay);

      final controller = NearbySearchNotifier(
        mediaRepo,
        sourceMedia: sourceItem,
        initialRadiusMeters: 50.0,
      );

      // Filter exactly on 2026-08-15
      controller.setDateRange(DateTime(2026, 8, 15), DateTime(2026, 8, 15));
      await Future.delayed(const Duration(milliseconds: 50));

      // The late-evening capture on the same calendar day must be included!
      expect(controller.state.results.any((r) => r.item.id == 'item-captured-late-evening'), isTrue);
    });
  });

  group('Nearby Search Multi-User Isolation & Defense-in-Depth Tests', () {
    test('16. MUST DENY: User B nearby search does NOT return User A media', () async {
      await mediaRepo.insertMedia(MediaItem(
        id: 'item-user-A-nearby',
        siteId: testSiteA,
        originalUri: 'media/orig_A.jpg',
        uri: 'media/evid_A.jpg',
        thumbUri: 'media/thumb_A.jpg',
        type: MediaItemType.photo,
        lat: centerLat + (2.0 / 111320.0), // 2m away
        lon: centerLon,
        accuracyM: 1.0,
        lowAccuracy: false,
        activityTag: 'Excavation',
        observationType: ObservationType.progress,
        capturedAt: DateTime.utc(2026, 8, 15, 12, 0, 0),
        creatorId: 'user-A',
        syncStatus: SyncStatusType.pending,
        isDeleted: false,
      ));

      final userBController = NearbySearchNotifier(
        mediaRepo,
        sourceMedia: null,
        defaultLat: centerLat,
        defaultLon: centerLon,
        initialRadiusMeters: 50.0,
        creatorId: 'user-B',
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(userBController.state.results, isEmpty);
      expect(userBController.state.totalCount, equals(0));
    });

    test('17. MUST FAIL CLOSED: Missing or null creatorId in findNearbyMedia returns empty results', () async {
      await mediaRepo.insertMedia(MediaItem(
        id: 'item-user-A-failclosed',
        siteId: testSiteA,
        originalUri: 'media/orig_fc.jpg',
        uri: 'media/evid_fc.jpg',
        thumbUri: 'media/thumb_fc.jpg',
        type: MediaItemType.photo,
        lat: centerLat + (2.0 / 111320.0),
        lon: centerLon,
        accuracyM: 1.0,
        lowAccuracy: false,
        activityTag: 'Excavation',
        observationType: ObservationType.progress,
        capturedAt: DateTime.utc(2026, 8, 15, 12, 0, 0),
        creatorId: 'user-A',
        syncStatus: SyncStatusType.pending,
        isDeleted: false,
      ));

      // Directly call findNearbyMedia with null creatorId
      final resultsNull = await mediaRepo.findNearbyMedia(
        centerLat: centerLat,
        centerLon: centerLon,
        radiusMeters: 50.0,
        creatorId: null,
      );
      expect(resultsNull, isEmpty);

      // Directly call findNearbyMedia with empty creatorId
      final resultsEmpty = await mediaRepo.findNearbyMedia(
        centerLat: centerLat,
        centerLon: centerLon,
        radiusMeters: 50.0,
        creatorId: '',
      );
      expect(resultsEmpty, isEmpty);

      // Controller initialized with null creatorId fails closed
      final nullController = NearbySearchNotifier(
        mediaRepo,
        sourceMedia: null,
        defaultLat: centerLat,
        defaultLon: centerLon,
        initialRadiusMeters: 50.0,
        creatorId: null,
      );
      await Future.delayed(const Duration(milliseconds: 50));
      expect(nullController.state.results, isEmpty);
    });

    test('18. MUST ALLOW: User A nearby search returns User A media and excludes User B media', () async {
      await mediaRepo.insertMedia(MediaItem(
        id: 'item-A-owned',
        siteId: testSiteA,
        originalUri: 'media/orig_A_own.jpg',
        uri: 'media/evid_A_own.jpg',
        thumbUri: 'media/thumb_A_own.jpg',
        type: MediaItemType.photo,
        lat: centerLat + (2.0 / 111320.0),
        lon: centerLon,
        accuracyM: 1.0,
        lowAccuracy: false,
        activityTag: 'Excavation',
        observationType: ObservationType.progress,
        capturedAt: DateTime.utc(2026, 8, 15, 12, 0, 0),
        creatorId: 'user-A',
        syncStatus: SyncStatusType.pending,
        isDeleted: false,
      ));

      await mediaRepo.insertMedia(MediaItem(
        id: 'item-B-owned',
        siteId: testSiteA,
        originalUri: 'media/orig_B_own.jpg',
        uri: 'media/evid_B_own.jpg',
        thumbUri: 'media/thumb_B_own.jpg',
        type: MediaItemType.photo,
        lat: centerLat + (3.0 / 111320.0),
        lon: centerLon,
        accuracyM: 1.0,
        lowAccuracy: false,
        activityTag: 'Excavation',
        observationType: ObservationType.progress,
        capturedAt: DateTime.utc(2026, 8, 15, 12, 0, 0),
        creatorId: 'user-B',
        syncStatus: SyncStatusType.pending,
        isDeleted: false,
      ));

      final userAController = NearbySearchNotifier(
        mediaRepo,
        sourceMedia: null,
        defaultLat: centerLat,
        defaultLon: centerLon,
        initialRadiusMeters: 50.0,
        creatorId: 'user-A',
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(userAController.state.results.any((r) => r.item.id == 'item-A-owned'), isTrue);
      expect(userAController.state.results.any((r) => r.item.id == 'item-B-owned'), isFalse);
    });

    test('19. LAT-001: legacy NULL-creator co-located row is visible to an authenticated nearby search', () async {
      // Pre-attribution legacy row: NULL creator_id, same site, same location.
      await mediaRepo.insertMedia(MediaItem(
        id: 'item-legacy-null-creator',
        siteId: testSiteA,
        originalUri: 'media/orig_legacy.jpg',
        uri: 'media/evid_legacy.jpg',
        thumbUri: 'media/thumb_legacy.jpg',
        type: MediaItemType.photo,
        lat: centerLat + (2.0 / 111320.0),
        lon: centerLon,
        accuracyM: 1.0,
        lowAccuracy: false,
        activityTag: 'Excavation',
        observationType: ObservationType.progress,
        capturedAt: DateTime.utc(2026, 8, 15, 11, 0, 0),
        creatorId: null,
        syncStatus: SyncStatusType.pending,
        isDeleted: false,
      ));

      await mediaRepo.insertMedia(MediaItem(
        id: 'item-B-intruder',
        siteId: testSiteA,
        originalUri: 'media/orig_B2.jpg',
        uri: 'media/evid_B2.jpg',
        thumbUri: 'media/thumb_B2.jpg',
        type: MediaItemType.photo,
        lat: centerLat + (3.0 / 111320.0),
        lon: centerLon,
        accuracyM: 1.0,
        lowAccuracy: false,
        activityTag: 'Excavation',
        observationType: ObservationType.progress,
        capturedAt: DateTime.utc(2026, 8, 15, 12, 0, 0),
        creatorId: 'user-B',
        syncStatus: SyncStatusType.pending,
        isDeleted: false,
      ));

      final results = await mediaRepo.findNearbyMedia(
        centerLat: centerLat,
        centerLon: centerLon,
        radiusMeters: 50.0,
        excludeMediaId: sourceItem.id,
        creatorId: 'user-A',
      );

      final ids = results.map((r) => r.item.id).toSet();
      // NULL-creator legacy row stays visible (ownership parity with sync queries).
      expect(ids.contains('item-legacy-null-creator'), isTrue);
      // Cross-creator isolation is unchanged.
      expect(ids.contains('item-B-intruder'), isFalse);
      // The source photo itself is still excluded.
      expect(ids.contains(sourceItem.id), isFalse);
    });
  });
}
