import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sitelens/core/services/permission_service.dart';

void main() {
  group('SiteLensPermissionStatus Tests', () {
    test('Identifies when core permissions are granted', () {
      const status = SiteLensPermissionStatus(
        camera: PermissionStatus.granted,
        location: PermissionStatus.granted,
        photos: PermissionStatus.granted,
      );

      expect(status.areCorePermissionsGranted, isTrue);
      expect(status.isPermanentlyDenied, isFalse);
    });

    test('Identifies when permissions are missing', () {
      const status = SiteLensPermissionStatus(
        camera: PermissionStatus.denied,
        location: PermissionStatus.granted,
      );

      expect(status.areCorePermissionsGranted, isFalse);
      expect(status.isPermanentlyDenied, isFalse);
    });

    test('Identifies permanently denied permission state', () {
      const status = SiteLensPermissionStatus(
        camera: PermissionStatus.permanentlyDenied,
        location: PermissionStatus.granted,
      );

      expect(status.areCorePermissionsGranted, isFalse);
      expect(status.isPermanentlyDenied, isTrue);
    });
  });
}
