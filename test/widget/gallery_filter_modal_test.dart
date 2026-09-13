import 'dart:ffi';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/open.dart';

import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/local/database/database_provider.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/data/repositories/site_repository.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/site_model.dart';
import 'package:sitelens/features/gallery/controllers/gallery_controller.dart';
import 'package:sitelens/features/gallery/widgets/gallery_filter_modal.dart';
import 'package:sitelens/features/sites/site_controller.dart';

void main() {
  late AppDatabase db;
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
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        mediaRepositoryProvider.overrideWithValue(LocalMediaRepository(db)),
        siteControllerProvider.overrideWith(
          (ref) => SiteController(MockSiteRepository(testSite)),
        ),
      ],
    );
    container.listen(filteredGalleryMediaProvider, (_, __) {});
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> seedSyncMedia() async {
    await db.into(db.media).insert(
          MediaCompanion.insert(
            id: 'm-pending',
            siteId: const drift.Value('site-alpha'),
            type: const drift.Value('photo'),
            uri: 'media/evid_pending.jpg',
            originalUri: const drift.Value('media/orig_pending.jpg'),
            thumbUri: const drift.Value('media/thumb_pending.jpg'),
            capturedAt: '2026-08-15T09:00:00.000Z',
            lat: 22.56298,
            lon: 88.30085,
            synced: const drift.Value(0),
          ),
        );
    await db.into(db.media).insert(
          MediaCompanion.insert(
            id: 'm-synced',
            siteId: const drift.Value('site-alpha'),
            type: const drift.Value('photo'),
            uri: 'media/evid_synced.jpg',
            originalUri: const drift.Value('media/orig_synced.jpg'),
            thumbUri: const drift.Value('media/thumb_synced.jpg'),
            capturedAt: '2026-08-15T10:00:00.000Z',
            lat: 22.56298,
            lon: 88.30085,
            synced: const drift.Value(1),
          ),
        );
  }

  Widget buildScope() {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => GalleryFilterModal.show(context),
              child: const Text('Open Filter'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
      'Sync Status filter is selectable in the modal and filters the gallery list',
      (tester) async {
    await tester.runAsync(seedSyncMedia);
    await tester.pumpWidget(buildScope());
    await tester.pumpAndSettle();

    // Open modal and select the Synced sync status
    await tester.tap(find.text('Open Filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All Sync States'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Synced').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply Filters'));
    await tester.pumpAndSettle();

    // Filter state now carries the sync status
    expect(
      container.read(galleryFilterProvider).syncStatus,
      SyncStatusType.synced,
    );
    expect(container.read(galleryFilterProvider).activeFilterCount, 1);

    // Only the synced item remains in the gallery list
    final asyncItems = container.read(filteredGalleryMediaProvider);
    expect(asyncItems.hasValue, isTrue);
    expect(asyncItems.value!.map((i) => i.id).toList(), equals(['m-synced']));
  });

  testWidgets(
      'Selecting All Sync States clears the sync filter and restores the full list',
      (tester) async {
    await tester.runAsync(seedSyncMedia);
    await tester.pumpWidget(buildScope());
    await tester.pumpAndSettle();

    // Apply Synced first
    await tester.tap(find.text('Open Filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All Sync States'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Synced').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply Filters'));
    await tester.pumpAndSettle();
    expect(
      container.read(galleryFilterProvider).syncStatus,
      SyncStatusType.synced,
    );

    // Re-open and select All Sync States
    await tester.tap(find.text('Open Filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Synced'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All Sync States').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply Filters'));
    await tester.pumpAndSettle();

    expect(container.read(galleryFilterProvider).syncStatus, isNull);
    expect(container.read(galleryFilterProvider).activeFilterCount, 0);

    final asyncItems = container.read(filteredGalleryMediaProvider);
    expect(asyncItems.hasValue, isTrue);
    expect(
      asyncItems.value!.map((i) => i.id).toList(),
      equals(['m-synced', 'm-pending']),
    );
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
  Future<void> deleteSite(String id, {String? creatorId}) async {}

  @override
  Future<bool> hasMediaForSite(String siteId) async => false;

  @override
  Future<void> seedDefaultSitesIfEmpty() async {}
}
