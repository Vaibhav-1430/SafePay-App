import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_spacing.dart';

/// SafePay Design System v2.0 — Production Fintech Grade
///
/// Inspired by Stripe, Revolut, Google Pay.
/// Neutral dark grays, professional indigo primary, emerald trust green.
/// All colors WCAG AA compliant for dark backgrounds.
class AppTheme {
  AppTheme._();

  // ═══════════════════════════════════════════════════════════════════
  // BRAND COLORS — Professional Indigo
  // ═══════════════════════════════════════════════════════════════════
  static const Color primaryColor   = Color(0xFF4F46E5); // Indigo-600
  static const Color primaryLight   = Color(0xFF818CF8); // Indigo-400
  static const Color primaryDark    = Color(0xFF3730A3); // Indigo-800
  static const Color primarySurface = Color(0xFF1E1B4B); // Indigo-950

  // Secondary — Emerald (trust / financial success)
  static const Color secondaryColor = Color(0xFF10B981); // Emerald-500
  static const Color secondaryDark  = Color(0xFF059669); // Emerald-600
  static const Color secondaryLight = Color(0xFF34D399); // Emerald-400

  // Accent — Use sparingly
  static const Color accentPink   = Color(0xFFF43F5E); // Rose-500
  static const Color accentOrange = Color(0xFFF59E0B); // Amber-500

  // ═══════════════════════════════════════════════════════════════════
  // DARK THEME — Pure Neutral Gray (zero purple tint)
  // ═══════════════════════════════════════════════════════════════════
  static const Color darkBg          = Color(0xFF0A0A0F); // Deeper near-black
  static const Color darkSurface     = Color(0xFF111116); // Zinc-950
  static const Color darkCard        = Color(0xFF18181D); // Card background
  static const Color darkCardLight   = Color(0xFF1F1F24); // Hover/elevated
  static const Color darkDivider     = Color(0xFF27272D); // Subtle border
  static const Color darkElevated    = Color(0xFF1F1F24); // Elevated surfaces
  static const Color darkOverlay     = Color(0xFF2A2A30); // Modal overlays

  // ═══════════════════════════════════════════════════════════════════
  // LIGHT THEME COLORS
  // ═══════════════════════════════════════════════════════════════════
  static const Color lightBg      = Color(0xFFF8FAFC); // Slate-50
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard    = Color(0xFFF1F5F9); // Slate-100

  // ═══════════════════════════════════════════════════════════════════
  // STATUS COLORS (WCAG AA on dark backgrounds)
  // ═══════════════════════════════════════════════════════════════════
  static const Color successColor  = Color(0xFF10B981); // Emerald-500
  static const Color errorColor    = Color(0xFFEF4444); // Red-500
  static const Color warningColor  = Color(0xFFF59E0B); // Amber-500
  static const Color pendingColor  = Color(0xFFF97316); // Orange-500
  static const Color infoColor     = Color(0xFF3B82F6); // Blue-500

  // ═══════════════════════════════════════════════════════════════════
  // TEXT COLORS — 4-level hierarchy
  // ═══════════════════════════════════════════════════════════════════
  static const Color textPrimary   = Color(0xFFF4F4F5); // Zinc-100
  static const Color textSecondary = Color(0xFFA1A1AA); // Zinc-400
  static const Color textMuted     = Color(0xFF71717A); // Zinc-500
  static const Color textDisabled  = Color(0xFF52525B); // Zinc-600

  // ═══════════════════════════════════════════════════════════════════
  // ELEVATION SHADOWS — Subtle, layered, no glow
  // ═══════════════════════════════════════════════════════════════════
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.12),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.06),
      blurRadius: 2,
      offset: const Offset(0, 1),
    ),
  ];

  static List<BoxShadow> get elevatedShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.20),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.08),
      blurRadius: 4,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get dropdownShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.30),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  // ═══════════════════════════════════════════════════════════════════
  // ANIMATION DURATIONS
  // ═══════════════════════════════════════════════════════════════════
  static const Duration fast    = Duration(milliseconds: 150);
  static const Duration normal  = Duration(milliseconds: 250);
  static const Duration slow    = Duration(milliseconds: 400);
  static const Duration slower  = Duration(milliseconds: 600);

  // ═══════════════════════════════════════════════════════════════════
  // DARK THEME
  // ═══════════════════════════════════════════════════════════════════
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: darkBg,
    colorScheme: const ColorScheme.dark(
      primary: primaryColor,
      secondary: secondaryColor,
      surface: darkSurface,
      error: errorColor,
    ),
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
    appBarTheme: AppBarTheme(
      backgroundColor: darkBg,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: darkSurface,
      ),
      iconTheme: const IconThemeData(color: textPrimary, size: 20),
      titleTextStyle: GoogleFonts.inter(
        color: textPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
    ),
    cardTheme: CardThemeData(
      color: darkCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: darkDivider, width: 1),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        textStyle: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: textPrimary,
        side: const BorderSide(color: darkDivider, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        textStyle: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryColor,
        textStyle: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkCard,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: darkDivider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: darkDivider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: primaryColor, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: errorColor, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: errorColor, width: 1.5),
      ),
      labelStyle: const TextStyle(color: textSecondary, fontSize: 14),
      hintStyle: const TextStyle(color: textDisabled, fontSize: 14),
      floatingLabelStyle: const TextStyle(color: primaryColor, fontSize: 13),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: darkSurface,
      selectedItemColor: primaryColor,
      unselectedItemColor: textMuted,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: darkSurface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: primaryColor.withValues(alpha: 0.12),
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: primaryColor,
          );
        }
        return GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: textMuted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: primaryColor, size: 22);
        }
        return const IconThemeData(color: textMuted, size: 22);
      }),
    ),
    dividerTheme: const DividerThemeData(
      color: darkDivider,
      thickness: 1,
      space: 0,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: darkCard,
      side: const BorderSide(color: darkDivider),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      labelStyle: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: textSecondary,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: darkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      titleTextStyle: GoogleFonts.inter(
        color: textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: GoogleFonts.inter(
        color: textSecondary,
        fontSize: 14,
        height: 1.5,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    ),
    // Page transitions
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );

  // ═══════════════════════════════════════════════════════════════════
  // LIGHT THEME
  // ═══════════════════════════════════════════════════════════════════
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: lightBg,
    colorScheme: const ColorScheme.light(
      primary: primaryColor,
      secondary: secondaryColor,
      surface: lightSurface,
      error: errorColor,
    ),
    textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
    appBarTheme: AppBarTheme(
      backgroundColor: lightSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: GoogleFonts.inter(
        color: const Color(0xFF18181B),
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
    ),
  );
}
