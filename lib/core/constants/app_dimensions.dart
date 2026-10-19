import 'package:flutter/material.dart';

/// Industrial Precision System Dimensions & Radii
///
/// Corner radii: 12px - 16px (curved-square / squircle design).
/// Micro elements: 4px.
/// Zero drop shadows.
abstract class AppDimensions {
  // Spacing
  static const double spaceXs = 4.0;
  static const double spaceSm = 8.0;
  static const double spaceMd = 16.0;
  static const double spaceLg = 24.0;
  static const double spaceXl = 32.0;

  // Mobile layout gutters & margins
  static const double gutterMobile = 16.0;
  static const double marginMobile = 16.0;

  // Desktop layout gutters & margins
  static const double gutterDesktop = 24.0;
  static const double marginDesktop = 32.0;

  // Radii - Industrial pill and rounded components
  static const double radiusMicro = 12.0;
  static const double radiusSm = 16.0;
  static const double radiusDefault = 24.0;
  static const double radiusMedium = 24.0;
  static const double radiusCard = 24.0;
  static const double radiusLg = 28.0;
  static const double radiusPill = 50.0;

  static final BorderRadius borderRadiusDefault = BorderRadius.circular(radiusDefault);
  static final BorderRadius borderRadiusCard = BorderRadius.circular(radiusCard);
  static final BorderRadius borderRadiusLg = BorderRadius.circular(radiusLg);
  static final BorderRadius borderRadiusMicro = BorderRadius.circular(radiusMicro);
  static final BorderRadius borderRadiusPill = BorderRadius.circular(radiusPill);

  // Borders
  static const double borderWidthThin = 1.0;
  static const double borderWidthStandard = 1.5;
  static const double borderWidthFocus = 2.5;

  // Touch targets
  static const double minTouchTarget = 48.0;
  static const double buttonHeight = 48.0;
  static const double inputHeight = 48.0;
}
