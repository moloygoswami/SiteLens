/// Pure, framework-independent mapping from authentication failures to
/// user-facing messages.
///
/// Normative basis:
/// - `01_PRD.MD` §9.1 — authentication error messages must be uniform between
///   "wrong password" and "no such account"; the system must never reveal
///   whether a given email address is registered.
/// - `04_SECURITY.MD` §2 — anti-enumeration: no client-visible error may allow
///   an attacker to determine whether an email address has a registered account.
/// - `05_ACCEPTANCE.MD` AC-AUTH-08 — the acceptance gate for the above.
/// - `06_TESTING.MD` TM-U-01 — the unit-level verification method.
///
/// This utility holds no state and performs no I/O, so it is directly
/// unit-testable and shared by every authentication surface (no duplicated
/// per-screen parsing).
library;

import 'package:firebase_auth/firebase_auth.dart';

/// The context an authentication failure surfaced in.
enum AuthErrorContext {
  /// Email/password or Google sign-in on the Login screen.
  signIn,

  /// Account creation on the Sign-up screen.
  signUp,
}

/// The single, uniform message returned for every credential-failure outcome.
///
/// Both "no such account" (`user-not-found`) and "wrong password"
/// (`wrong-password`) — and every equivalent consolidated code — MUST map to
/// this exact string, so that no client-visible difference can reveal whether
/// an email address is registered (AC-AUTH-08).
const String kUniformCredentialFailureMessage =
    'Invalid email or password. Please verify your credentials.';

/// Message for a transient connectivity failure during authentication.
const String kNetworkFailureMessage =
    'Network connection failed. Please check your internet connection.';

/// Message for a malformed email address supplied by the caller.
const String kInvalidEmailMessage = 'Please enter a valid work email address.';

/// Message for a pending (unverified) email account on sign-in.
const String kEmailNotVerifiedMessage =
    'Please verify your email address before signing in. Check your inbox for the verification link.';

/// Message for attempting sign-up with an already-registered email address.
///
/// Scoped to the sign-up context; see the anti-enumeration note on
/// [mapAuthErrorToMessage].
const String kEmailAlreadyInUseMessage =
    'An account already exists for this email address. Please sign in.';

/// Message for a password rejected by the provider's strength policy.
const String kWeakPasswordMessage =
    'Password is too weak. Please use at least 6 characters.';

/// Generic fallback for sign-in failures that carry no recognized code.
///
/// Deliberately does not echo the underlying error text: an echoed provider
/// message is an uncontrolled surface that could reveal whether an account
/// exists (AC-AUTH-08).
const String kGenericSignInFailureMessage =
    'Authentication failed. Please try again.';

/// Generic fallback for sign-up failures that carry no recognized code.
const String kGenericSignUpFailureMessage =
    'Sign up failed. Please try again.';

/// Firebase Authentication codes that indicate a credential failure and must
/// therefore collapse into [kUniformCredentialFailureMessage].
///
/// This set intentionally contains both the "account does not exist" and the
/// "password incorrect" families so that neither can ever be distinguished.
const Set<String> _credentialFailureCodes = {
  'user-not-found',
  'wrong-password',
  'invalid-credential',
  'invalid-login-credentials',
  'user-disabled',
};

/// A provider configuration/deployment notice (Email/Password provider not
/// enabled). Not a user credential failure and carries no account information.
const String _configurationNotice =
    'Firebase Authentication notice: The Email/Password sign-in provider is not yet enabled in the Firebase Console.\n\n'
    'To resolve:\n'
    '1. Open Firebase Console (project: sitelens-prod-80e7b)\n'
    '2. Navigate to Authentication > Sign-in method\n'
    '3. Enable "Email/Password" and save.';

/// Whether [error] carries [code], either as a structured
/// [FirebaseAuthException.code] or as the conventional
/// `[firebase_auth/<code>]` token embedded in its string form.
bool _hasCode(Object error, String code) {
  if (error is FirebaseAuthException && error.code == code) {
    return true;
  }
  return error.toString().contains(code);
}

/// Maps an authentication [error] to a user-facing message.
///
/// Anti-enumeration guarantee (AC-AUTH-08, security §2): in
/// [AuthErrorContext.signIn], every credential-failure code — including both
/// "no such account" and "wrong password" — resolves to the identical
/// [kUniformCredentialFailureMessage]. No other branch returns text that
/// depends on whether the supplied email address is registered.
///
/// Note: the sign-up context surfaces a distinct
/// [kEmailAlreadyInUseMessage]. `05_ACCEPTANCE.MD` AC-AUTH-08 scopes the
/// anti-enumeration requirement to *authentication* (sign-in) failures, so
/// sign-up behaviour is preserved as-is.
String mapAuthErrorToMessage(
  Object error, {
  AuthErrorContext context = AuthErrorContext.signIn,
}) {
  if (_hasCode(error, 'configuration-not-found') ||
      _hasCode(error, 'CONFIGURATION_NOT_FOUND')) {
    return _configurationNotice;
  }

  if (context == AuthErrorContext.signIn) {
    if (_hasCode(error, 'email-not-verified')) {
      return kEmailNotVerifiedMessage;
    }

    for (final code in _credentialFailureCodes) {
      if (_hasCode(error, code)) {
        return kUniformCredentialFailureMessage;
      }
    }

    if (_hasCode(error, 'invalid-email')) {
      return kInvalidEmailMessage;
    }
    if (_hasCode(error, 'network-request-failed')) {
      return kNetworkFailureMessage;
    }
    return kGenericSignInFailureMessage;
  }

  if (_hasCode(error, 'email-already-in-use')) {
    return kEmailAlreadyInUseMessage;
  }
  if (_hasCode(error, 'invalid-email')) {
    return kInvalidEmailMessage;
  }
  if (_hasCode(error, 'weak-password')) {
    return kWeakPasswordMessage;
  }
  if (_hasCode(error, 'network-request-failed')) {
    return kNetworkFailureMessage;
  }
  return kGenericSignUpFailureMessage;
}
