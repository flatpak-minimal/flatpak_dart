// lib/theme/app_theme.dart
//
// Dark industrial theme: near-black backgrounds, sharp hairline separators,
// teal action accent, amber warning accent, JetBrains Mono for all refs/URLs.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppTheme {
  // ── Palette ───────────────────────────────────────────────────────────
  static const bg0 = Color(0xFF0C0C0F); // page background
  static const bg1 = Color(0xFF13131A); // card / panel
  static const bg2 = Color(0xFF1C1C26); // elevated surface
  static const bg3 = Color(0xFF252533); // hover / selected row

  static const teal = Color(0xFF00C6A2); // primary action
  static const tealDim = Color(0xFF007A64); // teal inactive
  static const amber = Color(0xFFFFB020); // warning / destructive
  static const amberDim = Color(0xFF7A5410); // amber inactive

  static const fg0 = Color(0xFFE8E8F0); // primary text
  static const fg1 = Color(0xFF9A9AB0); // secondary text
  static const fg2 = Color(0xFF5A5A72); // tertiary / hint

  static const divider = Color(0xFF252532);
  static const border = Color(0xFF2E2E3E);

  // ── Typography ────────────────────────────────────────────────────────
  static TextStyle mono({
    double size = 13,
    Color color = fg0,
    FontWeight weight = FontWeight.w400,
  }) => TextStyle(
    fontFamily: 'JetBrainsMono',
    fontSize: size,
    color: color,
    fontWeight: weight,
    letterSpacing: -0.2,
  );

  static TextStyle ui({
    double size = 13,
    Color color = fg0,
    FontWeight weight = FontWeight.w400,
  }) => GoogleFonts.dmSans(
    fontSize: size,
    color: color,
    fontWeight: weight,
    letterSpacing: -0.1,
  );

  // ── ThemeData ─────────────────────────────────────────────────────────
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg0,
    colorScheme: const ColorScheme.dark(
      surface: bg1,
      surfaceContainer: bg2,
      primary: teal,
      secondary: amber,
      onPrimary: Color(0xFF001A14),
      onSecondary: Color(0xFF1A0E00),
      onSurface: fg0,
      outline: border,
      error: Color(0xFFFF5252),
    ),
    cardTheme: const CardThemeData(
      color: bg1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        side: BorderSide(color: border, width: 0.5),
      ),
      margin: EdgeInsets.zero,
      elevation: 0,
    ),
    dividerTheme: const DividerThemeData(
      color: divider,
      thickness: 0.5,
      space: 0,
    ),
    textTheme: GoogleFonts.dmSansTextTheme(ThemeData.dark().textTheme).copyWith(
      bodyMedium: GoogleFonts.dmSans(color: fg0, fontSize: 13),
      bodySmall: GoogleFonts.dmSans(color: fg1, fontSize: 11),
      labelSmall: GoogleFonts.dmSans(
        color: fg2,
        fontSize: 10,
        letterSpacing: 0.8,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: bg2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: border, width: 0.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: border, width: 0.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: teal, width: 1),
      ),
      hintStyle: GoogleFonts.dmSans(color: fg2, fontSize: 13),
      labelStyle: GoogleFonts.dmSans(color: fg1, fontSize: 12),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: teal,
        foregroundColor: const Color(0xFF001A14),
        textStyle: GoogleFonts.dmSans(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: fg1,
        side: const BorderSide(color: border, width: 0.5),
        textStyle: GoogleFonts.dmSans(fontSize: 13),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: bg2,
      selectedColor: teal.withValues(alpha: 0.15),
      labelStyle: GoogleFonts.dmSans(fontSize: 11, color: fg1),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(3),
        side: const BorderSide(color: border, width: 0.5),
      ),
    ),
    scrollbarTheme: const ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(Color(0xFF3A3A50)),
      radius: Radius.circular(2),
      thickness: WidgetStatePropertyAll(3),
    ),
  );
}
