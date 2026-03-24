import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class PageScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? commandBar;

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
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black.withOpacity(0.06)),
            ),
            child: child,
          )
        : child;

    Widget inner = Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: isMobile ? double.infinity : _railWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!hideHeader) header,

            // ✅ Command bar under header (Office 365 style)
            if (commandBar != null) ...[
              commandBar!,
              const SizedBox(height: 12),
            ],

            content,
          ],
        ),
      ),
    );

    // ✅ Scrollable scaffold (default)
    if (scrollable) {
      return Container(
        color: AppColors.pageBackgroundSoft,
        child: ListView(
          padding: pagePadding,
          children: [inner],
        ),
      );
    }

    // ✅ Non-scroll scaffold (pages with their own scrolling)
    return Container(
      color: AppColors.pageBackgroundSoft,
      padding: pagePadding,
      child: inner,
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

  /// Extra actions shown in the ⋯ overflow menu (Exchange Admin style)
  final List<FluentCommandAction> overflowActions;

  const FluentCommandBar({
    super.key,
    required this.actions,
    this.overflowActions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final divider = AppColors.divider; // make sure AppColors.divider exists

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: divider),
          bottom: BorderSide(color: divider),
        ),
      ),
      child: Row(
        children: [
          for (final a in actions)
            FluentCommandButton(
              icon: a.icon,
              label: a.label,
              onPressed: a.onPressed,
              accent: a.accent,
            ),

          const Spacer(),

          if (overflowActions.isNotEmpty)
            FluentOverflowMenuButton(actions: overflowActions),
        ],
      ),
    );
  }
}

class FluentCommandButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool accent;

  const FluentCommandButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color enabledFg = accent ? AppColors.brandBlue : const Color(0xFF111827);
    const Color disabledFg = Color(0xFF9CA3AF);

    // ✅ Fluent hover/press overlays
    final overlay = MaterialStateProperty.resolveWith<Color?>((states) {
      if (states.contains(MaterialState.disabled)) return Colors.transparent;
      if (states.contains(MaterialState.pressed)) return const Color(0x14000000);
      if (states.contains(MaterialState.hovered)) return const Color(0x0A000000);
      return Colors.transparent;
    });

    final fg = MaterialStateProperty.resolveWith<Color?>((states) {
      if (states.contains(MaterialState.disabled)) return disabledFg;
      return enabledFg;
    });

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ButtonStyle(
          minimumSize: MaterialStateProperty.all(const Size(0, 32)),
          padding: MaterialStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 12),
          ),
          overlayColor: overlay,
          foregroundColor: fg,
          textStyle: MaterialStateProperty.all(
            const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          shape: MaterialStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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

    final Rect buttonRect = button.localToGlobal(Offset.zero, ancestor: overlay) &
        button.size;

    final pos = RelativeRect.fromRect(
      buttonRect,
      Offset.zero & overlay.size,
    );

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
                color: a.enabled ? const Color(0xFF111827) : const Color(0xFF9CA3AF),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  a.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: a.enabled ? const Color(0xFF111827) : const Color(0xFF9CA3AF),
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