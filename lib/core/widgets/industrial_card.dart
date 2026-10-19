import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';

/// Industrial Card strictly in #ECECEC with 1.5px #0065C1 outline and ZERO shadows
class IndustrialCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double borderWidth;
  final BorderRadius? borderRadius;

  const IndustrialCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppDimensions.spaceMd),
    this.onTap,
    this.borderWidth = AppDimensions.borderWidthStandard,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = borderRadius ?? AppDimensions.borderRadiusCard;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: effectiveRadius,
        border: Border.all(
          color: AppColors.primary,
          width: borderWidth,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          mouseCursor: onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
          borderRadius: effectiveRadius,
          onTap: onTap,
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}
