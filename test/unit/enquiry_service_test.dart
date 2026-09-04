import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sitelens/features/support/controllers/enquiry_controller.dart';
import 'package:sitelens/features/support/models/enquiry_model.dart';
import 'package:sitelens/features/support/services/enquiry_service.dart';

void main() {
  group('UserEnquiry Model & Validation Tests', () {
    test('Validates name constraints', () {
      expect(UserEnquiry.validateName(null), isNotNull);
      expect(UserEnquiry.validateName(''), isNotNull);
      expect(UserEnquiry.validateName('   '), isNotNull);
      expect(UserEnquiry.validateName('A' * 101), isNotNull);
      expect(UserEnquiry.validateName('John Doe'), isNull);
    });

    test('Validates email format constraints', () {
      expect(UserEnquiry.validateEmail(null), isNotNull);
      expect(UserEnquiry.validateEmail(''), isNotNull);
      expect(UserEnquiry.validateEmail('invalid-email'), isNotNull);
      expect(UserEnquiry.validateEmail('user@'), isNotNull);
      expect(UserEnquiry.validateEmail('@domain.com'), isNotNull);
      expect(UserEnquiry.validateEmail('engineer@sitelens.app'), isNull);
      expect(UserEnquiry.validateEmail('john.doe+audit@construction.co.uk'), isNull);
    });

    test('Validates message length constraints', () {
      expect(UserEnquiry.validateMessage(null), isNotNull);
      expect(UserEnquiry.validateMessage(''), isNotNull);
      expect(UserEnquiry.validateMessage('Short'), isNotNull); // < 10 chars
      expect(UserEnquiry.validateMessage('This is a valid enquiry message over 10 chars.'), isNull);
    });

    test('Serializes to JSON with lowercase email and trimmed fields', () {
      final enquiry = UserEnquiry(
        submissionId: 'test-id-123',
        name: '  Alice Smith  ',
        email: '  ALICE@EXAMPLE.COM  ',
        category: EnquiryCategory.bugReport,
        message: '  Found a bug in camera preview.  ',
      );

      final json = enquiry.toJson();
      expect(json['submissionId'], 'test-id-123');
      expect(json['name'], 'Alice Smith');
      expect(json['email'], 'alice@example.com');
      expect(json['category'], 'bug_report');
      expect(json['message'], 'Found a bug in camera preview.');
    });

    test('Resolves EnquiryCategory from key correctly', () {
      expect(EnquiryCategory.fromKey('bug_report'), EnquiryCategory.bugReport);
      expect(EnquiryCategory.fromKey('feature_request'), EnquiryCategory.featureRequest);
      expect(EnquiryCategory.fromKey('enterprise_sales'), EnquiryCategory.enterpriseSales);
      expect(EnquiryCategory.fromKey('compliance_enquiry'), EnquiryCategory.complianceEnquiry);
      expect(EnquiryCategory.fromKey('unknown_key'), EnquiryCategory.general);
    });
  });

  group('FirebaseEnquiryService HTTP Handling Tests', () {
    test('Returns success result on HTTP 200', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.toString(), contains('submitUserEnquiry'));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['data']['email'], 'test@sitelens.app');

        return http.Response(
          jsonEncode({
            'result': {
              'success': true,
              'submissionId': 'sub-999',
              'message': 'Enquiry received successfully.',
              'idempotencyDuplicate': false,
            }
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = FirebaseEnquiryService(httpClient: mockClient);
      final enquiry = UserEnquiry(
        submissionId: 'sub-999',
        name: 'Bob',
        email: 'test@sitelens.app',
        category: EnquiryCategory.general,
        message: 'General enquiry text over 10 chars.',
      );

      final result = await service.submitEnquiry(enquiry);
      expect(result.isSuccess, isTrue);
      expect(result.submissionId, 'sub-999');
      expect(result.isDuplicate, isFalse);
    });

    test('Handles rate-limiting 429 response', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Rate limit exceeded', 429);
      });

      final service = FirebaseEnquiryService(httpClient: mockClient);
      final enquiry = UserEnquiry(
        submissionId: 'sub-rate-limit',
        name: 'Bob',
        email: 'test@sitelens.app',
        category: EnquiryCategory.general,
        message: 'General enquiry text over 10 chars.',
      );

      final result = await service.submitEnquiry(enquiry);
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('Rate limit exceeded'));
    });

    test('Handles network connection error gracefully', () async {
      final mockClient = MockClient((request) async {
        throw http.ClientException('Connection failed');
      });

      final service = FirebaseEnquiryService(httpClient: mockClient);
      final enquiry = UserEnquiry(
        submissionId: 'sub-net-err',
        name: 'Bob',
        email: 'test@sitelens.app',
        category: EnquiryCategory.general,
        message: 'General enquiry text over 10 chars.',
      );

      final result = await service.submitEnquiry(enquiry);
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('Network connection error'));
    });
  });

  group('EnquiryController State Tests', () {
    test('Coordinates state transitions through submission', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'result': {
              'success': true,
              'submissionId': 'sub-ctrl-test',
              'message': 'Received',
            }
          }),
          200,
        );
      });

      final service = FirebaseEnquiryService(httpClient: mockClient);
      final controller = EnquiryController(service);

      expect(controller.state.status, EnquiryStatus.initial);

      final future = controller.submitEnquiry(
        name: 'Charlie',
        email: 'charlie@test.com',
        category: EnquiryCategory.enterpriseSales,
        message: 'Enterprise inquiry for 100 inspectors.',
      );

      final success = await future;
      expect(success, isTrue);
      expect(controller.state.status, EnquiryStatus.success);
      expect(controller.state.result?.isSuccess, isTrue);

      controller.reset();
      expect(controller.state.status, EnquiryStatus.initial);
    });

    test('Blocks concurrent double submission', () async {
      int callCount = 0;
      final mockClient = MockClient((request) async {
        callCount++;
        await Future.delayed(const Duration(milliseconds: 50));
        return http.Response(
          jsonEncode({'result': {'success': true}}),
          200,
        );
      });

      final service = FirebaseEnquiryService(httpClient: mockClient);
      final controller = EnquiryController(service);

      final first = controller.submitEnquiry(
        name: 'A',
        email: 'a@a.com',
        category: EnquiryCategory.general,
        message: 'First attempt over ten chars.',
      );

      // Attempt second submission while first is in-flight
      final second = controller.submitEnquiry(
        name: 'B',
        email: 'b@b.com',
        category: EnquiryCategory.general,
        message: 'Second attempt over ten chars.',
      );

      final results = await Future.wait([first, second]);
      expect(results[0], isTrue);
      expect(results[1], isFalse); // Second submission was blocked
      expect(callCount, 1);
    });
  });
}
