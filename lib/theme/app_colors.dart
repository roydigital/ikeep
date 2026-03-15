import 'package:flutter/material.dart';

/// All color tokens for Ikeep. Dark-first palette with cool indigo accent.
class AppColors {
  AppColors._();

  // ── Brand ─────────────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF5B7CF6);       // Indigo blue
  static const Color primaryLight = Color(0xFF8FA5F8);  // Lighter indigo
  static const Color primaryDark = Color(0xFF3A5BE0);   // Darker indigo
  static const Color onPrimary = Color(0xFFFFFFFF);

  // ── Dark Background Layers ────────────────────────────────────────────────
  static const Color backgroundDark = Color(0xFF0C0C14);     // App background
  static const Color surfaceDark = Color(0xFF14141F);        // Cards, sheets
  static const Color surfaceVariantDark = Color(0xFF1C1C2A); // Elevated cards
  static const Color borderDark = Color(0xFF2A2A3C);         // Subtle borders

  // ── Light Background Layers ───────────────────────────────────────────────
  static const Color backgroundLight = Color(0xFFF4F6FF);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceVariantLight = Color(0xFFEEF0FF);
  static const Color borderLight = Color(0xFFDDE1F5);

  // ── Text ─────────────────────────────────────────────────────────────────
  static const Color textPrimaryDark = Color(0xFFE8E8F2);
  static const Color textSecondaryDark = Color(0xFF8080A8);
  static const Color textDisabledDark = Color(0xFF44445A);

  static const Color textPrimaryLight = Color(0xFF12121E);
  static const Color textSecondaryLight = Color(0xFF5A5A78);
  static const Color textDisabledLight = Color(0xFFAAAAAC);

  // ── Semantic ──────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF4BBFA0);   // Found it / confirmed
  static const Color warning = Color(0xFFF5A623);   // Expiry warning
  static const Color error = Color(0xFFE85757);     // Error states
  static const Color info = Color(0xFF5B9CF6);      // Info / sync

  // ── Tag chip colors ───────────────────────────────────────────────────────
  static const List<Color> tagColors = [
    Color(0xFF5B7CF6),
    Color(0xFF4BBFA0),
    Color(0xFFF5A623),
    Color(0xFFE85757),
    Color(0xFFB565D9),
    Color(0xFF4DAAEF),
  ];
}
