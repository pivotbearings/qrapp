import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_typography.dart';

/// Pivot Bearings India - Strict 2-Color Industrial Theme
///
/// Palette:
/// - Background / Surface: #ECECEC
/// - Primary / Foreground / Border: #0065C1
///
/// Strict rules:
/// - Zero drop shadows (all elevations set to 0.0)
/// - Zero gradients or opacity shifts
/// - Curved-square components with 12px-16px border radii
abstract class AppTheme {
  static ThemeData get industrialTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: AppTypography.fontFamily,

      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: AppColors.primary,
        onPrimary: AppColors.background,
        secondary: AppColors.primary,
        onSecondary: AppColors.background,
        error: AppColors.primary,
        onError: AppColors.background,
        surface: AppColors.background,
        onSurface: AppColors.primary,
        outline: AppColors.primary,
        outlineVariant: AppColors.primary,
      ),

      // Zero-shadow Flat Industrial App Bar
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.primary,
        elevation: 0.0,
        scrolledUnderElevation: 0.0,
        centerTitle: false,
        titleTextStyle: AppTypography.headlineSm,
        iconTheme: IconThemeData(color: AppColors.primary),
      ),

      // Card Theme - Zero shadow, curved pill shape, solid border
      cardTheme: CardThemeData(
        color: AppColors.background,
        elevation: 0.0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(
            color: AppColors.primary,
            width: AppDimensions.borderWidthStandard,
          ),
        ),
      ),

      // Primary & Secondary Buttons - Strictly Pill-Shaped with click mouse cursors
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          enabledMouseCursor: SystemMouseCursors.click,
          disabledMouseCursor: SystemMouseCursors.basic,
          elevation: 0.0,
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.background,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.82),
          disabledForegroundColor: AppColors.background,
          minimumSize: const Size(64, AppDimensions.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
            side: const BorderSide(
              color: AppColors.primary,
              width: AppDimensions.borderWidthStandard,
            ),
          ),
          textStyle: AppTypography.buttonPrimary,
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spaceLg, vertical: 12.0),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          enabledMouseCursor: SystemMouseCursors.click,
          disabledMouseCursor: SystemMouseCursors.basic,
          elevation: 0.0,
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.background,
          disabledForegroundColor: AppColors.primary,
          minimumSize: const Size(64, AppDimensions.buttonHeight),
          side: const BorderSide(
            color: AppColors.primary,
            width: AppDimensions.borderWidthStandard,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
          ),
          textStyle: AppTypography.buttonSecondary,
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spaceLg, vertical: 12.0),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          enabledMouseCursor: SystemMouseCursors.click,
          disabledMouseCursor: SystemMouseCursors.basic,
          foregroundColor: AppColors.primary,
          textStyle: AppTypography.labelMd,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
          ),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          mouseCursor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
          ),
        ),
      ),

      // Input Fields - Strictly Pill-Shaped
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 22.0, vertical: 15.0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: const BorderSide(
            color: AppColors.primary,
            width: AppDimensions.borderWidthStandard,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: const BorderSide(
            color: AppColors.primary,
            width: AppDimensions.borderWidthStandard,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: const BorderSide(
            color: AppColors.primary,
            width: AppDimensions.borderWidthFocus,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: const BorderSide(
            color: AppColors.primary,
            width: AppDimensions.borderWidthStandard,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: const BorderSide(
            color: AppColors.primary,
            width: AppDimensions.borderWidthFocus,
          ),
        ),
        labelStyle: AppTypography.bodyMd,
        hintStyle: AppTypography.bodyMd,
        errorStyle: AppTypography.caption,
      ),

      // Divider Theme
      dividerTheme: const DividerThemeData(
        color: AppColors.primary,
        thickness: AppDimensions.borderWidthThin,
        space: AppDimensions.spaceMd,
      ),

      // Dialog Theme
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.background,
        elevation: 0.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(
            color: AppColors.primary,
            width: AppDimensions.borderWidthStandard,
          ),
        ),
      ),

      // Explicit Industrial Text Theme with medium and semibold weights
      textTheme: const TextTheme(
        headlineLarge: AppTypography.headlineLg,
        headlineMedium: AppTypography.headlineMd,
        headlineSmall: AppTypography.headlineSm,
        titleLarge: AppTypography.headlineSm,
        titleMedium: AppTypography.labelLg,
        titleSmall: AppTypography.labelMd,
        bodyLarge: AppTypography.bodyLg,
        bodyMedium: AppTypography.bodyMd,
        bodySmall: AppTypography.bodySm,
        labelLarge: AppTypography.labelLg,
        labelMedium: AppTypography.labelMd,
        labelSmall: AppTypography.labelSm,
      ),

      // Navigation Bar / Bottom Bar Theme
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.background,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.primary,
        elevation: 0.0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 12.0,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 11.0,
          fontWeight: FontWeight.w500,
          color: AppColors.primary,
        ),
      ),

      // Minimalist Clean Floating SnackBar Theme
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primary,
        contentTextStyle: AppTypography.bodySm.copyWith(
          color: AppColors.background,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(50),
          side: const BorderSide(color: AppColors.primary, width: 1.0),
        ),
        elevation: 2.0,
      ),
    );
  }
}
