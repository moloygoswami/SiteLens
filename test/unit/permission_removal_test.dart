import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sitelens/core/services/permission_service.dart';

/// Guards for the audited removal of unused device media-library permissions.
///
/// SiteLens only ever writes evidence to app-private storage and never reads or
/// imports the device photo/video library, so READ_MEDIA_IMAGES,
/// READ_MEDIA_VIDEO, READ_EXTERNAL_STORAGE and WRITE_EXTERNAL_STORAGE must not
/// be declared or requested.
void main() {
  group('Unused media permissions removal — static guards', () {
    test('AndroidManifest does not request any of the removed media/storage permissions', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

      // Media-library permissions must be absent entirely.
      expect(manifest.contains('READ_MEDIA_IMAGES'), isFalse);
      expect(manifest.contains('READ_MEDIA_VIDEO'), isFalse);

      // External-storage permissions may appear ONLY as manifest-merger suppressions
      // (they are injected by the camera plugin and removed here); they must never be requested.
      final permissionLines =
          manifest.split('\n').where((l) => l.contains('uses-permission'));
      for (final name in ['READ_EXTERNAL_STORAGE', 'WRITE_EXTERNAL_STORAGE']) {
        for (final line in permissionLines.where((l) => l.contains(name))) {
          expect(line.contains('tools:node="remove"'), isTrue,
              reason: '$name must only appear as a tools:node="remove" suppression');
        }
      }

      // Sanity: core capture permissions must remain declared.
      expect(manifest.contains('android.permission.CAMERA'), isTrue);
      expect(manifest.contains('android.permission.ACCESS_FINE_LOCATION'), isTrue);
    });

    test('PermissionService references neither photos nor storage permissions', () {
      final source =
          File('lib/core/services/permission_service.dart').readAsStringSync();

      expect(source.contains('Permission.photos'), isFalse);
      expect(source.contains('Permission.storage'), isFalse);
    });

    test('requestAllCorePermissions requests only camera and location', () {
      final source =
          File('lib/core/services/permission_service.dart').readAsStringSync();

      final batch = RegExp(
        r'requestAllCorePermissions\(\)[\s\S]*?await \[([\s\S]*?)\]\.request\(\);',
      ).firstMatch(source);

      expect(batch, isNotNull, reason: 'requestAllCorePermissions() not found');
      final requested = batch!.group(1)!;
      expect(requested.contains('Permission.camera'), isTrue);
      expect(requested.contains('Permission.location'), isTrue);
      expect(requested.contains('Permission.photos'), isFalse);
      expect(requested.contains('Permission.storage'), isFalse);
    });
  });

  group('Core capture progression gate', () {
    test('camera + location are the only required (core) permissions', () {
      const granted = SiteLensPermissionStatus(
        camera: PermissionStatus.granted,
        location: PermissionStatus.granted,
      );
      expect(granted.areCorePermissionsGranted, isTrue);

      const missingLocation = SiteLensPermissionStatus(
        camera: PermissionStatus.granted,
        location: PermissionStatus.denied,
      );
      expect(missingLocation.areCorePermissionsGranted, isFalse);

      const missingCamera = SiteLensPermissionStatus(
        camera: PermissionStatus.denied,
        location: PermissionStatus.granted,
      );
      expect(missingCamera.areCorePermissionsGranted, isFalse);
    });
  });
}
