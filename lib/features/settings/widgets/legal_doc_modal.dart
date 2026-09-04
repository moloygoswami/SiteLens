import 'package:flutter/material.dart';
import '../../../app/theme.dart';

enum LegalDocType {
  termsOfService,
  privacyPolicy,
}

class LegalDocModal extends StatelessWidget {
  final LegalDocType type;

  const LegalDocModal({
    super.key,
    required this.type,
  });

  static Future<void> show(BuildContext context, LegalDocType type) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LegalDocModal(type: type),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = type == LegalDocType.termsOfService
        ? 'Terms of Service'
        : 'Privacy Policy';
    final content = type == LegalDocType.termsOfService
        ? _termsOfServiceContent
        : _privacyPolicyContent;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      'Last Updated: August 2026',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...content.map(
                      (section) => Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              section.heading,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              section.body,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          'I Understand',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LegalSection {
  final String heading;
  final String body;
  const _LegalSection(this.heading, this.body);
}

const List<_LegalSection> _termsOfServiceContent = [
  _LegalSection(
    '1. Acceptance of Terms',
    'By registering, accessing, or using the SiteLens application, you agree to be bound by these Terms of Service. If you do not agree with any part of these terms, you may not use the application.',
  ),
  _LegalSection(
    '2. Purpose & Evidence Integrity',
    'SiteLens is designed for engineering, construction inspection, and forensic field verification. Users agree to use the camera and GPS telemetry tools honestly. Any attempt to spoof, tamper with, or forge cryptographic provenance hashes or burned-in watermark metadata is strictly prohibited.',
  ),
  _LegalSection(
    '3. Account & Email Verification',
    'Users must provide a valid email address and verify their email prior to account activation. You are responsible for maintaining the confidentiality of your login credentials and for all activities that occur under your account.',
  ),
  _LegalSection(
    '4. Intellectual Property & Evidence Ownership',
    'All photographic and video evidence captured by you remains the property of your organization or project authority. SiteLens provides immutable timestamping and local-first cryptographic verification tools to secure your evidence.',
  ),
  _LegalSection(
    '5. Limitation of Liability',
    'SiteLens and its developers shall not be liable for any indirect, incidental, or consequential damages resulting from inaccurate GPS satellite readings, hardware sensor deviations, or third-party mapping service availability.',
  ),
];

const List<_LegalSection> _privacyPolicyContent = [
  _LegalSection(
    '1. Information We Collect',
    'We collect your registered email address, name, device hardware telemetry during active capture (GPS coordinates, altitude, compass bearing, camera lens zoom metadata), and site association IDs necessary for evidence indexing.',
  ),
  _LegalSection(
    '2. How Location Data Is Handled',
    'GPS coordinates are processed locally on your device to create immutable on-photo watermark stamps and calculate distance to historical inspection sites. High-accuracy location is queried only while actively capturing or browsing nearby site evidence.',
  ),
  _LegalSection(
    '3. Offline-First Storage',
    'Photos, videos, and cryptographic hashes are stored locally in your device\'s secure application sandbox storage database (Drift SQLite). Media is never shared with third-party tracking or advertising networks.',
  ),
  _LegalSection(
    '4. Third-Party Integrations',
    'When enabled by the user, optional cloud synchronization connects directly with Firebase Authentication and Google Photos API under your explicit authorization.',
  ),
  _LegalSection(
    '5. Contact & Data Deletion',
    'You may request account removal and data deletion at any time by contacting your project administrator or support@sitelens.local.',
  ),
];
