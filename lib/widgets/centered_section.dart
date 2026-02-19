import 'package:flutter/material.dart';

class CenteredSection extends StatelessWidget {
  final Widget child;

  /// Target max width for large screens. If you pass maxWidth in the call site,
  /// it becomes the "desktop" cap.
  final double maxWidth;

  /// Horizontal padding inside the centered area.
  final double horizontalPadding;

  const CenteredSection({
    super.key,
    required this.child,
    this.maxWidth = 900, // slightly wider for a more "premium" desktop feel
    this.horizontalPadding = 16,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;

        // Responsive caps:
        // - Mobile: use almost full width
        // - Tablet: cap a bit wider
        // - Desktop: cap at maxWidth
        final double effectiveMaxWidth = w < 600
            ? w // no need to constrain on small screens
            : w < 1024
                ? 760
                : maxWidth;

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: child,
            ),
          ),
        );
      },
    );
  }
}