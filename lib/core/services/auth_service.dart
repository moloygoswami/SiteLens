import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthUser {
  final String uid;
  final String? email;
  final String displayName;
  final bool isEmailVerified;

  const AuthUser({
    required this.uid,
    this.email,
    this.displayName = 'Site Engineer',
    this.isEmailVerified = false,
  });
}

class EmailNotVerifiedException implements Exception {
  final String message;
  final String email;
  const EmailNotVerifiedException({
    required this.message,
    required this.email,
  });

  @override
  String toString() => message;
}

class AuthService {
  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;

  AuthService({
    FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn();

  Stream<AuthUser?> get authStateChanges {
    return _firebaseAuth.authStateChanges().map((user) {
      if (user == null) return null;
      return AuthUser(
        uid: user.uid,
        email: user.email,
        displayName: user.displayName ?? (user.email?.split('@').first ?? 'Site Inspector'),
        isEmailVerified: user.emailVerified,
      );
    });
  }

  AuthUser? get currentUser {
    final user = _firebaseAuth.currentUser;
    if (user == null) return null;
    return AuthUser(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName ?? (user.email?.split('@').first ?? 'Site Inspector'),
      isEmailVerified: user.emailVerified,
    );
  }

  /// Sign up with work email and password.
  /// Automatically dispatches an email verification link to [email].
  Future<AuthUser> signUpWithEmailPassword(
    String email,
    String password, {
    String? displayName,
  }) async {
    try {
      final credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user!;

      if (displayName != null && displayName.trim().isNotEmpty) {
        await user.updateDisplayName(displayName.trim());
      }

      // Send email verification link
      await user.sendEmailVerification();

      return AuthUser(
        uid: user.uid,
        email: user.email,
        displayName: displayName ?? user.displayName ?? (user.email?.split('@').first ?? 'Site Inspector'),
        isEmailVerified: user.emailVerified,
      );
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Sign-Up Error: ${e.code} - ${e.message}');
      rethrow;
    }
  }

  /// Sign in with email and password.
  /// Enforces that the user has verified their email address before access is granted.
  Future<AuthUser> signInWithEmailPassword(String email, String password) async {
    try {
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user!;

      // Reload user to ensure latest verification status is retrieved from Firebase
      await user.reload();
      final freshUser = _firebaseAuth.currentUser ?? user;

      if (!freshUser.emailVerified) {
        // Sign out unverified session
        await _firebaseAuth.signOut();
        throw EmailNotVerifiedException(
          email: email.trim(),
          message: 'Your email address has not been verified yet. Please check your inbox for the verification link.',
        );
      }

      return AuthUser(
        uid: freshUser.uid,
        email: freshUser.email,
        displayName: freshUser.displayName ?? (freshUser.email?.split('@').first ?? 'Site Inspector'),
        isEmailVerified: freshUser.emailVerified,
      );
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth Error: ${e.code} - ${e.message}');
      rethrow;
    }
  }

  /// Resends an email verification link to the currently signed in or provided user.
  Future<void> sendEmailVerificationForUser(String email, String password) async {
    try {
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
      }
      await _firebaseAuth.signOut();
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Resend Verification Error: ${e.code} - ${e.message}');
      rethrow;
    }
  }

  /// Sends a password reset email.
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Password Reset Error: ${e.code} - ${e.message}');
      rethrow;
    }
  }

  Future<AuthUser?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // User aborted the sign-in flow
        return null;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _firebaseAuth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) return null;

      return AuthUser(
        uid: user.uid,
        email: user.email,
        displayName: user.displayName ?? (user.email?.split('@').first ?? 'Site Inspector'),
        isEmailVerified: user.emailVerified,
      );
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Google Auth Error: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    await _firebaseAuth.signOut();
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

final authStateProvider = StreamProvider<AuthUser?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.authStateChanges;
});

/// Extension on AuthService providing secure account-deletion operations
/// without mutating the frozen AuthService class interface.
extension AccountDeletionAuthService on AuthService {
  /// Whether the currently signed-in user authenticated with email/password.
  bool get isPasswordProvider {
    try {
      final user = _firebaseAuth.currentUser;
      if (user == null) return false;
      return user.providerData.any((p) => p.providerId == 'password');
    } catch (_) {
      return true;
    }
  }

  /// Re-authenticates the current user using their password.
  Future<void> reauthenticateWithPassword(String password) async {
    final user = _firebaseAuth.currentUser;
    if (user == null || user.email == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No active authenticated user session found.',
      );
    }
    final credential = EmailAuthProvider.credential(
      email: user.email!,
      password: password,
    );
    await user.reauthenticateWithCredential(credential);
  }

  /// Re-authenticates the current user using Google Sign-In.
  Future<void> reauthenticateWithGoogle() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No active authenticated user session found.',
      );
    }
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      throw FirebaseAuthException(
        code: 'cancelled',
        message: 'Google re-authentication was cancelled by the user.',
      );
    }
    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    final OAuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    await user.reauthenticateWithCredential(credential);
  }

  /// Authoritatively invokes the 2nd-gen Cloud Function to delete the user account.
  /// Server-side validation inspects all site memberships and cascades data deletion.
  Future<Map<String, dynamic>> deleteAccount({
    Map<String, String>? successorAdmins,
    FirebaseFunctions? functions,
  }) async {
    final fn = functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');
    final callable = fn.httpsCallable('deleteUserAccount');
    final response = await callable.call({
      if (successorAdmins != null) 'successorAdmins': successorAdmins,
    });
    if (response.data is Map) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    return {'success': true};
  }
}

/// Represents a shared site requiring an explicit successor admin assignment.
class SuccessorSiteRequirement {
  final String siteId;
  final String siteName;
  final List<EligibleMember> eligibleMembers;

  const SuccessorSiteRequirement({
    required this.siteId,
    required this.siteName,
    required this.eligibleMembers,
  });

  factory SuccessorSiteRequirement.fromMap(Map<dynamic, dynamic> map) {
    final rawMembers = map['eligibleMembers'];
    final membersList = rawMembers is List ? rawMembers : [];
    return SuccessorSiteRequirement(
      siteId: map['siteId']?.toString() ?? '',
      siteName: map['siteName']?.toString() ?? '',
      eligibleMembers: membersList
          .map((m) => EligibleMember.fromMap(Map<dynamic, dynamic>.from(m as Map)))
          .toList(),
    );
  }
}

/// Represents an active member eligible for admin succession on a shared site.
class EligibleMember {
  final String userId;
  final String role;
  final String status;

  const EligibleMember({
    required this.userId,
    required this.role,
    required this.status,
  });

  factory EligibleMember.fromMap(Map<dynamic, dynamic> map) {
    return EligibleMember(
      userId: map['userId']?.toString() ?? '',
      role: map['role']?.toString() ?? 'member',
      status: map['status']?.toString() ?? 'active',
    );
  }
}

