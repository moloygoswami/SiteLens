import 'dart:async';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:camera/camera.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:sqlite3/open.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sitelens/app/router.dart';
import 'package:sitelens/core/services/auth_service.dart';
import 'package:sitelens/core/services/permission_service.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/local/database/database_provider.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/features/camera/camera_screen.dart';
import 'package:sitelens/features/camera/controllers/camera_hardware_controller.dart';
import 'package:sitelens/features/camera/controllers/gps_hardware_controller.dart';
import 'package:sitelens/features/camera/services/camera_hardware_service.dart';
import 'package:sitelens/features/camera/services/evidence_storage_service.dart';
import 'package:sitelens/features/camera/services/location_hardware_service.dart';
import 'package:sitelens/features/camera/models/gnss_snapshot.dart';
import 'package:sitelens/features/camera/widgets/camera_top_hud.dart';
import 'package:sitelens/features/camera/widgets/camera_viewfinder.dart';
import 'package:sitelens/features/camera/widgets/camera_shutter_station.dart';
import 'package:sitelens/features/camera/widgets/gps_map_thumbnail.dart';
import 'package:sitelens/features/camera/widgets/gps_status_explainer_sheet.dart';
import 'package:sitelens/features/camera/models/camera_ui_state.dart';
import 'package:sitelens/features/sync/services/cloud_sync_service.dart';
import 'package:sitelens/features/sync/services/sync_coordinator.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/domain/models/site_model.dart';
import 'package:sitelens/data/repositories/site_repository.dart';
import 'package:sitelens/features/sites/site_controller.dart';
import 'package:sitelens/features/camera/services/media_persistence_coordinator.dart';
import 'package:image/image.dart' as img;
import 'package:sitelens/features/camera/models/camera_hardware_state.dart';
import 'package:sitelens/features/camera/controllers/map_thumbnail_controller.dart';
import 'package:sitelens/features/camera/services/evidence_processing_service.dart';
import 'package:sitelens/features/camera/models/processed_evidence_payload.dart';
import 'package:sitelens/features/camera/models/evidence_metadata_snapshot.dart';
import 'package:sitelens/features/review/models/pending_capture_payload.dart';
import 'package:sitelens/features/review/review_tag_screen.dart';
import 'package:sitelens/core/controllers/watermark_settings_controller.dart';
import 'package:sitelens/shared/widgets/evidence_metadata_hud_card.dart';

class TestCameraService extends CameraHardwareService {
  @override
  Future<List<CameraDescription>> getAvailableCameras() async => [];

  @override
  Future<double> getMinZoomLevel(CameraController controller) async => 0.5;

  @override
  Future<double> getMaxZoomLevel(CameraController controller) async => 5.0;
}

class TestLocationService extends LocationHardwareService {
  StreamController<Position>? _controller;
  Position? initialPosition = Position(
    latitude: 22.57264,
    longitude: 88.36391,
    timestamp: DateTime.utc(2026, 8, 15, 10, 30, 45),
    accuracy: 3.8,
    altitude: 18.4,
    altitudeAccuracy: 1.0,
    heading: 0.0,
    headingAccuracy: 1.0,
    speed: 0.0,
    speedAccuracy: 1.0,
  );

  StreamController<Position> get streamController =>
      _controller ??= StreamController<Position>.broadcast();

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async => LocationPermission.whileInUse;

  @override
  Future<Position?> getLastKnownPosition() async => initialPosition;

  @override
  Future<AltitudeTelemetry> getAltitudeTelemetry() async =>
      const AltitudeTelemetry(hasMslAltitude: true, mslAltitudeMeters: 18.4);

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    if (initialPosition != null) {
      Timer.run(() => streamController.add(initialPosition!));
    }
    return streamController.stream;
  }

  void emit(Position p) => streamController.add(p);
  void close() {
    _controller?.close();
    _controller = null;
  }
}

