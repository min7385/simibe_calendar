import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  static ThemeData get light {
    final fontFamily = GoogleFonts.notoSansKr().fontFamily;
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: fontFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.personal,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: AppColors.white,
    );

    final textTheme = base.textTheme.apply(
      fontFamily: GoogleFonts.notoSansKr().fontFamily,
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.notoSansKr(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
      ),
    );
  }
}
