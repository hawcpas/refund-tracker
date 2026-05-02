import 'package:flutter/material.dart';

/// ✅ Safely scales content text without affecting layout chrome.
/// - Does NOT use MediaQuery.textScaleFactor
/// - Does NOT affect fixed-height widgets outside this subtree
/// - Ideal for dashboards and enterprise shells
class ContentTextZoom extends StatelessWidget {
  final Widget child;
  final double scale;

  const ContentTextZoom({
    super.key,
    required this.child,
    this.scale = 1.1,
  });

  @override
  Widget build(BuildContext context) {
    final baseFontSize =
        Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14;

    return DefaultTextStyle.merge(
      style: TextStyle(
        fontSize: baseFontSize * scale,
      ),
      child: child,
    );
  }
}