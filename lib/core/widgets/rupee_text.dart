import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_typography.dart';

/// Renders the Indian Rupee symbol ('₹') using the dedicated Parkinsans font
class RupeeSymbol extends StatelessWidget {
  final double? size;
  final Color? color;
  final FontWeight? fontWeight;

  const RupeeSymbol({
    super.key,
    this.size,
    this.color,
    this.fontWeight,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      '₹',
      style: AppTypography.rupee(
        fontSize: size,
        color: color ?? AppColors.primary,
        fontWeight: fontWeight ?? FontWeight.bold,
      ),
    );
  }
}

/// Formats amounts with the Parkinsans Rupee symbol followed by the amount
class RupeeText extends StatelessWidget {
  final String amount;
  final TextStyle? style;

  const RupeeText(this.amount, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? AppTypography.bodyMd;
    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: [
          TextSpan(
            text: '₹',
            style: baseStyle.copyWith(
              fontFamily: AppTypography.rupeeFontFamily,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(
            text: ' $amount',
            style: baseStyle,
          ),
        ],
      ),
    );
  }
}
