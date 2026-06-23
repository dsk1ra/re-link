import 'package:flutter/material.dart';

/// Re:Link design DNA palette. Canonical values live in the relink-design-dna
/// skill; never introduce colours here that are not recorded there.
class AppColors {
  // Foundations — warm-tinted greys, never pure neutral.
  static const Color background = Color(0xFF201E1B);
  static const Color surface = Color(0xFF2A2723);
  static const Color surface2 = Color(0xFF353129);
  static const Color border = Color(0xFF2E2B26);
  static const Color borderStrong = Color(0xFF423D35);
  static const Color textPrimary = Color(0xFFECE9E2);
  static const Color textMuted = Color(0xFF8C877C);
  static const Color textFaint = Color(0xFF5E5A52);

  // Brand accents. Orange carries personality; blue marks technical metadata
  // and passive selection, never a primary CTA.
  static const Color action = Color(0xFFE06C2A);
  static const Color actionDim = Color(0xFF8F4516);
  static const Color info = Color(0xFF5B84AD);
  static const Color infoDim = Color(0xFF36506C);
  static const Color onAction = Color(0xFF201E1B);

  // Status triad — status indicators ONLY (dots, badges, status text,
  // countdowns). Never on buttons, fills, surfaces, or decoration.
  static const Color ok = Color(0xFF4CAF6E);
  static const Color warn = Color(0xFFD9A440);
  static const Color error = Color(0xFFD95757);
}

class UiConfig {
  static const EdgeInsets pagePadding = EdgeInsets.all(16);
}
