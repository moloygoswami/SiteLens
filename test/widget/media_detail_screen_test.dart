// ignore_for_file: subtype_of_sealed_class, must_be_immutable
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/open.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/data/repositories/site_repository.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/domain/models/site_model.dart';
import 'package:sitelens/core/services/auth_service.dart';
import 'package:sitelens/features/camera/services/evidence_storage_service.dart';
import 'package:sitelens/features/gallery/media_detail_screen.dart';
import 'package:sitelens/features/gallery/widgets/media_tag_edit_modal.dart';
import 'package:sitelens/features/sites/site_controller.dart';
import 'package:sitelens/features/sync/services/cloud_media_recovery_service.dart';

class FakeCloudMediaRecoveryService extends CloudMediaRecoveryService {
  int recoverCalls = 0;
  MediaItem? lastRecoveredItem;
  bool shouldFail = false;

  FakeCloudMediaRecoveryService(EvidenceStorageService storageService)
      : super(
          storage: FakeFirebaseStorage(),
          storageService: storageService,
        );

  @override
  Future<File> recoverOriginal({
    required MediaItem item,
    void Function(double progress)? onProgress,
  }) async {
    recoverCalls++;
    lastRecoveredItem = item;
    if (shouldFail) {
      throw Exception('Network download failed');
    }
    onProgress?.call(1.0);
    return File('/mock/path/${item.originalUri}');
  }
}

