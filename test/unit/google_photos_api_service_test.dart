import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitelens/features/google_photos/services/google_photos_api_service.dart';
import 'package:sitelens/features/google_photos/services/google_photos_auth_service.dart';

class FakeHttpHeaders extends Fake implements HttpHeaders {
  final Map<String, String> _headers = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _headers[name.toLowerCase()] = value.toString();
  }
}

class FakeHttpClientResponse extends Fake implements HttpClientResponse {
  @override
  final int statusCode;
  final String body;

  FakeHttpClientResponse(this.statusCode, this.body);

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream.value(utf8.encode(body)).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

class FakeHttpClientRequest extends Fake implements HttpClientRequest {
  final int statusCode;
  final String body;
  @override
  final HttpHeaders headers = FakeHttpHeaders();

  FakeHttpClientRequest(this.statusCode, this.body);

  @override
  void add(List<int> data) {}

  @override
  Future<HttpClientResponse> close() async {
    return FakeHttpClientResponse(statusCode, body);
  }
}

class FakeHttpClient extends Fake implements HttpClient {
  int responseStatusCode = 200;
  String responseBody = '{}';

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    return FakeHttpClientRequest(responseStatusCode, responseBody);
  }
}

class FakeGooglePhotosAuthService extends Fake implements GooglePhotosAuthService {
  @override
  Future<Map<String, String>> getAuthHeaders() async => {
        'Authorization': 'Bearer test_access_token',
      };
}

void main() {
  late FakeHttpClient fakeHttpClient;
  late FakeGooglePhotosAuthService fakeAuthService;
  late GooglePhotosApiService apiService;

  setUp(() {
    fakeHttpClient = FakeHttpClient();
    fakeAuthService = FakeGooglePhotosAuthService();
    apiService = GooglePhotosApiService(
      authService: fakeAuthService,
      httpClient: fakeHttpClient,
    );
  });

  group('GooglePhotosApiService.createMediaItem Unit Tests', () {
    test('Successful response with genuine mediaItem.id returns the ID', () async {
      fakeHttpClient.responseStatusCode = 200;
      fakeHttpClient.responseBody = jsonEncode({
        'newMediaItemResults': [
          {
            'uploadToken': 'token_123',
            'status': {'message': 'Success'},
            'mediaItem': {
              'id': 'genuine_google_photos_id_999',
              'productUrl': 'https://photos.google.com/lr/album/xxx/photo/yyy',
            }
          }
        ]
      });

      final result = await apiService.createMediaItem(
        uploadToken: 'token_123',
        fileName: 'evid_photo.jpg',
        description: 'Inspector note',
        albumId: 'album_123',
      );

      expect(result, equals('genuine_google_photos_id_999'));
    });

    test('Throws GooglePhotosApiException when newMediaItemResults is empty', () async {
      fakeHttpClient.responseStatusCode = 200;
      fakeHttpClient.responseBody = jsonEncode({
        'newMediaItemResults': []
      });

      expect(
        () => apiService.createMediaItem(
          uploadToken: 'token_123',
          fileName: 'evid_photo.jpg',
          description: '',
        ),
        throwsA(isA<GooglePhotosApiException>().having(
          (e) => e.message,
          'message',
          contains('empty or missing newMediaItemResults'),
        )),
      );
    });

    test('Throws GooglePhotosApiException when newMediaItemResults is null', () async {
      fakeHttpClient.responseStatusCode = 200;
      fakeHttpClient.responseBody = jsonEncode({});

      expect(
        () => apiService.createMediaItem(
          uploadToken: 'token_123',
          fileName: 'evid_photo.jpg',
          description: '',
        ),
        throwsA(isA<GooglePhotosApiException>().having(
          (e) => e.message,
          'message',
          contains('empty or missing newMediaItemResults'),
        )),
      );
    });

    test('Throws GooglePhotosApiException when status.code is non-zero (creation failure)', () async {
      fakeHttpClient.responseStatusCode = 200;
      fakeHttpClient.responseBody = jsonEncode({
        'newMediaItemResults': [
          {
            'uploadToken': 'token_123',
            'status': {
              'code': 3,
              'message': 'INVALID_ARGUMENT: Bad image payload',
            },
          }
        ]
      });

      expect(
        () => apiService.createMediaItem(
          uploadToken: 'token_123',
          fileName: 'evid_photo.jpg',
          description: '',
        ),
        throwsA(isA<GooglePhotosApiException>().having(
          (e) => e.message,
          'message',
          contains('code: 3'),
        )),
      );
    });

    test('Throws GooglePhotosApiException when mediaItem object is missing', () async {
      fakeHttpClient.responseStatusCode = 200;
      fakeHttpClient.responseBody = jsonEncode({
        'newMediaItemResults': [
          {
            'uploadToken': 'token_123',
            'status': {'code': 0, 'message': 'OK'},
          }
        ]
      });

      expect(
        () => apiService.createMediaItem(
          uploadToken: 'token_123',
          fileName: 'evid_photo.jpg',
          description: '',
        ),
        throwsA(isA<GooglePhotosApiException>().having(
          (e) => e.message,
          'message',
          contains('mediaItem object is missing'),
        )),
      );
    });

    test('Throws GooglePhotosApiException when mediaItem.id is missing', () async {
      fakeHttpClient.responseStatusCode = 200;
      fakeHttpClient.responseBody = jsonEncode({
        'newMediaItemResults': [
          {
            'uploadToken': 'token_123',
            'status': {'message': 'OK'},
            'mediaItem': {
              'productUrl': 'https://photos.google.com/...',
            }
          }
        ]
      });

      expect(
        () => apiService.createMediaItem(
          uploadToken: 'token_123',
          fileName: 'evid_photo.jpg',
          description: '',
        ),
        throwsA(isA<GooglePhotosApiException>().having(
          (e) => e.message,
          'message',
          contains('mediaItem.id is missing or empty'),
        )),
      );
    });

    test('Throws GooglePhotosApiException when mediaItem.id is empty whitespace', () async {
      fakeHttpClient.responseStatusCode = 200;
      fakeHttpClient.responseBody = jsonEncode({
        'newMediaItemResults': [
          {
            'uploadToken': 'token_123',
            'status': {'message': 'OK'},
            'mediaItem': {
              'id': '   ',
            }
          }
        ]
      });

      expect(
        () => apiService.createMediaItem(
          uploadToken: 'token_123',
          fileName: 'evid_photo.jpg',
          description: '',
        ),
        throwsA(isA<GooglePhotosApiException>().having(
          (e) => e.message,
          'message',
          contains('mediaItem.id is missing or empty'),
        )),
      );
    });

    test('Throws GooglePhotosAuthException on 401 Unauthorized', () async {
      fakeHttpClient.responseStatusCode = 401;
      fakeHttpClient.responseBody = 'Unauthorized';

      expect(
        () => apiService.createMediaItem(
          uploadToken: 'token_123',
          fileName: 'evid_photo.jpg',
          description: '',
        ),
        throwsA(isA<GooglePhotosAuthException>()),
      );
    });

    test('Throws GooglePhotosApiException with isRetryable=true on 429 / 503', () async {
      fakeHttpClient.responseStatusCode = 503;
      fakeHttpClient.responseBody = 'Service Unavailable';

      expect(
        () => apiService.createMediaItem(
          uploadToken: 'token_123',
          fileName: 'evid_photo.jpg',
          description: '',
        ),
        throwsA(isA<GooglePhotosApiException>().having(
          (e) => e.isRetryable,
          'isRetryable',
          isTrue,
        )),
      );
    });
  });
}
