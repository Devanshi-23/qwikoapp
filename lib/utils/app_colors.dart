import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF0C7634);
  static const Color accent = Color(0xFF64BA0F);

  /// Gradient end for surfaces that carry white text; [accent] is too light
  /// (about 2.5:1) for that.
  static const Color accentDark = Color(0xFF357A0B);
  static const Color primaryLight = Color(0xFFEAF6EE);
  static const Color inputFill = Color(0xFFF6FBF7);

  static const Color textDark = Color(0xFF172033);

  /// Small secondary text; about 5.4:1 on white.
  static const Color textSecondary = Color(0xFF5F6B7A);

  /// About 3.9:1 on white: large or decorative text and icons only.
  static const Color textGrey = Color(0xFF778196);
  static const Color border = Color(0xFFE8EBF2);
  static const Color background = Color(0xFFF6F7FB);

  static const Color error = Color(0xFFC62828);
  static const Color errorLight = Color(0xFFFDECEC);
  static const Color warning = Color(0xFFB45309);
  static const Color warningLight = Color(0xFFFFF4E5);
  static const Color info = Color(0xFF1D4ED8);
  static const Color infoLight = Color(0xFFE8EEFC);
  static const Color neutralLight = Color(0xFFF1F3F7);

  static const LinearGradient brandGradient = LinearGradient(
    colors: [primary, accentDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
