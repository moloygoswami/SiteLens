import 'dart:ffi';
import 'dart:io';
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
import 'package:sitelens/features/gallery/gallery_screen.dart';
import 'package:sitelens/features/gallery/media_detail_screen.dart';
import 'package:sitelens/features/gallery/widgets/gallery_empty_view.dart';
import 'package:sitelens/features/gallery/widgets/gallery_media_tile.dart';
import 'package:sitelens/features/sites/site_controller.dart';

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sitelens/core/services/auth_service.dart';
import 'package:sitelens/core/services/session_service.dart';
import 'package:sitelens/features/camera/services/evidence_storage_service.dart';
import 'package:sitelens/features/sync/services/cloud_sync_service.dart';
import 'package:sitelens/features/sync/services/sync_coordinator.dart';

class TestConnectivity implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      Stream.value([ConnectivityResult.wifi]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestCloudSyncService implements CloudSyncService {
  @override
  Future<void> syncMediaItem({
    required dynamic item,
    required String absoluteOriginalPath,
    required String absoluteEvidencePath,
    String? absoluteThumbnailPath,
    required String currentUserId,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestAuthService implements AuthService {
  @override
  AuthUser? get currentUser =>
      const AuthUser(uid: 'test-user', email: 'test@sitelens.local');

  @override
  Stream<AuthUser?> get authStateChanges => Stream.value(
      const AuthUser(uid: 'test-user', email: 'test@sitelens.local'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockSessionService extends StateNotifier<UserSessionState> implements SessionService {
  MockSessionService(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestEvidenceStorageService implements EvidenceStorageService {
  @override
  Future<Directory> getMediaDirectory() async => Directory.systemTemp;

  @override
  Future<String> resolveAbsolutePath(String relativePath) async =>
      '${Directory.systemTemp.path}/$relativePath';

  @override
  Future<void> deleteLocalMediaFiles({
    required String mediaId,
    String? originalUri,
    String? uri,
    String? thumbUri,
    String? type,
  }) async {}

  @override
  Future<IntegrityVerificationResult> verifyArtifactIntegrity({
    required String relativePath,
    required String? expectedSha256,
  }) async =>
      IntegrityVerificationResult.verified;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  late MediaRepository mediaRepo;
  late EvidenceStorageService storageService;

  const testSite = SiteModel(
    id: 'site-alpha',
    siteCode: 'SL-001',
    name: 'Sector Alpha',
    address: '100 Construction Way',
  );

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    open.overrideFor(
        OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'sitelens_active_site_id': 'site-alpha'});
    db = AppDatabase(NativeDatabase.memory());
    storageService = TestEvidenceStorageService();
    mediaRepo = LocalMediaRepository(db, storageService: storageService);
  });

  tearDown(() async {
    await db.close();
  });

  Widget createWidgetUnderTest() {
    return ProviderScope(
      overrides: [
        evidenceStorageServiceProvider.overrideWithValue(storageService),
        mediaRepositoryProvider.overrideWithValue(mediaRepo),
        siteRepositoryProvider.overrideWithValue(MockSiteRepository(testSite)),
        siteControllerProvider.overrideWith(
          (ref) => SiteController(MockSiteRepository(testSite)),
        ),
        sessionServiceProvider.overrideWith((ref) => MockSessionService(
              const UserSessionState(
                status: SessionStatus.authenticatedReady,
                user: AuthUser(uid: 'test-user', email: 'test@sitelens.local'),
              ),
            )),
        syncCoordinatorProvider.overrideWith(
          (ref) => SyncCoordinator(
            mediaRepo: mediaRepo,
            cloudSyncService: TestCloudSyncService(),
            storageService: storageService,
            authService: TestAuthService(),
            connectivity: TestConnectivity(),
          ),
        ),
      ],
      child: const MaterialApp(
        home: GalleryScreen(),
      ),
    );
  }

  group('GalleryScreen Widget Tests', () {
    testWidgets('Renders GalleryEmptyView when no items are present',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('EVIDENCE GALLERY'), findsOneWidget);
      expect(find.byType(GalleryEmptyView), findsOneWidget);
      expect(find.text('NO CAPTURED EVIDENCE YET'), findsOneWidget);
      expect(find.text('Open Inspection Camera'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('Renders Grid of GalleryMediaTile widgets when items exist',
        (tester) async {
      // Seed 2 items
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'm1',
              siteId: const drift.Value('site-alpha'),
              creatorId: const drift.Value('test-user'),
              type: const drift.Value('photo'),
              uri: 'media/evid_m1.jpg',
              originalUri: const drift.Value('media/orig_m1.jpg'),
              thumbUri: const drift.Value('media/thumb_m1.jpg'),
              capturedAt: '2026-08-15T10:00:00.000Z',
              lat: 22.56298,
              lon: 88.30085,
              observationType: const drift.Value('progress'),
              activityTag: const drift.Value('Excavation'),
            ),
          );
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'm2',
              siteId: const drift.Value('site-alpha'),
              creatorId: const drift.Value('test-user'),
              type: const drift.Value('video'),
              uri: 'media/evid_m2.jpg',
              originalUri: const drift.Value('media/orig_m2.mp4'),
              thumbUri: const drift.Value('media/thumb_m2.jpg'),
              capturedAt: '2026-08-15T11:00:00.000Z',
              lat: 22.56298,
              lon: 88.30085,
              observationType: const drift.Value('nonConformity'),
              activityTag: const drift.Value('Rebar'),
            ),
          );

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byType(GalleryMediaTile), findsNWidgets(2));
      expect(find.text('Progress'), findsWidgets);
      expect(find.text('Non-Conformity'), findsWidgets);
      expect(find.text('VIDEO'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('Tapping quick filter chip filters the media grid',
        (tester) async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'm1',
              siteId: const drift.Value('site-alpha'),
              creatorId: const drift.Value('test-user'),
              type: const drift.Value('photo'),
              uri: 'media/evid_m1.jpg',
              originalUri: const drift.Value('media/orig_m1.jpg'),
              thumbUri: const drift.Value('media/thumb_m1.jpg'),
              capturedAt: '2026-08-15T10:00:00.000Z',
              lat: 22.56298,
              lon: 88.30085,
              observationType: const drift.Value('progress'),
              activityTag: const drift.Value('Excavation'),
            ),
          );
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'm2',
              siteId: const drift.Value('site-alpha'),
              creatorId: const drift.Value('test-user'),
              type: const drift.Value('video'),
              uri: 'media/evid_m2.jpg',
              originalUri: const drift.Value('media/orig_m2.mp4'),
              thumbUri: const drift.Value('media/thumb_m2.jpg'),
              capturedAt: '2026-08-15T11:00:00.000Z',
              lat: 22.56298,
              lon: 88.30085,
              observationType: const drift.Value('nonConformity'),
              activityTag: const drift.Value('Rebar'),
            ),
          );

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byType(GalleryMediaTile), findsNWidgets(2));

      // Tap 'Progress' filter chip in the filter bar
      await tester.tap(find.widgetWithText(FilterChip, 'Progress'));
      await tester.pumpAndSettle();

      expect(find.byType(GalleryMediaTile), findsOneWidget);
      expect(find.text('Progress'), findsWidgets);
      expect(find.text('VIDEO'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('Tapping a tile navigates to MediaDetailScreen',
        (tester) async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'm1',
              siteId: const drift.Value('site-alpha'),
              creatorId: const drift.Value('test-user'),
              type: const drift.Value('photo'),
              uri: 'media/evid_m1.jpg',
              originalUri: const drift.Value('media/orig_m1.jpg'),
              thumbUri: const drift.Value('media/thumb_m1.jpg'),
              capturedAt: '2026-08-15T10:00:00.000Z',
              lat: 22.56298,
              lon: 88.30085,
              observationType: const drift.Value('progress'),
              activityTag: const drift.Value('Excavation'),
            ),
          );

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(GalleryMediaTile));
      await tester.pumpAndSettle();

      expect(find.byType(MediaDetailScreen), findsOneWidget);
      expect(find.text('PHOTO EVIDENCE DETAIL'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'Multi-selection mode toggles, updates count, and displays batch action bar',
        (tester) async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'm1',
              siteId: const drift.Value('site-alpha'),
              creatorId: const drift.Value('test-user'),
              type: const drift.Value('photo'),
              uri: 'media/evid_m1.jpg',
              originalUri: const drift.Value('media/orig_m1.jpg'),
              thumbUri: const drift.Value('media/thumb_m1.jpg'),
              capturedAt: '2026-08-15T10:00:00.000Z',
              lat: 22.56298,
              lon: 88.30085,
              observationType: const drift.Value('progress'),
            ),
          );
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'm2',
              siteId: const drift.Value('site-alpha'),
              creatorId: const drift.Value('test-user'),
              type: const drift.Value('photo'),
              uri: 'media/evid_m2.jpg',
              originalUri: const drift.Value('media/orig_m2.jpg'),
              thumbUri: const drift.Value('media/thumb_m2.jpg'),
              capturedAt: '2026-08-15T11:00:00.000Z',
              lat: 22.56298,
              lon: 88.30085,
              observationType: const drift.Value('general'),
            ),
          );

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Enter select mode by tapping the checklist icon in AppBar
      expect(find.byIcon(Icons.checklist_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.checklist_rounded));
      await tester.pumpAndSettle();

      expect(find.text('0 SELECTED'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);
      expect(find.text('ZIP'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      // Tap first tile to select
      await tester.tap(find.byType(GalleryMediaTile).first);
      await tester.pumpAndSettle();

      expect(find.text('1 SELECTED'), findsOneWidget);

      // Tap SELECT ALL in AppBar actions
      await tester.tap(find.text('SELECT ALL'));
      await tester.pumpAndSettle();

      expect(find.text('2 SELECTED'), findsOneWidget);
      expect(find.text('DESELECT ALL'), findsOneWidget);

      // Exit select mode via close icon
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('EVIDENCE GALLERY'), findsOneWidget);
      expect(find.text('Share'), findsNothing);
      expect(find.text('Delete'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'Long-pressing a tile opens context sheet with Find Nearby Evidence and navigation',
        (tester) async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'm1',
              siteId: const drift.Value('site-alpha'),
              creatorId: const drift.Value('test-user'),
              type: const drift.Value('photo'),
              uri: 'media/evid_m1.jpg',
              originalUri: const drift.Value('media/orig_m1.jpg'),
              thumbUri: const drift.Value('media/thumb_m1.jpg'),
              capturedAt: '2026-08-15T10:00:00.000Z',
              lat: 22.56298,
              lon: 88.30085,
              observationType: const drift.Value('progress'),
              activityTag: const drift.Value('Concrete Pour'),
            ),
          );

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Long-press first tile
      await tester.longPress(find.byType(GalleryMediaTile).first);
      await tester.pumpAndSettle();

      // Verify Context Sheet items
      expect(find.text('Find Nearby Evidence'), findsOneWidget);
      expect(find.text('View Evidence Details'), findsOneWidget);
      expect(find.text('Select Evidence (Multi-Select)'), findsOneWidget);
      expect(find.text('Share & Export Single File'), findsOneWidget);

      // Tap Find Nearby Evidence
      await tester.tap(find.text('Find Nearby Evidence'));
      await tester.pumpAndSettle();

      // Verify navigated to NearbySearchScreen
      expect(find.text('NEARBY EVIDENCE SEARCH'), findsOneWidget);
      expect(find.text('SPATIAL RADIUS'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'Multi-selection bulk Delete Selected opens confirmation, cancels, and confirms deletion properly',
        (tester) async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'del_m1',
              siteId: const drift.Value('site-alpha'),
              creatorId: const drift.Value('test-user'),
              type: const drift.Value('photo'),
              uri: 'media/evid_del_m1.jpg',
              originalUri: const drift.Value('media/orig_del_m1.jpg'),
              thumbUri: const drift.Value('media/thumb_del_m1.jpg'),
              capturedAt: '2026-08-15T10:00:00.000Z',
              lat: 22.56298,
              lon: 88.30085,
              observationType: const drift.Value('progress'),
            ),
          );
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'del_m2',
              siteId: const drift.Value('site-alpha'),
              creatorId: const drift.Value('test-user'),
              type: const drift.Value('photo'),
              uri: 'media/evid_del_m2.jpg',
              originalUri: const drift.Value('media/orig_del_m2.jpg'),
              thumbUri: const drift.Value('media/thumb_del_m2.jpg'),
              capturedAt: '2026-08-15T11:00:00.000Z',
              lat: 22.56298,
              lon: 88.30085,
              observationType: const drift.Value('general'),
            ),
          );

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Enter select mode
      await tester.tap(find.byIcon(Icons.checklist_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Delete'), findsOneWidget);

      // Select first tile
      await tester.tap(find.byType(GalleryMediaTile).first);
      await tester.pumpAndSettle();
      expect(find.text('1 SELECTED'), findsOneWidget);

      // Tap Delete button
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Verify confirmation dialog title & message (no icon)
      expect(find.text('Delete Selected'), findsOneWidget);
      expect(
          find.text(
              'Are you sure you want to delete this 1 selected media item?'),
          findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Tap Cancel -> dialog closes and selection is preserved
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('1 SELECTED'), findsOneWidget);

      // Select second tile as well
      await tester.tap(find.byType(GalleryMediaTile).at(1));
      await tester.pumpAndSettle();
      expect(find.text('2 SELECTED'), findsOneWidget);

      // Tap Delete button again
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Selected'), findsOneWidget);
      expect(
          find.text(
              'Are you sure you want to delete these 2 selected media items?'),
          findsOneWidget);

      // Confirm deletion by tapping Delete in the modal
      await tester.tap(find.descendant(
          of: find.byType(Dialog), matching: find.text('Delete')));
      await tester.pumpAndSettle();

      // Selection mode exited and items removed
      expect(find.text('2 items deleted'), findsOneWidget);
      expect(find.byType(GalleryEmptyView), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'GalleryMediaTile preserves uncropped evidence thumbnail using BoxFit.contain',
        (tester) async {
      final tempFile = File('${Directory.systemTemp.path}/media/thumb_m1.jpg')
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3, 4]);

      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'm1',
              siteId: const drift.Value('site-alpha'),
              creatorId: const drift.Value('test-user'),
              type: const drift.Value('photo'),
              uri: 'media/evid_m1.jpg',
              originalUri: const drift.Value('media/orig_m1.jpg'),
              thumbUri: const drift.Value('media/thumb_m1.jpg'),
              capturedAt: '2026-08-15T10:00:00.000Z',
              lat: 22.56298,
              lon: 88.30085,
              observationType: const drift.Value('progress'),
              activityTag: const drift.Value('Excavation'),
            ),
          );

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      final tiles = find.byType(GalleryMediaTile);
      expect(tiles, findsWidgets);

      // Verify Image within GalleryMediaTile uses BoxFit.contain
      final images = tester.widgetList<Image>(find.byType(Image));
      expect(images.every((img) => img.fit == BoxFit.contain), isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      tempFile.deleteSync();
    });
  });
}

class MockSiteRepository implements SiteRepository {
  final SiteModel site;
  MockSiteRepository(this.site);

  @override
  Future<List<SiteModel>> getAllSites({String? creatorId}) async => [site];

  @override
  Future<SiteModel?> getSiteById(String id, {String? creatorId}) async =>
      site.id == id ? site : null;

  @override
  Future<void> saveSite(SiteModel site, {String? creatorId}) async {}


  @override
  Future<void> deleteSite(String id, {String? creatorId}) async {}

  @override
  Future<bool> hasMediaForSite(String siteId, {String? creatorId}) async => false;

  @override
  Future<void> seedDefaultSitesIfEmpty() async {}

  @override
  Future<List<SiteModel>> hydrateRemoteSites(String userId) async => [];
}
