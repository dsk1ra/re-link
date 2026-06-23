import 'package:flutter/material.dart';

import 'package:application/src/presentation/ui/radius.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';

/// App-wide Material theme derived from the Re:Link design DNA tokens.
/// Depth comes from borders and surface luminance steps — never shadows.
ThemeData buildAppTheme() {
  const colorScheme = ColorScheme.dark(
    primary: AppColors.action,
    onPrimary: AppColors.onAction,
    secondary: AppColors.info,
    onSecondary: AppColors.textPrimary,
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    error: AppColors.error,
    onError: AppColors.textPrimary,
    outline: AppColors.border,
  );

  OutlineInputBorder inputBorder(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.sm),
    borderSide: BorderSide(color: color),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.background,
    canvasColor: AppColors.background,
    splashFactory: InkRipple.splashFactory,
    dividerColor: AppColors.border,
    fontFamily: AppTypography.sans,
    textTheme: const TextTheme(
      displayMedium: AppTypography.displayData,
      titleLarge: AppTypography.h1,
      titleMedium: AppTypography.h2,
      bodyMedium: AppTypography.body,
      labelMedium: AppTypography.label,
      labelSmall: AppTypography.caption,
    ),
    iconTheme: const IconThemeData(color: AppColors.textMuted, size: 20),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      shape: Border(bottom: BorderSide(color: AppColors.border)),
      titleTextStyle: TextStyle(
        fontFamily: AppTypography.mono,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: 16 * 0.06,
        color: AppColors.textPrimary,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface2,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppColors.borderStrong),
      ),
      titleTextStyle: AppTypography.h2,
      contentTextStyle: AppTypography.body,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surface2,
      contentTextStyle: AppTypography.label,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppColors.borderStrong),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: inputBorder(AppColors.border),
      enabledBorder: inputBorder(AppColors.border),
      focusedBorder: inputBorder(AppColors.borderStrong),
      disabledBorder: inputBorder(AppColors.border),
      errorBorder: inputBorder(AppColors.error),
      focusedErrorBorder: inputBorder(AppColors.error),
      hintStyle: AppTypography.data.copyWith(color: AppColors.textFaint),
      labelStyle: AppTypography.label.copyWith(color: AppColors.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.action,
        foregroundColor: AppColors.onAction,
        disabledBackgroundColor: AppColors.surface2,
        disabledForegroundColor: AppColors.textFaint,
        elevation: 0,
        shadowColor: Colors.transparent,
        textStyle: AppTypography.label,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        disabledForegroundColor: AppColors.textFaint,
        side: const BorderSide(color: AppColors.borderStrong),
        textStyle: AppTypography.label,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.action,
        disabledForegroundColor: AppColors.textFaint,
        textStyle: AppTypography.label,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.action
            : AppColors.textMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.actionDim
            : AppColors.surface2,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(AppColors.borderStrong),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.action,
      linearTrackColor: AppColors.border,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.action,
      selectionColor: AppColors.infoDim,
      selectionHandleColor: AppColors.action,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.borderStrong),
      ),
      textStyle: AppTypography.caption.copyWith(color: AppColors.textPrimary),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
      },
    ),
    visualDensity: VisualDensity.standard,
  );
}
