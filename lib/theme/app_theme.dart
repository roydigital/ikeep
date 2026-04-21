import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_dimensions.dart';

class AppTheme {
  AppTheme._();

  // Cache font family names once — avoids calling GoogleFonts constructors
  // (which produce TextStyles with inherit:false and implicit properties like
  // wordSpacing, decoration, etc. that break TextStyle.lerp during theme
  // transitions).
  static final String _headlineFamily =
      GoogleFonts.plusJakartaSans().fontFamily!;
  static final String _bodyFamily = GoogleFonts.dmSans().fontFamily!;
  static final String _labelFamily = GoogleFonts.spaceGrotesk().fontFamily!;

  static ThemeData get darkTheme => _buildDarkTheme();
  static ThemeData get lightTheme => _buildLightTheme();

  // ── Font helpers ──────────────────────────────────────────────────────────

  static TextStyle _headline(double size, FontWeight weight, Color color,
      {double letterSpacing = -0.5}) {
    return TextStyle(
      fontFamily: _headlineFamily,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle _body(double size, FontWeight weight, Color color,
      {double? height, double letterSpacing = 0}) {
    return TextStyle(
      fontFamily: _bodyFamily,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle _label(double size, FontWeight weight, Color color,
      {double letterSpacing = 0.3}) {
    return TextStyle(
      fontFamily: _labelFamily,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
    );
  }

  // ── Dark Theme ────────────────────────────────────────────────────────────

  static ThemeData _buildDarkTheme() {
    const colorScheme = ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      secondary: AppColors.secondary,
      onSecondary: AppColors.onPrimary,
      tertiary: AppColors.tertiary,
      surface: AppColors.surfaceDark,
      onSurface: AppColors.textPrimaryDark,
      error: AppColors.error,
      onError: AppColors.onPrimary,
      outline: AppColors.borderDark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.transparent,

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: _headline(
          20,
          FontWeight.w700,
          AppColors.textPrimaryDark,
          letterSpacing: -0.3,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimaryDark),
        systemOverlayStyle: const SystemUiOverlayStyle(
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
          side: BorderSide(
            color: AppColors.borderDark.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
      ),

      // Input
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        fillColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spacingMd,
          vertical: AppDimensions.spacingMd,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.inputBorderRadius),
          borderSide: BorderSide(
            color: AppColors.borderDark.withValues(alpha: 0.4),
            width: 0.5,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.inputBorderRadius),
          borderSide: BorderSide(
            color: AppColors.borderDark.withValues(alpha: 0.4),
            width: 0.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.inputBorderRadius),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        hintStyle: _body(14, FontWeight.w400, AppColors.textDisabledDark),
        labelStyle: _body(14, FontWeight.w500, AppColors.textSecondaryDark),
      ),

      // Chip (tags)
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.primary.withValues(alpha: 0.12),
        selectedColor: AppColors.primary.withValues(alpha: 0.25),
        labelStyle: _label(12, FontWeight.w500, AppColors.primaryLight),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
      dividerTheme: DividerThemeData(
        color: AppColors.borderDark.withValues(alpha: 0.5),
        thickness: 0.5,
        space: 0,
      ),

      // Text
      textTheme: _darkTextTheme(),

      // Floating action button
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
        ),
      ),

      // ElevatedButton
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          ),
          textStyle: _label(14, FontWeight.w600, AppColors.onPrimary),
        ),
      ),

      // TextButton
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryLight,
          textStyle: _label(14, FontWeight.w600, AppColors.primaryLight),
        ),
      ),

      // SnackBar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceVariantDark,
        contentTextStyle: _body(14, FontWeight.w400, AppColors.textPrimaryDark),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // Switch
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.secondary;
          }
          return AppColors.textDisabledDark;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.secondary.withValues(alpha: 0.3);
          }
          return AppColors.surfaceVariantDark;
        }),
      ),
    );
  }

  // ── Light Theme ───────────────────────────────────────────────────────────

  static ThemeData _buildLightTheme() {
    const colorScheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      secondary: AppColors.secondary,
      onSecondary: AppColors.onPrimary,
      tertiary: AppColors.tertiary,
      surface: AppColors.surfaceLight,
      onSurface: AppColors.textPrimaryLight,
      error: AppColors.error,
      onError: AppColors.onPrimary,
      outline: AppColors.borderLight,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.transparent,
      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: _headline(
          20,
          FontWeight.w700,
          AppColors.textPrimaryLight,
          letterSpacing: -0.3,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimaryLight),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarBrightness: Brightness.light,
          statusBarIconBrightness: Brightness.dark,
          statusBarColor: Colors.transparent,
        ),
      ),

      // Card
      cardTheme: CardThemeData(
        color: AppColors.surfaceLight,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          side: const BorderSide(color: AppColors.borderLight, width: 0.5),
        ),
      ),

      // Input
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        fillColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spacingMd,
          vertical: AppDimensions.spacingMd,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.inputBorderRadius),
          borderSide: BorderSide(
            color: AppColors.borderLight.withValues(alpha: 0.4),
            width: 0.5,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.inputBorderRadius),
          borderSide: BorderSide(
            color: AppColors.borderLight.withValues(alpha: 0.4),
            width: 0.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.inputBorderRadius),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        hintStyle: _body(14, FontWeight.w400, AppColors.textDisabledLight),
        labelStyle: _body(14, FontWeight.w500, AppColors.textSecondaryLight),
      ),

      // Chip (tags)
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.primary.withValues(alpha: 0.08),
        selectedColor: AppColors.primary.withValues(alpha: 0.15),
        labelStyle: _label(12, FontWeight.w500, AppColors.primary),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),

      // Bottom Sheet
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceLight,
        modalBackgroundColor: AppColors.surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppDimensions.bottomSheetRadius),
          ),
        ),
        showDragHandle: true,
        dragHandleColor: AppColors.borderLight,
      ),

      // Icon
      iconTheme: const IconThemeData(
        color: AppColors.textSecondaryLight,
        size: AppDimensions.iconMd,
      ),

      // Divider
      dividerTheme: DividerThemeData(
        color: AppColors.borderLight.withValues(alpha: 0.5),
        thickness: 0.5,
        space: 0,
      ),

      // Floating action button
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
        ),
      ),

      // ElevatedButton
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          ),
          textStyle: _label(14, FontWeight.w600, AppColors.onPrimary),
        ),
      ),

      // TextButton
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryLight,
          textStyle: _label(14, FontWeight.w600, AppColors.primaryLight),
        ),
      ),

      // SnackBar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceVariantLight,
        contentTextStyle:
            _body(14, FontWeight.w400, AppColors.textPrimaryLight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // Switch
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.secondary;
          }
          return AppColors.textDisabledLight;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.secondary.withValues(alpha: 0.3);
          }
          return AppColors.surfaceVariantLight;
        }),
      ),

      // Text
      textTheme: _lightTextTheme(),
    );
  }

  // ── Dark Text Theme ───────────────────────────────────────────────────────

  static TextTheme _darkTextTheme() {
    return TextTheme(
      displayLarge: _headline(32, FontWeight.w800, AppColors.textPrimaryDark),
      headlineMedium: _headline(
        24,
        FontWeight.w700,
        AppColors.textPrimaryDark,
        letterSpacing: -0.3,
      ),
      titleLarge: _headline(
        18,
        FontWeight.w700,
        AppColors.textPrimaryDark,
        letterSpacing: -0.2,
      ),
      titleMedium: _headline(
        16,
        FontWeight.w600,
        AppColors.textPrimaryDark,
        letterSpacing: 0,
      ),
      bodyLarge: _body(
        15,
        FontWeight.w400,
        AppColors.textPrimaryDark,
        height: 1.5,
      ),
      bodyMedium: _body(
        14,
        FontWeight.w400,
        AppColors.textSecondaryDark,
        height: 1.5,
      ),
      labelLarge: _label(
        14,
        FontWeight.w600,
        AppColors.textPrimaryDark,
        letterSpacing: 0.2,
      ),
      labelMedium: _label(
        12,
        FontWeight.w500,
        AppColors.textSecondaryDark,
        letterSpacing: 0.3,
      ),
      labelSmall: _label(
        11,
        FontWeight.w400,
        AppColors.textDisabledDark,
        letterSpacing: 0.4,
      ),
    );
  }

  // ── Light Text Theme ──────────────────────────────────────────────────────

  static TextTheme _lightTextTheme() {
    return TextTheme(
      displayLarge: _headline(32, FontWeight.w800, AppColors.textPrimaryLight),
      headlineMedium: _headline(
        24,
        FontWeight.w700,
        AppColors.textPrimaryLight,
        letterSpacing: -0.3,
      ),
      titleLarge: _headline(
        18,
        FontWeight.w700,
        AppColors.textPrimaryLight,
        letterSpacing: -0.2,
      ),
      titleMedium: _headline(
        16,
        FontWeight.w600,
        AppColors.textPrimaryLight,
        letterSpacing: 0,
      ),
      bodyLarge: _body(
        15,
        FontWeight.w400,
        AppColors.textPrimaryLight,
        height: 1.5,
      ),
      bodyMedium: _body(
        14,
        FontWeight.w400,
        AppColors.textSecondaryLight,
        height: 1.5,
      ),
      labelLarge: _label(
        14,
        FontWeight.w600,
        AppColors.textPrimaryLight,
        letterSpacing: 0.2,
      ),
      labelMedium: _label(
        12,
        FontWeight.w500,
        AppColors.textSecondaryLight,
        letterSpacing: 0.3,
      ),
      labelSmall: _label(
        11,
        FontWeight.w400,
        AppColors.textDisabledLight,
        letterSpacing: 0.4,
      ),
    );
  }
}
