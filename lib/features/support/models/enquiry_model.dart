import 'package:uuid/uuid.dart';

/// Categories of support/enquiry inquiries supported by SiteLens.
enum EnquiryCategory {
  general(
    key: 'general',
    label: 'General Enquiry',
    description: 'General questions or product information',
  ),
  bugReport(
    key: 'bug_report',
    label: 'Bug Report',
    description: 'Report an issue or unexpected behavior',
  ),
  featureRequest(
    key: 'feature_request',
    label: 'Feature Request',
    description: 'Suggest improvements or new capabilities',
  ),
  enterpriseSales(
    key: 'enterprise_sales',
    label: 'Enterprise / Site Deployment',
    description: 'Multi-site deployments, licensing, or onboarding',
  ),
  complianceEnquiry(
    key: 'compliance_enquiry',
    label: 'Compliance & Audit',
    description: 'Forensic integrity, legal or regulatory compliance',
  );

  const EnquiryCategory({
    required this.key,
    required this.label,
    required this.description,
  });

  final String key;
  final String label;
  final String description;

  static EnquiryCategory fromKey(String key) {
    return EnquiryCategory.values.firstWhere(
      (c) => c.key == key,
      orElse: () => EnquiryCategory.general,
    );
  }
}

/// Data model representing a user enquiry submission.
class UserEnquiry {
  final String submissionId;
  final String name;
  final String email;
  final EnquiryCategory category;
  final String message;
  final DateTime createdAt;

  UserEnquiry({
    String? submissionId,
    required this.name,
    required this.email,
    required this.category,
    required this.message,
    DateTime? createdAt,
  })  : submissionId = submissionId ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  static final RegExp _emailRegExp = RegExp(
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$",
  );

  /// Validates form inputs client-side before sending to server.
  static String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your name';
    }
    if (value.trim().length > 100) {
      return 'Name must be 100 characters or fewer';
    }
    return null;
  }

  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your email address';
    }
    final trimmed = value.trim();
    if (!_emailRegExp.hasMatch(trimmed) || trimmed.length > 254) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  static String? validateMessage(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your enquiry message';
    }
    final trimmed = value.trim();
    if (trimmed.length < 10) {
      return 'Message must be at least 10 characters';
    }
    if (trimmed.length > 5000) {
      return 'Message must be 5000 characters or fewer';
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'submissionId': submissionId,
      'name': name.trim(),
      'email': email.trim().toLowerCase(),
      'category': category.key,
      'message': message.trim(),
    };
  }
}
