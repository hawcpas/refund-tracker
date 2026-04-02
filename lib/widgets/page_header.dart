import 'package:flutter/material.dart';

class PageHeader extends StatelessWidget {
  final Widget child;

  const PageHeader({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      // ✅ ONLY vertical padding — horizontal comes from PageScaffold
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: child,
    );
  }
}