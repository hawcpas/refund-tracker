import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../theme/app_colors.dart';
import '../services/auth_service.dart';
import '../widgets/centered_section.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final AuthService _auth = AuthService();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _loadingProfile = true;
  bool _hasDropoffAccess = false;

  String _fullName = '';
  String _role = '';
  String _wildixExt = '';
  String _clearflyNumber = '';

  @override
  void initState() {
    super.initState();

    // ✅ Wait for first NON-null user (avoids web refresh race)
    FirebaseAuth.instance.authStateChanges().where((u) => u != null).first.then(
      (u) {
        if (!mounted) return;
        _loadProfile(u!);
      },
    );
  }

  Future<void> _loadProfile(User user) async {
    setState(() => _loadingProfile = true);

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get(const GetOptions(source: Source.server));

    final data = doc.data() ?? {};
    final first = (data['firstName'] ?? '').toString().trim();
    final last = (data['lastName'] ?? '').toString().trim();
    final display = (data['displayName'] ?? '').toString().trim();
    final name = ('$first $last').trim().isNotEmpty ? '$first $last' : display;

    final role = (data['role'] ?? '').toString().toLowerCase().trim();
    final hasDropoffs =
        role == 'admin' || (data['capabilities']?['dropoffs'] == true);

    final comms = Map<String, dynamic>.from(data['communications'] ?? {});
    final wildix = (comms['wildixExtension'] ?? '').toString().trim();
    final clearfly = (comms['clearflySmsNumber'] ?? '').toString().trim();

    if (!mounted) return;
    setState(() {
      _fullName = name;
      _role = role;
      _hasDropoffAccess = hasDropoffs;
      _wildixExt = wildix;
      _clearflyNumber = _formatUsPhone10(clearfly);
      _loadingProfile = false;
    });
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out'),
        content: const Text(
          'Are you sure you want to sign out of the firm portal?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _auth.logout();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  String _formatUsPhone10(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) return input.trim();
    final t = digits.substring(digits.length - 10);
    return '${t.substring(0, 3)}-${t.substring(3, 6)}-${t.substring(6)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final isAdmin = !_loadingProfile && _role == 'admin';
    final welcomeText = _fullName.isNotEmpty
        ? 'Welcome back, $_fullName'
        : 'Welcome back';

    // ✅ Mobile breakpoint for sidebar -> drawer
    final isMobileShell = MediaQuery.of(context).size.width < 900;
    final currentRoute = ModalRoute.of(context)?.settings.name ?? '/dashboard';

    void navigateTo(String route) async {
      // Close drawer first (mobile)
      if (_scaffoldKey.currentState?.isDrawerOpen == true) {
        Navigator.pop(context);
      }

      // ✅ Special action: logout
      if (route == '__logout__') {
        await _logout();
        return;
      }

      // If already on the route, do nothing
      if (route == currentRoute) return;

      Navigator.pushNamed(context, route);
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.pageBackgroundLight,

      appBar: AppBar(
        title: const Text('Dashboard'),
        leading: isMobileShell
            ? IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              )
            : null,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Sign out'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),

      // ✅ Drawer on mobile only
      drawer: isMobileShell
          ? Drawer(
              child: SafeArea(
                child: _SidebarNav(
                  compact: false,
                  currentRoute: currentRoute,
                  onNavigate: navigateTo,
                ),
              ),
            )
          : null,

      // ✅ Desktop: persistent sidebar + main content
      body: Row(
        children: [
          if (!isMobileShell)
            _SidebarNav(
              compact: true,
              currentRoute: currentRoute,
              onNavigate: navigateTo,
            ),

          // ✅ MAIN CONTENT (always visible on desktop)
          Expanded(
            child: Scrollbar(
              thumbVisibility: !isMobileShell,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                children: [
                  CenteredSection(
                    maxWidth: 980,
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final w = c.maxWidth;
                        final isMobile = w < 560;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ContextHeader(
                              loading: _loadingProfile,
                              welcomeText: welcomeText,
                              isAdmin: isAdmin,
                              isMobile: isMobile,
                              wildix: _wildixExt,
                              clearfly: _clearflyNumber,
                              onAdminTap: () =>
                                  Navigator.pushNamed(context, '/admin-users'),
                            ),
                            const SizedBox(height: 18),

                            if (_hasDropoffAccess) ...[
                              const _SectionLabel(
                                title: 'Incoming files',
                                subtitle:
                                    'All client-uploaded documents across all upload links.',
                              ),
                              const SizedBox(height: 12),
                              _PrimaryFeatureCard(
                                isMobile: isMobile,
                                title: 'File Box',
                                subtitle:
                                    'View and manage all uploaded files (newest first).',
                                icon: Icons.cloud_upload_outlined,
                                ctaLabel: 'Open file box',
                                onOpen: () => Navigator.pushNamed(
                                  context,
                                  '/dropoff-uploads',
                                ),
                              ),
                              const SizedBox(height: 28),
                              const _SectionLabel(
                                title: 'Request files',
                                subtitle:
                                    'Create secure upload links for clients to submit documents.',
                              ),
                              const SizedBox(height: 12),
                              _PrimaryFeatureCard(
                                isMobile: isMobile,
                                title: 'Generate Upload Links',
                                subtitle:
                                    'Create and manage secure upload links for clients.',
                                icon: Icons.link_outlined,
                                ctaLabel: 'Manage links',
                                onOpen: () => Navigator.pushNamed(
                                  context,
                                  '/view-dropoffs',
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 8),
                              _SurfaceCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Access notice',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            color: const Color(0xFF101828),
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'You currently do not have access to Client Upload Links. '
                                      'If you believe this is incorrect, please contact an administrator.',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: const Color(0xFF475467),
                                            height: 1.35,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 22),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ============================
/// Sidebar Navigation (Enterprise, compact + tight)
/// ============================
class _SidebarNav extends StatelessWidget {
  const _SidebarNav({
    required this.currentRoute,
    required this.onNavigate,
    this.compact = true,
  });

  final String currentRoute;
  final void Function(String route) onNavigate;
  final bool compact;

  Widget _item({
    required IconData icon,
    required String label,
    required String route,
    bool danger = false,
  }) {
    final isActive = currentRoute == route;

    final Color baseText = danger
        ? const Color(0xFFB42318)
        : const Color(0xFF344054);
    final Color baseIcon = danger
        ? const Color(0xFFB42318)
        : const Color(0xFF667085);

    final Color activeText = danger
        ? const Color(0xFFB42318)
        : AppColors.brandBlue;
    final Color activeIcon = danger
        ? const Color(0xFFB42318)
        : AppColors.brandBlue;

    final Color bg = isActive
        ? (danger
              ? const Color(0xFFB42318).withOpacity(0.10)
              : AppColors.brandBlue.withOpacity(0.12))
        : (danger
              ? const Color(0xFFB42318).withOpacity(0.06)
              : Colors.transparent);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onNavigate(route),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isActive ? activeIcon : baseIcon),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: isActive ? activeText : baseText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = compact ? 210.0 : double.infinity;

    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: Colors.black.withOpacity(0.06)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'NAVIGATION',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              letterSpacing: 1.1,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF98A2B3),
            ),
          ),
          const SizedBox(height: 10),

          _item(
            icon: Icons.dashboard_outlined,
            label: 'Dashboard',
            route: '/dashboard',
          ),
          const SizedBox(height: 4),

          _item(
            icon: Icons.folder_shared_outlined,
            label: 'Firm Documents',
            route: '/shared-files',
          ),
          const SizedBox(height: 4),

          _item(
            icon: Icons.link_outlined,
            label: 'Websites & Resources',
            route: '/resources',
          ),
          const SizedBox(height: 4),

          _item(
            icon: Icons.person_outline,
            label: 'Account Settings',
            route: '/account-settings',
          ),

          const SizedBox(height: 6),

          _item(
            icon: Icons.logout,
            label: 'Sign out',
            route: '__logout__',
            danger: true,
          ),
        ],
      ),
    );
  }
}

/// ============================
/// Small enterprise section label
/// ============================
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: theme.textTheme.labelLarge?.copyWith(
            letterSpacing: 1.1,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF667085),
          ),
        ),
        if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF475467),
              height: 1.30,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

