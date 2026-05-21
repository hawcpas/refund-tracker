import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'page_header.dart';

class PageScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? commandBar;
  final Color? backgroundColor;
  final Widget? preCommandBar;
  final double? maxContentWidth;

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
    this.commandBar,
    this.preCommandBar,
    this.backgroundColor,
    this.maxContentWidth, // ✅ NEW
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appTheme = Theme.of(context).extension<AppTheme>()!;
    final width = MediaQuery.of(context).size.width;

    final bool isMobile = width < 700;

    final EdgeInsets pagePadding = isMobile
        ? const EdgeInsets.fromLTRB(16, 16, 16, 24)
        : const EdgeInsets.fromLTRB(32, 24, 24, 32);

    final Widget header = hideHeader
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF111827),
                  letterSpacing: -0.2,
                ),
              ),
              if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF6B7280),
                    height: 1.30,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
              const SizedBox(height: 12),
            ],
          );

    final Widget content = wrapInCard
        ? Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: appTheme.contentBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black.withOpacity(0.06)),
            ),
            child: child,
          )
        : child;

    Widget inner = SizedBox(
      width: isMobile ? double.infinity : (maxContentWidth ?? _railWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hideHeader && !isMobile) PageHeader(child: header),

          // ✅ Optional content ABOVE command bar (Dashboard welcome)
          if (preCommandBar != null) ...[
            PageHeader(child: preCommandBar!),
            const SizedBox(height: 8),
          ],

          // ✅ Command bar under header
          if (commandBar != null) ...[commandBar!, const SizedBox(height: 12)],

          content,
        ],
      ),
    );

    // ✅ Scrollable scaffold (default)
    if (scrollable) {
      return Container(
        color: backgroundColor ?? appTheme.contentBackground,
        child: ListView(
          padding: pagePadding,
          children: [_FluentContentFrame(child: inner)],
        ),
      );
    }

    // ✅ Non-scroll scaffold (pages with their own scrolling)
    return Container(
      color: backgroundColor ?? appTheme.contentBackground,
      padding: pagePadding,
      child: _FluentContentFrame(child: inner),
    );
  }
}

class _FluentContentFrame extends StatelessWidget {
  final Widget child;

  const _FluentContentFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth, // ✅ lock right edge
          child: Align(
            alignment: Alignment.topLeft, // ✅ Fluent behavior
            child: child,
          ),
        );
      },
    );
  }
}

/// ============================
/// Fluent / Office 365 Command Bar
/// (hover states, disabled styles, overflow menu)
/// ============================

class FluentCommandAction {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed; // null = disabled
  final bool accent; // true = brandBlue, false = neutral

  const FluentCommandAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.accent = false,
  });

  bool get enabled => onPressed != null;
}

class FluentCommandBar extends StatelessWidget {
  /// Primary actions shown inline
  final List<FluentCommandAction> actions;

  /// Extra actions shown in the ⋯ overflow menu
  final List<FluentCommandAction> overflowActions;

  const FluentCommandBar({
    super.key,
    required this.actions,
    this.overflowActions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final appTheme = Theme.of(context).extension<AppTheme>()!;

    // ✅ Office365-style breakpoint
    final bool isNarrow = width < 720;

    // ✅ On narrow screens, collapse actions into overflow
    final List<FluentCommandAction> inlineActions = actions;

    final List<FluentCommandAction> overflow = overflowActions;

    if (isNarrow && inlineActions.isEmpty) {
      if (overflow.isEmpty) return const SizedBox.shrink();
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: appTheme.contentBackground,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.black.withOpacity(0.12), width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: FluentOverflowMenuButton(actions: overflow),
        ),
      );
    }

    return Container(
      width: double.infinity,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: appTheme.contentBackground,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.black.withOpacity(0.12), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: isNarrow
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                // ✅ THIS IS THE LINE YOU ASKED ABOUT
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final a in inlineActions)
                    FluentCommandButton(
                      icon: a.icon,
                      label: a.label,
                      onPressed: a.onPressed,
                      accent: a.accent,
                    ),

