import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../app/router.dart';
import '../../core/services/auth_service.dart';
import '../../shared/utils/responsive_layout.dart';
import '../../shared/widgets/app_drawer_icon.dart';
import '../../shared/widgets/primary_button.dart';
import '../settings/widgets/legal_doc_modal.dart';
import 'signup_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;
  bool _agreedToTerms = false;
  bool _isResendingVerification = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _parseAuthError(Object error) {
    if (error is EmailNotVerifiedException) {
      return error.message;
    }
    final str = error.toString();
    if (str.contains('email-not-verified')) {
      return 'Please verify your email address before signing in. Check your inbox for the verification link.';
    }
    if (str.contains('CONFIGURATION_NOT_FOUND') || str.contains('configuration-not-found')) {
      return 'Firebase Authentication notice: The Email/Password sign-in provider is not yet enabled in the Firebase Console.\n\n'
          'To resolve:\n'
          '1. Open Firebase Console (project: sitelens-prod-80e7b)\n'
          '2. Navigate to Authentication > Sign-in method\n'
          '3. Enable "Email/Password" and save.';
    }
    if (str.contains('user-not-found') ||
        str.contains('wrong-password') ||
        str.contains('invalid-credential') ||
        str.contains('user-disabled')) {
      return 'Invalid email or password. Please verify your credentials.';
    }
    if (str.contains('invalid-email')) {
      return 'Please enter a valid work email address.';
    }
    if (str.contains('network-request-failed')) {
      return 'Network connection failed. Please check your internet connection.';
    }
    return 'Authentication failed: ${str.replaceAll(RegExp(r'\[.*?\]'), '').trim()}';
  }

  Future<void> _handleResendVerification() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email and password to resend verification.')),
      );
      return;
    }

    setState(() => _isResendingVerification = true);
    try {
      await ref.read(authServiceProvider).sendEmailVerificationForUser(email, password);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.statusGreen,
            content: Text('Verification email resent to $email. Please check your inbox.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not resend email: ${_parseAuthError(e)}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isResendingVerification = false);
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    if (!_agreedToTerms) {
      setState(() {
        _errorMessage = 'Please agree to the Terms of Service and Privacy Policy before proceeding.';
      });
      return;
    }

    setState(() {
      _isGoogleLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      final user = await authService.signInWithGoogle();

      if (user != null && mounted) {
        // Reset to root so SessionRouter evaluates and renders the authenticated site setup screen
        Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.root, (route) => false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = _parseAuthError(e);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleLoading = false;
        });
      }
    }
  }

  Future<void> _handleEmailSignIn() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_agreedToTerms) {
      setState(() {
        _errorMessage = 'Please agree to the Terms of Service and Privacy Policy to proceed.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      await authService.signInWithEmailPassword(
        _emailController.text,
        _passwordController.text,
      );

      if (mounted) {
        // Reset to root so SessionRouter evaluates and renders the authenticated site setup screen
        Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.root, (route) => false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = _parseAuthError(e);
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final resetEmailController = TextEditingController(text: _emailController.text.trim());
    final dialogFormKey = GlobalKey<FormState>();
    bool isSending = false;
    String? dialogError;

    await showDialog<void>(
      context: context,
      barrierColor: const Color.fromRGBO(0, 0, 0, 0.6),
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
          backgroundColor: AppColors.surface,
          title: const Row(
            children: [
              Icon(Icons.lock_reset_rounded, color: AppColors.primary, size: 22),
              SizedBox(width: 10),
              Text(
                'Reset Password',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: dialogFormKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter your registered work email address. We will send you a secure link to create a new password.',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.statusRedLight,
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                        border: Border.all(color: AppColors.statusRed.withAlpha(80)),
                      ),
                      child: Text(
                        dialogError!,
                        style: const TextStyle(fontSize: 12, color: AppColors.statusRed, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'WORK EMAIL',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: resetEmailController,
                    keyboardType: TextInputType.emailAddress,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'name@company.com',
                      prefixIcon: const Icon(Icons.email_outlined, color: AppColors.textSecondary, size: 18),
                      filled: true,
                      fillColor: AppColors.surfaceContainer,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Please enter your work email';
                      }
                      if (!val.contains('@') || !val.contains('.')) {
                        return 'Please enter a valid email address';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isSending ? null : () => Navigator.of(dialogCtx).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                      ),
                      side: const BorderSide(color: AppColors.border, width: 1.0),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: isSending
                        ? null
                        : () async {
                            if (!dialogFormKey.currentState!.validate()) return;
                            final targetEmail = resetEmailController.text.trim();
                            setDialogState(() {
                              isSending = true;
                              dialogError = null;
                            });

                            try {
                              await ref.read(authServiceProvider).sendPasswordResetEmail(targetEmail);
                              if (dialogCtx.mounted) {
                                Navigator.of(dialogCtx).pop();
                              }
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: AppColors.statusGreen,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
                                    content: Text(
                                      'Password reset link sent to $targetEmail. Please check your inbox.',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                );
                              }
                            } catch (e) {
                              setDialogState(() {
                                isSending = false;
                                dialogError = _parseAuthError(e);
                              });
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                      ),
                    ),
                    child: isSending
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Send Reset Link',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= ResponsiveBreakpoints.expandedMin;

            if (isWide) {
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Left Pane: Enterprise Brand & Security Summary
                        Expanded(
                          flex: 5,
                          child: Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(AppRadii.card),
                              border: Border.all(color: AppColors.border, width: 1),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const AppDrawerIcon(
                                  size: 72,
                                  tooltip: 'SiteLens Evidence Camera',
                                ),
                                const SizedBox(height: 20),
                                const Text(
                                  'Enterprise Field Evidence',
                                  style: AppTypography.headlineMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Legally admissible, GPS-stamped photo and video inspection management for field engineers.',
                                  style: AppTypography.bodyMedium,
                                ),
                                const SizedBox(height: 24),
                                _buildSecurityHighlight(
                                  icon: Icons.fingerprint_rounded,
                                  title: 'SHA-256 Cryptographic Chain',
                                  subtitle: 'Direct hardware-level provenance hash stored on local SQLite & Cloud Firestore.',
                                ),
                                const SizedBox(height: 12),
                                _buildSecurityHighlight(
                                  icon: Icons.offline_pin_rounded,
                                  title: 'Full Offline Resilience',
                                  subtitle: 'Capture evidence in zero-connectivity environments with automatic background sync.',
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(width: 36),

                        // Right Pane: Form Controls
                        Expanded(
                          flex: 6,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: Form(
                              key: _formKey,
                              child: _buildFormContent(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            // Compact Mobile Form
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                  child: Form(
                    key: _formKey,
                    child: _buildFormContent(),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSecurityHighlight({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primaryContainer.withAlpha(100),
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          child: Icon(icon, size: 20, color: AppColors.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppTypography.bodyMedium.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFormContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Compact Screen Header
        const Text(
          'Sign In',
          style: AppTypography.headlineMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'Enter your credentials to access site evidence records.',
          style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),

        // Error message banner
        if (_errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.statusRedLight,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(color: AppColors.statusRed.withAlpha(70)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.statusRed, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(fontSize: 13, color: AppColors.statusRed, fontWeight: FontWeight.w500, height: 1.4),
                      ),
                    ),
                  ],
                ),
                if (_errorMessage!.contains('not been verified') || _errorMessage!.contains('verify your email')) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isResendingVerification ? null : _handleResendVerification,
                      icon: _isResendingVerification
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_rounded, size: 14),
                      label: const Text(
                        'Resend Verification Email',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.statusRed,
                        side: const BorderSide(color: AppColors.statusRed),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Email Field
        Text(
          'WORK EMAIL',
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: 'name@company.com',
            prefixIcon: const Icon(Icons.email_outlined, color: AppColors.textSecondary, size: 20),
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
          validator: (val) {
            if (val == null || val.trim().isEmpty) {
              return 'Please enter your work email';
            }
            return null;
          },
        ),
        const SizedBox(height: 20),

        // Password Field Header with Forgot Password action
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'PASSWORD',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            GestureDetector(
              onTap: _showForgotPasswordDialog,
              child: const Text(
                'Forgot Password?',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            hintText: 'Enter password',
            prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.textSecondary, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: AppColors.textSecondary,
                size: 20,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
          validator: (val) {
            if (val == null || val.isEmpty) {
              return 'Please enter your password';
            }
            return null;
          },
        ),
        const SizedBox(height: 18),

        // Terms & Privacy Policy Checkbox
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: _agreedToTerms,
                activeColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                onChanged: (val) {
                  setState(() {
                    _agreedToTerms = val ?? false;
                    if (_agreedToTerms) _errorMessage = null;
                  });
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: AppTypography.bodyMedium.copyWith(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                  children: [
                    const TextSpan(text: 'I agree to the '),
                    TextSpan(
                      text: 'Terms of Service',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => LegalDocModal.show(context, LegalDocType.termsOfService),
                    ),
                    const TextSpan(text: ' and '),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => LegalDocModal.show(context, LegalDocType.privacyPolicy),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),

        // Sign In Action
        PrimaryButton(
          label: 'Sign In',
          isLoading: _isLoading,
          onPressed: _isGoogleLoading ? null : _handleEmailSignIn,
        ),
        const SizedBox(height: 18),

        // Sign Up Link
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'New to SiteLens? ',
                style: AppTypography.bodyMedium.copyWith(fontSize: 13, color: AppColors.textSecondary),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SignupScreen()),
                  );
                },
                child: Text(
                  'Create an Account',
                  style: AppTypography.bodyMedium.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Divider: OR
        Row(
          children: [
            const Expanded(child: Divider(color: AppColors.border, thickness: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                'OR',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const Expanded(child: Divider(color: AppColors.border, thickness: 1)),
          ],
        ),
        const SizedBox(height: 20),

        // Google Sign In Action (OAuth / Workspace)
        OutlinedButton(
          onPressed: (_isLoading || _isGoogleLoading) ? null : _handleGoogleSignIn,
          style: OutlinedButton.styleFrom(
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.textPrimary,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            side: const BorderSide(color: AppColors.border, width: 1.5),
            elevation: 0,
          ),
          child: _isGoogleLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const _GoogleLogo(),
                    const SizedBox(width: 12),
                    Text(
                      'Continue with Google',
                      style: AppTypography.titleMedium.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 28),

        // Security footer note
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.security_rounded, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Protected by Firebase Authentication & SHA-256 evidence chain',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(18, 18),
      painter: _GoogleLogoPainter(),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final center = Offset(w / 2, h / 2);
    final radius = w / 2;

    final paintBlue = Paint()..color = const Color(0xFF4285F4)..style = PaintingStyle.fill;
    final paintRed = Paint()..color = const Color(0xFFEA4335)..style = PaintingStyle.fill;
    final paintYellow = Paint()..color = const Color(0xFFFBBC05)..style = PaintingStyle.fill;
    final paintGreen = Paint()..color = const Color(0xFF34A853)..style = PaintingStyle.fill;

    final rect = Rect.fromCircle(center: center, radius: radius);
    final innerRect = Rect.fromCircle(center: center, radius: radius * 0.55);

    // Blue Bar (Right)
    final bluePath = Path()
      ..moveTo(center.dx, center.dy - radius * 0.22)
      ..lineTo(center.dx + radius, center.dy - radius * 0.22)
      ..lineTo(center.dx + radius, center.dy + radius * 0.22)
      ..lineTo(center.dx, center.dy + radius * 0.22)
      ..close();
    canvas.drawPath(bluePath, paintBlue);

    // Red Arc (Top)
    final redPath = Path()
      ..arcTo(rect, -0.75, -1.8, false)
      ..arcTo(innerRect, -2.55, 1.8, false)
      ..close();
    canvas.drawPath(redPath, paintRed);

    // Yellow Arc (Left)
    final yellowPath = Path()
      ..arcTo(rect, -2.55, -1.6, false)
      ..arcTo(innerRect, -4.15, 1.6, false)
      ..close();
    canvas.drawPath(yellowPath, paintYellow);

    // Green Arc (Bottom)
    final greenPath = Path()
      ..arcTo(rect, -4.15, -1.8, false)
      ..arcTo(innerRect, -5.95, 1.8, false)
      ..close();
    canvas.drawPath(greenPath, paintGreen);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
