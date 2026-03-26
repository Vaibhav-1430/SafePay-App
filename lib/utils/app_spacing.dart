import 'package:flutter/material.dart';

/// 4pt grid spacing system for consistent layout across all screens.
class AppSpacing {
  AppSpacing._();

  // ── Base spacing values ──────────────────────────────────────────
  static const double xs   = 4;
  static const double sm   = 8;
  static const double md   = 12;
  static const double base = 16;
  static const double lg   = 20;
  static const double xl   = 24;
  static const double xxl  = 32;
  static const double xxxl = 40;
  static const double huge = 48;

  // ── Screen-level constants ───────────────────────────────────────
  static const EdgeInsets screenPadding =
      EdgeInsets.symmetric(horizontal: 20);
  static const EdgeInsets screenPaddingAll = EdgeInsets.all(20);
  static const EdgeInsets cardPadding = EdgeInsets.all(16);
  static const EdgeInsets cardPaddingLarge = EdgeInsets.all(20);

  // ── Vertical section gaps ────────────────────────────────────────
  static const SizedBox gapXs   = SizedBox(height: xs);
  static const SizedBox gapSm   = SizedBox(height: sm);
  static const SizedBox gapMd   = SizedBox(height: md);
  static const SizedBox gapBase = SizedBox(height: base);
  static const SizedBox gapLg   = SizedBox(height: lg);
  static const SizedBox gapXl   = SizedBox(height: xl);
  static const SizedBox gapXxl  = SizedBox(height: xxl);

  // ── Horizontal gaps ──────────────────────────────────────────────
  static const SizedBox hGapXs   = SizedBox(width: xs);
  static const SizedBox hGapSm   = SizedBox(width: sm);
  static const SizedBox hGapMd   = SizedBox(width: md);
  static const SizedBox hGapBase = SizedBox(width: base);
}

/// Consistent border-radius values – fintech-grade.
class AppRadius {
  AppRadius._();

  static const double xs   = 6;   // Status badges, tiny chips
  static const double sm   = 8;   // Small chips, inline badges
  static const double md   = 12;  // Input fields, small cards
  static const double lg   = 16;  // Standard cards
  static const double xl   = 20;  // Primary/large cards
  static const double full = 999; // Pill / circular
}
