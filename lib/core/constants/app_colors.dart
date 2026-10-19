import 'package:flutter/material.dart';

/// Pivot Bearings India - Strict Binary Design System Colors
///
/// NON-NEGOTIABLE RULE:
/// Exactly two colors are permitted across the entire application:
/// - Background: `#ECECEC`
/// - Primary: `#001F59`
///
/// Absolutely no pure white (#FFF), black (#000), intermediate grays,
/// gradients, shadows, or alpha opacity variations are permitted.
abstract class AppColors {
  /// Base canvas and surface background (#FFFFFF)
  static const Color background = Color(0xFFFFFFFF);

  /// Primary navy foreground, text, borders, active surfaces, icons (#001F59)
  static const Color primary = Color(0xFF001F59);

  // Semantically bound aliases strictly adhering to the 2-color rule
  static const Color surface = background;
  static const Color onBackground = primary;
  static const Color onSurface = primary;
  static const Color onPrimary = background;
  static const Color border = primary;
  static const Color icon = primary;
}
