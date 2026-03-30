import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../theme/app_colors.dart';
import '../widgets/page_scaffold.dart';
import '../shell/app_shell.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardActionCard extends StatelessWidget {
  const _DashboardActionCard({
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 220), // ✅ taller card
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 6,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ Blue top accent line (Microsoft style)
          Container(
            height: 3,
            decoration: const BoxDecoration(
              color: AppColors.brandBlue,
              borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ✅ Recommended label (no icon)
                const Text(
                  'Recommended',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandBlue,
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: Color(0xFF374151),
                  ),
                ),

                const SizedBox(height: 20),

                // ✅ Button anchored bottom-left
                SizedBox(
                  height: 34,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: onPressed,
                    child: Text(buttonLabel),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardIntroHeader extends StatelessWidget {
  const _DashboardIntroHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF111827),
              letterSpacing: -0.2,
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6B7280),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loadingProfile = true;
  bool _hasDropoffAccess = false;

  String _fullName = '';
  String _role = '';
  String _wildixExt = '';
  String _clearflyNumber = '';

  @override
  void initState() {
    super.initState();
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
        .get();

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
        ? 'Welcome, $_fullName'
        : 'Welcome';

    return PageScaffold(
      title: '',
      hideHeader: true,
      wrapInCard: false,

      // ✅ Welcome text ABOVE command bar (new slot)
      preCommandBar: _DashboardIntroHeader(
        title: welcomeText, // "Welcome, Guillermo"
        // subtitle: 'Here’s what you can do today',
      ),

      commandBar: FluentCommandBar(
        actions: [
          // File Box
          FluentCommandAction(
            icon: Icons.folder_open_outlined,
            label: 'Files',
            onPressed: _hasDropoffAccess
                ? () => Navigator.pushNamed(context, '/file-box')
                : null,
            accent: false,
          ),

          // Upload links
          FluentCommandAction(
            icon: Icons.link_outlined,
            label: 'Rqquest',
            onPressed: _hasDropoffAccess
                ? () => Navigator.pushNamed(context, '/generate-upload-link')
                : null,
            accent: false,
          ),

          // Admin (admins only)
          if (isAdmin)
            FluentCommandAction(
              icon: Icons.admin_panel_settings_outlined,
              label: 'Admin',
              onPressed: () {
                final shell = context.findAncestorStateOfType<AppShellState>();
                shell?.openAdmin();
              },
              accent: false, // ✅ neutral black
            ),
        ],
        overflowActions: const [],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ✅ Dashboard recommendation cards (Microsoft-style)
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 900;

              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: isNarrow ? constraints.maxWidth : 420,
                    child: _DashboardActionCard(
                      title: 'Files',
                      description:
                          'Review, manage, and securely store documents uploaded by clients.',
                      buttonLabel: 'Open files',
                      onPressed: _hasDropoffAccess
                          ? () => Navigator.pushNamed(context, '/file-box')
                          : () {},
                    ),
                  ),

                  SizedBox(
                    width: isNarrow ? constraints.maxWidth : 420,
                    child: _DashboardActionCard(
                      title: 'Requests',
                      description:
                          'Generate a secure upload link for clients to submit documents.',
                      buttonLabel: 'Request files',
                      onPressed: _hasDropoffAccess
                          ? () => Navigator.pushNamed(
                              context,
                              '/generate-upload-link',
                            )
                          : () {},
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 20),

          // ✅ Access notice (unchanged)
          if (!_hasDropoffAccess)
            _SurfaceTable(
              children: const [
                _InfoRow(
                  text:
                      'You do not currently have access to Files or Request links. '
                      'Please contact an administrator if this is unexpected.',
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// ============================
/// Office 365 style components
/// ============================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: const Color(0xFF374151),
        letterSpacing: 0.2,
      ),
    );
  }
}

class _SurfaceTable extends StatefulWidget {
  const _SurfaceTable({required this.children});
  final List<Widget> children;

  @override
  State<_SurfaceTable> createState() => _SurfaceTableState();
}

class _SurfaceTableState extends State<_SurfaceTable> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          // ✅ Noticeable hover background (same language as command bar)
          color: _hover ? const Color(0xFFF0F0F0) : AppColors.cardBackground,

          // ✅ Sharper, enterprise-style corners
          borderRadius: BorderRadius.circular(3),

          // ✅ Stronger border on hover
          border: Border.all(
            color: _hover
                ? Colors.black.withOpacity(0.28)
                : Colors.black.withOpacity(0.12),
            width: 1,
          ),

          // ✅ Deeper, clearer elevation on hover
          boxShadow: [
            BoxShadow(
              color: _hover
                  ? const Color(0x33000000) // ~20% black
                  : const Color(0x1A000000), // ~10% black
              blurRadius: _hover ? 8 : 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(children: widget.children),
      ),
    );
  }
}

class _RowItem extends StatelessWidget {
  const _RowItem({
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.brandBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6B7280),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF111827),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: const Color(0xFF6B7280),
          height: 1.4,
        ),
      ),
    );
  }
}
