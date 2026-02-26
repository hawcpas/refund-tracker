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
  String _role = '';

  // ✅ communications fields
  String _wildixExt = '';
  String _clearflyNumber = '';

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
        _role = '';
        _wildixExt = '';
        _clearflyNumber = '';
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

      // ✅ Pull communications from Firestore (same number for Clearfly/eFax)
      final comms = Map<String, dynamic>.from(data['communications'] ?? {});
      final wildixExt = (comms['wildixExtension'] ?? '').toString().trim();
      final clearflyRaw = (comms['clearflySmsNumber'] ?? '').toString().trim();
      final clearflyNum = clearflyRaw.isEmpty
          ? ''
          : _formatUsPhone10(clearflyRaw);

      if (!mounted) return;
      setState(() {
        _fullName = bestName;
        _role = (data['role'] ?? '').toString();
        _wildixExt = wildixExt;
        _clearflyNumber = clearflyNum;
        _loadingProfile = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingProfile = false);
    }
  }

  // ✅ Immediate logout
  Future<void> _logout() async {
    await _auth.logout();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  // ✅ Format any phone-like input into ###-###-#### (last 10 digits)
  String _formatUsPhone10(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    final ten = digits.length >= 10
        ? digits.substring(digits.length - 10)
        : digits;
    if (ten.length != 10) return input.trim();
    return '${ten.substring(0, 3)}-${ten.substring(3, 6)}-${ten.substring(6, 10)}';
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
            onPressed: _logout,
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

                  final bool isWide = w >= (leftCardWidth + gap + 280);
                  final bool isTight = w < 520;

                  final isAdmin =
                      !_loadingProfile && _role.toLowerCase().trim() == 'admin';

                  final welcomeCard = _WhiteSection(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                    child: _WelcomeCardContent(
                      loading: _loadingProfile,
                      welcomeText: welcomeText,
                      isAdmin: isAdmin,
                      isTight: isTight,
                      wildixExtension: _wildixExt,
                      clearflyNumber: _clearflyNumber,
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

            CenteredForm(
              child: Column(
                children: [
                  SizedBox(
                    height: 46,
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _logout,
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
    required this.isAdmin,
    required this.isTight,
    required this.onAdminTap,
    required this.wildixExtension,
    required this.clearflyNumber,
  });

  final bool loading;
  final String welcomeText;
  final bool isAdmin;
  final bool isTight;
  final VoidCallback onAdminTap;

  final String wildixExtension;
  final String clearflyNumber;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final hasWildix = wildixExtension.trim().isNotEmpty;
    final hasClearfly = clearflyNumber.trim().isNotEmpty;
    final showNumbers = !loading && (hasWildix || hasClearfly);

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

                    // ✅ Compact, left-aligned comms under welcome text
                    // ✅ Professional comms block under welcome text
                    if (showNumbers) ...[
                      const SizedBox(height: 10),
                      _CommsInlineBar(
                        hasWildix: hasWildix,
                        hasClearfly: hasClearfly,
                        wildixExtension: wildixExtension,
                        clearflyNumber: clearflyNumber,
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

class _CommsInlineBar extends StatelessWidget {
  const _CommsInlineBar({
    required this.hasWildix,
    required this.hasClearfly,
    required this.wildixExtension,
    required this.clearflyNumber,
  });

  final bool hasWildix;
  final bool hasClearfly;
  final String wildixExtension;
  final String clearflyNumber;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start, // ✅ left aligned
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (hasWildix) ...[
            Icon(
              Icons.phone_in_talk_outlined,
              size: 16,
              color: AppColors.brandBlue.withOpacity(0.90),
            ),
            const SizedBox(width: 6),
            Text(
              'Wildix',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF667085),
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Ext $wildixExtension',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: const Color(0xFF101828),
              ),
            ),
          ],

          // ✅ light separator
          if (hasWildix && hasClearfly) ...[
            const SizedBox(width: 10),
            Text(
              '|',
              style: theme.textTheme.labelMedium?.copyWith(
                color: const Color(0xFF98A2B3), // light grey
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
          ],

          if (hasClearfly) ...[
            Icon(
              Icons.sms_outlined,
              size: 16,
              color: AppColors.brandBlue.withOpacity(0.90),
            ),
            const SizedBox(width: 6),
            Text(
              'Clearfly/eFax',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF667085),
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                clearflyNumber,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF101828),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// ----------------------------
/// Quick Links Card (Right)
/// ----------------------------
class _QuickLinksCard extends StatelessWidget {
  const _QuickLinksCard({
    required this.onOpenResources,
    required this.onOpenSettings,
  });

  final VoidCallback onOpenResources;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final links = const <_DashLink>[
      _DashLink(
        title: 'Websites & Portals',
        subtitle: 'Portals, tools and useful websites',
        icon: Icons.link_outlined,
        action: _DashAction.openResources,
      ),
      _DashLink(
        title: 'Settings',
        subtitle: 'Update your name, password, and profile',
        icon: Icons.person_outline,
        action: _DashAction.openSettings,
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
        Column(
          children: [
            for (int i = 0; i < links.length; i++) ...[
              _QuickLinkRow(
                icon: links[i].icon,
                title: links[i].title,
                subtitle: links[i].subtitle,
                onTap: resolveAction(links[i].action),
              ),
              if (i != links.length - 1)
                Divider(height: 1, color: Colors.black.withOpacity(0.06)),
            ],
          ],
        ),
        const SizedBox(height: 8),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      padding: padding,
      child: child,
    );
  }
}
