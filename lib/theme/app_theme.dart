import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_dimensions.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme => _buildDarkTheme();
  static ThemeData get lightTheme => _buildLightTheme();

  static ThemeData _buildDarkTheme() {
    const colorScheme = ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      secondary: AppColors.success,
      onSecondary: AppColors.onPrimary,
      surface: AppColors.surfaceDark,
      onSurface: AppColors.textPrimaryDark,
      error: AppColors.error,
      onError: AppColors.onPrimary,
      outline: AppColors.borderDark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.backgroundDark,

      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.backgroundDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimaryDark,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimaryDark),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarBrightness: Brightness.dark,
          statusBarIconBrightness: Brightness.light,
          statusBarColor: Colors.transparent,
        ),
      ),

      // Card
      cardTheme: CardThemeData(
        color: AppColors.surfaceDark,
        elevation: AppDimensions.cardElevation,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          side: const BorderSide(color: AppColors.borderDark, width: 0.5),
        ),
      ),

      // Input
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceDark,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spacingMd,
          vertical: AppDimensions.spacingMd,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.inputBorderRadius),
          borderSide: const BorderSide(color: AppColors.borderDark, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.inputBorderRadius),
          borderSide: const BorderSide(color: AppColors.borderDark, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.inputBorderRadius),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        hintStyle: const TextStyle(color: AppColors.textDisabledDark),
        labelStyle: const TextStyle(color: AppColors.textSecondaryDark),
      ),

      // Chip (tags)
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceVariantDark,
        selectedColor: AppColors.primary.withValues(alpha: 0.2),
        labelStyle: const TextStyle(
          color: AppColors.textSecondaryDark,
          fontSize: 12,
        ),
        side: const BorderSide(color: AppColors.borderDark, width: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),

      // Bottom Sheet
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceDark,
        modalBackgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppDimensions.bottomSheetRadius),
          ),
        ),
        showDragHandle: true,
        dragHandleColor: AppColors.borderDark,
      ),

      // Icon
      iconTheme: const IconThemeData(
        color: AppColors.textSecondaryDark,
        size: AppDimensions.iconMd,
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: AppColors.borderDark,
        thickness: 0.5,
        space: 0,
      ),

      // Text
      textTheme: _darkTextTheme(),

      // Floating action button
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
        ),
      ),

      // SnackBar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceVariantDark,
        contentTextStyle: const TextStyle(color: AppColors.textPrimaryDark),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static ThemeData _buildLightTheme() {
    const colorScheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      secondary: AppColors.success,
      onSecondary: AppColors.onPrimary,
      surface: AppColors.surfaceLight,
      onSurface: AppColors.textPrimaryLight,
      error: AppColors.error,
      onError: AppColors.onPrimary,
      outline: AppColors.borderLight,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.backgroundLight,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.backgroundLight,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimaryLight,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimaryLight),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceLight,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          side: const BorderSide(color: AppColors.borderLight, width: 0.5),
        ),
      ),
      textTheme: _lightTextTheme(),
    );
  }

  static TextTheme _darkTextTheme() {
    return const TextTheme(
      displayLarge: TextStyle(
        color: AppColors.textPrimaryDark,
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineMedium: TextStyle(
        color: AppColors.textPrimaryDark,
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      titleLarge: TextStyle(
        color: AppColors.textPrimaryDark,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: TextStyle(
        color: AppColors.textPrimaryDark,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      bodyLarge: TextStyle(
        color: AppColors.textPrimaryDark,
        fontSize: 15,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        color: AppColors.textSecondaryDark,
        fontSize: 14,
        height: 1.5,
      ),
      labelLarge: TextStyle(
        color: AppColors.textPrimaryDark,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
      labelMedium: TextStyle(
        color: AppColors.textSecondaryDark,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
      ),
      labelSmall: TextStyle(
        color: AppColors.textDisabledDark,
        fontSize: 11,
        letterSpacing: 0.4,
      ),
    );
  }

  static TextTheme _lightTextTheme() {
    return const TextTheme(
      displayLarge: TextStyle(
        color: AppColors.textPrimaryLight,
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineMedium: TextStyle(
        color: AppColors.textPrimaryLight,
        fontSize: 24,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: TextStyle(
        color: AppColors.textPrimaryLight,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: TextStyle(
        color: AppColors.textPrimaryLight,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      bodyLarge: TextStyle(
        color: AppColors.textPrimaryLight,
        fontSize: 15,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        color: AppColors.textSecondaryLight,
        fontSize: 14,
        height: 1.5,
      ),
      labelLarge: TextStyle(
        color: AppColors.textPrimaryLight,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: TextStyle(
        color: AppColors.textSecondaryLight,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      labelSmall: TextStyle(
        color: AppColors.textDisabledLight,
        fontSize: 11,
      ),
    );
  }
}
