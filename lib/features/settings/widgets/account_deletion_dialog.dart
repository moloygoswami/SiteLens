import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/services/auth_service.dart';
import '../../../data/local/database/app_database.dart';

/// Interactive modal dialog guiding the user through the account deletion workflow.
///
/// Flow:
/// 1. Destructive Warning & Identity Re-authentication
/// 2. Authoritative Server-Side Deletion via 2nd-gen Cloud Function
/// 3. Successor Selection (if backend returns failed-precondition with requiresSuccessor)
/// 4. Local SQLite & Media Purge on Server Success
/// 5. Sign-out and Route Navigation to login
class AccountDeletionDialog extends StatefulWidget {
  final AuthService authService;
  final AppDatabase appDatabase;
  final FirebaseFunctions? functions;
  final VoidCallback? onDeleted;
  final bool? isPasswordProvider;
  final Future<void> Function(String password)? onReauthenticateWithPassword;
  final Future<void> Function()? onReauthenticateWithGoogle;
  final Future<Map<String, dynamic>> Function({Map<String, String>? successorAdmins})? onDeleteAccount;

  const AccountDeletionDialog({
    super.key,
    required this.authService,
    required this.appDatabase,
    this.functions,
    this.onDeleted,
    this.isPasswordProvider,
    this.onReauthenticateWithPassword,
    this.onReauthenticateWithGoogle,
    this.onDeleteAccount,
  });

  static Future<void> show(
    BuildContext context, {
    required AuthService authService,
    required AppDatabase appDatabase,
    FirebaseFunctions? functions,
    VoidCallback? onDeleted,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withAlpha((0.65 * 255).round()),
      builder: (ctx) => AccountDeletionDialog(
        authService: authService,
        appDatabase: appDatabase,
        functions: functions,
        onDeleted: onDeleted,
      ),
    );
  }

  @override
  State<AccountDeletionDialog> createState() => _AccountDeletionDialogState();
}

class _AccountDeletionDialogState extends State<AccountDeletionDialog> {
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  String? _statusMessage;
  String? _errorMessage;

