import 'dart:async';
import 'dart:ffi' show DynamicLibrary;
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
import 'package:sitelens/features/camera/models/camera_hardware_state.dart';
import 'package:sitelens/features/onboarding/permission_recovery_screen.dart';
import 'package:sitelens/features/sync/services/cloud_sync_service.dart';
import 'package:sitelens/features/sync/services/sync_coordinator.dart';
import 'package:sitelens/data/repositories/site_repository.dart';
import 'package:sitelens/domain/models/site_model.dart';

class _MockCameraAuthService implements AuthService {
  final _user = const AuthUser(uid: 'test-user-id', email: 'inspector@sitelens.local');
  @override
  Stream<AuthUser?> get authStateChanges => Stream.value(_user);
  @override
  AuthUser? get currentUser => _user;
  @override
  Future<AuthUser> signInWithEmailPassword(String e, String p) async => _user;
  @override
  Future<AuthUser?> signInWithGoogle() async => _user;
  @override
  Future<AuthUser> signUpWithEmailPassword(String e, String p, {String? displayName}) async => _user;
  @override
  Future<void> sendEmailVerificationForUser(String e, String p) async {}
  @override
  Future<void> sendPasswordResetEmail(String e) async {}
  @override
  Future<SessionVerificationResult> verifySession() async => const SessionVerificationResult.valid();
  @override
  Future<void> signOut() async {}
}

class _MockCameraLocationService extends LocationHardwareService {
  @override
  Future<LocationPermission> checkPermission() async => LocationPermission.always;
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<Position> getCurrentPosition() async => Position(
        latitude: 22.57264,
        longitude: 88.36391,
        timestamp: DateTime.now(),
        accuracy: 4.2,
        altitude: 12.0,
        heading: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
        altitudeAccuracy: 1.0,
        headingAccuracy: 1.0,
      );
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) => Stream.value(
        Position(
          latitude: 22.57264,
          longitude: 88.36391,
          timestamp: DateTime.now(),
          accuracy: 4.2,
          altitude: 12.0,
          heading: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
          altitudeAccuracy: 1.0,
          headingAccuracy: 1.0,
        ),
      );
}

class _TestPermissionService extends PermissionService {
  SiteLensPermissionStatus mockStatus;
  int requestCameraPermissionCallCount = 0;
  int checkCameraPermissionCallCount = 0;

  _TestPermissionService({
    this.mockStatus = const SiteLensPermissionStatus(
      camera: PermissionStatus.granted,
      location: PermissionStatus.granted,
      photos: PermissionStatus.granted,
    ),
  }) {
    state = mockStatus;
  }

  void updateCameraPermission(PermissionStatus status) {
    mockStatus = mockStatus.copyWith(camera: status);
    state = mockStatus;
  }

  @override
  Future<SiteLensPermissionStatus> checkAllPermissions() async {
    state = mockStatus;
    return mockStatus;
  }

  @override
  Future<PermissionStatus> checkCameraPermission() async {
    checkCameraPermissionCallCount++;
    state = mockStatus;
    return mockStatus.camera;
  }

  @override
  Future<PermissionStatus> requestCameraPermission() async {
    requestCameraPermissionCallCount++;
    state = mockStatus;
    return mockStatus.camera;
  }
}

