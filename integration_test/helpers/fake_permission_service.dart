import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sitelens/core/services/permission_service.dart';

class FakePermissionService extends StateNotifier<SiteLensPermissionStatus>
    implements PermissionService {
  FakePermissionService([
    super.initial = const SiteLensPermissionStatus(
      camera: PermissionStatus.granted,
      location: PermissionStatus.granted,
      photos: PermissionStatus.granted,
      microphone: PermissionStatus.granted,
      notifications: PermissionStatus.granted,
    ),
  ]);

  void setPermissions(SiteLensPermissionStatus status) {
    state = status;
  }

  @override
  Future<SiteLensPermissionStatus> checkAllPermissions() async => state;

  @override
  Future<PermissionStatus> requestCameraPermission() async => state.camera;

  @override
  Future<PermissionStatus> requestLocationPermission() async => state.location;

  @override
  Future<PermissionStatus> requestPhotosPermission() async => state.photos;

  @override
  Future<PermissionStatus> requestMicrophonePermission() async => state.microphone;

  @override
  Future<PermissionStatus> requestNotificationPermission() async => state.notifications;

  @override
  Future<void> requestAllCorePermissions() async {}

  @override
  Future<PermissionStatus> requestIgnoreBatteryOptimizations() async =>
      PermissionStatus.granted;

  @override
  Future<bool> isBatteryOptimizationIgnored() async => true;

  @override
  Future<bool> openSystemSettings() async => true;
}
