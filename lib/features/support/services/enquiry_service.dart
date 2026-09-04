import 'dart:convert';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../models/enquiry_model.dart';

/// Result returned from an enquiry submission.
class EnquirySubmissionResult {
  final bool isSuccess;
  final String submissionId;
  final String message;
  final bool isDuplicate;
  final String? errorMessage;

  const EnquirySubmissionResult({
    required this.isSuccess,
    required this.submissionId,
    required this.message,
    this.isDuplicate = false,
    this.errorMessage,
  });

  factory EnquirySubmissionResult.success({
    required String submissionId,
    String? message,
    bool isDuplicate = false,
  }) {
    return EnquirySubmissionResult(
      isSuccess: true,
      submissionId: submissionId,
      message: message ?? 'Your enquiry has been successfully received.',
      isDuplicate: isDuplicate,
    );
  }

  factory EnquirySubmissionResult.failure({
    required String submissionId,
    required String errorMessage,
  }) {
    return EnquirySubmissionResult(
      isSuccess: false,
      submissionId: submissionId,
      message: errorMessage,
      errorMessage: errorMessage,
    );
  }
}

/// Service interface for dispatching user enquiries to the backend.
abstract class IEnquiryService {
  Future<EnquirySubmissionResult> submitEnquiry(UserEnquiry enquiry);
}

/// Production implementation calling Firebase 2nd-gen callable function.
class FirebaseEnquiryService implements IEnquiryService {
  final http.Client _httpClient;
  final FirebaseAuth? _firebaseAuth;
  final String _projectId;
  final String _region;

  FirebaseEnquiryService({
    http.Client? httpClient,
    FirebaseAuth? firebaseAuth,
    String projectId = 'sitelens-prod-80e7b',
    String region = 'us-central1',
  })  : _httpClient = httpClient ?? http.Client(),
        _firebaseAuth = firebaseAuth,
        _projectId = projectId,
        _region = region;

  Uri get _callableUri => Uri.parse(
        'https://$_region-$_projectId.cloudfunctions.net/submitUserEnquiry',
      );

  @override
  Future<EnquirySubmissionResult> submitEnquiry(UserEnquiry enquiry) async {
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };

      // Attach Firebase App Check token (submitUserEnquiry enforces App Check server-side)
      try {
        final appCheckToken = await FirebaseAppCheck.instance.getToken();
        if (appCheckToken != null && appCheckToken.isNotEmpty) {
          headers['X-Firebase-AppCheck'] = appCheckToken;
        }
      } catch (_) {
        // Continue; in testing/unsupported environments, callable may reject if enforceAppCheck is active
      }

      // Attach Firebase Auth ID token if user is signed in
      if (_firebaseAuth != null) {
        final currentUser = _firebaseAuth.currentUser;
        if (currentUser != null) {
          try {
            final idToken = await currentUser.getIdToken();
            if (idToken != null) {
              headers['Authorization'] = 'Bearer $idToken';
            }
          } catch (_) {
            // Continue if token refresh fails
          }
        }
      }

      final body = jsonEncode({
        'data': enquiry.toJson(),
      });

      final response = await _httpClient
          .post(
            _callableUri,
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final resultData = decoded['result'] as Map<String, dynamic>? ?? {};

        return EnquirySubmissionResult.success(
          submissionId: enquiry.submissionId,
          message: resultData['message'] as String? ??
              'Your enquiry has been received by SiteLens support.',
          isDuplicate: resultData['idempotencyDuplicate'] == true,
        );
      }

      // Handle non-200 responses
      if (response.statusCode == 429) {
        return EnquirySubmissionResult.failure(
          submissionId: enquiry.submissionId,
          errorMessage:
              'Rate limit exceeded. Please wait a few moments before sending another enquiry.',
        );
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        return EnquirySubmissionResult.failure(
          submissionId: enquiry.submissionId,
          errorMessage:
              'Security verification failed. Please check your connection and try again.',
        );
      }

      if (response.statusCode >= 400 && response.statusCode < 500) {
        return EnquirySubmissionResult.failure(
          submissionId: enquiry.submissionId,
          errorMessage:
              'Invalid enquiry submission. Please verify your form details.',
        );
      }

      return EnquirySubmissionResult.failure(
        submissionId: enquiry.submissionId,
        errorMessage:
            'Unable to submit enquiry at this time. Please try again later.',
      );
    } catch (e) {
      return EnquirySubmissionResult.failure(
        submissionId: enquiry.submissionId,
        errorMessage:
            'Network connection error. Please check your internet and retry.',
      );
    }
  }
}

/// Global Riverpod Provider for EnquiryService
final enquiryServiceProvider = Provider<IEnquiryService>((ref) {
  return FirebaseEnquiryService();
});