class _TestCameraService extends CameraHardwareService {
  final List<CameraDescription> cameras;
  _TestCameraService({this.cameras = const [
    CameraDescription(
      name: '0',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
  ]});

  @override
  Future<List<CameraDescription>> getAvailableCameras() async => cameras;

  @override
  Future<void> initializeController(CameraController controller) async {}

  @override
  Future<void> disposeController(CameraController? controller) async {}

  @override
  Future<double> getMinZoomLevel(CameraController controller) async => 0.5;

  @override
  Future<double> getMaxZoomLevel(CameraController controller) async => 5.0;

  @override
  Future<void> setZoomLevel(CameraController controller, double zoom) async {}
}

class _MockSiteRepo implements SiteRepository {
  @override
  Future<List<SiteModel>> getAllSites({String? creatorId}) async => [];
  @override
  Future<SiteModel?> getSiteById(String id) async => null;
  @override
  Future<void> saveSite(SiteModel site) async {}
  @override
  Future<void> deleteSite(String id, {String? creatorId}) async {}
  @override
  Future<bool> hasMediaForSite(String siteId) async => false;
  @override
  Future<void> seedDefaultSitesIfEmpty() async {}
}

class _TestStorageService implements EvidenceStorageService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestCloudSyncService implements CloudSyncService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestConnectivity implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => Stream.value([ConnectivityResult.wifi]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _buildTestApp({
  required _TestPermissionService permissionService,
  CameraHardwareService? cameraService,
  List<NavigatorObserver> observers = const [],
}) {
  final db = AppDatabase(NativeDatabase.memory());
  return ProviderScope(
    overrides: [
      authServiceProvider.overrideWithValue(_MockCameraAuthService()),
      permissionServiceProvider.overrideWith((ref) => permissionService),
      cameraHardwareServiceProvider.overrideWithValue(cameraService ?? _TestCameraService()),
      locationHardwareServiceProvider.overrideWithValue(_MockCameraLocationService()),
      siteRepositoryProvider.overrideWithValue(_MockSiteRepo()),
      activeSiteMediaStreamProvider.overrideWith((ref) => Stream.value([])),
      appDatabaseProvider.overrideWithValue(db),
      syncCoordinatorProvider.overrideWith(
        (ref) => SyncCoordinator(
          mediaRepo: LocalMediaRepository(db),
          cloudSyncService: _TestCloudSyncService(),
          storageService: _TestStorageService(),
          authService: _MockCameraAuthService(),
          connectivity: _TestConnectivity(),
        ),
      ),
    ],
    child: MaterialApp(
      home: const CameraScreen(),
      onGenerateRoute: AppRoutes.onGenerateRoute,
      navigatorObservers: observers,
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

  tearDown(() {});

  void setPortraitView(WidgetTester tester) {
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  group('Camera Permission Recovery Tests', () {
    testWidgets('1. Temporary denial displays CAMERA ACCESS REQUIRED and GRANT ACCESS button invokes permission request', (tester) async {
      setPortraitView(tester);
      final permService = _TestPermissionService(
        mockStatus: const SiteLensPermissionStatus(
          camera: PermissionStatus.denied,
          location: PermissionStatus.granted,
          photos: PermissionStatus.granted,
        ),
      );

      await tester.pumpWidget(_buildTestApp(permissionService: permService));
      await tester.pumpAndSettle();

      // Viewfinder displays dedicated permission-required state
      expect(find.text('CAMERA ACCESS REQUIRED'), findsWidgets);
      expect(find.text('Camera access is required to capture evidence.'), findsWidgets);
      expect(find.text('GRANT ACCESS'), findsOneWidget);

      // Shutter is locked
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      expect(find.text('Camera permission required — grant access to capture evidence.'), findsOneWidget);

      // Tap GRANT ACCESS button -> routes request through PermissionService abstraction
      await tester.tap(find.text('GRANT ACCESS'));
      await tester.pumpAndSettle();

      expect(permService.requestCameraPermissionCallCount, greaterThanOrEqualTo(1));
    });

    testWidgets('2. Permanent denial displays CAMERA ACCESS BLOCKED and OPEN SETTINGS button navigates to recovery route', (tester) async {
      setPortraitView(tester);

      final permService = _TestPermissionService(
        mockStatus: const SiteLensPermissionStatus(
          camera: PermissionStatus.permanentlyDenied,
          location: PermissionStatus.granted,
          photos: PermissionStatus.granted,
        ),
      );

      await tester.pumpWidget(_buildTestApp(permissionService: permService));
      await tester.pumpAndSettle();

      // Viewfinder displays permanent denial state
      expect(find.text('CAMERA ACCESS BLOCKED'), findsWidgets);
      expect(find.text('OPEN SETTINGS'), findsOneWidget);

      // Shutter displays blocked status
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      expect(find.text('Camera permission blocked — enable in settings to capture evidence.'), findsOneWidget);

      // Tap OPEN SETTINGS -> pushes PermissionRecoveryScreen
      await tester.tap(find.text('OPEN SETTINGS'));
      await tester.pumpAndSettle();

      expect(find.byType(PermissionRecoveryScreen), findsOneWidget);
    });

    testWidgets('3. Restricted permission displays informative notice with NO futile in-app grant/recovery buttons', (tester) async {
      final permService = _TestPermissionService(
        mockStatus: const SiteLensPermissionStatus(
          camera: PermissionStatus.restricted,
          location: PermissionStatus.granted,
          photos: PermissionStatus.granted,
        ),
      );

      await tester.pumpWidget(_buildTestApp(permissionService: permService));
      await tester.pumpAndSettle();

      // Viewfinder displays restricted state
      expect(find.text('CAMERA ACCESS RESTRICTED'), findsWidgets);
      expect(find.textContaining('restricted by device policy'), findsWidgets);

      // Constraint 1 verification: MUST NOT render action buttons for restricted status
      expect(find.text('GRANT ACCESS'), findsNothing);
      expect(find.text('OPEN SETTINGS'), findsNothing);
      expect(find.text('RETRY CAMERA'), findsNothing);

      // Shutter is locked with policy message
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      expect(find.text('Camera access restricted by device policy.'), findsOneWidget);
    });

    testWidgets('4. Physical camera absence renders OPTICAL SENSOR UNAVAILABLE without falsely claiming missing permission', (tester) async {
      final permService = _TestPermissionService(
        mockStatus: const SiteLensPermissionStatus(
          camera: PermissionStatus.granted,
          location: PermissionStatus.granted,
          photos: PermissionStatus.granted,
        ),
      );

      // Empty cameras simulates absent physical sensor
      final emptyCamService = _TestCameraService(cameras: const []);

      await tester.pumpWidget(_buildTestApp(
        permissionService: permService,
        cameraService: emptyCamService,
      ));
      await tester.pumpAndSettle();

      // Honest physical hardware message
      expect(find.text('OPTICAL SENSOR UNAVAILABLE'), findsWidgets);
      expect(find.text('No physical camera detected on this device.'), findsOneWidget);
      expect(find.text('RETRY CAMERA'), findsOneWidget);

      // Never falsely claim permission is denied or blocked
      expect(find.text('GRANT ACCESS'), findsNothing);
      expect(find.text('CAMERA ACCESS REQUIRED'), findsNothing);
      expect(find.text('CAMERA ACCESS BLOCKED'), findsNothing);
    });

    testWidgets('5. Permission restoration on resume re-checks permission and transitions camera to ready', (tester) async {
      final permService = _TestPermissionService(
        mockStatus: const SiteLensPermissionStatus(
          camera: PermissionStatus.denied,
          location: PermissionStatus.granted,
          photos: PermissionStatus.granted,
        ),
      );

      await tester.pumpWidget(_buildTestApp(permissionService: permService));
      await tester.pumpAndSettle();

      expect(find.text('CAMERA ACCESS REQUIRED'), findsWidgets);

      // User grants permission in system
      permService.updateCameraPermission(PermissionStatus.granted);

      // App resumes / resumeCamera() invoked
      final element = tester.element(find.byType(CameraScreen));
      final container = ProviderScope.containerOf(element);
      await container.read(cameraHardwareProvider.notifier).resumeCamera();
      await tester.pumpAndSettle();

      // Camera transitions to ready
      final hwState = container.read(cameraHardwareProvider);
      expect(hwState.status, CameraStatus.ready);
      expect(find.text('ACTIVE SENSOR VIEWPORT'), findsOneWidget);
    });
  });
}
