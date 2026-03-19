import 'package:flutter/material.dart';

class PageScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  /// If true, PageScaffold uses a ListView for scrolling.
  /// If false, PageScaffold does NOT scroll (for pages that manage their own scrolling).
  final bool scrollable;

  /// Hide the default header (Dashboard/FileBox often provide their own header)
  final bool hideHeader;

  /// Wrap page content inside the default white card
  final bool wrapInCard;

  // Desktop tokens
  static const double _railWidth = 960;

  const PageScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.scrollable = true,
    this.hideHeader = false,
    this.wrapInCard = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.of(context).size.width;
    final bool isMobile = width < 700;

    final EdgeInsets pagePadding = isMobile
        ? const EdgeInsets.fromLTRB(16, 16, 16, 24)
        : const EdgeInsets.fromLTRB(32, 24, 24, 32);

    Widget header = const SizedBox.shrink();
    if (!hideHeader) {
      header = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF101828),
              letterSpacing: -0.2,
            ),
          ),
          if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF667085),
                height: 1.30,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 18),
        ],
      );
    }

    final Widget content = wrapInCard
        ? Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withOpacity(0.06)),
            ),
            child: child,
          )
        : child;

    // ✅ Scrollable scaffold (default): used by most pages
    if (scrollable) {
      return ListView(
        padding: pagePadding,
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: isMobile ? double.infinity : _railWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [header, content],
              ),
            ),
          ),
        ],
      );
    }

    // ✅ Non-scroll scaffold: used by pages that contain Expanded/ListView internally (File Box)
    return Padding(
      padding: pagePadding,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: isMobile ? double.infinity : _railWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!hideHeader) header,
              // If header is hidden, do NOT insert spacing here — page controls it.
              Expanded(child: content),
            ],
          ),
        ),
      ),
    );
  }
}
