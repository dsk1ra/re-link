import 'package:flutter/material.dart';

import 'package:application/src/presentation/ui/ui_config.dart';

/// Re:Link type scale. Two families, both bundled as assets:
/// Geist Mono is the voice (identity/data), Space Grotesk the body.
class AppTypography {
  static const String mono = 'Geist Mono';
  static const String sans = 'Space Grotesk';

  /// SAS verification code, pairing code — the app's one big-type moment.
  static const TextStyle displayData = TextStyle(
    fontFamily: mono,
    fontSize: 36,
    fontWeight: FontWeight.w600,
    letterSpacing: 36 * 0.08,
    color: AppColors.textPrimary,
  );

  /// Screen titles.
  static const TextStyle h1 = TextStyle(
    fontFamily: sans,
    fontSize: 28,
    fontWeight: FontWeight.w600,
    letterSpacing: 28 * -0.01,
    color: AppColors.textPrimary,
  );

  /// Section headings, card titles.
  static const TextStyle h2 = TextStyle(
    fontFamily: sans,
    fontSize: 20,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  /// Paragraphs, descriptions.
  static const TextStyle body = TextStyle(
    fontFamily: sans,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  /// Buttons, nav, form labels.
  static const TextStyle label = TextStyle(
    fontFamily: mono,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 13 * 0.02,
    color: AppColors.textPrimary,
  );

  /// UPPERCASE section labels with wide tracking.
  static const TextStyle eyebrow = TextStyle(
    fontFamily: mono,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 11 * 0.10,
    color: AppColors.textMuted,
  );

  /// IDs, fingerprints, hashes, URLs, JSON.
  static const TextStyle data = TextStyle(
    fontFamily: mono,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 14 * 0.02,
    color: AppColors.textPrimary,
  );

  /// Timestamps, status, meta.
  static const TextStyle caption = TextStyle(
    fontFamily: mono,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    letterSpacing: 11 * 0.04,
    color: AppColors.textMuted,
  );
}
