import 'dart:ffi';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/open.dart';
import 'package:sitelens/core/services/auth_service.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/data/repositories/site_repository.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/domain/models/site_model.dart';
import 'package:sitelens/features/camera/services/evidence_storage_service.dart';
import 'package:sitelens/features/gallery/media_detail_screen.dart';
import 'package:sitelens/features/gallery/services/evidence_export_service.dart';
import 'package:sitelens/features/gallery/widgets/single_item_share_sheet.dart';
import 'package:sitelens/features/sites/site_controller.dart';

/// The two persisted digests identify two different artifacts. They are always
/// distinct in production for photos (burned evidence JPEG vs immutable
/// original) and intentionally identical for videos (one recorded MP4).
const String originalSha =
    'a1b2c3d4e5f678901234567890abcdef1234567890abcdef1234567890abcdef';
const String evidenceSha =
    'f1e2d3c4b5a678901234567890abcdef1234567890abcdef1234567890abcdef';
const String videoSha =
    'c3d4e5f678901234567890abcdef1234567890abcdef1234567890abcdefa1b2';

const String originalShaPrefix = 'a1b2c3d4e5f67890';
const String evidenceShaPrefix = 'f1e2d3c4b5a67890';
const String videoShaPrefix = 'c3d4e5f678901234';

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

class TestEvidenceStorageService implements EvidenceStorageService {
  @override
  Future<Directory> getMediaDirectory() async => Directory.systemTemp;

  @override
  Future<String> resolveAbsolutePath(String relativePath) async =>
      '${Directory.systemTemp.path}/$relativePath';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestSiteRepository implements SiteRepository {
  final List<SiteModel> sites;
  TestSiteRepository(this.sites);

  @override
  Future<List<SiteModel>> getAllSites({String? creatorId}) async => sites;

  @override
  Future<SiteModel?> getSiteById(String id, {String? creatorId}) async =>
      sites.where((s) => s.id == id).firstOrNull;

  @override
  Future<void> saveSite(SiteModel site) async {}

  @override
  Future<void> deleteSite(String id, {String? creatorId}) async {}

  @override
  Future<bool> hasMediaForSite(String siteId, {String? creatorId}) async =>
      false;

  @override
  Future<void> seedDefaultSitesIfEmpty() async {}

  @override
  Future<List<SiteModel>> hydrateRemoteSites(String userId) async => [];
}

class CapturingExportService extends EvidenceExportService {
  CapturingExportService(super.storageService);

  String? lastSharedPath;

