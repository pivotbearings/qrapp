import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_typography.dart';

enum IndustrialButtonVariant {
  primary,
  secondary,
  success, // Industrial Green for Mark IN & verification
  danger,  // Industrial Red for Mark OUT & removal
}

/// Industrial Button with built-in rapid double-tap debouncing and loading states
class IndustrialButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IndustrialButtonVariant variant;
  final IconData? icon;
  final bool isLoading;
  final double? width;
  final double height;
  final Color? customBgColor;
  final Color? customFgColor;

  static int _lastGlobalTapTime = 0;

  const IndustrialButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = IndustrialButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.width,
    this.height = AppDimensions.buttonHeight,
    this.customBgColor,
    this.customFgColor,
  });

  const IndustrialButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.width,
    this.height = AppDimensions.buttonHeight,
    this.customBgColor,
    this.customFgColor,
  }) : variant = IndustrialButtonVariant.secondary;

  const IndustrialButton.success({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.width,
    this.height = AppDimensions.buttonHeight,
    this.customBgColor,
    this.customFgColor,
  }) : variant = IndustrialButtonVariant.success;

  const IndustrialButton.danger({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.width,
    this.height = AppDimensions.buttonHeight,
    this.customBgColor,
    this.customFgColor,
  }) : variant = IndustrialButtonVariant.danger;

  void _onTapHandler() {
    if (onPressed == null || isLoading) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    // Anti-double-tap guard: blocks duplicate executions within 650ms window
    if (now - _lastGlobalTapTime < 650) return;
    _lastGlobalTapTime = now;
    onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final bool isEnabled = onPressed != null && !isLoading;

    Color bgColor;
    Color fgColor;
    Color borderColor;

    switch (variant) {
      case IndustrialButtonVariant.success:
        bgColor = customBgColor ?? (isEnabled ? const Color(0xFF16A34A) : const Color(0xFF86EFAC));
        fgColor = customFgColor ?? Colors.white;
        borderColor = const Color(0xFF15803D);
        break;
      case IndustrialButtonVariant.danger:
        bgColor = customBgColor ?? (isEnabled ? const Color(0xFFDC2626) : const Color(0xFFFCA5A5));
        fgColor = customFgColor ?? Colors.white;
        borderColor = const Color(0xFFB91C1C);
        break;
      case IndustrialButtonVariant.secondary:
        bgColor = customBgColor ?? AppColors.background;
        fgColor = customFgColor ?? (isEnabled ? AppColors.primary : AppColors.primary.withValues(alpha: 0.5));
        borderColor = isEnabled ? AppColors.primary : AppColors.primary.withValues(alpha: 0.4);
        break;
      case IndustrialButtonVariant.primary:
        bgColor = customBgColor ?? (isEnabled ? AppColors.primary : AppColors.background);
        fgColor = customFgColor ?? (isEnabled ? AppColors.background : AppColors.primary);
        borderColor = AppColors.primary;
        break;
    }

    return SizedBox(
      width: width ?? double.infinity,
      height: height,
      child: Material(
        color: bgColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(50),
          side: BorderSide(
            color: borderColor,
            width: AppDimensions.borderWidthStandard,
          ),
        ),
        child: InkWell(
          mouseCursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onTap: isEnabled ? _onTapHandler : null,
          borderRadius: BorderRadius.circular(50),
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(fgColor),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, color: fgColor, size: 18),
                          const SizedBox(width: AppDimensions.spaceSm),
                        ],
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              label,
                              maxLines: 1,
                              style: (variant == IndustrialButtonVariant.primary && isEnabled)
                                  ? AppTypography.buttonPrimary
                                  : (variant == IndustrialButtonVariant.success || variant == IndustrialButtonVariant.danger)
                                      ? AppTypography.buttonPrimary.copyWith(
                                          color: fgColor,
                                          fontWeight: FontWeight.bold,
                                        )
                                      : AppTypography.buttonSecondary.copyWith(color: fgColor),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
