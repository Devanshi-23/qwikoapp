import 'package:flutter/material.dart';

import '../utils/app_colors.dart';

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// Screens stop growing past this width on tablets and the web.
  static const double maxContentWidth = 640;
}

abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
}

/// Display 24/800, title 18/800, subtitle 16/700, body 14/400,
/// caption 12/500, overline 10/700.
const TextTheme appTextTheme = TextTheme(
  headlineSmall: TextStyle(
    color: AppColors.textDark,
    fontSize: 24,
    fontWeight: FontWeight.w800,
  ),
  titleLarge: TextStyle(
    color: AppColors.textDark,
    fontSize: 18,
    fontWeight: FontWeight.w800,
  ),
  titleMedium: TextStyle(
    color: AppColors.textDark,
    fontSize: 16,
    fontWeight: FontWeight.w700,
  ),
  titleSmall: TextStyle(
    color: AppColors.textDark,
    fontSize: 14,
    fontWeight: FontWeight.w700,
  ),
  bodyLarge: TextStyle(color: AppColors.textDark, fontSize: 16),
  bodyMedium: TextStyle(color: AppColors.textDark, fontSize: 14),
  bodySmall: TextStyle(
    color: AppColors.textSecondary,
    fontSize: 12,
    fontWeight: FontWeight.w500,
  ),
  labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
  labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
  labelSmall: TextStyle(
    color: AppColors.textSecondary,
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
  ),
);

ThemeData buildAppTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    error: AppColors.error,
  ),
  useMaterial3: true,
  scaffoldBackgroundColor: AppColors.background,
  textTheme: appTextTheme,
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.white,
    foregroundColor: AppColors.textDark,
    elevation: 0,
    scrolledUnderElevation: 0.5,
    titleTextStyle: TextStyle(
      color: AppColors.textDark,
      fontSize: 18,
      fontWeight: FontWeight.w800,
    ),
  ),
  snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
);
