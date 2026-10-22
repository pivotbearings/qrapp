import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Pivot Bearings India Typography System
///
/// Fonts strictly restricted to:
/// - "NeueHaas" Light (neue-haas-light.otf) – weight 300, body/captions
/// - "NeueHaas" Roman (neue-haas-roman.otf) – weight 400/500/600/700, headings/labels
abstract class AppTypography {
  static const String fontFamily = 'NeueHaas';
  static const String rupeeFontFamily = 'Parkinsans';
  static const List<String> fontFamilyFallback = [
    'Inter',
    'Roboto',
    'Segoe UI',
    'Arial',
    'sans-serif',
    'Parkinsans',
  ];

  /// Dedicated TextStyle for the Indian Rupee symbol ('₹') using Parkinsans font
  static TextStyle rupee({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
  }) {
    return TextStyle(
      fontFamily: rupeeFontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight ?? FontWeight.bold,
      color: color ?? AppColors.primary,
    );
  }

  // Headings (Medium to Bold)
  static const TextStyle headlineLg = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 28.0,
    fontWeight: FontWeight.w600,
    height: 36.0 / 28.0,
    color: AppColors.primary,
    letterSpacing: -0.5,
  );

  static const TextStyle headlineLgMobile = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 24.0,
    fontWeight: FontWeight.w600,
    height: 32.0 / 24.0,
    color: AppColors.primary,
    letterSpacing: -0.3,
  );

  static const TextStyle headlineMd = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 20.0,
    fontWeight: FontWeight.w600,
    height: 28.0 / 20.0,
    color: AppColors.primary,
    letterSpacing: -0.2,
  );

  static const TextStyle headlineSm = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 16.0,
    fontWeight: FontWeight.w600,
    height: 24.0 / 16.0,
    color: AppColors.primary,
  );

  // Labels & Buttons (Medium/Semi-bold)
  static const TextStyle labelLg = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 16.0,
    fontWeight: FontWeight.w600,
    height: 20.0 / 16.0,
    color: AppColors.primary,
    letterSpacing: 0.3,
  );

  static const TextStyle labelMd = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 14.0,
    fontWeight: FontWeight.w600,
    height: 18.0 / 14.0,
    color: AppColors.primary,
    letterSpacing: 0.3,
  );

  static const TextStyle buttonPrimary = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 14.0,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: AppColors.background,
    letterSpacing: 0.8,
  );

  static const TextStyle buttonSecondary = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 14.0,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: AppColors.primary,
    letterSpacing: 0.8,
  );

  // Body & Inputs (Medium / Semibold weight w600 for high visibility and contrast)
  static const TextStyle bodyLg = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 16.0,
    fontWeight: FontWeight.w600,
    height: 24.0 / 16.0,
    color: AppColors.primary,
  );

  static const TextStyle bodyMd = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 14.0,
    fontWeight: FontWeight.w600,
    height: 20.0 / 14.0,
    color: AppColors.primary,
  );

  static const TextStyle bodySm = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 13.0,
    fontWeight: FontWeight.w600,
    height: 18.0 / 13.0,
    color: AppColors.primary,
  );

  static const TextStyle labelSm = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 13.0,
    fontWeight: FontWeight.w600,
    height: 18.0 / 13.0,
    color: AppColors.primary,
    letterSpacing: 0.2,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    height: 17.0 / 12.5,
    color: AppColors.primary,
    letterSpacing: 0.3,
  );

  static const TextStyle mono = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 13.0,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.0,
    color: AppColors.primary,
  );
}
