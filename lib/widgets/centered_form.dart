import 'package:flutter/material.dart';

class CenteredForm extends StatelessWidget {
  final Widget child;

  const CenteredForm({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: child,
      ),
    );
  }
}