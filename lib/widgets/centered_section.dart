import 'package:flutter/material.dart';

class CenteredSection extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const CenteredSection({
    super.key,
    required this.child,
    this.maxWidth = 720, // wider than forms, ideal for dashboards
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}