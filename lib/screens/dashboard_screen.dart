import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:refund_tracker/widgets/centered_form.dart';
import 'package:refund_tracker/widgets/centered_section.dart';
import '../theme/app_colors.dart';
import '../services/auth_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final AuthService _auth = AuthService();

  bool _loadingProfile = true;
  String _fullName = '';
  String _status = '';
  String _role = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _loadingProfile = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _loadingProfile = false;
        _fullName = '';
        _status = '';
        _role = '';
      });
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server));

      final data = doc.data() ?? {};
      final firstName = (data['firstName'] ?? '').toString().trim();
      final lastName = (data['lastName'] ?? '').toString().trim();
      final displayName = (data['displayName'] ?? '').toString().trim();

      final computedName = ('$firstName $lastName').trim();
      final bestName = computedName.isNotEmpty ? computedName : displayName;

      if (!mounted) return;
      setState(() {
        _fullName = bestName;
        _status = (data['status'] ?? '').toString();
        _role = (data['role'] ?? '').toString();
        _loadingProfile = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingProfile = false);
    }
  }

  // ✅ Immediate logout (no confirmation, no dialog)
  Future<void> _logout() async {
    await _auth.logout();
    if (!mounted) return;

    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final welcomeText = _fullName.isNotEmpty
        ? "Welcome back, $_fullName"
        : "Welcome back";

    // Matches your ResourcesScreen geometry
    const double maxPageWidth = 1100;
    const double leftCardWidth = 740;
    const double gap = 18;

    return Scaffold(
      backgroundColor: AppColors.pageBackgroundLight,
      appBar: AppBar(
        title: const Text("Dashboard"),
        actions: [
          IconButton(
            tooltip: "Logout",
            icon: const Icon(Icons.logout),
            onPressed: _logout, // ✅ immediate
          ),
        ],
      ),
      body: ColoredBox(
        color: AppColors.pageBackgroundLight,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          children: [
            CenteredSection(
              maxWidth: maxPageWidth,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;

                  // Layout decision:
                  // - Wide: Welcome (left) + Quick Links (right) aligned horizontally
                  // - Narrow: stack vertically
                  final bool isWide = w >= (leftCardWidth + gap + 280);
                  final bool isTight = w < 520;

                  final isAdmin =
                      !_loadingProfile && _role.toLowerCase().trim() == 'admin';

                  final welcomeCard = _WhiteSection(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                    child: _WelcomeCardContent(
                      loading: _loadingProfile,
                      welcomeText: welcomeText,
                      status: _status,
                      role: _role,
                      isAdmin: isAdmin,
                      isTight: isTight,
                      onAdminTap: () =>
                          Navigator.pushNamed(context, '/admin-users'),
                    ),
                  );

                  final linksCard = _WhiteSection(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                    child: _QuickLinksCard(
                      onOpenResources: () =>
                          Navigator.pushNamed(context, '/resources'),
                      onOpenSettings: () async {
                        final changed = await Navigator.pushNamed(
                          context,
                          '/account-settings',
                        );
                        if (changed == true) {
                          _loadProfile();
                        }
                      },
                    ),
                  );

                  if (isWide) {
                    // Align horizontally
                    final rightWidth = (w - leftCardWidth - gap).clamp(
                      280,
                      380,
                    );

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: leftCardWidth, child: welcomeCard),
                        const SizedBox(width: gap),
                        SizedBox(
                          width: rightWidth.toDouble(),
                          child: linksCard,
                        ),
                      ],
                    );
                  }

                  // Stack on smaller screens
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      welcomeCard,
                      const SizedBox(height: 18),
                      linksCard,
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 22),

            // ✅ LOGOUT (immediate)
            CenteredForm(
              child: Column(
                children: [
                  SizedBox(
                    height: 46,
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _logout, // ✅ immediate
                      icon: const Icon(Icons.logout),
                      label: const Text("Logout"),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brandBlue,
                        foregroundColor: AppColors.cardBackground,
                        textStyle: const TextStyle(fontWeight: FontWeight.w900),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "You can update your name and password any time from Account settings.",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.lightGrey,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// ----------------------------
/// Welcome Card Content (Left)
/// ----------------------------
class _WelcomeCardContent extends StatelessWidget {
  const _WelcomeCardContent({
    required this.loading,
    required this.welcomeText,
    required this.status,
    required this.role,
    required this.isAdmin,
    required this.isTight,
    required this.onAdminTap,
  });

  final bool loading;
  final String welcomeText;
  final String status;
  final String role;
  final bool isAdmin;
  final bool isTight;
  final VoidCallback onAdminTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                color: AppColors.brandBlue.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.dashboard_rounded,
                color: AppColors.brandBlue,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (loading) ...[
                    Container(
                      height: 22,
                      width: 260,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 14,
                      width: 320,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ] else ...[
                    Text(
                      welcomeText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.15,
                        color: const Color(0xFF101828),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Manage your account and security settings.",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF475467),
                        height: 1.30,
                      ),
                    ),
                    if (status.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _StatusChip(label: status),
                          if (role.isNotEmpty) _RoleChip(label: role),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),

            if (!isTight && isAdmin) ...[
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: SizedBox(
                  height: 40,
                  child: FilledButton.icon(
                    onPressed: onAdminTap,
                    icon: const Icon(
                      Icons.admin_panel_settings_rounded,
                      size: 18,
                    ),
                    label: const Text(
                      "Admin Console",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0B1220),
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shadowColor: Colors.black.withOpacity(0.25),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),

        if (isTight && isAdmin) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton.icon(
              onPressed: onAdminTap,
              icon: const Icon(Icons.admin_panel_settings_rounded, size: 20),
              label: const Text("Admin Console"),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0B1220),
                foregroundColor: Colors.white,
                elevation: 2,
                shadowColor: Colors.black.withOpacity(0.25),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// ----------------------------
/// Quick Links Card (Right)
/// Matches ResourcesScreen section style
/// ----------------------------
class _QuickLinksCard extends StatelessWidget {
  const _QuickLinksCard({
    required this.onOpenResources,
    required this.onOpenSettings,
  });

  final VoidCallback onOpenResources;
  final VoidCallback onOpenSettings;

  static const double rowIndent = 20;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final sections = <_DashSection>[
      _DashSection(
        title: 'Sites & Resources',
        description: 'Access firm websites, tools, and external systems.',
        items: const [
          _DashLink(
            title: 'Open resources',
            subtitle: 'Company tools, portals, and useful websites',
            icon: Icons.link_outlined,
            action: _DashAction.openResources,
          ),
        ],
      ),
      _DashSection(
        title: 'Account',
        description: 'Manage your personal account settings.',
        items: const [
          _DashLink(
            title: 'Settings',
            subtitle: 'Update your name, password, and profile',
            icon: Icons.person_outline,
            action: _DashAction.openSettings,
          ),
        ],
      ),
    ];

    VoidCallback resolveAction(_DashAction a) {
      switch (a) {
        case _DashAction.openResources:
          return onOpenResources;
        case _DashAction.openSettings:
          return onOpenSettings;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dashboard',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            color: const Color(0xFF101828),
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Quick access to common tools and settings.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF475467),
            height: 1.25,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 14),

        // ---------- SECTIONS ----------
        ...sections.map(
          (s) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(title: s.title, description: s.description),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: rowIndent),
                  child: Column(
                    children: [
                      for (int i = 0; i < s.items.length; i++) ...[
                        _QuickLinkRow(
                          icon: s.items[i].icon,
                          title: s.items[i].title,
                          subtitle: s.items[i].subtitle,
                          onTap: resolveAction(s.items[i].action),
                        ),
                        if (i != s.items.length - 1)
                          Divider(
                            height: 1,
                            color: Colors.black.withOpacity(0.06),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 6),
        Text(
          'Opens inside the app.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.lightGrey,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// ----------------------------
/// Models for right-side sections
/// ----------------------------
class _DashSection {
  final String title;
  final String description;
  final List<_DashLink> items;
  const _DashSection({
    required this.title,
    required this.description,
    required this.items,
  });
}

enum _DashAction { openResources, openSettings }

class _DashLink {
  final String title;
  final String subtitle;
  final IconData icon;
  final _DashAction action;
  const _DashLink({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.action,
  });
}

/// ----------------------------
/// Section header (same style as ResourcesScreen)
/// ----------------------------
class _SectionHeader extends StatelessWidget {
  final String title;
  final String description;

  const _SectionHeader({required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.brandBlue.withOpacity(0.04),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF101828),
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF475467),
              height: 1.25,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// ----------------------------
/// Link row (same hover/underline vibe as ResourcesScreen)
/// ----------------------------
class _QuickLinkRow extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickLinkRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  State<_QuickLinkRow> createState() => _QuickLinkRowState();
}

class _QuickLinkRowState extends State<_QuickLinkRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        hoverColor: Colors.black.withOpacity(0.03),
        splashColor: Colors.black.withOpacity(0.02),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 20,
                color: AppColors.brandBlue.withOpacity(0.85),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandBlue,
                        height: 1.05,
                        decoration: _hovered
                            ? TextDecoration.underline
                            : TextDecoration.none,
                        decorationThickness: 1.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF667085),
                        fontWeight: FontWeight.w500,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.brandBlue.withOpacity(_hovered ? 0.75 : 0.55),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- Small chips (optional polish) ----------
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final normalized = label.toLowerCase().trim();
    final Color bg = normalized == 'active'
        ? Colors.green.withOpacity(0.12)
        : AppColors.brandBlue.withOpacity(0.10);
    final Color fg = normalized == 'active'
        ? Colors.green.shade800
        : AppColors.brandBlue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.25)),
      ),
      child: Text(
        normalized.isEmpty ? '' : normalized,
        style: TextStyle(fontWeight: FontWeight.w800, color: fg, fontSize: 12),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final normalized = label.toLowerCase().trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withOpacity(0.10)),
      ),
      child: Text(
        normalized.isEmpty ? '' : normalized,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: Color(0xFF101828),
          fontSize: 12,
        ),
      ),
    );
  }
}

class _WhiteSection extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const _WhiteSection({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, // ✅ white surface
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.black.withOpacity(0.05), // ✅ subtle separation
        ),
      ),
      padding: padding,
      child: child,
    );
  }
}
