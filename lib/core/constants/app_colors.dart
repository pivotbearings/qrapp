import 'package:flutter/material.dart';

/// Pivot Bearings India - Strict Binary Design System Colors
///
/// NON-NEGOTIABLE RULE:
/// Exactly two colors are permitted across the entire application:
/// - Background: `#ECECEC`
/// - Primary: `#0065C1`
///
/// Absolutely no pure black (#000), intermediate grays,
/// gradients, shadows, or alpha opacity variations are permitted.
abstract class AppColors {
  /// Base canvas and surface background (#FFFFFF)
  static const Color background = Color(0xFFFFFFFF);

  /// Primary blue foreground, text, borders, active surfaces, icons (#0065C1)
  static const Color primary = Color(0xFF0065C1);

  // Semantically bound aliases strictly adhering to the 2-color rule
  static const Color surface = background;
  static const Color onBackground = primary;
  static const Color onSurface = primary;
  static const Color onPrimary = background;
  static const Color border = primary;
  static const Color icon = primary;
}
