import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ────────────────────────────────────────────────────────────────────────────
// Color Palette
// ────────────────────────────────────────────────────────────────────────────
class VastraColors {
  VastraColors._();

  static const Color background = Color(0xFF080808);
  static const Color surface = Color(0xFF121212);
  static const Color surfaceElevated = Color(0xFF1C1C1C);
  static const Color deepPurple = Color(0xFF1A1A2E);

  static const Color purpleAccent = Color(0xFF7C3AED);
  static const Color purpleNeon = Color(0xFFA855F7);
  static const Color purpleGlow = Color(0xFF8B5CF6);
  static const Color purpleDim = Color(0xFF4C1D95);
  static const Color indigo = Color(0xFF6366F1);

  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color textMuted = Color(0xFF4B5563);

  static const Color border = Color(0xFF1F2937);
  static const Color borderLight = Color(0xFF374151);
}

// ────────────────────────────────────────────────────────────────────────────
// Theme
// ────────────────────────────────────────────────────────────────────────────
class VastraTheme {
  VastraTheme._();

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: VastraColors.background,
      colorScheme: const ColorScheme.dark(
        primary: VastraColors.purpleAccent,
        secondary: VastraColors.purpleNeon,
        surface: VastraColors.surface,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Colors.white,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
        displayLarge: GoogleFonts.spaceGrotesk(
          fontSize: 48,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: -1.5,
        ),
        displayMedium: GoogleFonts.spaceGrotesk(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: -1.0,
        ),
        headlineLarge: GoogleFonts.spaceGrotesk(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        headlineMedium: GoogleFonts.spaceGrotesk(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 16,
          color: VastraColors.textSecondary,
          height: 1.6,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          color: VastraColors.textSecondary,
          height: 1.5,
        ),
        labelLarge: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: VastraColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: VastraColors.surfaceElevated,
        contentTextStyle: GoogleFonts.inter(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Decorations ────────────────────────────────────────────────────────────

  /// Glassmorphism card decoration
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
              Colors.white.withOpacity(0.06),
              Colors.white.withOpacity(0.02),
            ],
      ),
      border: Border.all(
        color: borderColor ?? Colors.white.withOpacity(0.08),
        width: 1,
      ),
      boxShadow: shadows ??
          [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
    );
  }

  /// Neon glow decoration for selected / active states
  static BoxDecoration neonDecoration({
    double borderRadius = 20,
    Color glowColor = VastraColors.purpleAccent,
    double glowIntensity = 0.4,
    List<Color>? gradientColors,
  }) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: gradientColors ??
            [
              glowColor.withOpacity(0.12),
              glowColor.withOpacity(0.04),
            ],
      ),
      border: Border.all(
        color: glowColor.withOpacity(0.8),
        width: 1.5,
      ),
      boxShadow: [
        BoxShadow(
          color: glowColor.withOpacity(glowIntensity),
          blurRadius: 20,
          spreadRadius: 1,
        ),
        BoxShadow(
          color: glowColor.withOpacity(glowIntensity * 0.4),
          blurRadius: 40,
          spreadRadius: 4,
        ),
      ],
    );
  }

  // ── Gradients ──────────────────────────────────────────────────────────────

  static const LinearGradient purpleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF7C3AED),
      Color(0xFF6D28D9),
      Color(0xFF5B21B6),
    ],
  );

  static const LinearGradient deepGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF0F0A1E),
      Color(0xFF080808),
      Color(0xFF0A0010),
    ],
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF1C1C2E),
      Color(0xFF12121A),
    ],
  );
}