class FakeFirebaseStorage implements FirebaseStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  late MediaRepository mediaRepo;
  late FakeEvidenceStorageService storageService;
  late FakeCloudMediaRecoveryService recoveryService;

  const testSite = SiteModel(
    id: 'site-alpha',
    siteCode: 'SL-001',
    name: 'Sector Alpha',
    address: '100 Construction Way',
  );

  final testPhotoItem = MediaItem(
    id: 'm1',
    siteId: 'site-alpha',
    type: MediaItemType.photo,
    uri: 'media/evid_m1.jpg',
    originalUri: 'media/orig_m1.jpg',
    thumbUri: 'media/thumb_m1.jpg',
    capturedAt: DateTime.utc(2026, 8, 15, 10, 30, 0),
    lat: 22.56298,
    lon: 88.30085,
    accuracyM: 3.5,
    lowAccuracy: false,
    activityTag: 'Excavation',
    observationType: ObservationType.progress,
    note: 'Trench excavation completed to bedrock',
    sha256Hash:
        'a1b2c3d4e5f678901234567890abcdef1234567890abcdef1234567890abcdef',
    syncStatus: SyncStatusType.pending,
    isDeleted: false,
  );

  final testSyncedPhotoItem = MediaItem(
    id: 'm2',
    siteId: 'site-alpha',
    type: MediaItemType.photo,
    uri: 'media/evid_m2.jpg',
    originalUri: 'media/orig_m2.jpg',
    thumbUri: 'media/thumb_m2.jpg',
    capturedAt: DateTime.utc(2026, 8, 15, 11, 0, 0),
    lat: 22.56298,
    lon: 88.30085,
    accuracyM: 3.5,
    lowAccuracy: false,
    activityTag: 'Concrete Pave',
    observationType: ObservationType.general,
    note: 'Pavement slab poured',
    sha256Hash:
        'b2c3d4e5f678901234567890abcdef1234567890abcdef1234567890abcdefa1',
    syncStatus: SyncStatusType.synced,
    isDeleted: false,
  );

  final testSyncedVideoItem = MediaItem(
    id: 'v1',
    siteId: 'site-alpha',
    type: MediaItemType.video,
    uri: 'media/orig_v1.mp4',
    originalUri: 'media/orig_v1.mp4',
    thumbUri: 'media/thumb_v1.jpg',
    capturedAt: DateTime.utc(2026, 8, 15, 12, 0, 0),
    lat: 22.56298,
    lon: 88.30085,
    accuracyM: 4.0,
    lowAccuracy: false,
    activityTag: 'Safety Walk',
    observationType: ObservationType.general,
    note: 'Walkthrough of site perimeter',
    sha256Hash:
        'c3d4e5f678901234567890abcdef1234567890abcdef1234567890abcdefa1b2',
    syncStatus: SyncStatusType.synced,
    isDeleted: false,
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
    storageService = FakeEvidenceStorageService();
    recoveryService = FakeCloudMediaRecoveryService(storageService);
    mediaRepo = LocalMediaRepository(db, storageService: storageService);

    // Seed test media into DB
    for (final item in [
      testPhotoItem,
      testSyncedPhotoItem,
      testSyncedVideoItem
    ]) {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: item.id,
              siteId: drift.Value(item.siteId),
              type: drift.Value(item.type.name),
              uri: item.uri,
              originalUri: drift.Value(item.originalUri),
              thumbUri: drift.Value(item.thumbUri),
              capturedAt: item.capturedAt.toIso8601String(),
              lat: item.lat,
              lon: item.lon,
              accuracyM: drift.Value(item.accuracyM),
              lowAccuracy: const drift.Value(0),
              activityTag: drift.Value(item.activityTag),
              observationType: drift.Value(item.observationType.name),
              note: drift.Value(item.note),
              sha256Hash: drift.Value(item.sha256Hash),
              synced: drift.Value(item.syncStatus.toInt()),
            ),
          );
    }
  });

  tearDown(() async {
    await db.close();
  });

  Widget createWidgetUnderTest(MediaItem item) {
    return ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(MockAuthService()),
        evidenceStorageServiceProvider.overrideWithValue(storageService),
        cloudMediaRecoveryServiceProvider.overrideWithValue(recoveryService),
        mediaRepositoryProvider.overrideWithValue(mediaRepo),
        siteRepositoryProvider.overrideWithValue(MockSiteRepository(testSite)),
        siteControllerProvider.overrideWith(
          (ref) => SiteController(MockSiteRepository(testSite)),
        ),
      ],
      child: MaterialApp(
        home: MediaDetailScreen(mediaItem: item),
      ),
    );
  }

  group('MediaDetailScreen Widget Tests', () {
    testWidgets('Displays capture-time historical telemetry & metadata',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest(testPhotoItem));
      await tester.pumpAndSettle();

      expect(find.text('PHOTO EVIDENCE DETAIL'), findsOneWidget);
      expect(find.text('PROGRESS'), findsOneWidget);
      expect(find.text('Excavation'), findsOneWidget);
      expect(find.textContaining('GPS PRECISION: ±3.5m'), findsOneWidget);
      expect(
          find.text('Trench excavation completed to bedrock'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'Displays original and evidence file paths and copies SHA-256 hash',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest(testPhotoItem));
      await tester.pumpAndSettle();

      // Ensure SHA-256 card is scrolled into view
      await tester.ensureVisible(find.byIcon(Icons.copy_rounded));
      await tester.pumpAndSettle();

      expect(find.text('ORIGINAL: media/orig_m1.jpg'), findsOneWidget);
      expect(find.text('EVIDENCE: media/evid_m1.jpg'), findsOneWidget);
      expect(find.text('THUMBNAIL: media/thumb_m1.jpg'), findsOneWidget);

      // Tap copy SHA-256 icon
      await tester.tap(find.byIcon(Icons.copy_rounded));
      await tester.pump();

      expect(find.text('Full SHA-256 Checksum copied to clipboard'),
          findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'Unsynced deletion presents simple confirmation dialog and permanently deletes local files and DB row',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest(testPhotoItem));
      await tester.pumpAndSettle();

      // Tap delete icon in AppBar
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();

      // Verify simple confirmation dialog
      expect(find.text('Delete Media'), findsOneWidget);
      expect(find.text('Are you sure you want to delete this media?'),
          findsOneWidget);

      // Tap Delete button
      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
      await tester.pumpAndSettle();

      // Verify row in SQLite is deleted and all local media files unlinked
      final raw = await (db.select(db.media)
            ..where((t) => t.id.equals(testPhotoItem.id)))
          .getSingleOrNull();
      expect(raw, isNull);
      expect(storageService.deletedFiles.contains('media/orig_m1.jpg'), isTrue);
      expect(storageService.deletedFiles.contains('media/evid_m1.jpg'), isTrue);
      expect(
          storageService.deletedFiles.contains('media/thumb_m1.jpg'), isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'Synced deletion presents simple confirmation dialog, frees local media and marks is_deleted = 1',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest(testSyncedPhotoItem));
      await tester.pumpAndSettle();

      // Tap delete icon in AppBar
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();

      // Verify simple confirmation dialog without decorative trash icon
      expect(find.text('Delete Media'), findsOneWidget);
      expect(find.text('Are you sure you want to delete this media?'),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(Dialog),
              matching: find.byIcon(Icons.delete_outline_rounded)),
          findsNothing);

      // Tap Delete button
      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
      await tester.pumpAndSettle();

      // Verify all local media files deleted and DB row is marked is_deleted = 1
      final raw = await (db.select(db.media)
            ..where((t) => t.id.equals(testSyncedPhotoItem.id)))
          .getSingle();
      expect(raw.isDeleted, equals(1));
      expect(storageService.deletedFiles.contains('media/orig_m2.jpg'), isTrue);
      expect(storageService.deletedFiles.contains('media/evid_m2.jpg'), isTrue);
      expect(
          storageService.deletedFiles.contains('media/thumb_m2.jpg'), isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'Synced photo with missing local original displays Download Original button and recovers',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest(testSyncedPhotoItem));
      await tester.pumpAndSettle();

      expect(find.text('ORIGINAL STORED IN CLOUD'), findsOneWidget);
      expect(find.text('DOWNLOAD ORIGINAL'), findsOneWidget);

      // Tap Download Original
      await tester.tap(find.text('DOWNLOAD ORIGINAL'));
      await tester.pumpAndSettle();

      expect(recoveryService.recoverCalls, equals(1));
      expect(recoveryService.lastRecoveredItem?.id, equals('m2'));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'Synced video with missing local original displays Download & Play Video button',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest(testSyncedVideoItem));
      await tester.pumpAndSettle();

      expect(find.text('VIDEO STORED IN CLOUD'), findsOneWidget);
      expect(find.text('DOWNLOAD & PLAY VIDEO'), findsOneWidget);

      // Tap Download & Play Video
      await tester.tap(find.text('DOWNLOAD & PLAY VIDEO'));
      await tester.pumpAndSettle();

      expect(recoveryService.recoverCalls, equals(1));
      expect(recoveryService.lastRecoveredItem?.id, equals('v1'));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('Opens Edit Tags modal and enforces strict Closed linking rule',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest(testPhotoItem));
      await tester.pumpAndSettle();

      // Tap edit tags icon in AppBar
      await tester.tap(find.byIcon(Icons.edit_note_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(MediaTagEditModal), findsOneWidget);
      expect(find.text('EDIT EVIDENCE TAGS'), findsOneWidget);

      // Select 'Closed' observation type when no eligible Before candidate exists
      await tester.tap(find.text('Closed'));
      await tester.pumpAndSettle();

      // Verify save is blocked with warning banner
      expect(find.text('NO OPEN NON-CONFORMITY WITHIN 10M'), findsOneWidget);
      expect(find.text('Link BEFORE to Save'), findsOneWidget);

      // Switch back to 'Material'
      await tester.tap(find.text('Material'));
      await tester.pumpAndSettle();

      // Verify Save button is unlocked
      expect(find.text('Save Changes'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('Tapping Share icon in AppBar opens SingleItemShareSheet',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest(testPhotoItem));
      await tester.pumpAndSettle();

      // Find and tap the Share action button in AppBar
      expect(find.byIcon(Icons.ios_share_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.ios_share_rounded));
      await tester.pumpAndSettle();

      // Verify share sheet header and options appear
      expect(find.text('SHARE & EXPORT EVIDENCE'), findsOneWidget);
      expect(find.text('Share Evidence Photo (JPEG)'), findsOneWidget);
      expect(find.text('Export PDF Inspection Note'), findsOneWidget);
      expect(find.text('Copy SHA-256 Checksum'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'Tapping Fullscreen Zoom opens canonical evidence JPEG without duplicate HUD overlay',
        (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('sitelens_test_');
      final evidFile = File('${tempDir.path}/evid_m1.jpg')
        ..writeAsBytesSync([1, 2, 3, 4]);
      final origFile = File('${tempDir.path}/orig_m1.jpg')
        ..writeAsBytesSync([5, 6, 7, 8]);
      final customStorage = FakeEvidenceStorageServiceMap({
        'media/evid_m1.jpg': evidFile.path,
        'media/orig_m1.jpg': origFile.path,
      });

      await tester.pumpWidget(ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(MockAuthService()),
          evidenceStorageServiceProvider.overrideWithValue(customStorage),
          cloudMediaRecoveryServiceProvider.overrideWithValue(recoveryService),
          mediaRepositoryProvider.overrideWithValue(mediaRepo),
          siteRepositoryProvider
              .overrideWithValue(MockSiteRepository(testSite)),
          siteControllerProvider.overrideWith(
            (ref) => SiteController(MockSiteRepository(testSite)),
          ),
        ],
        child: MaterialApp(
          home: MediaDetailScreen(mediaItem: testPhotoItem),
        ),
      ));
      await tester.pumpAndSettle();

      // Find and tap Fullscreen Zoom action
      expect(find.text('Fullscreen Zoom'), findsOneWidget);
      await tester.tap(find.text('Fullscreen Zoom'));
      await tester.pumpAndSettle();

      // Verify InteractiveViewer is present with the canonical evidence file
      expect(find.byType(InteractiveViewer), findsOneWidget);
      final imageFinder = find.byType(Image);
      expect(imageFinder, findsWidgets);

      // Verify Immersive Evidence Viewer header is present
      expect(find.text('IMMERSIVE EVIDENCE VIEWER'), findsOneWidget);

      // Verify tap on photo toggles header off
      await tester.tap(find.byType(InteractiveViewer));
      await tester.pumpAndSettle();
      expect(find.text('IMMERSIVE EVIDENCE VIEWER'), findsNothing);

      // Verify second tap toggles header back on
      await tester.tap(find.byType(InteractiveViewer));
      await tester.pumpAndSettle();
      expect(find.text('IMMERSIVE EVIDENCE VIEWER'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      tempDir.deleteSync(recursive: true);
    });

    testWidgets(
        'Photo Evidence Detail and Immersive Viewer preserve native aspect ratio without 3:4 constraint and use BoxFit.contain',
        (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('aspect_test_');
      final evidFile = File('${tempDir.path}/evid_m1.jpg')
        ..writeAsBytesSync([1, 2, 3, 4]);
      final customStorage = FakeEvidenceStorageServiceMap({
        'media/evid_m1.jpg': evidFile.path,
        'media/orig_m1.jpg': evidFile.path,
      });

      await tester.pumpWidget(ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(MockAuthService()),
          evidenceStorageServiceProvider.overrideWithValue(customStorage),
          cloudMediaRecoveryServiceProvider.overrideWithValue(recoveryService),
          mediaRepositoryProvider.overrideWithValue(mediaRepo),
          siteRepositoryProvider
              .overrideWithValue(MockSiteRepository(testSite)),
          siteControllerProvider.overrideWith(
            (ref) => SiteController(MockSiteRepository(testSite)),
          ),
        ],
        child: MaterialApp(
          home: MediaDetailScreen(mediaItem: testPhotoItem),
        ),
      ));
      await tester.pumpAndSettle();

      // 1. Verify Photo Detail does not have a 3:4 AspectRatio widget constraining the photo
      final detailAspectRatios =
          tester.widgetList<AspectRatio>(find.byType(AspectRatio));
      expect(
          detailAspectRatios
              .where((ar) => (ar.aspectRatio - 0.75).abs() < 0.001),
          isEmpty);

      // Verify Detail Image uses BoxFit.contain
      final detailImages = tester.widgetList<Image>(find.byType(Image));
      expect(detailImages.any((img) => img.fit == BoxFit.contain), isTrue);
      expect(detailImages.any((img) => img.fit == BoxFit.cover), isFalse);

      // 2. Open Fullscreen Zoom (Immersive Viewer)
      await tester.tap(find.text('Fullscreen Zoom'));
      await tester.pumpAndSettle();

      // Verify Immersive Viewer does not have a 3:4 AspectRatio widget
      final immersiveAspectRatios =
          tester.widgetList<AspectRatio>(find.byType(AspectRatio));
      expect(
          immersiveAspectRatios
              .where((ar) => (ar.aspectRatio - 0.75).abs() < 0.001),
          isEmpty);

      // Verify Immersive Image uses BoxFit.contain
      final immersiveImages = tester.widgetList<Image>(find.byType(Image));
      expect(immersiveImages.any((img) => img.fit == BoxFit.contain), isTrue);
      expect(immersiveImages.any((img) => img.fit == BoxFit.cover), isFalse);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      tempDir.deleteSync(recursive: true);
    });

    testWidgets('Photo Evidence Detail maintains canonical portrait viewport (screenHeight * 0.54)', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SharedPreferences.setMockInitialValues({});

      final tempDir = Directory.systemTemp.createTempSync('sitelens_detail_port_');
      final evidFile = File('${tempDir.path}/evid_m1.jpg');
      evidFile.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x01, 0x00, 0x60, 0x00, 0x60, 0x00, 0x00, 0xFF, 0xD9]);

      final customStorage = FakeEvidenceStorageServiceMap({
        'media/evid_m1.jpg': evidFile.path,
        'media/orig_m1.jpg': evidFile.path,
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authServiceProvider.overrideWithValue(MockAuthService()),
            evidenceStorageServiceProvider.overrideWithValue(customStorage),
            cloudMediaRecoveryServiceProvider.overrideWithValue(recoveryService),
            mediaRepositoryProvider.overrideWithValue(mediaRepo),
            siteRepositoryProvider.overrideWithValue(MockSiteRepository(testSite)),
            siteControllerProvider.overrideWith(
              (ref) => SiteController(MockSiteRepository(testSite)),
            ),
          ],
          child: MaterialApp(
            home: MediaDetailScreen(mediaItem: testPhotoItem),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify overall screen remains in portrait (app bar, tags, and observations are rendered)
      expect(find.text('PHOTO EVIDENCE DETAIL'), findsOneWidget);
      expect(find.text('PROGRESS'), findsOneWidget);
      expect(find.text('Excavation'), findsOneWidget);

      // In portrait policy, photo viewport height is screenHeight * 0.54 (1600 * 0.54 = 864)
      final interactiveViewerFinder = find.byType(InteractiveViewer);
      expect(interactiveViewerFinder, findsOneWidget);
      final size = tester.getSize(interactiveViewerFinder);
      expect(size.width, equals(800.0));
      expect(size.height, equals(864.0));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      tempDir.deleteSync(recursive: true);
    });

    testWidgets(
        'Downstream invariant: MediaDetailScreen renders burned image file and contains zero GoogleMap widgets',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest(testPhotoItem));
      await tester.pumpAndSettle();

      // Confirms the viewer renders using InteractiveViewer with Image
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byType(Image), findsWidgets);

      // Proves the downstream contract: zero GoogleMap platform views in the widget tree
      expect(
        find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == 'GoogleMap',
        ),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}