  // Populated when the backend requires successor admins for sole-admin shared sites
  List<SuccessorSiteRequirement>? _sitesNeedingSuccessor;
  final Map<String, String> _selectedSuccessors = {};

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _startDeletionFlow() async {
    setState(() {
      _errorMessage = null;
      _isLoading = true;
      _statusMessage = 'Re-authenticating...';
    });

    try {
      // 1. Re-authenticate
      final isPassword = widget.isPasswordProvider ?? widget.authService.isPasswordProvider;
      if (isPassword) {
        if (!_formKey.currentState!.validate()) {
          setState(() {
            _isLoading = false;
            _statusMessage = null;
          });
          return;
        }
        if (widget.onReauthenticateWithPassword != null) {
          await widget.onReauthenticateWithPassword!(_passwordController.text);
        } else {
          await widget.authService.reauthenticateWithPassword(_passwordController.text);
        }
      } else {
        if (widget.onReauthenticateWithGoogle != null) {
          await widget.onReauthenticateWithGoogle!();
        } else {
          await widget.authService.reauthenticateWithGoogle();
        }
      }

      // 2. Invoke Deletion on Server
      await _executeBackendDeletion();
    } on FirebaseAuthException catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = null;
        if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
          _errorMessage = 'Incorrect password. Please verify and try again.';
        } else if (e.code == 'cancelled') {
          _errorMessage = 'Re-authentication was cancelled.';
        } else {
          _errorMessage = 'Authentication error: ${e.message ?? e.code}';
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = null;
        _errorMessage = 'Re-authentication failed: $e';
      });
    }
  }

  Future<void> _executeBackendDeletion({Map<String, String>? successorAdmins}) async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Purging account & cloud data...';
      _errorMessage = null;
    });

    try {
      if (widget.onDeleteAccount != null) {
        await widget.onDeleteAccount!(successorAdmins: successorAdmins);
      } else {
        await widget.authService.deleteAccount(
          successorAdmins: successorAdmins,
          functions: widget.functions,
        );
      }

      // 3. Purge Local Sandbox Data strictly after server confirmation
      setState(() {
        _statusMessage = 'Purging local data...';
      });

      await widget.appDatabase.clearAllUserData();

      try {
        final appDir = await getApplicationDocumentsDirectory();
        final mediaDir = Directory('${appDir.path}/media');
        if (await mediaDir.exists()) {
          await mediaDir.delete(recursive: true);
        }
      } catch (_) {}

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('sitelens_active_site_id');
      } catch (_) {}

      try {
        await widget.authService.signOut();
      } catch (_) {}

      if (!mounted) return;

      widget.onDeleted?.call();

      Navigator.of(context).pop(); // Dismiss dialog
      Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.root, (route) => false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your account and personal data have been permanently deleted.'),
          backgroundColor: AppColors.statusGreen,
          duration: Duration(seconds: 4),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'failed-precondition' &&
          e.details is Map &&
          e.details['requiresSuccessor'] == true) {
        final rawSites = e.details['sitesNeedingSuccessor'];
        final sitesList = rawSites is List ? rawSites : [];
        final parsedRequirements = sitesList
            .map((s) => SuccessorSiteRequirement.fromMap(Map<dynamic, dynamic>.from(s as Map)))
            .toList();

        setState(() {
          _isLoading = false;
          _statusMessage = null;
          _sitesNeedingSuccessor = parsedRequirements;
          // Pre-select first eligible member for each site if available
          for (final req in parsedRequirements) {
            if (req.eligibleMembers.isNotEmpty) {
              _selectedSuccessors[req.siteId] = req.eligibleMembers.first.userId;
            }
          }
        });
        return;
      }

      setState(() {
        _isLoading = false;
        _statusMessage = null;
        _errorMessage = e.message ?? 'Deletion request failed. Please try again.';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = null;
        _errorMessage = 'Account deletion failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFF2EFEB),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _isLoading
              ? _buildLoadingView()
              : _sitesNeedingSuccessor != null
                  ? _buildSuccessorView()
                  : _buildConfirmationView(),
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        const CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.statusRed),
        ),
        const SizedBox(height: 24),
        Text(
          _statusMessage ?? 'Processing request...',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E1E1E),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildConfirmationView() {
    final isPassword = widget.isPasswordProvider ?? widget.authService.isPasswordProvider;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.statusRed.withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_forever_rounded,
                  color: AppColors.statusRed,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Delete Account',
                  style: TextStyle(
                    color: Color(0xFF1E1E1E),
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'This action is irreversible. Upon confirmation:',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF333333),
            ),
          ),
          const SizedBox(height: 10),
          _buildBulletPoint('Your authentication credentials and user profile will be permanently deleted.'),
          _buildBulletPoint('Sole-member project sites and their cloud-stored photos will be permanently destroyed.'),
          _buildBulletPoint('Evidence contributed to shared sites is retained for audit integrity with your author identity pseudonymized.'),
          _buildBulletPoint('All local database records, cached media, and pending sync queues on this device will be purged.'),
          const SizedBox(height: 16),
          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.statusRed.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.statusRed.withAlpha(60)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.statusRed, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: AppColors.statusRed, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (isPassword) ...[
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Confirm your password to proceed:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF444444)),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: 'Enter account password',
                      prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    validator: (val) {
                      if (val == null || val.isEmpty) {
                        return 'Password is required to confirm deletion';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.withAlpha(15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withAlpha(50)),
              ),
              child: Row(
                children: const [
                  Icon(Icons.info_outline_rounded, color: Colors.blue, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You will be prompted to re-authenticate with Google before deletion.',
                      style: TextStyle(color: Colors.blue, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: const Color(0xFFE5E3DF),
                      foregroundColor: const Color(0xFF333333),
                      side: BorderSide.none,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: ElevatedButton(
                    onPressed: _startDeletionFlow,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.statusRed,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    child: const Text(
                      'DELETE',
                      style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessorView() {
    final sites = _sitesNeedingSuccessor!;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.supervisor_account_rounded,
                  color: Colors.orange,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Admin Succession Required',
                  style: TextStyle(
                    color: Color(0xFF1E1E1E),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'You are the sole administrator of one or more shared sites. Please designate an active team member to succeed you as administrator:',
            style: TextStyle(fontSize: 12, color: Color(0xFF444444)),
          ),
          const SizedBox(height: 14),
          ...sites.map((siteReq) {
            final currentSelection = _selectedSuccessors[siteReq.siteId];

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    siteReq.siteName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: currentSelection,
                    isExpanded: true,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                    ),
                    items: siteReq.eligibleMembers.map((member) {
                      return DropdownMenuItem<String>(
                        value: member.userId,
                        child: Text(
                          '${member.userId} (${member.role})',
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedSuccessors[siteReq.siteId] = val;
                        });
                      }
                    },
                  ),
                ],
              ),
            );
          }),
          if (_errorMessage != null) ...[
            Text(
              _errorMessage!,
              style: const TextStyle(color: AppColors.statusRed, fontSize: 12),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: const Color(0xFFE5E3DF),
                      foregroundColor: const Color(0xFF333333),
                      side: BorderSide.none,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: ElevatedButton(
                    onPressed: () {
                      _executeBackendDeletion(successorAdmins: _selectedSuccessors);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.statusRed,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    child: const Text(
                      'CONFIRM DELETION',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 0.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: AppColors.statusRed, fontWeight: FontWeight.bold, fontSize: 14)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, height: 1.35, color: Color(0xFF555555)),
            ),
          ),
        ],
      ),
    );
  }
}
