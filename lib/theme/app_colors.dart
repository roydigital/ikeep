import 'package:flutter/material.dart';

/// All color tokens for Ikeep. Automatically themed from the app logo.
class AppColors {
  AppColors._();

  // ── Brand ─────────────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF4E1FB4);       // Deep purple
  static const Color primaryLight = Color(0xFF865ED4);  // Lighter purple
  static const Color primaryDark = Color(0xFF330B8A);   // Darker purple
  static const Color onPrimary = Color(0xFFFFFFFF);

  // ── Dark Background Layers ────────────────────────────────────────────────
  // Derived from logo's darkest colors
  static const Color backgroundDark = Color(0xFF040124);     // App background
  static const Color surfaceDark = Color(0xFF0D0A2C);        // Cards, sheets
  static const Color surfaceVariantDark = Color(0xFF161235); // Elevated cards
  static const Color borderDark = Color(0xFF221E42);         // Subtle borders

  // ── Light Background Layers ───────────────────────────────────────────────
  // Derived from logo's lightest background colors
  static const Color backgroundLight = Color(0xFFF7F5FC);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceVariantLight = Color(0xFFEBE6F5);
  static const Color borderLight = Color(0xFFDCD6EB);

  // ── Text ─────────────────────────────────────────────────────────────────
  static const Color textPrimaryDark = Color(0xFFE9E5F8);
  static const Color textSecondaryDark = Color(0xFF9891B8);
  static const Color textDisabledDark = Color(0xFF554D7A);

  static const Color textPrimaryLight = Color(0xFF141221);
  static const Color textSecondaryLight = Color(0xFF5F597A);
  static const Color textDisabledLight = Color(0xFFA59FB5);

  // ── Semantic ──────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF4BBFA0);   // Found it / confirmed
  static const Color warning = Color(0xFFF5A623);   // Expiry warning
  static const Color error = Color(0xFFE85757);     // Error states
  static const Color info = Color(0xFF5B9CF6);      // Info / sync

  // ── Tag chip colors ───────────────────────────────────────────────────────
  static const List<Color> tagColors = [
    Color(0xFF4E1FB4),
    Color(0xFF4BBFA0),
    Color(0xFFF5A623),
    Color(0xFFE85757),
    Color(0xFFB565D9),
    Color(0xFF4DAAEF),
  ];
}
