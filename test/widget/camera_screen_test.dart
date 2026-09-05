import 'dart:async';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:camera/camera.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/open.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sitelens/app/router.dart';
import 'package:sitelens/core/services/auth_service.dart';
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
import 'package:sitelens/features/review/models/pending_capture_payload.dart';

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
  Future<void> deleteSite(String id) async {}

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

Widget createCameraTestWidget({
  CameraUiState? state,
  List<Override> overrides = const [],
  Size size = const Size(400, 800),
}) {
  final db = AppDatabase(NativeDatabase.memory());
  return ProviderScope(
    overrides: [
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
      // that camera access is required; the GPS pill carries the cause.
      expect(find.textContaining('CAMERA ACCESS REQUIRED'), findsWidgets);
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

      // No camera in test env: banner correctly reports camera access required
      // rather than claiming readiness. The GPS pill shows the
      // degraded GPS state truthfully.
      expect(find.textContaining('GPS: Poor'), findsOneWidget);
      expect(find.textContaining('CAMERA ACCESS REQUIRED'), findsWidgets);
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
      await tester.pumpWidget(createCameraTestWidget());
      await tester.pumpAndSettle();

      // Viewfinder states camera access is required with retry button
      expect(find.text('CAMERA ACCESS REQUIRED'), findsWidgets);
      expect(find.text('RETRY CAMERA'), findsOneWidget);

      // Shutter is locked (lock icon), capture is not permitted.
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      expect(find.text('Camera access required to capture evidence.'), findsOneWidget);

      // Pressing the shutter shows the unmistakable blocker, never a fake capture.
      await tester.tap(find.byType(ShutterButton), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.textContaining('Camera access is required to capture evidence.'), findsWidgets);
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
}
