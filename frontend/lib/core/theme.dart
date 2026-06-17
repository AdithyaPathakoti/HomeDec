import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ────────────────────────────────────────────────────────────────────────────
// Vastra Monochrome Shadcn/UI Color Palette
// ────────────────────────────────────────────────────────────────────────────
class VastraColors {
  VastraColors._();

  // ── Backgrounds ───────────────────────────────────────────────────────────
  static const Color background     = Color(0xFF09090B); // zinc-950
  static const Color surface        = Color(0xFF09090B); // zinc-950
  static const Color surfaceElevated= Color(0xFF18181B); // zinc-900
  static const Color surfaceCard    = Color(0xFF18181B); // zinc-900

  // ── Brand (Monochrome compatibility mappings) ─────────────────────────────
  static const Color navy           = Color(0xFF18181B); 
  static const Color ivory          = Color(0xFFFAFAFA); // zinc-50
  static const Color gold           = Color(0xFFFAFAFA); // primary brand color (crisp white)
  static const Color goldLight      = Color(0xFFFAFAFA); 
  static const Color goldDark       = Color(0xFF18181B); 
  static const Color terracotta     = Color(0xFFE4E4E7); // zinc-200
  static const Color warmGray       = Color(0xFFD4D4D8); // zinc-300
  static const Color warmGrayDark   = Color(0xFF71717A); // zinc-500

  // ── Text ──────────────────────────────────────────────────────────────────
  static const Color textPrimary    = Color(0xFFFAFAFA); // zinc-50
  static const Color textSecondary  = Color(0xFFA1A1AA); // zinc-400
  static const Color textMuted      = Color(0xFF71717A); // zinc-500
  static const Color textOnGold     = Color(0xFF09090B); // dark text on white bg

  // ── UI Elements ───────────────────────────────────────────────────────────
  static const Color border         = Color(0xFF27272A); // zinc-800
  static const Color borderLight    = Color(0xFF27272A); // zinc-800
  static const Color borderGold     = Color(0xFF27272A); // zinc-800
  static const Color divider        = Color(0xFF27272A); // zinc-800
}

// ────────────────────────────────────────────────────────────────────────────
// Vastra Shadcn/UI Theme
// ────────────────────────────────────────────────────────────────────────────
class VastraTheme {
  VastraTheme._();

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: VastraColors.background,
      colorScheme: const ColorScheme.dark(
        primary: VastraColors.gold,
        secondary: VastraColors.terracotta,
        surface: VastraColors.surface,
        onPrimary: VastraColors.textOnGold,
        onSecondary: VastraColors.textPrimary,
        onSurface: VastraColors.textPrimary,
        error: Color(0xFFEF4444), // zinc destructive red
      ),
      textTheme: _buildTextTheme(),
      appBarTheme: AppBarTheme(
        backgroundColor: VastraColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: VastraColors.ivory),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: VastraColors.ivory,
          letterSpacing: -0.3,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: VastraColors.surfaceElevated,
        contentTextStyle: GoogleFonts.inter(color: VastraColors.ivory),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: VastraColors.border, width: 1.0),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static TextTheme _buildTextTheme() {
    return TextTheme(
      displayLarge: GoogleFonts.inter(
        fontSize: 42,
        fontWeight: FontWeight.w800,
        color: VastraColors.textPrimary,
        letterSpacing: -1.0,
        height: 1.15,
      ),
      displayMedium: GoogleFonts.inter(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: VastraColors.textPrimary,
        letterSpacing: -0.8,
        height: 1.2,
      ),
      headlineLarge: GoogleFonts.inter(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: VastraColors.textPrimary,
        letterSpacing: -0.5,
        height: 1.25,
      ),
      headlineMedium: GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: VastraColors.textPrimary,
        letterSpacing: -0.4,
        height: 1.3,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: VastraColors.textPrimary,
        letterSpacing: -0.2,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: VastraColors.textPrimary,
        letterSpacing: -0.1,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: VastraColors.textSecondary,
        height: 1.6,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: VastraColors.textSecondary,
        height: 1.5,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: VastraColors.textMuted,
        height: 1.4,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: VastraColors.textPrimary,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: VastraColors.warmGray,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 9,
        fontWeight: FontWeight.w500,
        color: VastraColors.textMuted,
        letterSpacing: 0.5,
      ),
    );
  }

  // ── Box Decorations ────────────────────────────────────────────────────────

  /// Shadcn styled card decoration
  static BoxDecoration glassDecoration({
    double borderRadius = 12,
    Color? borderColor,
    List<Color>? gradientColors,
    List<BoxShadow>? shadows,
  }) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: gradientColors ?? const [
          Color(0xFF1E1E24), // zinc-900 slightly lighter
          Color(0xFF0F0F11), // zinc-950 slightly darker
        ],
      ),
      border: Border.all(
        color: borderColor ?? VastraColors.border,
        width: 1,
      ),
      boxShadow: shadows ?? [
        BoxShadow(
          color: Colors.black.withOpacity(0.45),
          blurRadius: 10,
          spreadRadius: 0,
          offset: const Offset(0, 4),
        )
      ],
    );
  }

  /// Selected / Active state card decoration
  static BoxDecoration goldDecoration({
    double borderRadius = 12,
    double glowIntensity = 0.0,
    List<Color>? gradientColors,
  }) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: gradientColors ?? const [
          Color(0xFFFAFAFA),
          Color(0xFFE4E4E7),
        ],
      ),
      border: Border.all(
        color: VastraColors.textPrimary,
        width: 1.5,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.white.withOpacity(0.12),
          blurRadius: 8,
          spreadRadius: 0,
          offset: const Offset(0, 2),
        )
      ],
    );
  }

  /// Subtle surface decoration — for inputs, chips
  static BoxDecoration warmSurfaceDecoration({
    double borderRadius = 12,
    Color? color,
  }) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color ?? VastraColors.surfaceCard,
          const Color(0xFF0F0F11),
        ],
      ),
      border: Border.all(
        color: VastraColors.border,
        width: 1.0,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.25),
          blurRadius: 4,
          offset: const Offset(0, 2),
        )
      ],
    );
  }

  // ── Gradients ──────────────────────────────────────────────────────────────

  /// Hero background - flat zinc-950 color simulation
  static const LinearGradient deepGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF09090B),
      Color(0xFF09090B),
    ],
  );

  /// Shadcn primary action gradient (solid white)
  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFAFAFA),
      Color(0xFFFAFAFA),
    ],
  );

  /// Standard surface fill
  static const LinearGradient warmSurfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF18181B),
      Color(0xFF18181B),
    ],
  );

  /// Secondary action gradient
  static const LinearGradient terracottaGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF27272A),
      Color(0xFF27272A),
    ],
  );
}