class _CameraTestConnectivity implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => Stream.value([ConnectivityResult.wifi]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CameraTestAuthService implements AuthService {
  @override
  AuthUser? get currentUser => const AuthUser(uid: 'test-user', email: 'test@sitelens.local');

  @override
  Stream<AuthUser?> get authStateChanges => Stream.value(const AuthUser(uid: 'test-user', email: 'test@sitelens.local'));

  @override
  Future<SessionVerificationResult> verifySession() async => const SessionVerificationResult.valid();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CameraTestCloudSyncService implements CloudSyncService {
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

class _CameraTestEvidenceStorageService implements EvidenceStorageService {
  @override
  Future<Directory> getMediaDirectory() async => Directory.systemTemp;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Storage fake for the recovery flow: returns a real `.../media` directory
/// (mirroring the real service) so the preserved video can actually be written.
class _RecoveryTestEvidenceStorageService extends EvidenceStorageService {
  Directory? _mediaDir;

  @override
  Future<Directory> getMediaDirectory() async {
    if (_mediaDir != null && await _mediaDir!.exists()) return _mediaDir!;
    final base = await Directory.systemTemp.createTemp('sitelens_base_');
    final mediaDir = Directory('${base.path}/media');
    await mediaDir.create(recursive: true);
    _mediaDir = mediaDir;
    return mediaDir;
  }

  @override
  Future<String> resolveAbsolutePath(String relativePath) async =>
      '${(await getMediaDirectory()).parent.path}/$relativePath';
}

/// Camera service that reports a real (test) camera and produces a real temp
/// video file on stop, so the interrupted-recording recovery flow can read and
/// preserve actual bytes end-to-end.
class _RecordingRecoveryCameraService extends CameraHardwareService {
  final File videoFile;
  bool isRecording = false;

  _RecordingRecoveryCameraService(this.videoFile);

  @override
  Future<List<CameraDescription>> getAvailableCameras() async {
    return [
      const CameraDescription(
        name: '0',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      ),
    ];
  }

  @override
  Future<void> initializeController(CameraController controller) async {}

  @override
  Future<void> startVideoRecording(CameraController controller) async {
    isRecording = true;
  }

  @override
  Future<XFile> stopVideoRecording(CameraController controller) async {
    // No real IO inside the test's fake async zone: the file was created in
    // setup and already exists on disk.
    isRecording = false;
    return XFile(videoFile.path);
  }

  @override
  bool isRecordingVideo(CameraController? controller) => isRecording;

  @override
  Future<void> disposeController(CameraController? controller) async {}

  @override
  Future<void> setZoomLevel(CameraController controller, double zoom) async {}

  @override
  Future<double> getMinZoomLevel(CameraController controller) async => 0.5;

  @override
  Future<double> getMaxZoomLevel(CameraController controller) async => 5.0;
}

class MockEmptyCameraService extends CameraHardwareService {
  @override
  Future<List<CameraDescription>> getAvailableCameras() async => [];
}

class _CameraTestPermissionService extends PermissionService {
  _CameraTestPermissionService() {
    state = const SiteLensPermissionStatus(
      camera: PermissionStatus.granted,
      location: PermissionStatus.granted,
      photos: PermissionStatus.granted,
    );
  }

  @override
  Future<SiteLensPermissionStatus> checkAllPermissions() async {
    return state;
  }

  @override
  Future<PermissionStatus> checkCameraPermission() async {
    return state.camera;
  }

  @override
  Future<PermissionStatus> requestCameraPermission() async {
    return state.camera;
  }
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

/// Throws to simulate a persistence failure during "Keep for later".
class _KeepForLaterFailureException implements Exception {
  @override
  String toString() => 'Simulated persistence failure';
}

class _RecordingRecoveryCoordinator implements MediaPersistenceCoordinator {
  final bool shouldFail;
  int keepForLaterCalls = 0;
  PendingCapturePayload? lastPayload;

  _RecordingRecoveryCoordinator({this.shouldFail = false});

  @override
  Future<MediaItem> keepForLater(PendingCapturePayload payload) async {
    keepForLaterCalls++;
    lastPayload = payload;
    if (shouldFail) throw _KeepForLaterFailureException();
    return MediaItem(
      id: payload.mediaId,
      siteId: payload.metadataSnapshot.siteId,
      originalUri: payload.originalFilePath,
      uri: payload.evidenceFilePath ?? payload.originalFilePath,
      thumbUri: payload.thumbnailFilePath,
      type: payload.mediaType,
      lat: payload.metadataSnapshot.latitude,
      lon: payload.metadataSnapshot.longitude,
      accuracyM: payload.metadataSnapshot.accuracyMeters,
      lowAccuracy: payload.metadataSnapshot.lowAccuracy,
      capturedAt: payload.metadataSnapshot.capturedAtUtc,
      sha256Hash: payload.sha256Hash,
      evidenceSha256Hash: payload.sha256Hash,
      capturedAddress: payload.metadataSnapshot.resolvedAddress,
      creatorId: payload.metadataSnapshot.creatorId,
      syncStatus: SyncStatusType.pending,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReentrancyNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> routes = [];
  int pushedRouteCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    routes.add(route);
    if (previousRoute != null) {
      pushedRouteCount++;
    }
  }
}

class _ReentrancyCameraHardwareNotifier extends CameraHardwareNotifier {
  _ReentrancyCameraHardwareNotifier(this.service, this.tempDir)
      : super(service) {
    state = state.copyWith(status: CameraStatus.ready);
  }

  final CameraHardwareService service;
  final Directory tempDir;
  int takePhotoCallCount = 0;
  bool shouldFail = false;

  @override
  Future<void> initialize() async {
    state = state.copyWith(status: CameraStatus.ready);
  }

  @override
  Future<XFile?> takePhoto() async {
    takePhotoCallCount++;
    if (shouldFail) {
      throw Exception('Simulated camera hardware fault');
    }
    state = state.copyWith(status: CameraStatus.capturing);
    try {
      final testImg = img.Image(width: 10, height: 10);
      final bytes = Uint8List.fromList(img.encodeJpg(testImg));
      return XFile.fromData(
        bytes,
        path: '${tempDir.path}/reentrancy_capture_$takePhotoCallCount.jpg',
      );
    } finally {
      // Exactly mirrors production CameraHardwareController: resets status to ready
      // immediately upon hardware completion, creating the post-hardware re-entrancy window.
      state = state.copyWith(status: CameraStatus.ready);
    }
  }
}

class _ReentrancyEvidenceStorageService extends EvidenceStorageService {
  @override
  String getOriginalRelativePath(String mediaId) => 'media/orig_$mediaId.jpg';

  @override
  Future<void> deleteTempCameraFile(String tempPath) async {}

  @override
  Future<String> resolveAbsolutePath(String relativePath) async => '/tmp/$relativePath';

  @override
  Future<Directory> getMediaDirectory() async => Directory.systemTemp;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReentrancyEvidenceProcessingService implements EvidenceProcessingService {
  @override
  Future<ProcessedEvidencePayload> processCapture({
    required Uint8List originalBytes,
    required EvidenceMetadataSnapshot snapshot,
    Uint8List? mapTileBytes,
    bool isGpsLocked = true,
    bool showAddress = true,
    bool showMapTile = true,
    CameraAspectRatio? targetAspectRatio,
    bool Function()? isCancelled,
  }) async {
    return ProcessedEvidencePayload(
      isSuccess: true,
      mediaId: snapshot.mediaId,
      originalFilePath: 'media/orig_${snapshot.mediaId}.jpg',
      evidenceFilePath: 'media/evid_${snapshot.mediaId}.jpg',
      thumbnailFilePath: 'media/thumb_${snapshot.mediaId}.jpg',
      originalSha256: 'mock-orig-sha',
      evidenceSha256: 'mock-evid-sha',
      originalFileSizeBytes: originalBytes.length,
      evidenceFileSizeBytes: originalBytes.length,
      thumbnailFileSizeBytes: 100,
      thumbnailWidth: 10,
      thumbnailHeight: 10,
      metadataSnapshot: snapshot,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget createCameraTestWidget({
  CameraUiState? state,
  List<Override> overrides = const [],
  Size size = const Size(400, 800),
  List<NavigatorObserver> navigatorObservers = const [],
}) {
  final db = AppDatabase(NativeDatabase.memory());
  return ProviderScope(
    overrides: [
      authServiceProvider.overrideWithValue(_CameraTestAuthService()),
      permissionServiceProvider.overrideWith((ref) => _CameraTestPermissionService()),
      cameraHardwareServiceProvider.overrideWithValue(TestCameraService()),
      locationHardwareServiceProvider.overrideWithValue(TestLocationService()),
      activeSiteMediaStreamProvider.overrideWith((ref) => Stream.value([])),
      appDatabaseProvider.overrideWithValue(db),
      syncCoordinatorProvider.overrideWith(
        (ref) => SyncCoordinator(
          mediaRepo: LocalMediaRepository(db),
          cloudSyncService: _CameraTestCloudSyncService(),
          storageService: _CameraTestEvidenceStorageService(),
          authService: _CameraTestAuthService(),
          connectivity: _CameraTestConnectivity(),
        ),
      ),
      ...overrides,
    ],
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          padding: const EdgeInsets.only(top: 24, bottom: 16),
        ),
        child: CameraScreen(key: UniqueKey()),
      ),
      navigatorObservers: navigatorObservers,
      onGenerateRoute: AppRoutes.onGenerateRoute,
    ),
  );
}

void main() {
  setUpAll(() {
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CameraScreen M2.3 & M2.4 Combined Hardware Integration Tests', () {
    testWidgets('Renders all primary layout zones, fallback viewport, and branding in default test environment', (tester) async {
      await tester.pumpWidget(createCameraTestWidget());
      await tester.pumpAndSettle();

      // Top HUD
      expect(find.byType(CameraTopHud), findsOneWidget);
      expect(find.byType(GpsStatusPill), findsOneWidget);
      expect(find.textContaining('GPS: High'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CameraTopHud),
          matching: find.textContaining('2026-08-15 10:30:45 UTC'),
        ),
        findsOneWidget,
      );

      // Viewfinder
      expect(find.byType(CameraViewfinder), findsOneWidget);
      expect(find.byType(CameraStatusViewport), findsOneWidget);
      expect(find.byType(RegistrationMarks), findsOneWidget);
      expect(find.byType(ThirdsGrid), findsOneWidget);
      expect(find.byType(WatermarkPreview), findsOneWidget);
      expect(find.byType(GpsMapThumbnail), findsOneWidget);
      expect(find.byType(ViewfinderControls), findsOneWidget);

      // Shutter Station
      expect(find.byType(CameraShutterStation), findsOneWidget);
      expect(find.byType(ReadinessBanner), findsOneWidget);
      expect(find.byType(ModeSwitcher), findsOneWidget);
      expect(find.byType(ShutterButton), findsOneWidget);
      expect(find.byType(GalleryShortcut), findsOneWidget);
      expect(find.byType(CameraSwitcher), findsOneWidget);
    });

    testWidgets('F3: Live minimap disappears when Mini Map Tile is disabled and returns when enabled', (tester) async {
      SharedPreferences.setMockInitialValues({'setting_watermark_show_map_tile': true});

      await tester.pumpWidget(createCameraTestWidget());
      await tester.pumpAndSettle();

      // Enabled by default: minimap tile is rendered
      expect(find.byType(GpsMapThumbnail), findsOneWidget);
      expect(find.byType(StandaloneMinimapWidget), findsOneWidget);

      // Disable Mini Map Tile setting
      final element = tester.element(find.byType(CameraScreen));
      final container = ProviderScope.containerOf(element);
      await container.read(watermarkSettingsProvider.notifier).setShowMapTile(false);
      await tester.pumpAndSettle();

      // Disabled: minimap tile must NOT be displayed in live viewfinder
      expect(find.byType(GpsMapThumbnail), findsNothing);
      expect(find.byType(StandaloneMinimapWidget), findsNothing);

      // Re-enable Mini Map Tile setting
      await container.read(watermarkSettingsProvider.notifier).setShowMapTile(true);
      await tester.pumpAndSettle();

      // Returns when enabled
      expect(find.byType(GpsMapThumbnail), findsOneWidget);
      expect(find.byType(StandaloneMinimapWidget), findsOneWidget);
    });

    testWidgets('HUD shows truthful fix-status geofence label: GPS Fixed with a fix (never Active Site)', (tester) async {
      // Valid fix, no site coordinates -> "GPS Fixed" (never "Active Site").
      await tester.pumpWidget(createCameraTestWidget());
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(CameraTopHud),
          matching: find.text('GPS Fixed'),
        ),
        findsOneWidget,
      );
      expect(find.text('Active Site'), findsNothing);
      expect(find.text('Inside Perimeter'), findsNothing);
      expect(find.text('Outside Perimeter'), findsNothing);
    });

    testWidgets('HUD shows Acquiring Fix when no GPS fix exists', (tester) async {
      await tester.pumpWidget(createCameraTestWidget(
        overrides: [
          locationHardwareServiceProvider
              .overrideWithValue(TestLocationService()..initialPosition = null),
        ],
      ));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(CameraTopHud),
          matching: find.text('Acquiring Fix'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Combined Shutter Readiness Matrix: Searching GPS locks shutter with lock icon', (tester) async {
      final searchingLocationService = TestLocationService()..initialPosition = null;

      await tester.pumpWidget(ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(_CameraTestAuthService()),
          permissionServiceProvider.overrideWith((ref) => _CameraTestPermissionService()),
          cameraHardwareServiceProvider.overrideWithValue(TestCameraService()),
          locationHardwareServiceProvider.overrideWithValue(searchingLocationService),
        ],
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(400, 800),
              padding: EdgeInsets.only(top: 24, bottom: 16),
            ),
            child: CameraScreen(),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('GPS: Searching'), findsOneWidget);
      // No camera + no GPS: the banner must never claim readiness. It states
      // that optical sensor is unavailable; the GPS pill carries the cause.
      expect(find.textContaining('OPTICAL SENSOR UNAVAILABLE'), findsWidgets);
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    });

    testWidgets('Combined Shutter Readiness Matrix: Degraded GPS permits capture with degraded banner', (tester) async {
      final degradedPosition = Position(
        latitude: 22.57264,
        longitude: 88.36391,
        timestamp: DateTime.utc(2026, 8, 15, 10, 30, 45),
        accuracy: 25.0, // > 20m
        altitude: 18.4,
        altitudeAccuracy: 1.0,
        heading: 0.0,
        headingAccuracy: 1.0,
        speed: 0.0,
        speedAccuracy: 1.0,
      );

      final degradedLocationService = TestLocationService()..initialPosition = degradedPosition;

      await tester.pumpWidget(createCameraTestWidget(
        overrides: [
          locationHardwareServiceProvider.overrideWithValue(degradedLocationService),
        ],
      ));
      await tester.pumpAndSettle();

      // No camera in test env: banner correctly reports optical sensor unavailable
      // rather than claiming readiness. The GPS pill shows the
      // degraded GPS state truthfully.
      expect(find.textContaining('GPS: Poor'), findsOneWidget);
      expect(find.textContaining('OPTICAL SENSOR UNAVAILABLE'), findsWidgets);
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    });

    testWidgets('ModeSwitcher toggles between PHOTO and VIDEO capture modes in UI state', (tester) async {
      await tester.pumpWidget(createCameraTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('PHOTO'), findsOneWidget);
      expect(find.text('VIDEO'), findsOneWidget);

      // Tap VIDEO mode: selected pill state flips to VIDEO (shutter stays
      // locked in the no-camera test env and correctly shows the lock icon).
      await tester.tap(find.text('VIDEO'));
      await tester.pumpAndSettle();

      // Tap PHOTO mode: selected pill state flips back.
      await tester.tap(find.text('PHOTO'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    });

    testWidgets('Viewfinder controls toggle grid, cycle flash, and cycle lens zoom', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createCameraTestWidget());
      await tester.pumpAndSettle();

      // Initial: Grid is ON
      expect(find.byType(ThirdsGrid), findsOneWidget);

      // Toggle Grid -> OFF
      await tester.tap(find.byIcon(Icons.grid_on_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(ThirdsGrid), findsNothing);

      // Toggle Grid -> ON
      await tester.tap(find.byIcon(Icons.grid_off_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(ThirdsGrid), findsOneWidget);

      // Initial Flash: Auto
      expect(find.byIcon(Icons.flash_auto_rounded), findsOneWidget);

      // Cycle Flash -> On
      await tester.tap(find.byIcon(Icons.flash_auto_rounded));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.flash_on_rounded), findsOneWidget);

      // Initial Lens Zoom button in ViewfinderControls
      final lensButton = find.bySemanticsLabel(RegExp(r'Camera lens zoom:'));
      expect(lensButton, findsOneWidget);
      await tester.tap(lensButton);
      await tester.pumpAndSettle();

      // Aspect Ratio: 4:3 by default
      expect(find.text('4:3'), findsOneWidget);
      await tester.tap(find.text('4:3'));
      await tester.pumpAndSettle();
      expect(find.text('16:9'), findsOneWidget);

      // Timer: Off by default
      expect(find.byIcon(Icons.timer_off_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.timer_off_outlined));
      await tester.pumpAndSettle();
      expect(find.text('3s'), findsOneWidget);
    });

    testWidgets('Tap-to-focus renders FocusReticle at tapped coordinate', (tester) async {
      await tester.pumpWidget(createCameraTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(FocusReticle), findsNothing);

      // Tap in center of viewport
      await tester.tapAt(const Offset(200, 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(FocusReticle), findsOneWidget);
    });

    testWidgets('WatermarkPreview displays technical provenance metadata and map pin', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createCameraTestWidget());
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byType(WatermarkPreview), matching: find.textContaining('SITE:')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(WatermarkPreview), matching: find.textContaining('ADDR:')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(WatermarkPreview),
          matching: find.textContaining('Integrity hash: Pending until saved'),
        ),
        findsOneWidget,
      );
      expect(find.byType(GpsMapThumbnail), findsOneWidget);
    });

    testWidgets('Gallery and camera flip buttons provide responsive UI feedback', (tester) async {
      await tester.pumpWidget(createCameraTestWidget());
      await tester.pumpAndSettle();

      // Tap Gallery shortcut
      await tester.tap(find.byType(GalleryShortcut));
      await tester.pumpAndSettle();

      // Pop back from GalleryScreen to CameraScreen
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      // Tap Camera Switcher (Flip)
      await tester.tap(find.byType(CameraSwitcher));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('Tapping timestamp strip opens TimestampSettingsModal and toggles formats', (tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      await tester.pumpWidget(createCameraTestWidget());
      await tester.pumpAndSettle();

      // Tap timestamp strip settings icon
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();

      // Verify modal is displayed
      expect(find.text('Overlay Timestamp Settings'), findsOneWidget);
      expect(find.textContaining('Local Time'), findsOneWidget);
      expect(find.text('12-Hour (02:30:00 PM)'), findsOneWidget);

      // Tap 12-Hour option
      await tester.tap(find.text('12-Hour (02:30:00 PM)'));
      await tester.pumpAndSettle();

      // Close modal
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
    });

    testWidgets('Camera maintains canonical portrait layout even with wide viewport', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createCameraTestWidget());
      await tester.pumpAndSettle();

      // Verify Top HUD, Viewfinder, and Shutter Station are present in canonical portrait Column layout
      expect(find.byType(CameraTopHud), findsOneWidget);
      expect(find.byType(CameraViewfinder), findsOneWidget);
      expect(find.byType(CameraShutterStation), findsOneWidget);
      expect(find.byType(WatermarkPreview), findsOneWidget);
      expect(find.byType(GpsMapThumbnail), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('WatermarkPreview shows honest pending hash state and no fabricated hash', (tester) async {
      await tester.pumpWidget(createCameraTestWidget());
      await tester.pumpAndSettle();

      // The hash is NEVER claimed before save + hash computation.
      expect(find.textContaining('Integrity hash: Pending until saved'), findsOneWidget);
      expect(find.textContaining('PIXEL HASH'), findsNothing);
      expect(find.textContaining('SHA-256'), findsNothing);
    });

    testWidgets('Tapping GPS pill opens cause-specific GPS status explainer', (tester) async {
      await tester.pumpWidget(createCameraTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(GpsStatusPill));
      await tester.pumpAndSettle();

      expect(find.byType(GpsStatusExplainerSheet), findsOneWidget);
      expect(find.text('Waiting for GPS lock'), findsOneWidget);
    });

    testWidgets('Unavailable camera state blocks capture and provides clear guidance', (tester) async {
      // No cameras in the test service -> CameraStatus.unavailable
      await tester.pumpWidget(createCameraTestWidget(
        overrides: [
          cameraHardwareServiceProvider.overrideWithValue(MockEmptyCameraService()),
        ],
      ));
      await tester.pumpAndSettle();

      // Viewfinder states optical sensor is unavailable with retry button
      expect(find.text('OPTICAL SENSOR UNAVAILABLE'), findsWidgets);
      expect(find.text('RETRY CAMERA'), findsOneWidget);

      // Shutter is locked (lock icon), capture is not permitted.
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      expect(find.text('Optical sensor unavailable — evidence capture disabled.'), findsOneWidget);

      // Pressing the shutter shows the unmistakable blocker, never a fake capture.
      await tester.tap(find.byType(ShutterButton), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.textContaining('Optical sensor is unavailable on this device.'), findsWidgets);
    });
  });

  group('Interrupted-recordings recovery (R1 — Keep for later persistence)', () {
    const testSite = SiteModel(
      id: 'site-alpha',
      siteCode: 'SL-001',
      name: 'Sector Alpha',
      address: '100 Construction Way',
    );

    Widget buildRecoveryTestWidget({
      required _RecordingRecoveryCameraService cameraService,
      required _RecordingRecoveryCoordinator coordinator,
      List<Override> overrides = const [],
    }) {
      return ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(_CameraTestAuthService()),
          permissionServiceProvider.overrideWith((ref) => _CameraTestPermissionService()),
          cameraHardwareServiceProvider.overrideWithValue(cameraService),
          locationHardwareServiceProvider.overrideWithValue(TestLocationService()),
          activeSiteMediaStreamProvider.overrideWith((ref) => Stream.value([])),
          appDatabaseProvider.overrideWithValue(AppDatabase(NativeDatabase.memory())),
          evidenceStorageServiceProvider.overrideWithValue(_RecoveryTestEvidenceStorageService()),
          authServiceProvider.overrideWithValue(_CameraTestAuthService()),
          siteRepositoryProvider.overrideWithValue(MockSiteRepository(testSite)),
          siteControllerProvider.overrideWith(
            (ref) => SiteController(MockSiteRepository(testSite)),
          ),
          mediaPersistenceCoordinatorProvider.overrideWithValue(coordinator),
          syncCoordinatorProvider.overrideWith(
            (ref) => SyncCoordinator(
              mediaRepo: LocalMediaRepository(AppDatabase(NativeDatabase.memory())),
              cloudSyncService: _CameraTestCloudSyncService(),
              storageService: _RecoveryTestEvidenceStorageService(),
              authService: _CameraTestAuthService(),
              connectivity: _CameraTestConnectivity(),
            ),
          ),
          ...overrides,
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              // Wide enough to avoid the pre-existing ModeSwitcher overflow at
              // narrow widths in the camera-ready state.
              size: Size(600, 800),
              padding: EdgeInsets.only(top: 24, bottom: 16),
            ),
            child: CameraScreen(key: UniqueKey()),
          ),
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      );
    }

    Future<File> createTempVideoFile() async {
      final dir = await Directory.systemTemp.createTemp('sitelens_recovery_');
      final file = File('${dir.path}/in-flight.mp4');
      await file.writeAsBytes(
        List<int>.generate(128, (i) => i % 251),
        flush: true,
      );
      return file;
    }

    Future<CameraHardwareNotifier> startRecording(
      WidgetTester tester,
    ) async {
      final element = tester.element(find.byType(CameraScreen));
      final notifier = ProviderScope.containerOf(element)
          .read(cameraHardwareProvider.notifier);
      // Wait for camera readiness.
      await tester.pumpAndSettle();
      // start/pause involve real file IO (the video bytes), which only
      // completes on the real event loop inside runAsync.
      await tester.runAsync(() async {
        final started = await notifier.startVideoRecording();
        expect(started, isTrue, reason: 'video recording must start');
        await notifier.pauseCamera();
      });
      await tester.pump();
      return notifier;
    }

    testWidgets('Keep for later calls keepForLater with the preserved video and shows a truthful success snackbar', (tester) async {
      final coordinator = _RecordingRecoveryCoordinator();
      final videoFile = (await tester.runAsync(createTempVideoFile))!;
      final cameraService = _RecordingRecoveryCameraService(videoFile);

      await tester.pumpWidget(buildRecoveryTestWidget(
        cameraService: cameraService,
        coordinator: coordinator,
      ));
      await tester.pumpAndSettle();

      // Start an in-flight recording, then simulate a lifecycle pause that stops it.
      final notifier = await startRecording(tester);
      expect(notifier.state.hasInterruptedRecording, isTrue);
      expect(notifier.inFlightVideoFile, isNot(null));

      // Simulate app resume → triggers _showInterruptedRecordingRecovery. The
      // recovery reads/writes the preserved video, so run it on the real loop.
      await tester.runAsync(() async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Recovery dialog is shown.
      expect(find.text('Recording interrupted'), findsOneWidget);

      // Choose "Keep for later".
      await tester.runAsync(() async {
        await tester.tap(find.text('Keep for later'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Truthful success snackbar.
      expect(
        find.textContaining('saved for later'),
        findsOneWidget,
      );
      // keepForLater was invoked with the preserved video payload.
      expect(coordinator.keepForLaterCalls, 1);
      expect(coordinator.lastPayload, isNot(null));
      expect(coordinator.lastPayload!.mediaType, MediaItemType.video);
      expect(coordinator.lastPayload!.originalFilePath, contains('media/orig_'));
    });

    testWidgets('Keep for later shows a failure snackbar when persistence fails', (tester) async {
      final coordinator = _RecordingRecoveryCoordinator(shouldFail: true);
      final videoFile = (await tester.runAsync(createTempVideoFile))!;
      final cameraService = _RecordingRecoveryCameraService(videoFile);

      await tester.pumpWidget(buildRecoveryTestWidget(
        cameraService: cameraService,
        coordinator: coordinator,
      ));
      await tester.pumpAndSettle();

      final notifier = await startRecording(tester);
      expect(notifier.state.hasInterruptedRecording, isTrue);

      await tester.runAsync(() async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Recording interrupted'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.text('Keep for later'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Does NOT claim gallery success — reports the failure explicitly.
      expect(find.textContaining('Could not save'), findsOneWidget);
      expect(find.textContaining('review it in the gallery'), findsNothing);
    });

    testWidgets('Explicit discard does not call keepForLater and shows a discard snackbar', (tester) async {
      final coordinator = _RecordingRecoveryCoordinator();
      final videoFile = (await tester.runAsync(createTempVideoFile))!;
      final cameraService = _RecordingRecoveryCameraService(videoFile);

      await tester.pumpWidget(buildRecoveryTestWidget(
        cameraService: cameraService,
        coordinator: coordinator,
      ));
      await tester.pumpAndSettle();

      final notifier = await startRecording(tester);
      expect(notifier.state.hasInterruptedRecording, isTrue);

      await tester.runAsync(() async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Recording interrupted'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.text('Discard'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.textContaining('discarded'),
        findsOneWidget,
      );
      // Discard is an explicit, separate action: no "Keep for later" persistence.
      expect(coordinator.keepForLaterCalls, 0);
    });

    testWidgets('C-1: Normal video stop hands off cleanly — no interrupted-recording state remains', (tester) async {
      final videoFile = (await tester.runAsync(createTempVideoFile))!;
      final cameraService = _RecordingRecoveryCameraService(videoFile);

      await tester.pumpWidget(buildRecoveryTestWidget(
        cameraService: cameraService,
        coordinator: _RecordingRecoveryCoordinator(),
      ));
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(CameraScreen));
      final notifier = ProviderScope.containerOf(element).read(cameraHardwareProvider.notifier);

      // Switch to video capture mode through the mode switcher UI.
      await tester.tap(find.text('VIDEO'));
      await tester.pumpAndSettle();

      // Start recording, then stop through the screen's normal handoff path
      // (shutter tap while recording).
      await tester.runAsync(() async {
        final started = await notifier.startVideoRecording();
        expect(started, isTrue, reason: 'video recording must start');
      });
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.byType(ShutterButton), warnIfMissed: false);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // The recording reached the review flow.
      expect(find.byType(ReviewTagScreen), findsOneWidget);

      // C-1: the handoff cleared the in-flight reference and the
      // interrupted-recording flag.
      expect(notifier.inFlightVideoFile, null);
      expect(notifier.state.hasInterruptedRecording, isFalse);

      // The C-1 regression: a later pause/resume cycle must not raise a false
      // interrupted-recording recovery for the already-handed-off recording.
      await tester.runAsync(() async {
        await notifier.pauseCamera();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await notifier.resumeCamera();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(notifier.state.hasInterruptedRecording, isFalse);
      expect(find.text('Recording interrupted'), findsNothing);
    });

    testWidgets('Viewfinder toggles Outdoor High-Contrast mode when button tapped', (tester) async {
      await tester.pumpWidget(createCameraTestWidget());
      await tester.pumpAndSettle();

      // Find the Outdoor High-Contrast toggle button in ViewfinderControls
      final contrastButton = find.byTooltip(RegExp(r'Outdoor High-Contrast'));
      expect(contrastButton, findsOneWidget);

      // Tap to toggle high-contrast mode ON
      await tester.tap(contrastButton);
      await tester.pumpAndSettle();

      expect(find.byTooltip('Outdoor High-Contrast: On'), findsOneWidget);
    });

    testWidgets('Degraded GPS displays figure-8 compass calibration prompt', (tester) async {
      final locService = TestLocationService();
      locService.initialPosition = Position(
        latitude: 22.57264,
        longitude: 88.36391,
        timestamp: DateTime.utc(2026, 8, 15, 10, 30, 45),
        accuracy: 25.0,
        altitude: 18.4,
        altitudeAccuracy: 1.0,
        heading: 145.0,
        headingAccuracy: 1.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );
      await tester.pumpWidget(createCameraTestWidget(
        overrides: [
          locationHardwareServiceProvider.overrideWithValue(locService),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Calibrate: Tilt in figure-8 motion'), findsOneWidget);
    });
  });

  group('F3 Shutter Button State Machine Re-Entrancy Hazard Remediation', () {
    testWidgets(
        'Verifies F3 remediation: Rapid shutter re-activation during in-flight post-hardware processing is safely ignored and produces exactly one review navigation',
        (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('sitelens_f3_reentrancy_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final cameraNotifier = _ReentrancyCameraHardwareNotifier(TestCameraService(), tempDir);
      final navObserver = _ReentrancyNavigatorObserver();
      final gateCompleter = Completer<Uint8List?>();

      await tester.pumpWidget(createCameraTestWidget(
        overrides: [
          cameraHardwareProvider.overrideWith((ref) => cameraNotifier),
          evidenceStorageServiceProvider.overrideWithValue(_ReentrancyEvidenceStorageService()),
          evidenceProcessingServiceProvider.overrideWithValue(_ReentrancyEvidenceProcessingService()),
          authServiceProvider.overrideWithValue(_CameraTestAuthService()),
        ],
        navigatorObservers: [navObserver],
      ));
      await tester.pumpAndSettle();

      // Register the gate on mapThumbnailControllerProvider so post-hardware processing suspends
      final element = tester.element(find.byType(CameraScreen));
      final container = ProviderScope.containerOf(element);
      container.read(mapThumbnailControllerProvider.notifier).registerLiveSnapshotProvider(
        () => gateCompleter.future,
      );

      // Verify initial state: no shutter activations, no routes pushed, shutter ready
      expect(cameraNotifier.takePhotoCallCount, 0);
      expect(navObserver.pushedRouteCount, 0);
      expect(find.byType(ShutterButton), findsOneWidget);

      // 1. First shutter activation: enters post-hardware processing
      await tester.tap(find.byType(ShutterButton));
      await tester.pump();

      expect(
        cameraNotifier.takePhotoCallCount,
        1,
        reason: 'Criterion 1: First shutter activation enters post-hardware processing and completes takePhoto()',
      );

      // 2. That processing remains in flight awaiting live map snapshot
      expect(
        gateCompleter.isCompleted,
        isFalse,
        reason: 'Criterion 2: Post-hardware processing remains in flight awaiting map snapshot gate',
      );
      expect(
        navObserver.pushedRouteCount,
        0,
        reason: 'Criterion 2: Navigation has not yet occurred while first capture is in flight',
      );
      final shutterButtonBeforeSecondTap = tester.widget<ShutterButton>(find.byType(ShutterButton));
      expect(
        shutterButtonBeforeSecondTap.isLocked,
        isTrue,
        reason: 'Criterion 2: Shutter button is locked in UI via screen-level _isExecutingCapture lock during capture transaction',
      );

      // 3. Second shutter activation occurs during that in-flight interval
      await tester.tap(find.byType(ShutterButton), warnIfMissed: false);
      await tester.pump();

      // 4. Overlapping capture is blocked
      expect(
        cameraNotifier.takePhotoCallCount,
        1,
        reason: 'Criterion 4: Overlapping capture prevented — second shutter actuation was safely dropped by mutex',
      );

      // 5. Release post-hardware processing and verify exactly one review route is pushed
      gateCompleter.complete(Uint8List.fromList([1, 2, 3, 4]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(
        navObserver.pushedRouteCount,
        1,
        reason: 'Criterion 5: Exactly one review route was pushed without duplicate transitions',
      );
      expect(find.byType(ReviewTagScreen), findsOneWidget);
    });

    testWidgets('Verifies shutter capture lock releases cleanly after capture failure', (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('sitelens_f3_error_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final cameraNotifier = _ReentrancyCameraHardwareNotifier(TestCameraService(), tempDir);
      final navObserver = _ReentrancyNavigatorObserver();

      await tester.pumpWidget(createCameraTestWidget(
        overrides: [
          cameraHardwareProvider.overrideWith((ref) => cameraNotifier),
          evidenceStorageServiceProvider.overrideWithValue(_ReentrancyEvidenceStorageService()),
          evidenceProcessingServiceProvider.overrideWithValue(_ReentrancyEvidenceProcessingService()),
          authServiceProvider.overrideWithValue(_CameraTestAuthService()),
        ],
        navigatorObservers: [navObserver],
      ));
      await tester.pumpAndSettle();

      // Ensure shutter ready initially
      expect(tester.widget<ShutterButton>(find.byType(ShutterButton)).isLocked, isFalse);

      // Force failure on hardware capture
      cameraNotifier.shouldFail = true;
      await tester.tap(find.byType(ShutterButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // Error was handled, no route pushed, and snackbar shown
      expect(navObserver.pushedRouteCount, 0);
      expect(find.textContaining('Simulated camera hardware fault'), findsOneWidget);

      // Lock is released and shutter is ready again
      expect(tester.widget<ShutterButton>(find.byType(ShutterButton)).isLocked, isFalse);

      // Register live snapshot provider so second capture succeeds cleanly
      final element = tester.element(find.byType(CameraScreen));
      final container = ProviderScope.containerOf(element);
      container.read(mapThumbnailControllerProvider.notifier).registerLiveSnapshotProvider(
        () async => Uint8List.fromList([1, 2, 3, 4]),
      );

      // Dismiss the error snackbar so it does not obscure shutter hit test
      ScaffoldMessenger.of(element).clearSnackBars();
      await tester.pumpAndSettle();

      // Retry capture with failure cleared
      cameraNotifier.shouldFail = false;
      await tester.tap(find.byType(ShutterButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // Exactly one route pushed on retry
      expect(navObserver.pushedRouteCount, 1);
      expect(find.byType(ReviewTagScreen), findsOneWidget);
    });
  });

  group('A2 CameraX Route Coverage Lifecycle', () {
    testWidgets(
        'CameraX is released while CameraScreen is covered and reacquired when visible',
        (tester) async {
      final service = _RouteLifecycleCameraService();
      await tester.pumpWidget(createCameraTestWidget(
        navigatorObservers: [appRouteObserver],
        overrides: [
          cameraHardwareServiceProvider.overrideWithValue(service),
        ],
      ));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(CameraScreen)),
      );

      // Visible -> active, exactly one camera resource.
      expect(container.read(cameraHardwareProvider).status, CameraStatus.ready);
      expect(service.initializeControllerCalls, 1);
      expect(service.liveControllers, 1);

      // Covered by a page route (gallery / video evidence / fullscreen).
      await _pushCoveringPage(tester);
      expect(
        container.read(cameraHardwareProvider).status,
        CameraStatus.unavailable,
      );
      expect(service.liveControllers, 0);

      // Visible again -> safely reactivated.
      await _popCoveringPage(tester);
      expect(container.read(cameraHardwareProvider).status, CameraStatus.ready);
      expect(service.liveControllers, 1);
      expect(service.initializeControllerCalls, 2);
    });

    testWidgets(
        'repeated cover/reveal cycles never duplicate initialization nor leak',
        (tester) async {
      final service = _RouteLifecycleCameraService();
      await tester.pumpWidget(createCameraTestWidget(
        navigatorObservers: [appRouteObserver],
        overrides: [
          cameraHardwareServiceProvider.overrideWithValue(service),
        ],
      ));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(CameraScreen)),
      );
      expect(service.initializeControllerCalls, 1);
      expect(service.liveControllers, 1);

      for (var cycle = 0; cycle < 3; cycle++) {
        await _pushCoveringPage(tester, label: 'COVER $cycle');
        expect(service.liveControllers, 0,
            reason: 'covered: CameraX must be released');
        expect(container.read(cameraHardwareProvider).status,
            CameraStatus.unavailable);

        await _popCoveringPage(tester);
        expect(service.liveControllers, 1,
            reason: 'visible: exactly one camera resource');
        expect(container.read(cameraHardwareProvider).status,
            CameraStatus.ready);
        expect(service.initializeControllerCalls, cycle + 2);
      }

      // No leaked controllers: everything created is either live or disposed.
      expect(
        service.disposeControllerCalls,
        service.createControllerCalls - service.liveControllers,
      );
    });

    testWidgets(
        'CameraX stays inactive while any page route covers it (nested routes)',
        (tester) async {
      final service = _RouteLifecycleCameraService();
      await tester.pumpWidget(createCameraTestWidget(
        navigatorObservers: [appRouteObserver],
        overrides: [
          cameraHardwareServiceProvider.overrideWithValue(service),
        ],
      ));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(CameraScreen)),
      );

      await _pushCoveringPage(tester, label: 'A');
      expect(container.read(cameraHardwareProvider).status,
          CameraStatus.unavailable);
      final initsAfterFirstCover = service.initializeControllerCalls;

      // A second covering route must not resume the camera underneath.
      await _pushCoveringPage(tester, label: 'B');
      expect(container.read(cameraHardwareProvider).status,
          CameraStatus.unavailable);
      expect(service.initializeControllerCalls, initsAfterFirstCover);

      // Popping B leaves A covering -> still inactive.
      await _popCoveringPage(tester);
      expect(container.read(cameraHardwareProvider).status,
          CameraStatus.unavailable);
      expect(service.initializeControllerCalls, initsAfterFirstCover);

      // Popping A reveals the camera -> reactivated exactly once.
      await _popCoveringPage(tester);
      expect(container.read(cameraHardwareProvider).status, CameraStatus.ready);
      expect(service.initializeControllerCalls, initsAfterFirstCover + 1);
    });

    testWidgets(
        'background/foreground while covered does not reactivate CameraX',
        (tester) async {
      final service = _RouteLifecycleCameraService();
      await tester.pumpWidget(createCameraTestWidget(
        navigatorObservers: [appRouteObserver],
        overrides: [
          cameraHardwareServiceProvider.overrideWithValue(service),
        ],
      ));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(CameraScreen)),
      );

      await _pushCoveringPage(tester);
      final initsUnderCover = service.initializeControllerCalls;
      expect(container.read(cameraHardwareProvider).status,
          CameraStatus.unavailable);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(container.read(cameraHardwareProvider).status,
          CameraStatus.unavailable);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // Still covered: resumed lifecycle must NOT reinitialize CameraX.
      expect(container.read(cameraHardwareProvider).status,
          CameraStatus.unavailable);
      expect(service.initializeControllerCalls, initsUnderCover);
      expect(service.liveControllers, 0);

      // Revealing the screen reactivates exactly once.
      await _popCoveringPage(tester);
      expect(container.read(cameraHardwareProvider).status, CameraStatus.ready);
      expect(service.initializeControllerCalls, initsUnderCover + 1);
      expect(service.liveControllers, 1);
    });

    testWidgets(
        'redundant pause/resume requests never leak nor duplicate a camera resource',
        (tester) async {
      final service = _RouteLifecycleCameraService();
      await tester.pumpWidget(createCameraTestWidget(
        overrides: [
          cameraHardwareServiceProvider.overrideWithValue(service),
        ],
      ));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(CameraScreen)),
      );
      final notifier = container.read(cameraHardwareProvider.notifier);

      await notifier.pauseCamera();
      final disposesAfterFirstPause = service.disposeControllerCalls;
      expect(service.liveControllers, 0);

      await notifier.pauseCamera();
      await notifier.pauseCamera();
      expect(service.disposeControllerCalls, disposesAfterFirstPause,
          reason: 'redundant pauses must not touch the controller again');
      expect(service.liveControllers, 0);

      // Repeated resumes converge on exactly one live camera resource and
      // never leak a controller.
      await notifier.resumeCamera();
      await notifier.resumeCamera();
      await notifier.resumeCamera();
      expect(service.liveControllers, 1,
          reason: 'exactly one camera resource owner after repeated resumes');
      expect(service.createControllerCalls, service.initializeControllerCalls);
      expect(service.disposeControllerCalls,
          service.createControllerCalls - service.liveControllers);
    });

    testWidgets(
        'disposing CameraScreen while active releases CameraX and late callbacks are harmless',
        (tester) async {
      final service = _RouteLifecycleCameraService();
      await tester.pumpWidget(createCameraTestWidget(
        navigatorObservers: [appRouteObserver],
        overrides: [
          cameraHardwareServiceProvider.overrideWithValue(service),
        ],
      ));
      await tester.pumpAndSettle();
      expect(service.liveControllers, 1);

      // Dispose the screen while the camera is active.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      expect(service.liveControllers, 0,
          reason: 'disposal must release the camera resource');

      // Late lifecycle events after disposal must be harmless.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();

      expect(service.liveControllers, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'failed CameraX resume exposes a truthful error state without leaking',
        (tester) async {
      final service = _RouteLifecycleCameraService();
      await tester.pumpWidget(createCameraTestWidget(
        navigatorObservers: [appRouteObserver],
        overrides: [
          cameraHardwareServiceProvider.overrideWithValue(service),
        ],
      ));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(CameraScreen)),
      );
      expect(container.read(cameraHardwareProvider).status, CameraStatus.ready);

      await _pushCoveringPage(tester);
      expect(container.read(cameraHardwareProvider).status,
          CameraStatus.unavailable);

      // CameraX cannot be reacquired on reveal.
      service.failInitialization = true;
      await _popCoveringPage(tester);

      final state = container.read(cameraHardwareProvider);
      expect(state.status, CameraStatus.error,
          reason: 'a failed resume must surface a truthful error state');
      expect(state.errorMessage, isNotNull);
      expect(state.isReady, isFalse);
      expect(service.liveControllers, 0,
          reason: 'failed initialization candidates must be disposed');
    });
  });

  group('B1 GPS State Semantics & Capture Gate', () {
    testWidgets(
        'capture readiness uses live-fix provenance: last-known locks, live fix unlocks',
        (tester) async {
      // 1. Cached/last-known seed only — no live stream emission.
      await tester.pumpWidget(createCameraTestWidget(
        overrides: [
          cameraHardwareServiceProvider
              .overrideWithValue(_RouteLifecycleCameraService()),
          locationHardwareServiceProvider
              .overrideWithValue(_LastKnownOnlyLocationService()),
        ],
      ));
      await tester.pumpAndSettle();

      expect(
        tester.widget<ShutterButton>(find.byType(ShutterButton)).isLocked,
        isTrue,
        reason:
            'cached/last-known coordinates must never unlock evidence capture',
      );
      expect(find.textContaining('GPS: Last known'), findsOneWidget);
      expect(find.textContaining('GPS Fixed'), findsNothing);
      expect(
        find.textContaining('Shutter locked — GPS required for evidence'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // 2. A live fix (default live stream) unlocks the shutter.
      await tester.pumpWidget(createCameraTestWidget(
        overrides: [
          cameraHardwareServiceProvider
              .overrideWithValue(_RouteLifecycleCameraService()),
        ],
      ));
      await tester.pumpAndSettle();

      expect(
        tester.widget<ShutterButton>(find.byType(ShutterButton)).isLocked,
        isFalse,
      );
      expect(find.textContaining('GPS Fixed'), findsOneWidget);
      expect(find.textContaining('GPS: Last known'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'GPS state stays truthful across a covered route round-trip',
        (tester) async {
      await tester.pumpWidget(createCameraTestWidget(
        navigatorObservers: [appRouteObserver],
        overrides: [
          cameraHardwareServiceProvider
              .overrideWithValue(_RouteLifecycleCameraService()),
        ],
      ));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(CameraScreen)),
      );
      expect(container.read(gpsHardwareProvider).hasLiveFix, isTrue);

      await _pushCoveringPage(tester);
      await _popCoveringPage(tester);

      // Returning from a covered route neither fabricates nor drops provenance.
      expect(container.read(gpsHardwareProvider).hasLiveFix, isTrue);
      expect(
        tester.widget<ShutterButton>(find.byType(ShutterButton)).isLocked,
        isFalse,
      );

      // If the live fix is lost while covered, the revealed screen stays locked.
      await _pushCoveringPage(tester);
      container.read(gpsHardwareProvider.notifier).setStaleOrSearching();
      await tester.pumpAndSettle();
      await _popCoveringPage(tester);

      expect(container.read(gpsHardwareProvider).hasLiveFix, isFalse);
      expect(
        tester.widget<ShutterButton>(find.byType(ShutterButton)).isLocked,
        isTrue,
      );
      expect(find.textContaining('GPS: Searching'), findsOneWidget);
    });
  });
}

/// Camera service that reports a real (test) camera and counts controller
/// creation / initialization / disposal so tests can prove there is exactly
/// one camera resource owner and no leak.
class _RouteLifecycleCameraService extends CameraHardwareService {
  int createControllerCalls = 0;
  int initializeControllerCalls = 0;
  int disposeControllerCalls = 0;
  int liveControllers = 0;
  bool failInitialization = false;

  static const CameraDescription _backCamera = CameraDescription(
    name: '0',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 90,
  );

  @override
  Future<List<CameraDescription>> getAvailableCameras() async => [_backCamera];

  @override
  CameraController createController({
    required CameraDescription cameraDescription,
    ResolutionPreset resolutionPreset = ResolutionPreset.max,
    bool enableAudio = true,
  }) {
    createControllerCalls++;
    liveControllers++;
    return super.createController(
      cameraDescription: cameraDescription,
      resolutionPreset: resolutionPreset,
      enableAudio: enableAudio,
    );
  }

  @override
  Future<void> initializeController(CameraController controller) async {
    initializeControllerCalls++;
    if (failInitialization) {
      // Fails every resolution-preset attempt, so reacquisition cannot recover.
      throw CameraException('CameraUnavailable', 'Simulated camera fault');
    }
  }

  @override
  Future<void> disposeController(CameraController? controller) async {
    if (controller == null) return;
    disposeControllerCalls++;
    liveControllers--;
  }

  @override
  Future<double> getMinZoomLevel(CameraController controller) async => 1.0;

  @override
  Future<double> getMaxZoomLevel(CameraController controller) async => 5.0;

  @override
  Future<void> setZoomLevel(CameraController controller, double zoom) async {}
}

/// Pushes a full-page route above CameraScreen; page routes are exactly what
/// [appRouteObserver] reports as coverage (dialogs/bottom sheets are not).
Future<void> _pushCoveringPage(WidgetTester tester, {String label = 'COVER'}) async {
  tester.state<NavigatorState>(find.byType(Navigator).first).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(label)),
            body: Center(child: Text(label)),
          ),
        ),
      );
  await tester.pumpAndSettle();
}

Future<void> _popCoveringPage(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator).first).pop();
  await tester.pumpAndSettle();
}

/// Location service that supplies a fresh, accurate last-known position but
/// never emits a live position stream — i.e. "last-known only".
class _LastKnownOnlyLocationService extends LocationHardwareService {
  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<Position?> getLastKnownPosition() async => Position(
        latitude: 22.562856,
        longitude: 88.300731,
        timestamp: DateTime.now().toUtc().subtract(const Duration(seconds: 5)),
        accuracy: 4.6,
        altitude: 2.7,
        altitudeAccuracy: 1.0,
        heading: 0.0,
        headingAccuracy: 1.0,
        speed: 0.0,
        speedAccuracy: 1.0,
      );

  @override
  Future<AltitudeTelemetry> getAltitudeTelemetry() async =>
      const AltitudeTelemetry(hasMslAltitude: true, mslAltitudeMeters: 2.7);

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      const Stream<Position>.empty();
}
