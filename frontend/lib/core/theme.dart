import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ────────────────────────────────────────────────────────────────────────────
// Vastra Warm Luxury Color Palette
// ────────────────────────────────────────────────────────────────────────────
class VastraColors {
  VastraColors._();

  // ── Backgrounds ───────────────────────────────────────────────────────────
  static const Color background     = Color(0xFF0D0A08); // warm near-black
  static const Color surface        = Color(0xFF16120E); // warm dark brown-black
  static const Color surfaceElevated= Color(0xFF1F1A14); // elevated card
  static const Color surfaceCard    = Color(0xFF241E17); // card surface

  // ── Brand ─────────────────────────────────────────────────────────────────
  static const Color navy           = Color(0xFF1A1A2E); // deep navy from spec
  static const Color ivory          = Color(0xFFF5F0EB); // ivory from spec
  static const Color gold           = Color(0xFFE8A045); // gold accent from spec
  static const Color goldLight      = Color(0xFFF0BE7A); // lighter gold highlight
  static const Color goldDark       = Color(0xFFB87830); // darker gold shadow
  static const Color terracotta     = Color(0xFFC17A50); // warm terracotta
  static const Color warmGray       = Color(0xFFD4C5B0); // warm gray from spec
  static const Color warmGrayDark   = Color(0xFF8A7A6A); // muted warm gray

  // ── Text ──────────────────────────────────────────────────────────────────
  static const Color textPrimary    = Color(0xFFF5F0EB); // ivory for headings
  static const Color textSecondary  = Color(0xFFB8A898); // warm secondary text
  static const Color textMuted      = Color(0xFF6B5E52); // muted warm gray
  static const Color textOnGold     = Color(0xFF1A0E05); // dark text on gold bg

  // ── UI Elements ───────────────────────────────────────────────────────────
  static const Color border         = Color(0xFF2A2018); // warm dark border
  static const Color borderLight    = Color(0xFF3D3025); // slightly lighter border
  static const Color borderGold     = Color(0xFF5A4020); // gold-tinted border
  static const Color divider        = Color(0xFF251E16); // divider line
}

// ────────────────────────────────────────────────────────────────────────────
// Vastra Theme
// ────────────────────────────────────────────────────────────────────────────
class VastraTheme {
  VastraTheme._();

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: VastraColors.background,
      colorScheme: ColorScheme.dark(
        primary: VastraColors.gold,
        secondary: VastraColors.terracotta,
        surface: VastraColors.surface,
        onPrimary: VastraColors.textOnGold,
        onSecondary: VastraColors.textPrimary,
        onSurface: VastraColors.textPrimary,
        error: const Color(0xFFE07070),
      ),
      textTheme: _buildTextTheme(),
      appBarTheme: AppBarTheme(
        backgroundColor: VastraColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: VastraColors.ivory),
        titleTextStyle: GoogleFonts.playfairDisplay(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: VastraColors.ivory,
          letterSpacing: 0.3,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: VastraColors.surfaceElevated,
        contentTextStyle: GoogleFonts.dmSans(color: VastraColors.ivory),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: VastraColors.borderGold, width: 0.8),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static TextTheme _buildTextTheme() {
    return TextTheme(
      // Playfair Display for all display/headline text — editorial luxury feel
      displayLarge: GoogleFonts.playfairDisplay(
        fontSize: 48,
        fontWeight: FontWeight.w700,
        color: VastraColors.textPrimary,
        letterSpacing: -1.0,
        height: 1.15,
      ),
      displayMedium: GoogleFonts.playfairDisplay(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        color: VastraColors.textPrimary,
        letterSpacing: -0.5,
        height: 1.2,
      ),
      headlineLarge: GoogleFonts.playfairDisplay(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: VastraColors.textPrimary,
        height: 1.25,
      ),
      headlineMedium: GoogleFonts.playfairDisplay(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: VastraColors.textPrimary,
        height: 1.3,
      ),
      // DM Sans for body/label/UI text — clean and readable
      titleLarge: GoogleFonts.dmSans(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: VastraColors.textPrimary,
      ),
      titleMedium: GoogleFonts.dmSans(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: VastraColors.textPrimary,
      ),
      bodyLarge: GoogleFonts.dmSans(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: VastraColors.textSecondary,
        height: 1.65,
      ),
      bodyMedium: GoogleFonts.dmSans(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: VastraColors.textSecondary,
        height: 1.55,
      ),
      bodySmall: GoogleFonts.dmSans(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: VastraColors.textMuted,
        height: 1.5,
      ),
      labelLarge: GoogleFonts.dmSans(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: VastraColors.textPrimary,
        letterSpacing: 0.3,
      ),
      labelMedium: GoogleFonts.dmSans(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: VastraColors.warmGray,
        letterSpacing: 0.8,
      ),
      labelSmall: GoogleFonts.dmSans(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: VastraColors.textMuted,
        letterSpacing: 1.0,
      ),
    );
  }

  // ── Box Decorations ────────────────────────────────────────────────────────

  /// Warm glassmorphism card — the primary card style
  static BoxDecoration glassDecoration({
    double borderRadius = 20,
    Color? borderColor,
    List<Color>? gradientColors,
    List<BoxShadow>? shadows,
  }) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: gradientColors ??
            [
              VastraColors.ivory.withOpacity(0.05),
              VastraColors.ivory.withOpacity(0.02),
            ],
      ),
      border: Border.all(
        color: borderColor ?? VastraColors.borderLight.withOpacity(0.5),
        width: 1,
      ),
      boxShadow: shadows ??
          [
            BoxShadow(
              color: Colors.black.withOpacity(0.45),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
    );
  }

  /// Gold glow decoration — for selected/active states
  static BoxDecoration goldDecoration({
    double borderRadius = 20,
    double glowIntensity = 0.35,
    List<Color>? gradientColors,
  }) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: gradientColors ??
            [
              VastraColors.gold.withOpacity(0.14),
              VastraColors.terracotta.withOpacity(0.06),
            ],
      ),
      border: Border.all(
        color: VastraColors.gold.withOpacity(0.75),
        width: 1.5,
      ),
      boxShadow: [
        BoxShadow(
          color: VastraColors.gold.withOpacity(glowIntensity),
          blurRadius: 20,
          spreadRadius: 1,
        ),
        BoxShadow(
          color: VastraColors.gold.withOpacity(glowIntensity * 0.35),
          blurRadius: 40,
          spreadRadius: 4,
        ),
      ],
    );
  }

  /// Subtle warm surface decoration — for input fields, chips
  static BoxDecoration warmSurfaceDecoration({
    double borderRadius = 12,
    Color? color,
  }) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      color: color ?? VastraColors.surfaceCard,
      border: Border.all(
        color: VastraColors.borderLight,
        width: 0.8,
      ),
    );
  }

  // ── Gradients ──────────────────────────────────────────────────────────────

  /// Hero background gradient — warm dark from top to bottom
  static const LinearGradient deepGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF120E09),
      Color(0xFF0D0A08),
      Color(0xFF0A0806),
    ],
  );

  /// Gold accent gradient — for buttons, highlights, logo
  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFE8A045), // gold
      Color(0xFFCB7B30), // amber-gold
      Color(0xFFB86420), // deep bronze
    ],
  );

  /// Warm surface gradient — for elevated cards
  static const LinearGradient warmSurfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF241E17),
      Color(0xFF1A1510),
    ],
  );

  /// Terracotta accent gradient
  static const LinearGradient terracottaGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFC17A50),
      Color(0xFFA05E38),
    ],
  );
}
