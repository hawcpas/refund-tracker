import 'package:flutter/material.dart';

class AppColors {
  // =========================
  // Fluent / Office 365 layout
  // =========================

  /// Legacy main app canvas (Office365 gray)
  /// ⚠️ Keep for now — do NOT change yet
  static const Color pageCanvas = Color(0xFFF7F5F2);

  static const Color navigationCanvas = Color(0xFFF7F5F2); // #f7f5f2

  /// ✅ Page-level surface (utility bar + background behind content)
  static const Color pageSurface = Color(0xFFF7F5F2); // same as nav panes

  /// ✅ NEW: Light content canvas (modern enterprise)
  /// Used for main page content backgrounds
  static const Color contentCanvas = Color(0xFFFFFFFF);

  /// Left navigation rail background
  static const Color navRail = navigationCanvas; // ✅ alias for safety

  /// Card / surface background
  static const Color cardBackground = Colors.white;

  /// Standard dividers (safe on white)
  static const Color divider = Color(0xFFE7E5E3); // #e7e5e3

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
