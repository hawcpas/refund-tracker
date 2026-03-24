import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../theme/app_colors.dart';
import '../widgets/page_scaffold.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
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
      title: welcomeText,
      subtitle: 'Axume & Associates CPAs · Firm Portal',
      hideHeader: false, // ✅ IMPORTANT
      wrapInCard: false,

      // ✅ OFFICE‑STYLE COMMAND BAR
      commandBar: FluentCommandBar(
        actions: [
          if (isAdmin)
            FluentCommandAction(
              icon: Icons.admin_panel_settings_outlined,
              label: 'Admin console',
              onPressed: () => Navigator.pushNamed(context, '/admin-users'),
              accent: true,
            ),
        ],
        overflowActions: [
          // Example overflow items (optional)
          FluentCommandAction(
            icon: Icons.settings_outlined,
            label: 'Account settings',
            onPressed: () => Navigator.pushNamed(context, '/account-settings'),
          ),
          FluentCommandAction(
            icon: Icons.refresh,
            label: 'Refresh',
            onPressed: _loadingProfile
                ? null
                : () {
                    final u = FirebaseAuth.instance.currentUser;
                    if (u != null) _loadProfile(u);
                  },
          ),
        ],
      ),

      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),

                Text(
                  'Axume & Associates CPAs · Firm Portal',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6B7280),
                  ),
                ),

                const SizedBox(height: 24),

                // ===== Section: Access =====
                _SectionHeader(title: 'Quick access'),

                const SizedBox(height: 8),

                _SurfaceTable(
                  children: [
                    if (_hasDropoffAccess)
                      _RowItem(
                        icon: Icons.folder_open_outlined,
                        title: 'File Box',
                        subtitle:
                            'View and manage all client‑uploaded documents',
                        onTap: () => Navigator.pushNamed(context, '/file-box'),
                      ),
                    if (_hasDropoffAccess)
                      _RowItem(
                        icon: Icons.link_outlined,
                        title: 'Upload links',
                        subtitle:
                            'Create and manage secure client upload links',
                        onTap: () => Navigator.pushNamed(
                          context,
                          '/generate-upload-link',
                        ),
                      ),
                    if (!_hasDropoffAccess)
                      _InfoRow(
                        text:
                            'You do not currently have access to client upload links. '
                            'Please contact an administrator if this is unexpected.',
                      ),
                  ],
                ),

                const SizedBox(height: 24),

                // ===== Section: Comms =====
                if (_wildixExt.isNotEmpty || _clearflyNumber.isNotEmpty) ...[
                  _SectionHeader(title: 'Communication'),
                  const SizedBox(height: 8),
                  _SurfaceTable(
                    children: [
                      if (_wildixExt.isNotEmpty)
                        _KeyValueRow(
                          label: 'Wildix extension',
                          value: _wildixExt,
                        ),
                      if (_clearflyNumber.isNotEmpty)
                        _KeyValueRow(
                          label: 'Clearfly / eFax',
                          value: _clearflyNumber,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
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

class _SurfaceTable extends StatelessWidget {
  const _SurfaceTable({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(children: children),
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
