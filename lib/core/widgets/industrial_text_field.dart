import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_typography.dart';

/// Industrial Text Input conforming to 2-color design system
class IndustrialTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool readOnly;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? errorText;
  final bool uppercase;
  final FormFieldValidator<String>? validator;

  const IndustrialTextField({
    super.key,
    this.controller,
    this.label,
    this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.prefixIcon,
    this.suffixIcon,
    this.readOnly = false,
    this.obscureText = false,
    this.keyboardType,
    this.errorText,
    this.uppercase = false,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            uppercase ? label!.toUpperCase() : label!,
            style: AppTypography.labelSm.copyWith(
              letterSpacing: uppercase ? 0.8 : 0.0,
            ),
          ),
          const SizedBox(height: 6.0),
        ],
        TextFormField(
          controller: controller,
          readOnly: readOnly,
          obscureText: obscureText,
          keyboardType: keyboardType,
          style: AppTypography.bodyMd,
          cursorColor: AppColors.primary,
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
          validator: validator,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
            errorText: errorText != null ? '[!] $errorText' : null,
          ),
        ),
      ],
    );
  }
}
