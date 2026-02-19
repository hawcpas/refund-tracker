import 'package:flutter/material.dart';

class CenteredForm extends StatelessWidget {
  final Widget child;

  /// Base max width for a form. 420 is great for login/credentials.
  final double maxWidth;

  /// Horizontal padding for small screens.
  final double horizontalPadding;

  const CenteredForm({
    super.key,
    required this.child,
    this.maxWidth = 420,
    this.horizontalPadding = 16,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;

        // On very small widths, avoid over-constraining and just pad.
        final double effectiveMaxWidth =
            w < 480 ? w : (w < 900 ? 480 : maxWidth);

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