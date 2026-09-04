import 'dart:ffi';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/local/database/database_provider.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/features/camera/services/evidence_storage_service.dart';
import 'package:sitelens/features/nearby/nearby_search_screen.dart';
import 'package:sitelens/features/nearby/widgets/nearby_map_view.dart';

class MockStorageService extends EvidenceStorageService {
  @override
  Future<String> resolveAbsolutePath(String relativePath) async {
    return '/mock/path/$relativePath';
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

    // Seed candidate media
    await mediaRepo.insertMedia(MediaItem(
      id: 'candidate-1',
      siteId: testSiteId,
      originalUri: 'media/orig_c1.jpg',
      uri: 'media/evid_c1.jpg',
      thumbUri: 'media/thumb_c1.jpg',
      type: MediaItemType.photo,
      lat: centerLat + (5.0 / 111320.0),
      lon: centerLon,
      accuracyM: 2.0,
      lowAccuracy: false,
      activityTag: 'Excavation',
      observationType: ObservationType.progress,
      linkedMediaId: null,
      note: 'North trench',
      capturedAt: DateTime.utc(2026, 8, 15, 11, 0, 0),
      sha256Hash: 'hash-c1',
      evidenceSha256Hash: 'evid-hash-c1',
      capturedAddress: 'Shibpur, Howrah',
      syncStatus: SyncStatusType.pending,
      isDeleted: false,
    ));
  });

  tearDown(() async {
    await db.close();
  });

  group('NearbyMapView & Map Toggle Widget Tests', () {
    testWidgets('NearbyMapView renders gracefully with center coordinates and pin count', (tester) async {
      final sampleResult = NearbyMediaResult(
        item: sourceItem,
        distanceMeters: 0.0,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            evidenceStorageServiceProvider.overrideWithValue(mockStorage),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: NearbyMapView(
                centerLat: centerLat,
                centerLon: centerLon,
                radiusMeters: 25.0,
                results: [sampleResult],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Spatial Map Mode Active'), findsOneWidget);
      expect(find.text('1 nearby candidate pin(s) plotted.'), findsOneWidget);
      expect(find.textContaining('Origin: 22.56400, 88.30000'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('Tapping Map View toggle in NearbySearchScreen switches viewMode to Map', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            mediaRepositoryProvider.overrideWithValue(mediaRepo),
            evidenceStorageServiceProvider.overrideWithValue(mockStorage),
          ],
          child: MaterialApp(
            home: NearbySearchScreen(sourceMedia: sourceItem),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify all 3 toggle options exist
      expect(find.text('Grouped'), findsOneWidget);
      expect(find.text('Timeline'), findsOneWidget);
      expect(find.text('Map View'), findsOneWidget);

      // Tap Map View toggle
      await tester.tap(find.text('Map View'));
      await tester.pumpAndSettle();

      // Verify header changed to Map
      expect(find.text('SPATIAL MAP RADIUS CANVAS'), findsOneWidget);
      expect(find.text('Spatial Map Mode Active'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}
