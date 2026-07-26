import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  // Palette reprise des maquettes Gemma Edu / Mpanabe AI.
  static const Color background = Color(0xFFFCFBFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF0B1038);
  static const Color textSecondary = Color(0xFF747998);
  static const Color border = Color(0xFFE8E3F4);
  static const Color accent = Color(0xFF5B22F2);
  static const Color accentDark = Color(0xFF4312D9);
  static const Color accentLight = Color(0xFF8B5BFF);
  static const Color lavender = Color(0xFFF1EBFF);
  static const Color softLavender = Color(0xFFFAF8FF);
  static const Color success = Color(0xFF19B84B);
  static const Color successBackground = Color(0xFFF0FFF4);
  static const Color warning = Color(0xFFFFA800);
  static const Color error = Color(0xFFEF233C);
  static const Color errorBackground = Color(0xFFFFF1F3);

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7A39FF), Color(0xFF4A12DD)],
  );


  static const LinearGradient missionGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF7F3FF), Color(0xFFEDE5FF)],
  );

  static const LinearGradient pageGlow = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFDFBFF), Color(0xFFF8F4FF)],
  );

  static List<BoxShadow> get softShadow => const [
        BoxShadow(
          color: Color(0x120B1038),
          blurRadius: 24,
          offset: Offset(0, 10),
        ),
      ];

  static ThemeData get theme {
    final base = ThemeData.light(useMaterial3: true);
    final textTheme = GoogleFonts.nunitoTextTheme(base.textTheme).apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
    );

    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      colorScheme: base.colorScheme.copyWith(
        primary: accent,
        secondary: accentLight,
        surface: surface,
        error: error,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 13,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(color: textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: accent, width: 1.6),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: textPrimary,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: border,
      ),
    );
  }
}
