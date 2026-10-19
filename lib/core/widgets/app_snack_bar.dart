import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_typography.dart';

/// Clean, minimalistic, non-stacking industrial snack bar utility.
///
/// Features:
/// - Strictly non-stacking: Immediately clears any queued or existing snackbars.
/// - Quick display: Automatically dismisses in 1.5 seconds (1-2s range).
/// - Minimalist aesthetic: Pill-shaped floating design with crisp typography.
class AppSnackBar {
  AppSnackBar._();

  /// Displays a clean, non-stacking feedback message
  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
    IconData? icon,
    Duration duration = const Duration(milliseconds: 1500),
  }) {
    final messenger = ScaffoldMessenger.of(context);

    // Wipe any existing or stacked snack bars immediately so only the latest is displayed
    messenger.clearSnackBars();

    final effectiveIcon = icon ??
        (isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded);

    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: duration,
        elevation: 2.0,
        backgroundColor: Colors.transparent,
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: AppColors.primary, width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                effectiveIcon,
                size: 18,
                color: isError ? const Color(0xFFFCA5A5) : AppColors.background,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  message,
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.background,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Displays an error snack bar
  static void showError(
    BuildContext context,
    String message, {
    Duration duration = const Duration(milliseconds: 1800),
  }) {
    show(context, message, isError: true, duration: duration);
  }

  /// Displays a success snack bar
  static void showSuccess(
    BuildContext context,
    String message, {
    Duration duration = const Duration(milliseconds: 1500),
  }) {
    show(context, message, isError: false, duration: duration);
  }

  /// Displays an informational snack bar
  static void showInfo(
    BuildContext context,
    String message, {
    Duration duration = const Duration(milliseconds: 1500),
  }) {
    show(
      context,
      message,
      isError: false,
      icon: Icons.info_outline_rounded,
      duration: duration,
    );
  }
}
