import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Primary greens
  static const Color green       = Color(0xFF1a7a3a);
  static const Color greenDark   = Color(0xFF145f2d);
  static const Color greenLight  = Color(0xFFe8f5ed);
  static const Color greenXLight = Color(0xFFf2faf5);

  // Background / surface
  static const Color bg          = Color(0xFFf8faf9);
  static const Color white       = Color(0xFFFFFFFF);
  static const Color border      = Color(0xFFd1d5db);
  static const Color borderLight = Color(0xFFe5e7eb);

  // Text
  static const Color textDark    = Color(0xFF1a2e1f);
  static const Color textMid     = Color(0xFF374151);
  static const Color textMuted   = Color(0xFF6b7280);

  // Semantic
  static const Color error       = Color(0xFFdc2626);
  static const Color errorLight  = Color(0xFFfee2e2);
  static const Color warning     = Color(0xFFd97706);
  static const Color warningLight= Color(0xFFfef3c7);

  // Badges
  static const Color badgeDraft    = Color(0xFFe0e7ff);
  static const Color badgeDraftTx  = Color(0xFF3730a3);
  static const Color badgeSubmit   = Color(0xFFd1fae5);
  static const Color badgeSubmitTx = Color(0xFF065f46);
  static const Color badgePending  = Color(0xFFfef3c7);
  static const Color badgePendTx   = Color(0xFF92400e);
}

class AppTextStyles {
  static TextStyle display({Color? color}) => GoogleFonts.outfit(
    fontSize: 26, fontWeight: FontWeight.w800,
    color: color ?? AppColors.textDark, letterSpacing: -0.3,
  );
  static TextStyle heading({Color? color}) => GoogleFonts.outfit(
    fontSize: 20, fontWeight: FontWeight.w700,
    color: color ?? AppColors.textDark,
  );
  static TextStyle subheading({Color? color}) => GoogleFonts.outfit(
    fontSize: 15, fontWeight: FontWeight.w700,
    color: color ?? AppColors.textMid,
  );
  static TextStyle body({Color? color}) => GoogleFonts.outfit(
    fontSize: 14, fontWeight: FontWeight.w400,
    color: color ?? AppColors.textMid,
  );
  static TextStyle bodyBold({Color? color}) => GoogleFonts.outfit(
    fontSize: 14, fontWeight: FontWeight.w600,
    color: color ?? AppColors.textDark,
  );
  static TextStyle caption({Color? color}) => GoogleFonts.outfit(
    fontSize: 12, fontWeight: FontWeight.w400,
    color: color ?? AppColors.textMuted,
  );
  static TextStyle label({Color? color}) => GoogleFonts.outfit(
    fontSize: 11, fontWeight: FontWeight.w700,
    color: color ?? AppColors.textMuted,
    letterSpacing: 0.8,
  );
  static TextStyle small({Color? color}) => GoogleFonts.outfit(
    fontSize: 13, fontWeight: FontWeight.w400,
    color: color ?? AppColors.textMid,
  );
  static TextStyle smallBold({Color? color}) => GoogleFonts.outfit(
    fontSize: 13, fontWeight: FontWeight.w600,
    color: color ?? AppColors.textDark,
  );
  static TextStyle number({Color? color}) => GoogleFonts.outfit(
    fontSize: 28, fontWeight: FontWeight.w800,
    color: color ?? AppColors.textDark,
  );
}

class AppTheme {
  static BoxDecoration cardDecoration({
    Color? bg,
    double radius = 14,
  }) => BoxDecoration(
    color: bg ?? AppColors.white,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: AppColors.borderLight, width: 1),
    boxShadow: [
      BoxShadow(
        color: AppColors.green.withOpacity(0.07),
        blurRadius: 12,
        offset: const Offset(0, 2),
      ),
    ],
  );

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: ColorScheme.light(
      primary: AppColors.green,
      onPrimary: AppColors.white,
      secondary: AppColors.greenLight,
      surface: AppColors.white,
      error: AppColors.error,
    ),
    textTheme: GoogleFonts.outfitTextTheme(),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.greenDark,
      foregroundColor: AppColors.white,
      elevation: 0,
      titleTextStyle: GoogleFonts.outfit(
        color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w700,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.green,
        foregroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        textStyle: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.green,
        side: const BorderSide(color: AppColors.green, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        textStyle: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.greenXLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: AppColors.border, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: AppColors.border, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: AppColors.green, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 13.5),
    ),
    dividerColor: AppColors.borderLight,
  );
}
