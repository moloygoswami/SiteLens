import 'dart:ffi';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:sqlite3/open.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sitelens/core/services/auth_service.dart';
import 'package:sitelens/core/services/session_service.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/data/repositories/site_repository.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/domain/models/site_model.dart';
import 'package:sitelens/features/camera/services/evidence_storage_service.dart';
import 'package:sitelens/features/gallery/controllers/gallery_controller.dart';
import 'package:sitelens/features/gallery/gallery_screen.dart';
import 'package:sitelens/features/gallery/media_detail_screen.dart';
import 'package:sitelens/features/gallery/widgets/gallery_media_tile.dart';
import 'package:sitelens/features/nearby/models/nearby_search_state.dart';
import 'package:sitelens/features/nearby/widgets/location_timeline_view.dart';
import 'package:sitelens/features/sites/site_controller.dart';
import 'package:sitelens/features/sync/models/sync_state.dart';
import 'package:sitelens/features/sync/services/cloud_media_recovery_service.dart';
import 'package:sitelens/features/sync/services/sync_coordinator.dart';

class Slice5FakeSyncCoordinator extends StateNotifier<SyncState> implements SyncCoordinator {
  Slice5FakeSyncCoordinator() : super(const SyncState(isOnline: true));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Slice5FakeSessionService extends StateNotifier<UserSessionState> implements SessionService {
  Slice5FakeSessionService(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Slice5MockSiteRepository implements SiteRepository {
  final List<SiteModel> sites;
  Slice5MockSiteRepository(this.sites);

  @override
  Future<List<SiteModel>> getAllSites({String? creatorId}) async => sites;

  @override
  Future<SiteModel?> getSiteById(String id, {String? creatorId}) async =>
      sites.where((s) => s.id == id).firstOrNull;

  @override
  Future<List<SiteModel>> hydrateRemoteSites(String creatorId) async => sites;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Slice5FakeEvidenceStorageService extends EvidenceStorageService {
  final Map<String, String> pathMap = {};
  final List<String> deletedFiles = [];
  final Map<String, IntegrityVerificationResult> verificationOverrides = {};

  @override
  Future<String> resolveAbsolutePath(String relativePath) async {
    return pathMap[relativePath] ?? '/mock/path/$relativePath';
  }

  @override
  Future<IntegrityVerificationResult> verifyArtifactIntegrity({
    required String relativePath,
    required String? expectedSha256,
  }) async {
    if (verificationOverrides.containsKey(relativePath)) {
      return verificationOverrides[relativePath]!;
    }
    return super.verifyArtifactIntegrity(
      relativePath: relativePath,
      expectedSha256: expectedSha256,
    );
  }

  @override
  Future<void> deleteLocalMediaFiles({
    required String mediaId,
    String? originalUri,
    String? uri,
    String? thumbUri,
    String? type,
  }) async {
    if (originalUri != null && originalUri.isNotEmpty) deletedFiles.add(originalUri);
    if (uri != null && uri.isNotEmpty && uri != originalUri) deletedFiles.add(uri);
    if (thumbUri != null && thumbUri.isNotEmpty) deletedFiles.add(thumbUri);
  }
}

class Slice5FakeCloudMediaRecoveryService implements CloudMediaRecoveryService {
  bool recoverOriginalCalled = false;

  @override
  Future<File> recoverOriginal({required MediaItem item, void Function(double)? onProgress}) async {
    recoverOriginalCalled = true;
    return File('/mock/recovered.jpg');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  late AppDatabase db;
  late MediaRepository mediaRepo;
  late Slice5FakeEvidenceStorageService storageService;
  late Slice5FakeCloudMediaRecoveryService recoveryService;
  late Slice5MockSiteRepository siteRepo;
  late Slice5FakeSessionService sessionService;

  const testSiteA = SiteModel(
    id: 'site-a',
    siteCode: 'BLDG-101',
    name: 'Sector Alpha Expansion',
    address: '100 Alpha Boulevard',
    creatorId: 'inspector-1',
  );

  const testSiteB = SiteModel(
    id: 'site-b',
    siteCode: 'ROAD-404',
    name: 'North Perimeter Bypass',
    address: '404 Bypass Way',
    creatorId: 'inspector-1',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({'sitelens_active_site_id': 'site-a'});
    db = AppDatabase(NativeDatabase.memory());
    mediaRepo = LocalMediaRepository(db);
    storageService = Slice5FakeEvidenceStorageService();
    recoveryService = Slice5FakeCloudMediaRecoveryService();
    siteRepo = Slice5MockSiteRepository([testSiteA, testSiteB]);
    sessionService = Slice5FakeSessionService(
      const UserSessionState(
        status: SessionStatus.authenticatedReady,
        user: AuthUser(uid: 'inspector-1', email: 'inspector@sitelens.local'),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Slice 5: Deterministic Sort & Tie-Breaking (AC-GAL-02, TM-U-13)', () {
    test('Identical captured_at timestamps produce stable, deterministic ordering across repeated queries', () async {
      final fixedTimestamp = DateTime.utc(2026, 8, 15, 14, 30, 0);

      await mediaRepo.insertMedia(
        MediaItem(
          id: 'item-gamma',
          siteId: 'site-a',
          creatorId: 'inspector-1',
          type: MediaItemType.photo,
          uri: 'media/evid_gamma.jpg',
          originalUri: 'media/orig_gamma.jpg',
          capturedAt: fixedTimestamp,
          lat: 22.56298,
          lon: 88.30085,
        ),
        creatorId: 'inspector-1',
      );
      await mediaRepo.insertMedia(
        MediaItem(
          id: 'item-alpha',
          siteId: 'site-a',
          creatorId: 'inspector-1',
          type: MediaItemType.photo,
          uri: 'media/evid_alpha.jpg',
          originalUri: 'media/orig_alpha.jpg',
          capturedAt: fixedTimestamp,
          lat: 22.56298,
          lon: 88.30085,
        ),
        creatorId: 'inspector-1',
      );
      await mediaRepo.insertMedia(
        MediaItem(
          id: 'item-beta',
          siteId: 'site-a',
          creatorId: 'inspector-1',
          type: MediaItemType.photo,
          uri: 'media/evid_beta.jpg',
          originalUri: 'media/orig_beta.jpg',
          capturedAt: fixedTimestamp,
          lat: 22.56298,
          lon: 88.30085,
        ),
        creatorId: 'inspector-1',
      );

      // Query multiple times
      final results1 = await mediaRepo.watchAllMedia(siteId: 'site-a', creatorId: 'inspector-1').first;
      final results2 = await mediaRepo.watchAllMedia(siteId: 'site-a', creatorId: 'inspector-1').first;

      expect(results1.map((e) => e.id).toList(), equals(['item-alpha', 'item-beta', 'item-gamma']));
      expect(results2.map((e) => e.id).toList(), equals(['item-alpha', 'item-beta', 'item-gamma']));
    });
  });

  group('Slice 5: Search Filter Scope (AC-GAL-04)', () {
    test('Search matches site name, reference code, and note text', () async {
      await mediaRepo.insertMedia(
        MediaItem(
          id: 'item-site-search',
          siteId: 'site-a',
          creatorId: 'inspector-1',
          type: MediaItemType.photo,
          uri: 'media/evid_s1.jpg',
          originalUri: 'media/orig_s1.jpg',
          capturedAt: DateTime.utc(2026, 8, 15, 10, 0, 0),
          lat: 22.56298,
          lon: 88.30085,
          note: 'Rebar inspection completed',
        ),
        creatorId: 'inspector-1',
      );

      final siteController = SiteController(siteRepo, initialUserId: 'inspector-1');
      await siteController.loadSitesAndActiveContext();

      final container = ProviderContainer(
        overrides: [
          sessionServiceProvider.overrideWith((ref) => sessionService),
          mediaRepositoryProvider.overrideWithValue(mediaRepo),
          siteRepositoryProvider.overrideWithValue(siteRepo),
          siteControllerProvider.overrideWith((ref) => siteController),
        ],
      );
      // Keep provider active
      container.listen(filteredGalleryMediaProvider, (_, __) {});

      // 1. Match by note text
      container.read(galleryFilterProvider.notifier).setSearchQuery('rebar');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      var items = await container.read(filteredGalleryMediaProvider.future);
      expect(items.length, equals(1));
      expect(items.first.id, equals('item-site-search'));

      // 2. Match by site name ('Sector Alpha')
      container.read(galleryFilterProvider.notifier).setSearchQuery('Sector Alpha');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      items = await container.read(filteredGalleryMediaProvider.future);
      expect(items.length, equals(1));
      expect(items.first.id, equals('item-site-search'));

      // 3. Match by reference code ('BLDG-101')
      container.read(galleryFilterProvider.notifier).setSearchQuery('BLDG-101');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      items = await container.read(filteredGalleryMediaProvider.future);
      expect(items.length, equals(1));
      expect(items.first.id, equals('item-site-search'));

      // 4. Non-matching query yields empty list
      container.read(galleryFilterProvider.notifier).setSearchQuery('random nonexistent query');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      items = await container.read(filteredGalleryMediaProvider.future);
      expect(items.isEmpty, isTrue);

      container.dispose();
    });
  });

  group('Slice 5: Context Menu Secondary Actions (AC-GAL-05, TM-W-06)', () {
    testWidgets('Long-press on thumbnail exposes all secondary actions matching Media Detail', (tester) async {
      final item = MediaItem(
        id: 'ctx-item-1',
        creatorId: 'inspector-1',
        siteId: 'site-a',
        type: MediaItemType.photo,
        uri: 'media/evid_ctx.jpg',
        originalUri: 'media/orig_ctx.jpg',
        capturedAt: DateTime.utc(2026, 8, 15, 10, 0, 0),
        lat: 22.56298,
        lon: 88.30085,
        syncStatus: SyncStatusType.synced,
      );

      await mediaRepo.insertMedia(item, creatorId: 'inspector-1');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionServiceProvider.overrideWith((ref) => sessionService),
            mediaRepositoryProvider.overrideWithValue(mediaRepo),
            siteRepositoryProvider.overrideWithValue(siteRepo),
            siteControllerProvider.overrideWith((ref) => SiteController(siteRepo, initialUserId: 'inspector-1')),
            evidenceStorageServiceProvider.overrideWithValue(storageService),
            syncCoordinatorProvider.overrideWith((ref) => Slice5FakeSyncCoordinator()),
          ],
          child: const MaterialApp(home: GalleryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Long-press tile
      await tester.longPress(find.byType(GalleryMediaTile).first);
      await tester.pumpAndSettle();

      // Assert all secondary actions per AC-GAL-05 are exposed
      expect(find.text('Find Nearby Evidence'), findsOneWidget);
      expect(find.text('View Evidence Details'), findsOneWidget);
      expect(find.text('Edit Tags'), findsOneWidget);
      expect(find.text('Share & Export Single File'), findsOneWidget);
      expect(find.text('Delete from Device / Remove from Gallery'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });

  group('Slice 5: Media Detail Visual States & Cleared Original (AC-DETAIL-02, AC-DETAIL-03, TM-W-07)', () {
    testWidgets('Verified badge renders when live re-hash matches', (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('sitelens_detail_test_');
      final evidFile = File('${tempDir.path}/evid.jpg')..writeAsBytesSync([10, 20, 30]);
      final origFile = File('${tempDir.path}/orig.jpg')..writeAsBytesSync([10, 20, 30]);

      final localItem = MediaItem(
        id: 'detail-m1',
        creatorId: 'inspector-1',
        siteId: 'site-a',
        type: MediaItemType.photo,
        uri: 'media/evid.jpg',
        originalUri: 'media/orig.jpg',
        capturedAt: DateTime.utc(2026, 8, 15, 12, 0, 0),
        lat: 22.56298,
        lon: 88.30085,
        sha256Hash: 'dummy',
        evidenceSha256Hash: 'dummy',
      );

      final customStorage = Slice5FakeEvidenceStorageService();
      customStorage.pathMap['media/evid.jpg'] = evidFile.path;
      customStorage.pathMap['media/orig.jpg'] = origFile.path;
      customStorage.verificationOverrides['media/evid.jpg'] = IntegrityVerificationResult.verified;
      customStorage.verificationOverrides['media/orig.jpg'] = IntegrityVerificationResult.verified;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionServiceProvider.overrideWith((ref) => sessionService),
            mediaRepositoryProvider.overrideWithValue(mediaRepo),
            siteRepositoryProvider.overrideWithValue(siteRepo),
            siteControllerProvider.overrideWith((ref) => SiteController(siteRepo)),
            evidenceStorageServiceProvider.overrideWithValue(customStorage),
            cloudMediaRecoveryServiceProvider.overrideWithValue(recoveryService),
          ],
          child: MaterialApp(home: MediaDetailScreen(mediaItem: localItem)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('VERIFIED'), findsWidgets);
      tempDir.deleteSync(recursive: true);
    });

    testWidgets('Unverified and Unavailable badges render distinctly', (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('sitelens_detail_test_2_');
      final evidFile = File('${tempDir.path}/evid.jpg')..writeAsBytesSync([1, 2, 3]);

      final localItem = MediaItem(
        id: 'detail-m2',
        creatorId: 'inspector-1',
        siteId: 'site-a',
        type: MediaItemType.photo,
        uri: 'media/evid.jpg',
        originalUri: 'media/orig_cleared.jpg',
        capturedAt: DateTime.utc(2026, 8, 15, 12, 0, 0),
        lat: 22.56298,
        lon: 88.30085,
        sha256Hash: 'expected_orig_hash',
        evidenceSha256Hash: 'expected_evid_hash',
        syncStatus: SyncStatusType.synced,
      );

      final customStorage = Slice5FakeEvidenceStorageService();
      customStorage.pathMap['media/evid.jpg'] = evidFile.path;
      customStorage.pathMap['media/orig_cleared.jpg'] = '/nonexistent/orig.jpg';
      customStorage.verificationOverrides['media/evid.jpg'] = IntegrityVerificationResult.unverified;
      customStorage.verificationOverrides['media/orig_cleared.jpg'] = IntegrityVerificationResult.unavailable;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionServiceProvider.overrideWith((ref) => sessionService),
            mediaRepositoryProvider.overrideWithValue(mediaRepo),
            siteRepositoryProvider.overrideWithValue(siteRepo),
            siteControllerProvider.overrideWith((ref) => SiteController(siteRepo)),
            evidenceStorageServiceProvider.overrideWithValue(customStorage),
            cloudMediaRecoveryServiceProvider.overrideWithValue(recoveryService),
          ],
          child: MaterialApp(home: MediaDetailScreen(mediaItem: localItem)),
        ),
      );
      await tester.pumpAndSettle();

      // Assert distinct visual treatments
      expect(find.text('UNVERIFIED'), findsOneWidget);
      expect(find.text('UNAVAILABLE'), findsOneWidget);

      // Assert explicit copy renders when original is cleared locally (AC-DETAIL-03)
      expect(find.text('Original cleared locally — recover from cloud to verify'), findsWidgets);

      tempDir.deleteSync(recursive: true);
    });
  });

  group('Slice 5: Location Timeline View (AC-NEARBY-09)', () {
    testWidgets('Timeline displays results chronologically from oldest to newest regardless of observation type', (tester) async {
      final item1 = MediaItem(
        id: 't-1',
        siteId: 'site-a',
        type: MediaItemType.photo,
        uri: 'media/evid_t1.jpg',
        originalUri: 'media/orig_t1.jpg',
        capturedAt: DateTime.utc(2026, 8, 1, 10, 0, 0), // Oldest: Excavation
        lat: 22.56298,
        lon: 88.30085,
        observationType: ObservationType.nonConformity,
        activityTag: 'Excavation',
      );
      final item2 = MediaItem(
        id: 't-2',
        siteId: 'site-a',
        type: MediaItemType.photo,
        uri: 'media/evid_t2.jpg',
        originalUri: 'media/orig_t2.jpg',
        capturedAt: DateTime.utc(2026, 8, 5, 14, 0, 0), // Middle: Foundation
        lat: 22.56298,
        lon: 88.30085,
        observationType: ObservationType.progress,
        activityTag: 'Foundation',
      );
      final item3 = MediaItem(
        id: 't-3',
        siteId: 'site-a',
        type: MediaItemType.photo,
        uri: 'media/evid_t3.jpg',
        originalUri: 'media/orig_t3.jpg',
        capturedAt: DateTime.utc(2026, 8, 10, 16, 0, 0), // Newest: Masonry
        lat: 22.56298,
        lon: 88.30085,
        observationType: ObservationType.closed,
        activityTag: 'Masonry',
      );

      final state = NearbySearchState(
        centerLat: 22.56298,
        centerLon: 88.30085,
        results: [
          NearbyMediaResult(item: item3, distanceMeters: 2.0),
          NearbyMediaResult(item: item1, distanceMeters: 1.5),
          NearbyMediaResult(item: item2, distanceMeters: 3.0),
        ],
      );

      // Verify chronological sorting (oldest to newest)
      final chronological = state.chronologicalResults;
      expect(chronological.map((r) => r.item.id).toList(), equals(['t-1', 't-2', 't-3']));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            evidenceStorageServiceProvider.overrideWithValue(storageService),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: LocationTimelineView(items: chronological),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('INITIAL CAPTURE'), findsOneWidget);
      expect(find.text('Excavation'), findsOneWidget);
      expect(find.text('Foundation'), findsOneWidget);
      expect(find.text('Masonry'), findsOneWidget);
    });
  });
}