  @override
  Future<void> shareSingleFile(String absolutePath, {String? text}) async {
    lastSharedPath = absolutePath;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const site = SiteModel(
    id: 'site-m4',
    siteCode: 'M4-1',
    name: 'Sector Mike Four',
    address: '4 Digest Way',
    creatorId: 'test-user',
  );

  late AppDatabase db;
  late MediaRepository mediaRepo;
  late TestEvidenceStorageService storageService;
  late TestSiteRepository siteRepo;
  late CapturingExportService exportService;
  late List<MethodCall> platformCalls;

  setUpAll(() {
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    open.overrideFor(
        OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    storageService = TestEvidenceStorageService();
    mediaRepo = LocalMediaRepository(db, storageService: storageService);
    siteRepo = TestSiteRepository(const [site]);
    exportService = CapturingExportService(storageService);

    // Capture the real Flutter platform-channel traffic so assertions observe
    // exactly what production would place on the system clipboard.
    platformCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      platformCalls.add(call);
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    await db.close();
  });

  /// The text handed to the OS clipboard by the most recent Clipboard.setData.
  String? lastClipboardText() {
    for (final call in platformCalls.reversed) {
      if (call.method == 'Clipboard.setData') {
        return (call.arguments as Map)['text'] as String?;
      }
    }
    return null;
  }

  final photoItem = MediaItem(
    id: 'm4-photo',
    siteId: 'site-m4',
    creatorId: 'test-user',
    uri: 'media/evid_m4-photo.jpg',
    originalUri: 'media/orig_m4-photo.jpg',
    thumbUri: 'media/thumb_m4-photo.jpg',
    type: MediaItemType.photo,
    lat: 22.56298,
    lon: 88.30085,
    accuracyM: 3.5,
    lowAccuracy: false,
    capturedAt: DateTime.utc(2026, 8, 15, 10, 30, 0),
    activityTag: 'Excavation',
    observationType: ObservationType.progress,
    sha256Hash: originalSha,
    evidenceSha256Hash: evidenceSha,
    syncStatus: SyncStatusType.pending,
    isDeleted: false,
  );

  // Production video semantics: the recorded MP4 is both the immutable
  // original and the shared evidence artifact, so both digests coincide.
  final videoItem = MediaItem(
    id: 'm4-video',
    siteId: 'site-m4',
    creatorId: 'test-user',
    uri: 'media/orig_m4-video.mp4',
    originalUri: 'media/orig_m4-video.mp4',
    thumbUri: 'media/thumb_m4-video.jpg',
    type: MediaItemType.video,
    lat: 22.56298,
    lon: 88.30085,
    accuracyM: 4.0,
    lowAccuracy: false,
    capturedAt: DateTime.utc(2026, 8, 15, 12, 0, 0),
    observationType: ObservationType.general,
    sha256Hash: videoSha,
    evidenceSha256Hash: videoSha,
    syncStatus: SyncStatusType.pending,
    isDeleted: false,
  );

  Widget createShareSheet({required MediaItem item}) {
    return ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(TestAuthService()),
        evidenceStorageServiceProvider.overrideWithValue(storageService),
        evidenceExportServiceProvider.overrideWithValue(exportService),
        siteRepositoryProvider.overrideWithValue(siteRepo),
        siteControllerProvider.overrideWith(
          (ref) => SiteController(siteRepo, initialUserId: 'test-user'),
        ),
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

  Widget createDetailScreen({required MediaItem item}) {
    return ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(TestAuthService()),
        evidenceStorageServiceProvider.overrideWithValue(storageService),
        mediaRepositoryProvider.overrideWithValue(mediaRepo),
        siteRepositoryProvider.overrideWithValue(siteRepo),
        siteControllerProvider.overrideWith(
          (ref) => SiteController(siteRepo, initialUserId: 'test-user'),
        ),
      ],
      child: MaterialApp(home: MediaDetailScreen(mediaItem: item)),
    );
  }

  Future<void> tapCopy(WidgetTester tester, String label) async {
    final finder = find.byTooltip('Copy $label Hash');
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('M4 Regression: RD-M4-01 / RD-M4-02 Evidence Hash Authority', () {
    testWidgets(
        'A. RD-M4-01: sharing a photo copies the digest of the shared evidence artifact',
        (tester) async {
      await tester.pumpWidget(createShareSheet(item: photoItem));
      await tester.pumpAndSettle();

      // The sheet actually exports the burned evidence JPEG (item.uri)...
      await tester.tap(find.text('OPEN SHEET'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share Evidence Photo (JPEG)'));
      await tester.pumpAndSettle();
      expect(exportService.lastSharedPath, endsWith('media/evid_m4-photo.jpg'));

      // ...and the copied checksum must therefore be that artifact's digest.
      await tester.tap(find.text('OPEN SHEET'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy SHA-256 Checksum'));
      await tester.pumpAndSettle();

      expect(lastClipboardText(), evidenceSha);
      expect(lastClipboardText(), isNot(originalSha));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'B. RD-M4-02: detail screen displays ORIGINAL and EVIDENCE SHA-256 distinctly',
        (tester) async {
      await tester.pumpWidget(createDetailScreen(item: photoItem));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.textContaining('ORIGINAL SHA-256:'));
      await tester.pumpAndSettle();

      expect(find.textContaining('ORIGINAL SHA-256: $originalShaPrefix'),
          findsOneWidget);
      expect(find.textContaining('EVIDENCE SHA-256: $evidenceShaPrefix'),
          findsOneWidget);
      // The previous ambiguous generic label is gone.
      expect(find.textContaining('SHA256:'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('C. RD-M4-02: copying the original digest returns sha256Hash',
        (tester) async {
      await tester.pumpWidget(createDetailScreen(item: photoItem));
      await tester.pumpAndSettle();

      await tapCopy(tester, 'ORIGINAL SHA-256');

      expect(lastClipboardText(), originalSha);
      expect(lastClipboardText(), isNot(evidenceSha));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'D. RD-M4-02: copying the evidence digest returns evidenceSha256Hash',
        (tester) async {
      await tester.pumpWidget(createDetailScreen(item: photoItem));
      await tester.pumpAndSettle();

      await tapCopy(tester, 'EVIDENCE SHA-256');

      expect(lastClipboardText(), evidenceSha);
      expect(lastClipboardText(), isNot(originalSha));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'E. RD-M4-02: video evidence keeps one recorded MP4 digest for both artifacts',
        (tester) async {
      await tester.pumpWidget(createDetailScreen(item: videoItem));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.textContaining('EVIDENCE SHA-256:'));
      await tester.pumpAndSettle();

      // One recorded MP4 => the original and evidence digests are identical.
      expect(find.textContaining('ORIGINAL SHA-256: $videoShaPrefix'),
          findsOneWidget);
      expect(find.textContaining('EVIDENCE SHA-256: $videoShaPrefix'),
          findsOneWidget);
      expect(videoItem.uri, videoItem.originalUri);

      await tapCopy(tester, 'ORIGINAL SHA-256');
      expect(lastClipboardText(), videoSha);

      await tapCopy(tester, 'EVIDENCE SHA-256');
      expect(lastClipboardText(), videoSha);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}
