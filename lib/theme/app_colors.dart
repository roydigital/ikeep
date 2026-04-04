import 'package:flutter/material.dart';

/// All color tokens for Ikeep — Vibrant design system.
class AppColors {
  AppColors._();

  // ── Brand ─────────────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF6C5CE7); // Electric Purple
  static const Color primaryLight = Color(0xFFA29BFE); // Soft Lavender
  static const Color primaryDark = Color(0xFF4834D4); // Deep Purple
  static const Color onPrimary = Color(0xFFFFFFFF);

  // ── Accent Colors ─────────────────────────────────────────────────────────
  static const Color secondary = Color(0xFF00CEC9); // Vibrant Teal
  static const Color tertiary = Color(0xFFFD79A8); // Coral Pink
  static const Color accentYellow = Color(0xFFFFEAA7); // Warm Gold

  // ── Dark Background Layers ────────────────────────────────────────────────
  static const Color backgroundDark = Color(0xFF0F0B1E); // Deep Space
  static const Color surfaceDark = Color(0xFF1A1530); // Card surface
  static const Color surfaceVariantDark = Color(0xFF252040); // Elevated card
  static const Color borderDark = Color(0xFF3D3560); // Subtle border
  static const Color accentSurfaceDark = Color(0xFF241359); // Tinted chips
  static const Color accentSurfaceDarkStrong = Color(0xFF32206F);

  // ── Light Background Layers ───────────────────────────────────────────────
  static const Color backgroundLight = Color(0xFFF5F3FF);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceVariantLight = Color(0xFFEDE8F5);
  static const Color borderLight = Color(0xFFDCD6EB);
  static const Color surface = surfaceLight;

  // ── Text ─────────────────────────────────────────────────────────────────
  static const Color textPrimaryDark = Color(0xFFF0ECFF);
  static const Color textSecondaryDark = Color(0xFFBDB4DB);
  static const Color textDisabledDark = Color(0xFF7A6FA8);

  static const Color textPrimaryLight = Color(0xFF141221);
  static const Color textSecondaryLight = Color(0xFF5F597A);
  static const Color textDisabledLight = Color(0xFFA59FB5);
  static const Color textFaded = textSecondaryLight;

  // ── Semantic ──────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF00B894); // Mint Green
  static const Color warning = Color(0xFFFDCB6E); // Warm Amber
  static const Color error = Color(0xFFFF6B6B); // Soft Red
  static const Color info = Color(0xFF74B9FF); // Sky Blue

  // ── Gradient Definitions ──────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient pinkGoldGradient = LinearGradient(
    colors: [tertiary, accentYellow],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient tealGreenGradient = LinearGradient(
    colors: [secondary, success],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient purplePinkGradient = LinearGradient(
    colors: [primary, tertiary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient surfaceGradientDark = LinearGradient(
    colors: [Color(0xFF1A1530), Color(0xFF15102A)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ── Tag chip colors ───────────────────────────────────────────────────────
  static const List<Color> tagColors = [
    Color(0xFF6C5CE7), // Electric Purple
    Color(0xFF00CEC9), // Vibrant Teal
    Color(0xFFFD79A8), // Coral Pink
    Color(0xFFFFEAA7), // Warm Gold
    Color(0xFF00B894), // Mint Green
    Color(0xFF74B9FF), // Sky Blue
  ];

  // ── Glow shadows ──────────────────────────────────────────────────────────
  static List<BoxShadow> primaryGlow({double opacity = 0.4, double blur = 20}) {
    return [
      BoxShadow(
        color: primary.withValues(alpha: opacity),
        blurRadius: blur,
        spreadRadius: 0,
      ),
    ];
  }

  static List<BoxShadow> tealGlow({double opacity = 0.3, double blur = 16}) {
    return [
      BoxShadow(
        color: secondary.withValues(alpha: opacity),
        blurRadius: blur,
        spreadRadius: 0,
      ),
    ];
  }

  static List<BoxShadow> gradientGlow({double opacity = 0.35, double blur = 24}) {
    return [
      BoxShadow(
        color: primary.withValues(alpha: opacity),
        blurRadius: blur,
        spreadRadius: 0,
        offset: const Offset(-4, 0),
      ),
      BoxShadow(
        color: secondary.withValues(alpha: opacity * 0.7),
        blurRadius: blur,
        spreadRadius: 0,
        offset: const Offset(4, 0),
      ),
    ];
  }
}