/// ============================
/// Enterprise Context Header
/// ============================
class _ContextHeader extends StatelessWidget {
  const _ContextHeader({
    required this.loading,
    required this.welcomeText,
    required this.isAdmin,
    required this.isMobile,
    required this.wildix,
    required this.clearfly,
    required this.onAdminTap,
  });

  final bool loading;
  final String welcomeText;
  final bool isAdmin;
  final bool isMobile;
  final String wildix;
  final String clearfly;
  final VoidCallback onAdminTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final hasWildix = wildix.trim().isNotEmpty;
    final hasClearfly = clearfly.trim().isNotEmpty;
    final showComms = !loading && (hasWildix || hasClearfly);

    final title = loading ? 'Loading…' : welcomeText;

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: AppColors.brandBlue.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.dashboard_rounded,
                  color: AppColors.brandBlue,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF101828),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Axume & Associates CPAs – Firm Portal',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF475467),
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isMobile && isAdmin) ...[
                const SizedBox(width: 12),
                _CompactButton(
                  label: 'Admin Console',
                  icon: Icons.admin_panel_settings_rounded,
                  onPressed: onAdminTap,
                  dark: true,
                ),
              ],
            ],
          ),
          if (isMobile && isAdmin) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                onPressed: onAdminTap,
                icon: const Icon(Icons.admin_panel_settings_rounded, size: 18),
                label: const Text('Admin Console'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0B1220),
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
          if (showComms) ...[
            const SizedBox(height: 14),
            _CommsInlineBar(
              hasWildix: hasWildix,
              hasClearfly: hasClearfly,
              wildixExtension: wildix,
              clearflyNumber: clearfly,
            ),
          ],
        ],
      ),
    );
  }
}

/// ============================
/// Primary Feature Card
/// ============================
class _PrimaryFeatureCard extends StatelessWidget {
  const _PrimaryFeatureCard({
    required this.isMobile,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.ctaLabel,
    required this.onOpen,
  });

  final bool isMobile;
  final String title;
  final String subtitle;
  final IconData icon;
  final String ctaLabel;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: AppColors.brandBlue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.brandBlue, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF101828),
                        letterSpacing: -0.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF475467),
                        height: 1.30,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isMobile) ...[
                const SizedBox(width: 12),
                _CompactButton(
                  label: ctaLabel,
                  icon: Icons.open_in_new_rounded,
                  onPressed: onOpen,
                ),
              ],
            ],
          ),
          if (isMobile) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton(
                onPressed: onOpen,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(ctaLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// ============================
/// Shared Card Surface (Enterprise)
/// ============================
class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: child,
    );
  }
}

/// ============================
/// Compact Button
/// ============================
class _CompactButton extends StatelessWidget {
  const _CompactButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.dark = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: FilledButton.styleFrom(
          backgroundColor: dark ? const Color(0xFF0B1220) : AppColors.brandBlue,
          foregroundColor: Colors.white,
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
    );
  }
}

/// ============================
/// Comms Bar
/// ============================
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
          if (hasWildix && hasClearfly) ...[
            const SizedBox(width: 10),
            Text(
              '|',
              style: theme.textTheme.labelMedium?.copyWith(
                color: const Color(0xFF98A2B3),
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
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
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
