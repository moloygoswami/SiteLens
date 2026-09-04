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
import 'package:sitelens/features/nearby/controllers/nearby_search_controller.dart';
import 'package:sitelens/features/nearby/widgets/nearby_filter_modal.dart';

void main() {
  late AppDatabase db;
  late MediaRepository mediaRepo;

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

    await db.into(db.sites).insert(
          SitesCompanion.insert(
            id: testSiteId,
            siteCode: const drift.Value('101'),
            name: const drift.Value('Test Site Alpha'),
            address: const drift.Value('123 Main Road'),
          ),
        );

    await mediaRepo.insertMedia(sourceItem);
  });

  tearDown(() async {
    await db.close();
  });

  Widget buildTestableModal(WidgetRef Function(WidgetRef ref)? refCallback) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        mediaRepositoryProvider.overrideWithValue(mediaRepo),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              // Keep provider alive by watching it
              ref.watch(nearbySearchControllerProvider(sourceItem));
              if (refCallback != null) {
                refCallback(ref);
              }
              return Center(
                child: ElevatedButton(
                  onPressed: () => NearbyFilterModal.show(context, sourceItem),
                  child: const Text('Open Filters'),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  group('NearbyFilterModal Widget Tests (M5.5)', () {
    testWidgets('Renders all PRD 11.2 filter controls correctly', (tester) async {
      await tester.pumpWidget(buildTestableModal(null));
      await tester.pumpAndSettle();

      // Open Modal
      await tester.tap(find.text('Open Filters'));
      await tester.pumpAndSettle();

      // Header & Title
      expect(find.text('FILTER NEARBY MEDIA'), findsOneWidget);
      expect(find.text('Reset All'), findsOneWidget);

      // 1. Same Site Only Switch
      expect(find.text('Same Site Only'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);

      // 2. Activity Text Input
      expect(find.text('ACTIVITY / WORK STAGE'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // 3. Observation Type Chips
      expect(find.text('OBSERVATION TYPE'), findsOneWidget);
      expect(find.text('All Types'), findsOneWidget);
      expect(find.text('Non-Conformity'), findsOneWidget);
      expect(find.text('Closed'), findsOneWidget);
      expect(find.text('Progress'), findsOneWidget);
      expect(find.text('Material'), findsOneWidget);
      expect(find.text('General'), findsOneWidget);

      // 4. Date Range
      expect(find.text('DATE RANGE'), findsOneWidget);
      expect(find.text('All Capture Dates'), findsOneWidget);

      // 5. Apply Button
      expect(find.text('Apply Filters'), findsOneWidget);
    });

    testWidgets('Selecting filters and applying updates NearbySearchController state', (tester) async {
      late WidgetRef capturedRef;
      await tester.pumpWidget(buildTestableModal((ref) {
        capturedRef = ref;
        return ref;
      }));
      await tester.pumpAndSettle();

      // Open Modal
      await tester.tap(find.text('Open Filters'));
      await tester.pumpAndSettle();

      // Enter Activity text
      await tester.enterText(find.byType(TextField), 'Rebar');
      await tester.pumpAndSettle();

      // Select Observation Type 'Closed'
      await tester.tap(find.text('Closed'));
      await tester.pumpAndSettle();

      // Toggle Same Site to false
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      // Tap Apply
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      // Verify state was updated in controller
      final searchState = capturedRef.read(nearbySearchControllerProvider(sourceItem));
      expect(searchState.filters.sameSiteOnly, isFalse);
      expect(searchState.filters.activityTag, equals('Rebar'));
      expect(searchState.filters.observationType, equals(ObservationType.closed));
      expect(searchState.filters.activeFilterCount, equals(3)); // sameSite false (+1), activity (+1), observation (+1)
    });

    testWidgets('Tapping Reset All restores default filter values without affecting radius', (tester) async {
      late WidgetRef capturedRef;
      await tester.pumpWidget(buildTestableModal((ref) {
        capturedRef = ref;
        return ref;
      }));
      await tester.pumpAndSettle();

      // Set custom radius first
      capturedRef.read(nearbySearchControllerProvider(sourceItem).notifier).setRadius(50.0);
      capturedRef.read(nearbySearchControllerProvider(sourceItem).notifier).setObservationType(ObservationType.nonConformity);
      await tester.pumpAndSettle();

      expect(capturedRef.read(nearbySearchControllerProvider(sourceItem)).radiusMeters, equals(50.0));
      expect(capturedRef.read(nearbySearchControllerProvider(sourceItem)).filters.activeFilterCount, equals(1));

      // Open Modal
      await tester.tap(find.text('Open Filters'));
      await tester.pumpAndSettle();

      // Tap Reset All
      await tester.tap(find.text('Reset All'));
      await tester.pumpAndSettle();

      // Verify filters reset to defaults
      final searchState = capturedRef.read(nearbySearchControllerProvider(sourceItem));
      expect(searchState.filters.sameSiteOnly, isTrue);
      expect(searchState.filters.activityTag, isNull);
      expect(searchState.filters.observationType, isNull);
      expect(searchState.filters.activeFilterCount, equals(0));

      // CRITICAL PRD CONTRACT: Spatial radius must remain unchanged!
      expect(searchState.radiusMeters, equals(50.0));
    });
  });
}