                  if (!isNarrow) const Spacer(),

                  if (overflow.isNotEmpty)
                    FluentOverflowMenuButton(actions: overflow),
                ],
              ),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final a in inlineActions)
                  FluentCommandButton(
                    icon: a.icon,
                    label: a.label,
                    onPressed: a.onPressed,
                    accent: a.accent,
                  ),
                const Spacer(),
                if (overflow.isNotEmpty)
                  FluentOverflowMenuButton(actions: overflow),
              ],
            ),
    );
  }
}

class FluentCommandButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed; // null = disabled
  final bool accent;

  const FluentCommandButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.accent = false,
  });

  @override
  State<FluentCommandButton> createState() => _FluentCommandButtonState();
}

class _FluentCommandButtonState extends State<FluentCommandButton> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;

    final Color fgEnabled = widget.accent
        ? AppColors.brandBlue
        : const Color(0xFF111827);
    const Color fgDisabled = Color(0xFF9CA3AF);

    // ✅ Darker, more noticeable per-segment hover
    final Color bg = !enabled
        ? Colors.transparent
        : _pressed
        ? Colors.black.withOpacity(0.16)
        : (_hover ? Colors.black.withOpacity(0.10) : Colors.transparent);

    // Optional: subtle border on hover (very Office365)
    final Color border = !enabled
        ? Colors.transparent
        : (_hover || _pressed
              ? Colors.black.withOpacity(0.16)
              : Colors.transparent);

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) {
          if (!enabled) return;
          setState(() => _hover = true);
        },
        onExit: (_) {
          if (!enabled) return;
          setState(() {
            _hover = false;
            _pressed = false;
          });
        },
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            height: 40, // ✅ matches Office365 control height
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: border, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: 18,
                  color: enabled ? fgEnabled : fgDisabled,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    color: enabled ? fgEnabled : fgDisabled,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FluentOverflowMenuButton extends StatelessWidget {
  final List<FluentCommandAction> actions;

  const FluentOverflowMenuButton({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    const overlayHover = Color(0x0A000000);
    const overlayPressed = Color(0x14000000);

    return _OverflowButtonSurface(
      onTap: () async {
        final selected = await _showOverflowMenu(context, actions);
        if (selected != null && selected.onPressed != null) {
          selected.onPressed!.call();
        }
      },
      child: const Row(
        children: [
          Icon(Icons.more_horiz, size: 18, color: Color(0xFF111827)),
          SizedBox(width: 6),
          Text(
            'More',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111827),
              height: 1.2,
            ),
          ),
        ],
      ),
      hoverColor: overlayHover,
      pressedColor: overlayPressed,
    );
  }

  Future<FluentCommandAction?> _showOverflowMenu(
    BuildContext context,
    List<FluentCommandAction> actions,
  ) async {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    final Rect buttonRect =
        button.localToGlobal(Offset.zero, ancestor: overlay) & button.size;

    final pos = RelativeRect.fromRect(buttonRect, Offset.zero & overlay.size);

    return showMenu<FluentCommandAction>(
      context: context,
      position: pos,
      items: actions.map((a) {
        return PopupMenuItem<FluentCommandAction>(
          value: a,
          enabled: a.enabled,
          child: Row(
            children: [
              Icon(
                a.icon,
                size: 18,
                color: a.enabled
                    ? const Color(0xFF111827)
                    : const Color(0xFF9CA3AF),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  a.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: a.enabled
                        ? const Color(0xFF111827)
                        : const Color(0xFF9CA3AF),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _OverflowButtonSurface extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final Color hoverColor;
  final Color pressedColor;

  const _OverflowButtonSurface({
    required this.child,
    required this.onTap,
    required this.hoverColor,
    required this.pressedColor,
  });

  @override
  State<_OverflowButtonSurface> createState() => _OverflowButtonSurfaceState();
}

class _OverflowButtonSurfaceState extends State<_OverflowButtonSurface> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bg = _pressed
        ? widget.pressedColor
        : (_hover ? widget.hoverColor : Colors.transparent);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: widget.child,
        ),
      ),
    );
  }
}
