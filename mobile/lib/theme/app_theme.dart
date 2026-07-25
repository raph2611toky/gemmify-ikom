import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  static const Color background = Color(0xFFFDFCFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF0C1238);
  static const Color textSecondary = Color(0xFF7C809F);
  static const Color border = Color(0xFFEDEAF5);
  static const Color accent = Color(0xFF5A22E8);
  static const Color accentDark = Color(0xFF4314D1);
  static const Color accentLight = Color(0xFF8A58FF);
  static const Color lavender = Color(0xFFF3EEFF);
  static const Color softLavender = Color(0xFFFAF8FF);
  static const Color error = Color(0xFFD84A4A);
  static const Color errorBackground = Color(0xFFFFEEEE);
  static const Color success = Color(0xFF20B96F);

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7B3CFF), Color(0xFF4A11DC)],
  );

  static const LinearGradient missionGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF8F5FF), Color(0xFFEDE6FF)],
  );

  static List<BoxShadow> get softShadow => const [
        BoxShadow(
          color: Color(0x120C1238),
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
        backgroundColor: background,
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
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        hintStyle: textTheme.bodyMedium?.copyWith(color: textSecondary),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: textPrimary,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: border,
      ),
    );
  }
}
