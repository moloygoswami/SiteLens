import 'dart:ffi';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sitelens/core/controllers/nearby_settings_controller.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/local/database/database_provider.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/features/camera/services/evidence_storage_service.dart';
import 'package:sitelens/features/nearby/nearby_search_screen.dart';

class MockStorageService extends EvidenceStorageService {
  @override
  Future<String> resolveAbsolutePath(String relativePath) async {
    return '/mock/path/$relativePath';
  }
}

class FakeNearbySettingsNotifier extends NearbySettingsNotifier {
  FakeNearbySettingsNotifier(double initial) : super() {
    state = initial;
  }
}

void main() {
  late AppDatabase db;
  late MediaRepository mediaRepo;
  late MockStorageService mockStorage;

  final testSiteId = 'site-101';
  final centerLat = 22.56400;
  final centerLon = 88.30000;

  setUpAll(() {
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  final sourceItem = MediaItem(
    id: 'source-1',
    siteId: testSiteId,
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
    creatorId: 'user-test',
    syncStatus: SyncStatusType.pending,
    isDeleted: false,
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    mediaRepo = LocalMediaRepository(db);
    mockStorage = MockStorageService();

    // Seed test site
    await db.into(db.sites).insert(
          SitesCompanion.insert(
            id: testSiteId,
            siteCode: const drift.Value('101'),
            name: const drift.Value('Test Site Alpha'),
            address: const drift.Value('123 Main Road'),
          ),
        );

    // Seed source item
    await mediaRepo.insertMedia(sourceItem);

    // Seed Candidate 1: 4m away, Open Non-Conformity (Before)
    await mediaRepo.insertMedia(MediaItem(
      id: 'candidate-before-4m',
      siteId: testSiteId,
      originalUri: 'media/orig_b1.jpg',
      uri: 'media/evid_b1.jpg',
      thumbUri: 'media/thumb_b1.jpg',
      type: MediaItemType.photo,
      lat: centerLat + (4.0 / 111320.0),
      lon: centerLon,
      accuracyM: 1.5,
      lowAccuracy: false,
      activityTag: 'Excavation',
      observationType: ObservationType.nonConformity,
      linkedMediaId: null,
      note: 'Cracked trench shoring',
      capturedAt: DateTime.utc(2026, 8, 15, 9, 0, 0),
      creatorId: 'user-test',
      sha256Hash: 'hash-b1',
      evidenceSha256Hash: 'evid-hash-b1',
      capturedAddress: 'Shibpur, Howrah',
      syncStatus: SyncStatusType.pending,
      isDeleted: false,
    ));

    // Seed Candidate 2: 8m away, Closed (After)
    await mediaRepo.insertMedia(MediaItem(
      id: 'candidate-after-8m',
      siteId: testSiteId,
      originalUri: 'media/orig_a1.jpg',
      uri: 'media/evid_a1.jpg',
      thumbUri: 'media/thumb_a1.jpg',
      type: MediaItemType.photo,
      lat: centerLat + (8.0 / 111320.0),
      lon: centerLon,
      accuracyM: 2.0,
      lowAccuracy: false,
      activityTag: 'Excavation',
      observationType: ObservationType.closed,
      linkedMediaId: null,
      note: 'Shoring reinforced',
      capturedAt: DateTime.utc(2026, 8, 15, 14, 0, 0),
      creatorId: 'user-test',
      sha256Hash: 'hash-a1',
      evidenceSha256Hash: 'evid-hash-a1',
      capturedAddress: 'Shibpur, Howrah',
      syncStatus: SyncStatusType.pending,
      isDeleted: false,
    ));

    // Seed Candidate 3: 18m away, Progress
    await mediaRepo.insertMedia(MediaItem(
      id: 'candidate-prog-18m',
      siteId: testSiteId,
      originalUri: 'media/orig_p1.jpg',
      uri: 'media/evid_p1.jpg',
      thumbUri: 'media/thumb_p1.jpg',
      type: MediaItemType.photo,
      lat: centerLat + (18.0 / 111320.0),
      lon: centerLon,
      accuracyM: 2.0,
      lowAccuracy: false,
      activityTag: 'Rebar',
      observationType: ObservationType.progress,
      linkedMediaId: null,
      note: 'Rebar placed',
      capturedAt: DateTime.utc(2026, 8, 15, 12, 0, 0),
      creatorId: 'user-test',
      sha256Hash: 'hash-p1',
      evidenceSha256Hash: 'evid-hash-p1',
      capturedAddress: 'Shibpur, Howrah',
      syncStatus: SyncStatusType.pending,
      isDeleted: false,
    ));
  });

  tearDown(() async {
    await db.close();
  });

  Widget createWidgetUnderTest(MediaItem? source) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        mediaRepositoryProvider.overrideWithValue(mediaRepo),
        evidenceStorageServiceProvider.overrideWithValue(mockStorage),
        nearbySettingsProvider.overrideWith((ref) => FakeNearbySettingsNotifier(25.0)),
      ],
      child: MaterialApp(
        home: NearbySearchScreen(sourceMedia: source),
      ),
    );
  }

  group('NearbySearchScreen Widget Tests', () {
    testWidgets('Renders NearbySearchScreen with source anchor, radius strip, and grouped results', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest(sourceItem));
      await tester.pumpAndSettle();

      // Verify Header and Anchor
      expect(find.text('NEARBY EVIDENCE SEARCH'), findsOneWidget);
      expect(find.text('SOURCE ANCHOR'), findsOneWidget);
      expect(find.text('• site-101'), findsOneWidget);

      // Verify Radius presets
      expect(find.text('2m'), findsOneWidget);
      expect(find.text('5m'), findsOneWidget);
      expect(find.text('10m'), findsOneWidget);
      expect(find.text('25m'), findsOneWidget);
      expect(find.text('50m'), findsOneWidget);

      // Default radius is 25m, so all 3 candidates (4m, 8m, 18m) should appear
      expect(find.text('3 ITEMS'), findsOneWidget);

      // Verify Group Headers
      expect(find.text('BEFORE / OPEN NON-CONFORMITY'), findsOneWidget);
      expect(find.text('AFTER / RESOLUTION'), findsOneWidget);
      expect(find.text('PROGRESS DOCUMENTATION'), findsOneWidget);

      // Verify Distance pills
      expect(find.text('4.0m away'), findsOneWidget);
      expect(find.text('8.0m away'), findsOneWidget);
      expect(find.text('18.0m away'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('Tapping a smaller radius chip (5m) contracts search boundary and updates results', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest(sourceItem));
      await tester.pumpAndSettle();

      expect(find.text('3 ITEMS'), findsOneWidget);

      // Tap 5m preset chip
      await tester.tap(find.text('5m'));
      await tester.pumpAndSettle();

      // Only candidate-before-4m should remain
      expect(find.text('1 ITEMS'), findsOneWidget);
      expect(find.text('4.0m away'), findsOneWidget);
      expect(find.text('8.0m away'), findsNothing);
      expect(find.text('18.0m away'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('Tapping a tiny radius chip (2m) shows clean empty state and expand button', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest(sourceItem));
      await tester.pumpAndSettle();

      // Tap 2m preset chip (no items within 2m)
      await tester.tap(find.text('2m'));
      await tester.pumpAndSettle();

      expect(find.text('0 ITEMS'), findsOneWidget);
      expect(find.text('No Evidence Within 2m'), findsOneWidget);
      expect(find.text('Expand to 50m Radius'), findsOneWidget);

      // Tap expand to 50m button
      await tester.tap(find.text('Expand to 50m Radius'));
      await tester.pumpAndSettle();

      expect(find.text('3 ITEMS'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('Tapping filter action in AppBar opens NearbyFilterModal and displays active filter chips', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest(sourceItem));
      await tester.pumpAndSettle();

      // Tap filter action in AppBar
      await tester.tap(find.byTooltip('Filter Nearby Media'));
      await tester.pumpAndSettle();

      expect(find.text('FILTER NEARBY MEDIA'), findsOneWidget);

      // Select 'Non-Conformity' filter chip inside modal
      await tester.tap(find.text('Non-Conformity'));
      await tester.pumpAndSettle();

      // Tap Apply Filters
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      // Verify active filter badge renders '1'
      expect(find.text('1'), findsOneWidget);

      // Verify Active Filter chip strip renders 'Non-Conformity'
      expect(find.text('Non-Conformity'), findsWidgets);
      expect(find.text('Clear All'), findsOneWidget);

      // Only candidate-before-4m should match (Non-Conformity)
      expect(find.text('1 ITEMS'), findsOneWidget);

      // Tap Clear All
      await tester.tap(find.text('Clear All'));
      await tester.pumpAndSettle();

      // Filters should clear and all 3 items reappear
      expect(find.text('3 ITEMS'), findsOneWidget);
      expect(find.text('Clear All'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}
