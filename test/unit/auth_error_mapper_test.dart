import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitelens/core/utils/auth_error_mapper.dart';

/// Slice 1A — anti-enumeration authentication error mapping.
///
/// Verifies `06_TESTING.MD` TM-U-01 ("Test the authentication-error-message
/// construction path with both a 'wrong password' and a 'no such account'
/// input, asserting identical output") against `05_ACCEPTANCE.MD` AC-AUTH-08.
void main() {
  group('TM-U-01 auth error mapping — anti-enumeration (AC-AUTH-08)', () {
    test('sign-in maps "no such account" and "wrong password" to identical output', () {
      final noSuchAccount = mapAuthErrorToMessage(
        Exception('[firebase_auth/user-not-found] There is no user record corresponding to this identifier.'),
      );
      final wrongPassword = mapAuthErrorToMessage(
        Exception('[firebase_auth/wrong-password] The password is invalid.'),
      );

      expect(noSuchAccount, equals(wrongPassword));
      expect(noSuchAccount, equals(kUniformCredentialFailureMessage));
    });

    test('every credential-failure code collapses into the single uniform message', () {
      const credentialCodes = [
        'user-not-found',
        'wrong-password',
        'invalid-credential',
        'invalid-login-credentials',
        'user-disabled',
      ];

      for (final code in credentialCodes) {
        expect(
          mapAuthErrorToMessage(FirebaseAuthException(code: code, message: 'provider detail')),
          equals(kUniformCredentialFailureMessage),
          reason: 'code "$code" must not be distinguishable from any other credential failure',
        );
      }
    });

    test('the uniform message reveals nothing about account existence', () {
      final lower = kUniformCredentialFailureMessage.toLowerCase();
      expect(lower.contains('not found'), isFalse);
      expect(lower.contains('no account'), isFalse);
      expect(lower.contains('exist'), isFalse);
      expect(lower.contains('disabled'), isFalse);
      expect(lower.contains('registered'), isFalse);
      expect(kUniformCredentialFailureMessage.contains('user-not-found'), isFalse);
      expect(kUniformCredentialFailureMessage.contains('wrong-password'), isFalse);
    });

    test('an unrecognized sign-in failure returns a generic message without echoing the raw error', () {
      final message = mapAuthErrorToMessage(
        Exception('[firebase_auth/unmapped-provider-code] secret-provider-detail'),
      );

      expect(message, equals(kGenericSignInFailureMessage));
      expect(message.contains('unmapped-provider-code'), isFalse);
      expect(message.contains('secret-provider-detail'), isFalse);
    });

    test('network and malformed-email failures map to their distinct non-enumerating messages', () {
      expect(
        mapAuthErrorToMessage(Exception('[firebase_auth/network-request-failed] Network error.')),
        equals(kNetworkFailureMessage),
      );
      expect(
        mapAuthErrorToMessage(Exception('[firebase_auth/invalid-email] Malformed address.')),
        equals(kInvalidEmailMessage),
      );
    });

    test('a pending verification account maps to the verification message', () {
      expect(
        mapAuthErrorToMessage(Exception('[firebase_auth/email-not-verified] Not verified.')),
        equals(kEmailNotVerifiedMessage),
      );
    });

    test('the provider configuration notice is preserved verbatim', () {
      final message = mapAuthErrorToMessage(
        Exception('[firebase_auth/configuration-not-found] Provider disabled.'),
      );
      expect(message, contains('Email/Password sign-in provider is not yet enabled'));
    });

    test('sign-up context maps its own validation failures', () {
      expect(
        mapAuthErrorToMessage(
          Exception('[firebase_auth/email-already-in-use] In use.'),
          context: AuthErrorContext.signUp,
        ),
        equals(kEmailAlreadyInUseMessage),
      );
      expect(
        mapAuthErrorToMessage(
          Exception('[firebase_auth/weak-password] Too weak.'),
          context: AuthErrorContext.signUp,
        ),
        equals(kWeakPasswordMessage),
      );
      expect(
        mapAuthErrorToMessage(
          Exception('[firebase_auth/invalid-email] Malformed.'),
          context: AuthErrorContext.signUp,
        ),
        equals(kInvalidEmailMessage),
      );
      expect(
        mapAuthErrorToMessage(
          Exception('[firebase_auth/network-request-failed] Offline.'),
          context: AuthErrorContext.signUp,
        ),
        equals(kNetworkFailureMessage),
      );
      expect(
        mapAuthErrorToMessage(Exception('unexpected failure'), context: AuthErrorContext.signUp),
        equals(kGenericSignUpFailureMessage),
      );
    });
  });
}
