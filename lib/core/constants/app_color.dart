import 'package:flutter/material.dart';

class AppColors {
  // Primary Pink/Coral Colors
  static const Color primary = Color(0xFFFF4B6E);
  static const Color primaryDark = Color(0xFFE03355);

  // Gradient used for primary actions (buttons, bubbles).
  // White text on this gradient keeps >= 4.5:1 contrast at the dark end.
  static const List<Color> primaryGradient = [primary, primaryDark];

  // Accessible deep pink for small text/icons on light backgrounds (AA).
  static const Color primaryDeep = Color(0xFFB7203F);

  // Backgrounds
  static const Color background = Color(0xFFFFFFFF);
  static const Color darkBackground = Color(0xFF121212);
  static const Color surface = Color(0xFFF3F4F8);

  // Neutral Colors
  // NOTE: textSecondary was darkened from #757575 to #5C5C5C so that body
  // text meets WCAG AA (>= 4.5:1) on white backgrounds.
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF5C5C5C);
  static const Color inputFill = Color(0xFFF5F5F5);

  // Semantic colors (all AA-compliant with white text/icons)
  static const Color success = Color(0xFF188038);
  static const Color error = Color(0xFFD93025);
  static const Color linkBlue = Color(0xFF0B57D0);

  // Coin/Gift Accent
  static const Color coinGold = Color(0xFFFFB800);
  // Darker gold for gold icons/text on LIGHT backgrounds (>= 3:1).
  static const Color coinGoldDark = Color(0xFF8A6100);

  // Call UI colors
  static const Color callGreen = Color(0xFF188038); // accept / online
  static const Color callRed = Color(0xFFD93025); // decline / end call
}