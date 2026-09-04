import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitelens/core/services/auth_service.dart';
import 'package:sitelens/features/support/models/enquiry_model.dart';
import 'package:sitelens/features/support/services/enquiry_service.dart';
import 'package:sitelens/features/support/widgets/user_enquiry_modal.dart';
import '../../integration_test/helpers/fake_auth_service.dart';

class MockEnquiryService implements IEnquiryService {
  EnquirySubmissionResult? responseToReturn;
  UserEnquiry? lastSubmittedEnquiry;
  int submitCount = 0;

  @override
  Future<EnquirySubmissionResult> submitEnquiry(UserEnquiry enquiry) async {
    submitCount++;
    lastSubmittedEnquiry = enquiry;
    return responseToReturn ??
        EnquirySubmissionResult.success(
          submissionId: enquiry.submissionId,
          message: 'Enquiry received successfully.',
        );
  }
}

void main() {
  late MockEnquiryService mockEnquiryService;
  late FakeAuthService fakeAuthService;

  setUp(() {
    mockEnquiryService = MockEnquiryService();
    fakeAuthService = FakeAuthService(
      const AuthUser(
        uid: 'inspector_007',
        email: 'inspector@sitelens.app',
        displayName: 'Chief Inspector',
      ),
    );
  });

  Widget createWidgetUnderTest() {
    return ProviderScope(
      overrides: [
        enquiryServiceProvider.overrideWithValue(mockEnquiryService),
        authServiceProvider.overrideWithValue(fakeAuthService),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: UserEnquiryModal(),
        ),
      ),
    );
  }

  group('UserEnquiryModal Widget Tests', () {
    testWidgets('Renders modal header, prefilled auth fields, and category chips',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('CONTACT SUPPORT'), findsOneWidget);
      expect(find.text('Chief Inspector'), findsOneWidget);
      expect(find.text('inspector@sitelens.app'), findsOneWidget);
      expect(find.text('General Enquiry'), findsOneWidget);
      expect(find.text('Bug Report'), findsOneWidget);
      expect(find.text('Feature Request'), findsOneWidget);
      expect(find.text('SUBMIT ENQUIRY'), findsOneWidget);
    });

    testWidgets('Validates form fields and blocks submission on empty message',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Tap submit without typing message
      await tester.tap(find.text('SUBMIT ENQUIRY'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your enquiry message'), findsOneWidget);
      expect(mockEnquiryService.submitCount, 0);
    });

    testWidgets('Submits valid enquiry and shows success confirmation view',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Select category
      await tester.tap(find.text('Bug Report'));
      await tester.pumpAndSettle();

      // Enter valid message
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Message / Description'),
        'The compass direction in HUD flipped 180 degrees after rotating the phone.',
      );
      await tester.pumpAndSettle();

      // Tap submit
      await tester.tap(find.text('SUBMIT ENQUIRY'));
      await tester.pumpAndSettle();

      expect(mockEnquiryService.submitCount, 1);
      expect(mockEnquiryService.lastSubmittedEnquiry?.category, EnquiryCategory.bugReport);
      expect(find.text('Enquiry Submitted'), findsOneWidget);
      expect(find.text('DONE'), findsOneWidget);
    });

    testWidgets('Shows error banner when service fails and allows retry',
        (tester) async {
      mockEnquiryService.responseToReturn = EnquirySubmissionResult.failure(
        submissionId: 'err-123',
        errorMessage: 'Network timeout. Please retry.',
      );

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Message / Description'),
        'Testing error handling on failure.',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SUBMIT ENQUIRY'));
      await tester.pumpAndSettle();

      expect(find.text('Network timeout. Please retry.'), findsOneWidget);
      expect(find.text('SUBMIT ENQUIRY'), findsOneWidget); // Still on form view
    });
  });
}
