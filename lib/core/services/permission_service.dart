import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

class SiteLensPermissionStatus {
  final PermissionStatus camera;
  final PermissionStatus location;
  final PermissionStatus microphone;
  final PermissionStatus notifications;

  const SiteLensPermissionStatus({
    this.camera = PermissionStatus.denied,
    this.location = PermissionStatus.denied,
    this.microphone = PermissionStatus.denied,
    this.notifications = PermissionStatus.denied,
  });

  bool get areCorePermissionsGranted =>
      camera.isGranted && location.isGranted;

  bool get isPermanentlyDenied =>
      camera.isPermanentlyDenied || location.isPermanentlyDenied;

  bool get isCameraGranted => camera.isGranted || camera.isLimited;
  bool get isCameraDenied => camera.isDenied;
  bool get isCameraPermanentlyDenied => camera.isPermanentlyDenied;
  bool get isCameraRestricted => camera.isRestricted;

  SiteLensPermissionStatus copyWith({
    PermissionStatus? camera,
    PermissionStatus? location,
    PermissionStatus? microphone,
    PermissionStatus? notifications,
  }) {
    return SiteLensPermissionStatus(
      camera: camera ?? this.camera,
      location: location ?? this.location,
      microphone: microphone ?? this.microphone,
      notifications: notifications ?? this.notifications,
    );
  }
}

class PermissionService extends StateNotifier<SiteLensPermissionStatus> {
  PermissionService() : super(const SiteLensPermissionStatus()) {
    checkAllPermissions();
  }

  Future<PermissionStatus> checkCameraPermission() async {
    try {
      final status = await Permission.camera.status;
      state = state.copyWith(camera: status);
      return status;
    } catch (e) {
      debugPrint('Error checking camera permission: $e');
      return state.camera;
    }
  }

  Future<SiteLensPermissionStatus> checkAllPermissions() async {
    try {
      final cameraStatus = await Permission.camera.status;

      var locationStatus = await Permission.location.status;
      if (!locationStatus.isGranted) {
        final locWhenInUse = await Permission.locationWhenInUse.status;
        if (locWhenInUse.isGranted) {
          locationStatus = locWhenInUse;
        }
      }

      final micStatus = await Permission.microphone.status;
      final notifStatus = await Permission.notification.status;

      final updated = SiteLensPermissionStatus(
        camera: cameraStatus,
        location: locationStatus,
        microphone: micStatus,
        notifications: notifStatus,
      );

      state = updated;
      return updated;
    } catch (e) {
      debugPrint('Error checking permissions: $e');
      return state;
    }
  }

  Future<PermissionStatus> requestCameraPermission() async {
    final res = await Permission.camera.request();
    await checkCameraPermission();
    return res;
  }

  Future<PermissionStatus> requestLocationPermission() async {
    var res = await Permission.location.request();
    if (!res.isGranted) {
      res = await Permission.locationWhenInUse.request();
    }
    await checkAllPermissions();
    return res;
  }

  Future<PermissionStatus> requestMicrophonePermission() async {
    final res = await Permission.microphone.request();
    await checkAllPermissions();
    return res;
  }

  Future<PermissionStatus> requestNotificationPermission() async {
    final res = await Permission.notification.request();
    await checkAllPermissions();
    return res;
  }

  Future<void> requestAllCorePermissions() async {
    // Request via batch to allow OS to display permissions natively in sequence
    await [
      Permission.camera,
      Permission.location,
    ].request();
    await checkAllPermissions();
  }

  Future<bool> openSystemSettings() async {
    return await openAppSettings();
  }
}

final permissionServiceProvider =
    StateNotifierProvider<PermissionService, SiteLensPermissionStatus>((ref) {
  return PermissionService();
});
