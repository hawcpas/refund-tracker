import 'package:flutter/material.dart';
import 'app_colors.dart';

@immutable
class AppTheme extends ThemeExtension<AppTheme> {
  final Color pageBackground;      // gutters / shell
  final Color contentBackground;   // utility bar + content
  final Color navigationBackground;
  final Color divider;

  const AppTheme({
    required this.pageBackground,
    required this.contentBackground,
    required this.navigationBackground,
    required this.divider,
  });

  @override
  AppTheme copyWith({
    Color? pageBackground,
    Color? contentBackground,
    Color? navigationBackground,
    Color? divider,
  }) {
    return AppTheme(
      pageBackground: pageBackground ?? this.pageBackground,
      contentBackground: contentBackground ?? this.contentBackground,
      navigationBackground:
          navigationBackground ?? this.navigationBackground,
      divider: divider ?? this.divider,
    );
  }

  @override
  AppTheme lerp(ThemeExtension<AppTheme>? other, double t) {
    if (other is! AppTheme) return this;
    return AppTheme(
      pageBackground:
          Color.lerp(pageBackground, other.pageBackground, t)!,
      contentBackground:
          Color.lerp(contentBackground, other.contentBackground, t)!,
      navigationBackground:
          Color.lerp(navigationBackground, other.navigationBackground, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
    );
  }
}