class FakeEvidenceStorageServiceMap extends FakeEvidenceStorageService {
  final Map<String, String> pathMap;
  FakeEvidenceStorageServiceMap(this.pathMap);

  @override
  Future<String> resolveAbsolutePath(String relativePath) async {
    return pathMap[relativePath] ?? '/mock/path/$relativePath';
  }
}

class FakeEvidenceStorageServiceWithFile extends FakeEvidenceStorageService {
  final String actualFilePath;
  FakeEvidenceStorageServiceWithFile(this.actualFilePath);

  @override
  Future<String> resolveAbsolutePath(String relativePath) async {
    return actualFilePath;
  }
}

class FakeEvidenceStorageService extends EvidenceStorageService {
  final List<String> deletedFiles = [];

  @override
  Future<String> resolveAbsolutePath(String relativePath) async {
    return '/mock/path/$relativePath';
  }

  @override
  Future<void> deleteLocalMediaFiles({
    required String mediaId,
    String? originalUri,
    String? uri,
    String? thumbUri,
    String? type,
  }) async {
    if (originalUri != null && originalUri.isNotEmpty) {
      deletedFiles.add(originalUri);
    }
    if (uri != null && uri.isNotEmpty && uri != originalUri) {
      deletedFiles.add(uri);
    }
    if (thumbUri != null && thumbUri.isNotEmpty) {
      deletedFiles.add(thumbUri);
    }
  }
}

