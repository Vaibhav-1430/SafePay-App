import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';

/// 5-level type hierarchy for consistent text rendering.
///
/// Level 1: [balanceDisplay] – the big balance ₹ number
/// Level 2: [headline]       – screen titles / section titles
/// Level 3: [title]          – card titles, names
/// Level 4: [body]           – descriptions, secondary text
/// Level 5: [caption]        – timestamps, metadata, small labels
class AppTypography {
  AppTypography._();

  // ── Level 1: Balance Display ────────────────────────────────────
  static TextStyle balanceDisplay = GoogleFonts.inter(
    fontSize: 38,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.5,
    color: AppTheme.textPrimary,
    height: 1.1,
  );

  // ── Level 1b: Amount Display (success/payment screens) ──────────
  static TextStyle amountDisplay = GoogleFonts.inter(
    fontSize: 42,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.5,
    color: AppTheme.successColor,
    height: 1.1,
  );

  // ── Level 2: Headline (screen / section titles) ─────────────────
  static TextStyle headline = GoogleFonts.inter(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: AppTheme.textPrimary,
    height: 1.3,
  );

  static TextStyle headlineLarge = GoogleFonts.inter(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: AppTheme.textPrimary,
    height: 1.2,
  );

  // ── Level 3: Title (card titles, names, labels) ─────────────────
  static TextStyle title = GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppTheme.textPrimary,
    height: 1.4,
  );

  static TextStyle titleSmall = GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: AppTheme.textPrimary,
    height: 1.4,
  );

  // ── Level 4: Body (descriptions, secondary info) ────────────────
  static TextStyle body = GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppTheme.textSecondary,
    height: 1.5,
  );

  static TextStyle bodyMedium = GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppTheme.textSecondary,
    height: 1.4,
  );

  // ── Level 5: Caption (timestamps, metadata) ─────────────────────
  static TextStyle caption = GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppTheme.textMuted,
    letterSpacing: 0.2,
    height: 1.4,
  );

  static TextStyle captionSmall = GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppTheme.textMuted,
    height: 1.3,
  );

  // ── Special: Amounts ────────────────────────────────────────────
  static TextStyle amountSent = GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppTheme.errorColor,
  );

  static TextStyle amountReceived = GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppTheme.successColor,
  );

  // ── Overline (section labels like "SEND TO") ────────────────────
  static TextStyle overline = GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
    color: AppTheme.textMuted,
    height: 1.3,
  );

  // ── Button Text ─────────────────────────────────────────────────
  static TextStyle button = GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    letterSpacing: -0.1,
  );

  static TextStyle buttonSmall = GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );

  // ── Label (form labels, tags) ───────────────────────────────────
  static TextStyle label = GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppTheme.textMuted,
    height: 1.4,
  );

  // ── Tabular Figures (for PIN, OTP, timers) ──────────────────────
  static TextStyle tabular = GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: AppTheme.textPrimary,
    fontFeatures: [const FontFeature.tabularFigures()],
  );
}
