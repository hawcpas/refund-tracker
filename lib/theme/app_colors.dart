import 'package:flutter/material.dart';

class AppColors {
  // =========================
  // Fluent / Office 365 layout
  // =========================

  /// Legacy main app canvas (Office365 gray)
  /// ⚠️ Keep for now — do NOT change yet
  static const Color pageCanvas = Color(0xFFDADADA); // #dadada

  /// ✅ NEW: Light content canvas (modern enterprise)
  /// Used for main page content backgrounds
  static const Color contentCanvas = Color(0xFFFCFCFD); // near-white

  /// Left navigation rail background
  static const Color navRail = Color(0xFFE9E9E9); // #e9e9e9

  /// Card / surface background
  static const Color cardBackground = Colors.white;

  /// Standard dividers (safe on white)
  static const Color divider = Color(0xFFE5E7EB);

  // =========================
  // Typography & utility
  // =========================

  /// Primary neutral text (Fluent)
  static const Color primaryText = Color(0xFF323130);

  /// Secondary / muted text (Fluent)
  static const Color mutedText = Color(0xFF605E5C);

  /// ✅ NEW: Icon color optimized for white / light canvases
  static const Color iconNeutral = Color(0xFF667085);

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