class MockSiteRepository implements SiteRepository {
  final SiteModel site;
  MockSiteRepository(this.site);

  @override
  Future<List<SiteModel>> getAllSites({String? creatorId}) async => [site];

  @override
  Future<SiteModel?> getSiteById(String id) async =>
      site.id == id ? site : null;

  @override
  Future<void> saveSite(SiteModel site) async {}

  @override
  Future<void> deleteSite(String id) async {}

  @override
  Future<void> seedDefaultSitesIfEmpty() async {}
}

class MockAuthService implements AuthService {
  final AuthUser _user = const AuthUser(
    uid: 'test-inspector-uid',
    email: 'inspector@company.com',
    displayName: 'Test Inspector',
  );

  @override
  Stream<AuthUser?> get authStateChanges => Stream.value(_user);

  @override
  AuthUser? get currentUser => _user;

  @override
  Future<AuthUser> signInWithEmailPassword(
          String email, String password) async =>
      _user;

  @override
  Future<AuthUser?> signInWithGoogle() async => _user;

  @override
  Future<AuthUser> signUpWithEmailPassword(
    String email,
    String password, {
    String? displayName,
  }) async =>
      _user;

  @override
  Future<void> sendEmailVerificationForUser(
      String email, String password) async {}

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<void> signOut() async {}
}
