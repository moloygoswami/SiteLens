import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
import '../../../core/services/auth_service.dart';
import '../controllers/enquiry_controller.dart';
import '../models/enquiry_model.dart';

/// Modal bottom sheet allowing users to submit enquiries and feedback to SiteLens support.
class UserEnquiryModal extends ConsumerStatefulWidget {
  const UserEnquiryModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const UserEnquiryModal(),
    );
  }

  @override
  ConsumerState<UserEnquiryModal> createState() => _UserEnquiryModalState();
}

class _UserEnquiryModalState extends ConsumerState<UserEnquiryModal> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _messageController;

  EnquiryCategory _selectedCategory = EnquiryCategory.general;

  @override
  void initState() {
    super.initState();
    final authUser = ref.read(authServiceProvider).currentUser;
    final initialEmail = authUser?.email ?? '';
    final initialName = authUser?.displayName ?? (initialEmail.isNotEmpty ? initialEmail.split('@').first : '');

    _nameController = TextEditingController(text: initialName);
    _emailController = TextEditingController(text: initialEmail);
    _messageController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await ref.read(enquiryControllerProvider.notifier).submitEnquiry(
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          category: _selectedCategory,
          message: _messageController.text.trim(),
        );

    if (success && mounted) {
      _messageController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final enquiryState = ref.watch(enquiryControllerProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: bottomInset + 24,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: enquiryState.isSuccess
            ? _buildSuccessView(context, enquiryState)
            : _buildFormView(context, enquiryState),
      ),
    );
  }

  Widget _buildSuccessView(BuildContext context, EnquiryState state) {
    final submissionId = state.result?.submissionId ?? '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary.withAlpha(30),
            border: Border.all(color: AppColors.primary, width: 2),
          ),
          child: const Icon(
            Icons.check_rounded,
            color: AppColors.primary,
            size: 32,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Enquiry Submitted',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            state.result?.message ?? 'Our support engineering team has received your enquiry.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ),
        if (submissionId.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.tag_rounded, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  'REF: ${submissionId.length > 12 ? submissionId.substring(0, 12) : submissionId}...',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryLight,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              ref.read(enquiryControllerProvider.notifier).reset();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.pill)),
            ),
            child: const Text('DONE', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ),
      ],
    );
  }

  Widget _buildFormView(BuildContext context, EnquiryState state) {
    return SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title & Subtitle
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.primary.withAlpha(100)),
                  ),
                  child: const Icon(Icons.mail_outline_rounded, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CONTACT SUPPORT',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        'Submit technical inquiries or feedback to engineering',
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Error Banner if previous attempt failed
            if (state.isError && state.errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.statusRed.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.statusRed.withAlpha(120)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.statusRed, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.errorMessage!,
                        style: const TextStyle(fontSize: 12, color: AppColors.statusRedLight),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 1. Category Selector
            Text(
              'ENQUIRY CATEGORY',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: EnquiryCategory.values.map((cat) {
                final isSelected = _selectedCategory == cat;
                return ChoiceChip(
                  label: Text(
                    cat.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? Colors.black : AppColors.textPrimary,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: AppColors.primary,
                  backgroundColor: AppColors.background,
                  side: BorderSide(
                    color: isSelected ? AppColors.primary : AppColors.border,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedCategory = cat);
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // 2. Name Field
            TextFormField(
              controller: _nameController,
              validator: UserEnquiry.validateName,
              textInputAction: TextInputAction.next,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Your Name',
                labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                prefixIcon: const Icon(Icons.person_outline_rounded, size: 18, color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primary)),
              ),
            ),
            const SizedBox(height: 12),

            // 3. Email Field
            TextFormField(
              controller: _emailController,
              validator: UserEnquiry.validateEmail,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Email Address (Reply-To)',
                labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                prefixIcon: const Icon(Icons.alternate_email_rounded, size: 18, color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primary)),
              ),
            ),
            const SizedBox(height: 12),

            // 4. Message Field
            TextFormField(
              controller: _messageController,
              validator: UserEnquiry.validateMessage,
              maxLines: 4,
              maxLength: 5000,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Message / Description',
                labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                alignLabelWithHint: true,
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primary)),
              ),
            ),
            const SizedBox(height: 16),

            // 5. Submit Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: state.isSubmitting ? null : _handleSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: AppColors.primary.withAlpha(120),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.pill)),
                ),
                child: state.isSubmitting
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text('SENDING ENQUIRY...', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                        ],
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.send_rounded, size: 16),
                          SizedBox(width: 8),
                          Text('SUBMIT ENQUIRY', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
