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
import 'package:sitelens/features/nearby/widgets/location_timeline_view.dart';

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

    // Step 1: Initial capture (10:00 UTC) - Excavation (Before)
    await mediaRepo.insertMedia(MediaItem(
      id: 'step-1-excavation',
      siteId: testSiteId,
      originalUri: 'media/orig_step1.jpg',
      uri: 'media/evid_step1.jpg',
      thumbUri: 'media/thumb_step1.jpg',
      type: MediaItemType.photo,
      lat: centerLat + (2.0 / 111320.0),
      lon: centerLon,
      accuracyM: 1.5,
      lowAccuracy: false,
      activityTag: 'Excavation',
      observationType: ObservationType.nonConformity,
      linkedMediaId: null,
      note: 'Deep trench excavated',
      capturedAt: DateTime.utc(2026, 8, 15, 10, 0, 0),
      creatorId: 'user-test',
      sha256Hash: 'hash-step1',
      evidenceSha256Hash: 'evid-hash-step1',
      capturedAddress: 'Shibpur, Howrah',
      syncStatus: SyncStatusType.pending,
      isDeleted: false,
    ));

    // Step 2: 3 hours later (13:00 UTC) - Rebar Foundation (Progress)
    await mediaRepo.insertMedia(MediaItem(
      id: 'step-2-rebar',
      siteId: testSiteId,
      originalUri: 'media/orig_step2.jpg',
      uri: 'media/evid_step2.jpg',
      thumbUri: 'media/thumb_step2.jpg',
      type: MediaItemType.photo,
      lat: centerLat + (4.0 / 111320.0),
      lon: centerLon,
      accuracyM: 2.0,
      lowAccuracy: false,
      activityTag: 'Rebar Foundation',
      observationType: ObservationType.progress,
      linkedMediaId: null,
      note: 'Reinforcement cage placed',
      capturedAt: DateTime.utc(2026, 8, 15, 13, 0, 0),
      creatorId: 'user-test',
      sha256Hash: 'hash-step2',
      evidenceSha256Hash: 'evid-hash-step2',
      capturedAddress: 'Shibpur, Howrah',
      syncStatus: SyncStatusType.pending,
      isDeleted: false,
    ));

    // Step 3: 2 days later (Aug 17 09:00 UTC) - Concrete Pour (Closed)
    await mediaRepo.insertMedia(MediaItem(
      id: 'step-3-concrete',
      siteId: testSiteId,
      originalUri: 'media/orig_step3.jpg',
      uri: 'media/evid_step3.jpg',
      thumbUri: 'media/thumb_step3.jpg',
      type: MediaItemType.photo,
      lat: centerLat + (3.0 / 111320.0),
      lon: centerLon,
      accuracyM: 2.0,
      lowAccuracy: false,
      activityTag: 'Concrete Pour',
      observationType: ObservationType.closed,
      linkedMediaId: null,
      note: 'M25 grade pour completed',
      capturedAt: DateTime.utc(2026, 8, 17, 9, 0, 0),
      creatorId: 'user-test',
      sha256Hash: 'hash-step3',
      evidenceSha256Hash: 'evid-hash-step3',
      capturedAddress: 'Shibpur, Howrah',
      syncStatus: SyncStatusType.pending,
      isDeleted: false,
    ));
  });

  tearDown(() async {
    await db.close();
  });

  Widget createWidgetUnderTest() {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        mediaRepositoryProvider.overrideWithValue(mediaRepo),
        evidenceStorageServiceProvider.overrideWithValue(mockStorage),
      ],
      child: MaterialApp(
        home: NearbySearchScreen(sourceMedia: sourceItem),
      ),
    );
  }

  group('LocationTimelineView & History Toggle Widget Tests', () {
    testWidgets('Toggling from Grouped to Full History displays sequential chronological timeline', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Initial state is Grouped View
      expect(find.text('Grouped'), findsOneWidget);
      expect(find.text('Timeline'), findsOneWidget);
      expect(find.text('Map View'), findsOneWidget);
      expect(find.text('SPATIAL EVIDENCE FOUND'), findsOneWidget);

      // Tap Timeline toggle tab
      await tester.tap(find.text('Timeline'));
      await tester.pumpAndSettle();

      // Verify header changed to chronological history
      expect(find.text('CHRONOLOGICAL LIFECYCLE HISTORY'), findsOneWidget);

      // Verify LocationTimelineView rendered all 3 steps in order
      expect(find.text('STEP #1'), findsOneWidget);
      expect(find.text('STEP #2'), findsOneWidget);
      expect(find.text('STEP #3'), findsOneWidget);

      // Verify activities
      expect(find.text('Excavation'), findsOneWidget);
      expect(find.text('Rebar Foundation'), findsOneWidget);
      expect(find.text('Concrete Pour'), findsOneWidget);

      // Verify time delta badges
      expect(find.text('INITIAL CAPTURE'), findsOneWidget);
      expect(find.text('+3 h later'), findsOneWidget);
      expect(find.text('+1 d 20h later'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('LocationTimelineView displays empty placeholder when items list is empty', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            evidenceStorageServiceProvider.overrideWithValue(mockStorage),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: LocationTimelineView(items: []),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No Timeline Evidence'), findsOneWidget);
      expect(find.byIcon(Icons.timeline_rounded), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}
