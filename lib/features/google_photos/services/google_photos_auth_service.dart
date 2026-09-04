import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

final googlePhotosAuthServiceProvider = Provider<GooglePhotosAuthService>((ref) {
  return GooglePhotosAuthService();
});

class GooglePhotosAuthService {
  static const String photosScope = 'https://www.googleapis.com/auth/photoslibrary.appendonly';

  final GoogleSignIn _googleSignIn;

  GooglePhotosAuthService({GoogleSignIn? googleSignIn})
      : _googleSignIn = googleSignIn ??
            GoogleSignIn(
              scopes: const [photosScope, 'email'],
            );

  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  Stream<GoogleSignInAccount?> get onCurrentUserChanged => _googleSignIn.onCurrentUserChanged;

  Future<GoogleSignInAccount?> connect() async {
    try {
      final account = await _googleSignIn.signIn();
      return account;
    } catch (e) {
      debugPrint('GooglePhotosAuthService connect error: $e');
      rethrow;
    }
  }

  Future<void> disconnect() async {
    try {
      await _googleSignIn.disconnect();
    } catch (e) {
      debugPrint('GooglePhotosAuthService disconnect error: $e');
      await _googleSignIn.signOut();
    }
  }

  Future<Map<String, String>> getAuthHeaders() async {
    final account = _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();
    if (account == null) {
      throw Exception('Google Photos user is not connected.');
    }
    return account.authHeaders;
  }

  Future<bool> isSignedIn() async {
    return _googleSignIn.isSignedIn();
  }
}
