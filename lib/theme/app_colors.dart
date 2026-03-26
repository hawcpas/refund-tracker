import 'package:flutter/material.dart';

class AppColors {
  // =========================
  // Fluent / Office 365 layout
  // =========================

  /// Main app canvas (Office365 background)
  static const Color pageCanvas = Color(0xFFDADADA); // ✅ #dadada

  /// Left navigation rail background
  static const Color navRail = Color(0xFFE9E9E9); // ✅ #e9e9e9

  /// Card / surface background
  static const Color cardBackground = Colors.white;

  /// Standard dividers
  static const Color divider = Color(0xFFE5E7EB);

  // =========================
  // Typography & utility
  // =========================

  /// Primary neutral text (Fluent)
  static const Color primaryText = Color(0xFF323130);

  /// Secondary / muted text (Fluent)
  static const Color mutedText = Color(0xFF605E5C);

  // =========================
  // Brand
  // =========================

  static const Color brandBlue = Color(0xFF08449E);

  // =========================
  // Legacy (keep to avoid breakage)
  // =========================

  static const Color pageBackgroundLight = Color(0xFFDCDCDC);
  static const Color pageBackgroundSoft = Color(0xFFE3E3E3);
  static const Color pageBackgroundDark = Color(0xFF0B346A);
}