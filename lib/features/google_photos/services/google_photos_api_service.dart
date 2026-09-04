import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'google_photos_auth_service.dart';

class GooglePhotosAuthException implements Exception {
  final String message;
  GooglePhotosAuthException(this.message);
  @override
  String toString() => 'GooglePhotosAuthException: $message';
}

class GooglePhotosApiException implements Exception {
  final String message;
  final int? statusCode;
  final bool isRetryable;
  GooglePhotosApiException(this.message, {this.statusCode, this.isRetryable = false});
  @override
  String toString() => 'GooglePhotosApiException ($statusCode): $message';
}

final googlePhotosApiServiceProvider = Provider<GooglePhotosApiService>((ref) {
  final authService = ref.watch(googlePhotosAuthServiceProvider);
  return GooglePhotosApiService(authService: authService);
});

class GooglePhotosApiService {
  final GooglePhotosAuthService _authService;
  final HttpClient _httpClient;
  String? _cachedAlbumId;

  GooglePhotosApiService({
    required GooglePhotosAuthService authService,
    HttpClient? httpClient,
  })  : _authService = authService,
        _httpClient = httpClient ?? HttpClient();

  static const String baseUrl = 'https://photoslibrary.googleapis.com/v1';

  /// Uploads binary raw bytes to Google Photos upload endpoint and returns the uploadToken.
  Future<String> uploadBytes({
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final authHeaders = await _getAuthHeaders();
    final uri = Uri.parse('$baseUrl/uploads');

    final request = await _httpClient.postUrl(uri);
    authHeaders.forEach((k, v) => request.headers.set(k, v));
    request.headers.set('Content-type', 'application/octet-stream');
    request.headers.set('X-Goog-Upload-Content-Type', mimeType);
    request.headers.set('X-Goog-Upload-Protocol', 'raw');

    request.add(bytes);
    final response = await request.close();

    final responseBody = await utf8.decodeStream(response);

    if (response.statusCode == 200) {
      return responseBody.trim();
    } else if (response.statusCode == 401 || response.statusCode == 403) {
      throw GooglePhotosAuthException('Authentication expired or unauthorized ($response.statusCode).');
    } else if (response.statusCode == 429 || response.statusCode >= 500) {
      throw GooglePhotosApiException('Upload server error ($response.statusCode): $responseBody', statusCode: response.statusCode, isRetryable: true);
    } else {
      throw GooglePhotosApiException('Upload failed ($response.statusCode): $responseBody', statusCode: response.statusCode);
    }
  }

  /// Creates a media item in Google Photos from an upload token and assigns it to the album.
  Future<String> createMediaItem({
    required String uploadToken,
    required String fileName,
    required String description,
    String? albumId,
  }) async {
    final authHeaders = await _getAuthHeaders();
    final uri = Uri.parse('$baseUrl/mediaItems:batchCreate');

    final request = await _httpClient.postUrl(uri);
    authHeaders.forEach((k, v) => request.headers.set(k, v));
    request.headers.set('Content-Type', 'application/json; charset=utf-8');

    final payload = {
      if (albumId != null && albumId.isNotEmpty) 'albumId': albumId,
      'newMediaItems': [
        {
          if (description.trim().isNotEmpty) 'description': description.trim(),
          'simpleMediaItem': {
            'fileName': fileName,
            'uploadToken': uploadToken,
          },
        }
      ],
    };

    request.add(utf8.encode(jsonEncode(payload)));
    final response = await request.close();
    final responseBody = await utf8.decodeStream(response);

    if (response.statusCode == 200) {
      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      final results = data['newMediaItemResults'] as List<dynamic>?;
      if (results == null || results.isEmpty) {
        throw GooglePhotosApiException(
          'Media creation failed: empty or missing newMediaItemResults in response.',
          statusCode: response.statusCode,
        );
      }

      final first = results.first as Map<String, dynamic>;
      final status = first['status'] as Map<String, dynamic>?;
      final statusCode = status?['code'] as int? ?? 0;
      final statusMessage = status?['message'] as String?;

      if (statusCode != 0) {
        throw GooglePhotosApiException(
          'Media creation error (code: $statusCode): ${statusMessage ?? "Status code non-zero"}',
          statusCode: response.statusCode,
        );
      }

      final mediaItem = first['mediaItem'] as Map<String, dynamic>?;
      if (mediaItem == null) {
        throw GooglePhotosApiException(
          'Media creation failed: mediaItem object is missing in response.${statusMessage != null ? " Status: $statusMessage" : ""}',
          statusCode: response.statusCode,
        );
      }

      final mediaItemId = mediaItem['id'] as String?;
      if (mediaItemId == null || mediaItemId.trim().isEmpty) {
        throw GooglePhotosApiException(
          'Media creation failed: mediaItem.id is missing or empty in response.',
          statusCode: response.statusCode,
        );
      }

      return mediaItemId;
    } else if (response.statusCode == 401 || response.statusCode == 403) {
      throw GooglePhotosAuthException('Authentication expired ($response.statusCode).');
    } else if (response.statusCode == 429 || response.statusCode >= 500) {
      throw GooglePhotosApiException('Media creation transient error ($response.statusCode)', statusCode: response.statusCode, isRetryable: true);
    } else {
      throw GooglePhotosApiException('Media creation failed ($response.statusCode): $responseBody', statusCode: response.statusCode);
    }
  }

  static const String keyAlbumId = 'setting_google_photos_album_id';

  /// Gets or creates the 'SiteLens Evidence' album and returns its ID.
  Future<String?> getOrCreateAlbum(String albumTitle) async {
    if (_cachedAlbumId != null) return _cachedAlbumId;

    try {
      final prefs = await SharedPreferences.getInstance();
      final persistedId = prefs.getString(keyAlbumId);
      if (persistedId != null && persistedId.isNotEmpty) {
        _cachedAlbumId = persistedId;
        return persistedId;
      }

      final authHeaders = await _getAuthHeaders();
      final uri = Uri.parse('$baseUrl/albums');

      final request = await _httpClient.postUrl(uri);
      authHeaders.forEach((k, v) => request.headers.set(k, v));
      request.headers.set('Content-Type', 'application/json; charset=utf-8');

      final payload = {
        'album': {'title': albumTitle}
      };

      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close();
      final responseBody = await utf8.decodeStream(response);

      if (response.statusCode == 200) {
        final data = jsonDecode(responseBody) as Map<String, dynamic>;
        final id = data['id'] as String?;
        if (id != null && id.isNotEmpty) {
          _cachedAlbumId = id;
          await prefs.setString(keyAlbumId, id);
          return id;
        }
      }
    } catch (e) {
      debugPrint('Album creation warning (will fallback to general library): $e');
    }
    return null;
  }

  /// Invalidates cached album ID if Google Photos reports invalid/deleted album.
  Future<void> invalidateAlbumId() async {
    _cachedAlbumId = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(keyAlbumId);
    } catch (_) {}
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    try {
      return await _authService.getAuthHeaders();
    } catch (e) {
      throw GooglePhotosAuthException(e.toString());
    }
  }
}
