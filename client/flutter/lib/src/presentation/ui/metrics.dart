import 'package:flutter/material.dart';

class AppUiMetrics {
  static const double appBarTitleFontSize = 16;
  static const double badgeFontSize = 11;
  static const double badgeBorderRadius = 2;
  static const EdgeInsets badgePadding = EdgeInsets.symmetric(
    horizontal: 10,
    vertical: 5,
  );
  static const double badgeDotSize = 7;
  static const double badgeDotGap = 8;
  static const double disconnectedIconSize = 56;

  /// Wide layouts (launcher, session screens).
  static const double maxContentWidth = 900;

  /// Single-column forms (welcome, join, server config).
  static const double formWidth = 520;

  /// Icons: Lucide, 20px grid.
  static const double iconSize = 20;

  /// Decorative dot grid: 32px pitch (4px base unit), dots matching the
  /// 1.5px Lucide stroke weight, anchored top-left.
  static const double dotGridPitch = 32;
  static const double dotGridDotSize = 1.5;
}
