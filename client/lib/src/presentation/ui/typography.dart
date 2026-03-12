import 'package:flutter/material.dart';

import 'package:application/src/presentation/ui/ui_config.dart';

class AppTypography {
  static const String _sansFamily = 'IBM Plex Sans';
  static const String _monoFamily = 'IBM Plex Mono';

  static TextStyle title({double size = 20, FontWeight weight = FontWeight.w700}) {
    return TextStyle(
      fontFamily: _sansFamily,
      fontSize: size,
      fontWeight: weight,
      color: AppColors.textPrimary,
    );
  }

  static TextStyle body({double size = 14, FontWeight weight = FontWeight.w400, Color? color}) {
    return TextStyle(
      fontFamily: _sansFamily,
      fontSize: size,
      fontWeight: weight,
      color: color ?? AppColors.textPrimary,
    );
  }

  static TextStyle mono({double size = 13, FontWeight weight = FontWeight.w500, Color? color}) {
    return TextStyle(
      fontFamily: _monoFamily,
      fontSize: size,
      fontWeight: weight,
      color: color ?? AppColors.textPrimary,
    );
  }
}
