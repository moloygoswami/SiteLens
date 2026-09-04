import 'package:flutter/material.dart';
import '../../app/theme.dart';

/// Standardized 2-button confirmation dialog used across the app.
///
/// Visual spec: warm off-white card, 24px radius, 24px padding, centered
/// with a 380px max width, dimmed 0.55 backdrop, and two equal-width
/// 48px pill buttons (light-gray Cancel + red primary action).
class ConfirmationDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final IconData? icon;
  final Widget? extraContent;
  final bool destructive;

  const ConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.icon,
    this.extraContent,
    this.destructive = true,
  });

  /// Shows the dialog and resolves to `true` when the confirm action is
  /// pressed, `false` when dismissed (Cancel, barrier tap, or back).
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    IconData? icon,
    Widget? extraContent,
    bool destructive = true,
  }) {
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withAlpha((0.55 * 255).round()),
      builder: (ctx) => ConfirmationDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        icon: icon,
        extraContent: extraContent,
        destructive: destructive,
      ),
    ).then((value) => value ?? false);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFF2EFEB),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Icon(icon, color: destructive ? AppColors.statusRed : AppColors.primary, size: 28),
                const SizedBox(height: 12),
              ],
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF1E1E1E),
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: const TextStyle(
                  color: Color(0xFF555555),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              if (extraContent != null) ...[
                const SizedBox(height: 16),
                extraContent!,
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: const Color(0xFFE5E3DF),
                          foregroundColor: const Color(0xFF333333),
                          side: BorderSide.none,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: destructive
                              ? AppColors.statusRed
                              : AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: Text(confirmLabel),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
