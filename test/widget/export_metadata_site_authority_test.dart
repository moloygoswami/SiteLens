import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/open.dart';
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
import 'package:sitelens/features/gallery/services/evidence_export_service.dart';
import 'package:sitelens/features/gallery/widgets/single_item_share_sheet.dart';
import 'package:sitelens/features/sites/site_controller.dart';
import 'package:sitelens/features/sync/services/cloud_sync_service.dart';
import 'package:sitelens/features/sync/services/sync_coordinator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

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

class MockSessionService extends StateNotifier<UserSessionState>
    implements SessionService {
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestSiteRepository implements SiteRepository {
  final List<SiteModel> sites;
  TestSiteRepository(this.sites);

  @override
  Future<List<SiteModel>> getAllSites({String? creatorId}) async => sites;

  @override
  Future<SiteModel?> getSiteById(String id, {String? creatorId}) async {
    return sites.where((s) => s.id == id).firstOrNull;
  }

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

class MockEvidenceExportService extends EvidenceExportService {
  MockEvidenceExportService(super.storageService);

  String? lastSharedPath;
  String? lastSharedText;
  MediaItem? lastExportedItem;
  String? lastExportedSiteCode;
  String? lastExportedSiteName;
  List<MediaItem>? lastBatchPdfItems;
  String? lastBatchPdfSiteCode;
  String? lastBatchPdfSiteName;
  List<MediaItem>? lastBatchZipItems;
  String? lastBatchZipSiteCode;
  String? lastBatchZipSiteName;

  @override
  Future<void> shareSingleFile(String absolutePath, {String? text}) async {
    lastSharedPath = absolutePath;
    lastSharedText = text;
  }

  @override
  Future<void> exportSingleInspectionNotePdf({
    required MediaItem item,
    String? siteCode,
    String? siteName,
    String? exporterEmail,
    String? exporterUid,
    Uint8List? imageBytes,
    EvidenceReportMode mode = EvidenceReportMode.standardInspectionNote,
  }) async {
    lastExportedItem = item;
    lastExportedSiteCode = siteCode;
    lastExportedSiteName = siteName;
  }

  @override
  Future<void> exportBatchPdf(
    List<MediaItem> items, {
    String? siteCode,
    String? siteName,
    String? exporterEmail,
    String? exporterUid,
    EvidenceReportMode mode = EvidenceReportMode.standardInspectionNote,
  }) async {
    lastBatchPdfItems = items;
    lastBatchPdfSiteCode = siteCode;
    lastBatchPdfSiteName = siteName;
  }

  @override
  Future<void> exportBatchZip(
    List<MediaItem> items, {
    String? siteCode,
    String? siteName,
    String? exporterEmail,
    String? exporterUid,
    EvidenceReportMode mode = EvidenceReportMode.standardInspectionNote,
  }) async {
    lastBatchZipItems = items;
    lastBatchZipSiteCode = siteCode;
    lastBatchZipSiteName = siteName;
  }
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    open.overrideFor(
        OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  const siteA = SiteModel(
    id: 'site-a',
    siteCode: 'ALPHA',
    name: 'Sector Alpha',
    address: '100 Alpha Way',
    creatorId: 'test-user',
  );

  const siteB = SiteModel(
    id: 'site-b',
    siteCode: 'BRAVO',
    name: 'Sector Bravo',
    address: '200 Bravo Way',
    creatorId: 'test-user',
  );

  late AppDatabase db;
  late MediaRepository mediaRepo;
  late TestEvidenceStorageService storageService;
  late TestSiteRepository siteRepo;
  late MockEvidenceExportService mockExportService;
  late File fakeMediaFile;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'sitelens_active_site_id': 'site-b'});
    db = AppDatabase(NativeDatabase.memory());
    storageService = TestEvidenceStorageService();
    mediaRepo = LocalMediaRepository(db, storageService: storageService);
    siteRepo = TestSiteRepository([siteA, siteB]);
    mockExportService = MockEvidenceExportService(storageService);

    fakeMediaFile = File('${Directory.systemTemp.path}/media/evid_test.jpg');
    fakeMediaFile.parent.createSync(recursive: true);
    fakeMediaFile.writeAsBytesSync([1, 2, 3, 4]);
  });

  tearDown(() async {
    await db.close();
    if (fakeMediaFile.existsSync()) {
      fakeMediaFile.deleteSync();
    }
  });

  final itemSiteA = MediaItem(
    id: 'item-site-a-1',
    siteId: 'site-a',
    creatorId: 'test-user',
    originalUri: 'media/orig_test.jpg',
    uri: 'media/evid_test.jpg',
    thumbUri: 'media/thumb_test.jpg',
    type: MediaItemType.photo,
    lat: 22.56298,
    lon: 88.30085,
    capturedAt: DateTime.utc(2026, 8, 15, 10, 0, 0),
    capturedAddress: '42 Alpha Boulevard',
    sha256Hash: 'a' * 64,
    evidenceSha256Hash: 'b' * 64,
    syncStatus: SyncStatusType.pending,
    isDeleted: false,
  );

  final itemSiteA2 = MediaItem(
    id: 'item-site-a-2',
    siteId: 'site-a',
    creatorId: 'test-user',
    originalUri: 'media/orig_test2.jpg',
    uri: 'media/evid_test2.jpg',
    thumbUri: 'media/thumb_test2.jpg',
    type: MediaItemType.photo,
    lat: 22.56300,
    lon: 88.30090,
    capturedAt: DateTime.utc(2026, 8, 15, 10, 5, 0),
    capturedAddress: '44 Alpha Boulevard',
    sha256Hash: 'c' * 64,
    evidenceSha256Hash: 'd' * 64,
    syncStatus: SyncStatusType.pending,
    isDeleted: false,
  );

  final itemSiteB = MediaItem(
    id: 'item-site-b-1',
    siteId: 'site-b',
    creatorId: 'test-user',
    originalUri: 'media/orig_test_b.jpg',
    uri: 'media/evid_test_b.jpg',
    thumbUri: 'media/thumb_test_b.jpg',
    type: MediaItemType.photo,
    lat: 22.60000,
    lon: 88.40000,
    capturedAt: DateTime.utc(2026, 8, 15, 11, 0, 0),
    capturedAddress: '10 Bravo Road',
    sha256Hash: 'e' * 64,
    evidenceSha256Hash: 'f' * 64,
    syncStatus: SyncStatusType.pending,
    isDeleted: false,
  );

  Widget createShareSheetTestWidget({
    required MediaItem item,
    SiteModel? activeSite = siteB,
  }) {
    return ProviderScope(
      overrides: [
        evidenceStorageServiceProvider.overrideWithValue(storageService),
        evidenceExportServiceProvider.overrideWithValue(mockExportService),
        siteRepositoryProvider.overrideWithValue(siteRepo),
        authServiceProvider.overrideWithValue(TestAuthService()),
        siteControllerProvider.overrideWith((ref) {
          final ctrl = SiteController(siteRepo, initialUserId: 'test-user');
          if (activeSite != null) {
            ctrl.setActiveSite(activeSite);
          }
          return ctrl;
        }),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => SingleItemShareSheet.show(ctx, item),
                child: const Text('OPEN SHEET'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget createGalleryTestWidget({
    SiteModel? activeSite = siteB,
    String? filterSiteId,
    List<MediaItem>? overrideMediaItems,
  }) {
    return ProviderScope(
      overrides: [
        if (filterSiteId != null)
          galleryFilterProvider.overrideWith((ref) {
            final notifier = GalleryFilterNotifier();
            notifier.setSiteId(filterSiteId);
            return notifier;
          }),
        if (overrideMediaItems != null)
          filteredGalleryMediaProvider
              .overrideWith((ref) => Stream.value(overrideMediaItems)),
        evidenceStorageServiceProvider.overrideWithValue(storageService),
        evidenceExportServiceProvider.overrideWithValue(mockExportService),
        mediaRepositoryProvider.overrideWithValue(mediaRepo),
        siteRepositoryProvider.overrideWithValue(siteRepo),
        authServiceProvider.overrideWithValue(TestAuthService()),
        siteControllerProvider.overrideWith((ref) {
          final ctrl = SiteController(siteRepo, initialUserId: 'test-user');
          if (activeSite != null) {
            ctrl.setActiveSite(activeSite);
          }
          return ctrl;
        }),
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

  group('M3 Regression: RD-M3-01 Export Metadata Site Authority', () {
    testWidgets(
        'A. Single-item share: Evidence captured under Site A with Site B active exports Site A metadata',
        (tester) async {
      await tester.pumpWidget(createShareSheetTestWidget(
        item: itemSiteA,
        activeSite: siteB, // Site B is currently active
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('OPEN SHEET'));
      await tester.pumpAndSettle();

      // Tap Option 1: Share Evidence Photo
      final shareTile = find.text('Share Evidence Photo (JPEG)');
      expect(shareTile, findsOneWidget);
      await tester.tap(shareTile);
      await tester.pumpAndSettle();

      // Verify share text uses Site A (ALPHA), NOT Site B (BRAVO)
      expect(mockExportService.lastSharedText, isNotNull);
      expect(
        mockExportService.lastSharedText,
        'SiteLens Evidence: ALPHA • 42 Alpha Boulevard',
      );
      expect(mockExportService.lastSharedText!.contains('BRAVO'), isFalse);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'B. Single-item PDF: Evidence captured under Site A with Site B active exports inspection note using Site A code and name',
        (tester) async {
      await tester.pumpWidget(createShareSheetTestWidget(
        item: itemSiteA,
        activeSite: siteB, // Site B is currently active
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('OPEN SHEET'));
      await tester.pumpAndSettle();

      // Tap Option 2: Export PDF Inspection Note
      final pdfTile = find.text('Export PDF Inspection Note');
      expect(pdfTile, findsOneWidget);
      await tester.tap(pdfTile);
      await tester.pumpAndSettle();

      // Verify exported PDF metadata uses Site A, NOT Site B
      expect(mockExportService.lastExportedSiteCode, 'ALPHA');
      expect(mockExportService.lastExportedSiteName, 'Sector Alpha');
      expect(mockExportService.lastExportedSiteCode == 'BRAVO', isFalse);
      expect(mockExportService.lastExportedSiteName == 'Sector Bravo', isFalse);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'C. Batch same-site: Multiple Site A items with Site B active export batch using Site A',
        (tester) async {
      // Seed both Site A items into SQLite
      await mediaRepo.insertMedia(itemSiteA);
      await mediaRepo.insertMedia(itemSiteA2);

      await tester.pumpWidget(createGalleryTestWidget(
        activeSite: siteB,
        filterSiteId: 'site-a',
      ));
      await tester.pumpAndSettle();

      // Enter select mode
      final selectButton = find.byIcon(Icons.checklist_rounded);
      expect(selectButton, findsOneWidget);
      await tester.tap(selectButton);
      await tester.pumpAndSettle();

      // Tap SELECT ALL
      final selectAllButton = find.text('SELECT ALL');
      expect(selectAllButton, findsOneWidget);
      await tester.tap(selectAllButton);
      await tester.pumpAndSettle();

      // Tap PDF Batch export button in bottom bar
      final pdfBatchButton = find.text('PDF');
      expect(pdfBatchButton, findsOneWidget);
      await tester.tap(pdfBatchButton);
      await tester.pumpAndSettle();

      // Verify batch PDF receives Site A, NOT Site B
      expect(mockExportService.lastBatchPdfSiteCode, 'ALPHA');
      expect(mockExportService.lastBatchPdfSiteName, 'Sector Alpha');

      // Tap ZIP Batch export button in bottom bar
      final zipBatchButton = find.text('ZIP');
      expect(zipBatchButton, findsOneWidget);
      await tester.tap(zipBatchButton);
      await tester.pumpAndSettle();

      // Verify batch ZIP receives Site A, NOT Site B
      expect(mockExportService.lastBatchZipSiteCode, 'ALPHA');
      expect(mockExportService.lastBatchZipSiteName, 'Sector Alpha');

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'D. Batch multi-site: Site A and Site B items selected export with neutral site context (null)',
        (tester) async {
      // Seed 1 Site A item and 1 Site B item
      await mediaRepo.insertMedia(itemSiteA);
      await mediaRepo.insertMedia(itemSiteB);

      await tester.pumpWidget(createGalleryTestWidget(
        activeSite: siteB,
        overrideMediaItems: [itemSiteA, itemSiteB],
      ));
      await tester.pumpAndSettle();

      // Enter select mode
      final selectButton = find.byIcon(Icons.checklist_rounded);
      expect(selectButton, findsOneWidget);
      await tester.tap(selectButton);
      await tester.pumpAndSettle();

      // Select all items (one from Site A, one from Site B)
      final selectAllButton = find.text('SELECT ALL');
      expect(selectAllButton, findsOneWidget);
      await tester.tap(selectAllButton);
      await tester.pumpAndSettle();

      // Tap PDF Batch export
      final pdfBatchButton = find.text('PDF');
      expect(pdfBatchButton, findsOneWidget);
      await tester.tap(pdfBatchButton);
      await tester.pumpAndSettle();

      // Verify multi-site batch uses neutral site context (null), NOT Site A or Site B
      expect(mockExportService.lastBatchPdfSiteCode, isNull);
      expect(mockExportService.lastBatchPdfSiteName, isNull);

      // Tap ZIP Batch export
      final zipBatchButton = find.text('ZIP');
      expect(zipBatchButton, findsOneWidget);
      await tester.tap(zipBatchButton);
      await tester.pumpAndSettle();

      // Verify multi-site batch ZIP uses neutral site context (null)
      expect(mockExportService.lastBatchZipSiteCode, isNull);
      expect(mockExportService.lastBatchZipSiteName, isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'E. No active site: Historical evidence exports using its persisted site identity',
        (tester) async {
      // Active site is explicitly null
      await tester.pumpWidget(createShareSheetTestWidget(
        item: itemSiteA,
        activeSite: null,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('OPEN SHEET'));
      await tester.pumpAndSettle();

      // Tap Option 2: Export PDF Inspection Note
      final pdfTile = find.text('Export PDF Inspection Note');
      expect(pdfTile, findsOneWidget);
      await tester.tap(pdfTile);
      await tester.pumpAndSettle();

      // Verify exported PDF metadata resolves Site A from persisted siteId
      expect(mockExportService.lastExportedSiteCode, 'ALPHA');
      expect(mockExportService.lastExportedSiteName, 'Sector Alpha');

      // Open sheet again since Option 2 popped the bottom sheet
      await tester.tap(find.text('OPEN SHEET'));
      await tester.pumpAndSettle();

      // Tap Option 1: Share Evidence Photo
      final shareTile = find.text('Share Evidence Photo (JPEG)');
      expect(shareTile, findsOneWidget);
      await tester.tap(shareTile);
      await tester.pumpAndSettle();

      // Verify share text uses Site A (ALPHA)
      expect(mockExportService.lastSharedText, isNotNull);
      expect(
        mockExportService.lastSharedText,
        'SiteLens Evidence: ALPHA • 42 Alpha Boulevard',
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}
