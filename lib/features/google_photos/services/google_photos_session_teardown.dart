import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/session_end_teardown.dart';
import '../controllers/google_photos_settings_controller.dart';
import 'google_photos_api_service.dart';

/// Revokes and clears the ending user's Google Photos grant when a SiteLens
/// session ends, so no Photos state survives across account boundaries.
///
/// Registered in the composition root via [sessionEndTeardownsProvider].
class GooglePhotosSessionEndTeardown implements SessionEndTeardown {
  final Ref _ref;

  GooglePhotosSessionEndTeardown(this._ref);

  @override
  Future<void> onSessionEnded(String endingUid) async {
    await _ref.read(googlePhotosSettingsProvider.notifier).revokeAndClearForUser(endingUid);
    await _ref.read(googlePhotosApiServiceProvider).invalidateAlbumId(ownerUid: endingUid);
  }
}
