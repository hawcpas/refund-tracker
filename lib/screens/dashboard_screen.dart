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

  bool _loadingProfile = true;
  bool _hasDropoffAccess = false;

  String _fullName = '';
  String _role = '';
  String _wildixExt = '';
  String _clearflyNumber = '';

  @override
  void initState() {
    super.initState();

    // ✅ Wait for FirebaseAuth to produce a real user (same concept as _AuthGate)
    // ✅ Wait for the first NON-null user (avoids the web refresh race condition)
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

    return Scaffold(
      backgroundColor: AppColors.pageBackgroundLight,
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          CenteredSection(
            // Slightly less wide than before to avoid “stretched” feel
            maxWidth: 980,
            child: LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth;

                final isMobile = w < 560;
                final isWide = w >= 980;

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

                    // ✅ NEW: Enterprise section header for "Request files"
                    if (_hasDropoffAccess) ...[
                      _SectionLabel(
                        title: 'Request files',
                        subtitle:
                            'Create secure upload links and track incoming documents.',
                      ),
                      const SizedBox(height: 12),

                      _PrimaryFeatureCard(
                        isMobile: isMobile,
                        title: 'Client Upload Links',
                        subtitle:
                            'Secure links for clients to submit documents.',
                        icon: Icons.link_outlined,
                        ctaLabel: 'Manage links',
                        onOpen: () =>
                            Navigator.pushNamed(context, '/view-dropoffs'),
                      ),

                      const SizedBox(height: 12),

                      _PrimaryFeatureCard(
                        isMobile: isMobile,
                        title: 'View uploaded files',
                        subtitle:
                            'All client uploads across all upload links (newest first).',
                        icon: Icons.cloud_upload_outlined,
                        ctaLabel: 'Open uploads',
                        onOpen: () =>
                            Navigator.pushNamed(context, '/dropoff-uploads'),
                      ),

                      const SizedBox(height: 24),
                    ] else ...[
                      const SizedBox(height: 6),
                    ],

                    Text(
                      'Quick access',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF101828),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ✅ Enterprise grid: 1 column mobile, 2 column medium, 3 column desktop
                    _ToolGrid(
                      columns: isMobile ? 1 : (isWide ? 3 : 2),
                      onOpenSharedFiles: () =>
                          Navigator.pushNamed(context, '/shared-files'),
                      onOpenResources: () =>
                          Navigator.pushNamed(context, '/resources'),
                      onOpenSettings: () async {
                        final changed = await Navigator.pushNamed(
                          context,
                          '/account-settings',
                        );
                        if (changed == true) {
                          final user = FirebaseAuth.instance.currentUser;
                          if (user != null) {
                            _loadProfile(user);
                          }
                        }
                      },
                    ),

                    const SizedBox(height: 22),

                    // ✅ Bottom logout (enterprise-style)
                    _BottomLogoutPanel(onLogout: _logout),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// ============================
/// NEW: Small enterprise section label
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
/// - Compact CTA (not stretched)
/// - Mobile stacks cleanly
/// - Shows comms bar when available
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
          // Top row: icon + title + (admin button)
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
/// Enterprise Tool Grid
/// ============================
class _ToolGrid extends StatelessWidget {
  const _ToolGrid({
    required this.columns,
    required this.onOpenSharedFiles,
    required this.onOpenResources,
    required this.onOpenSettings,
  });

  final int columns;
  final VoidCallback onOpenSharedFiles;
  final VoidCallback onOpenResources;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final isMobile = columns == 1;
    final childAspectRatio = isMobile ? 3.3 : (columns == 2 ? 3.0 : 2.9);

    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: childAspectRatio,
      ),
      children: [
        _ToolCard(
          icon: Icons.folder_shared_outlined,
          title: 'Shared Files',
          subtitle: 'Firm‑wide documents and shared resources.',
          onTap: onOpenSharedFiles,
        ),
        _ToolCard(
          icon: Icons.link_outlined,
          title: 'Websites & Portals',
          subtitle: 'External portals and firm tools.',
          onTap: onOpenResources,
        ),
        _ToolCard(
          icon: Icons.person_outline,
          title: 'Account Settings',
          subtitle: 'Update your name, password, and profile.',
          onTap: onOpenSettings,
        ),
      ],
    );
  }
}

/// ============================
/// Bottom Logout Panel
/// ============================
class _BottomLogoutPanel extends StatelessWidget {
  const _BottomLogoutPanel({required this.onLogout});
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Session',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: const Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Sign out of the firm portal on this device.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF475467),
              height: 1.30,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton.icon(
              onPressed: onLogout,
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
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
/// Enterprise Tool Card
/// ============================
class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppColors.brandBlue.withOpacity(0.9)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF101828),
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF667085),
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.brandBlue.withOpacity(0.55),
            ),
          ],
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
