import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_typography.dart';

/// Industrial Status Badge with clear red/green indicators for expired warranty and invalid QR
class IndustrialStatusBadge extends StatelessWidget {
  final String statusText;
  final IconData? icon;
  final bool isPrimary;
  final bool? isDanger;
  final bool? isSuccess;

  const IndustrialStatusBadge({
    super.key,
    required this.statusText,
    this.icon,
    this.isPrimary = true,
    this.isDanger,
    this.isSuccess,
  });

  @override
  Widget build(BuildContext context) {
    final upper = statusText.toUpperCase();
    final bool danger = isDanger ?? (upper.contains('EXPIRED') || upper.contains('INVALID') || upper.contains('BLOCKED') || upper.contains('FAILED'));
    final bool success = isSuccess ?? (upper.contains('ACTIVE') || upper.contains('VERIFIED') || upper.contains('GENUINE'));

    Color bgColor;
    Color borderColor;
    Color textColor;
    IconData? badgeIcon = icon;

    if (danger) {
      bgColor = const Color(0xFFFEE2E2); // Light red
      borderColor = const Color(0xFFDC2626); // Crimson red
      textColor = const Color(0xFFB91C1C); // Dark red
      badgeIcon ??= Icons.error_outline;
    } else if (success) {
      bgColor = const Color(0xFFDCFCE7); // Light green
      borderColor = const Color(0xFF16A34A); // Emerald green
      textColor = const Color(0xFF15803D); // Dark green
      badgeIcon ??= Icons.check_circle_outline;
    } else {
      bgColor = AppColors.background;
      borderColor = AppColors.primary;
      textColor = AppColors.primary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(50),
        border: Border.all(
          color: borderColor,
          width: danger ? 1.5 : AppDimensions.borderWidthThin,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badgeIcon != null) ...[
            Icon(badgeIcon, color: textColor, size: 14),
            const SizedBox(width: AppDimensions.spaceXs),
          ],
          Flexible(
            child: Text(
              statusText,
              style: AppTypography.caption.copyWith(
                color: textColor,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}
