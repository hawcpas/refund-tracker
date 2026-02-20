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
      // ✅ FORCE fresh data from Firestore (bypass cache)
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final welcomeText = _fullName.isNotEmpty
        ? "Welcome back, $_fullName"
        : "Welcome back";

    return Scaffold(
      backgroundColor: AppColors.pageBackgroundLight,
      appBar: AppBar(
        title: const Text("Dashboard"),
        actions: [
          IconButton(
            tooltip: "Logout",
            icon: const Icon(Icons.logout),
            onPressed: () => _confirmLogout(context),
          ),
        ],
      ),
      body: ColoredBox(
        color: AppColors.pageBackgroundLight,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
          children: [
            // ✅ HEADER
            CenteredSection(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(
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
                          if (_loadingProfile) ...[
                            // ✅ Placeholder state (no flicker)
                            Container(
                              height: 22,
                              width: 220,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: 14,
                              width: 260,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.04),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ] else ...[
                            Text(
                              welcomeText,
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

                            if (_status.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                children: [
                                  _StatusChip(label: _status),
                                  if (_role.isNotEmpty) _RoleChip(label: _role),
                                ],
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 18),

            // ✅ ACCOUNT SECTION
            CenteredSection(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Account",
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
                      color: const Color(0xFF101828),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ✅ NEW: Account settings (first/last name)
                  _SubtleHoverTile(
                    icon: Icons.person_outline,
                    title: "Account settings",
                    subtitle: "Update your name and profile information",
                    onTap: () async {
                      final changed = await Navigator.pushNamed(
                        context,
                        '/account-settings',
                      );

                      if (changed == true) {
                        _loadProfile(); // ✅ THIS is what refreshes the name
                      }
                    },
                  ),

                  const SizedBox(height: 10),

                  _SubtleHoverTile(
                    icon: Icons.lock_reset,
                    title: "Change password",
                    subtitle: "Update your login credentials",
                    onTap: () =>
                        Navigator.pushNamed(context, '/change-password'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // ✅ LOGOUT
            CenteredForm(
              child: Column(
                children: [
                  SizedBox(
                    height: 46,
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _confirmLogout(context),
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

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Log out"),
        content: const Text("Are you sure you want to log out?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: AppColors.cardBackground,
            ),
            onPressed: () async {
              Navigator.pop(context);
              await _auth.logout();
              if (!context.mounted) return;
              Navigator.pushReplacementNamed(context, '/login');
            },
            child: const Text("Logout"),
          ),
        ],
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

/// ✅ Subtle hover darken only (no lift, no border/shadow shifts)
class _SubtleHoverTile extends StatefulWidget {
  const _SubtleHoverTile({
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
  State<_SubtleHoverTile> createState() => _SubtleHoverTileState();
}

class _SubtleHoverTileState extends State<_SubtleHoverTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black.withOpacity(0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            hoverColor: Colors.black.withOpacity(0.03),
            highlightColor: Colors.black.withOpacity(0.05),
            splashColor: Colors.black.withOpacity(0.04),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      widget.icon,
                      color: AppColors.brandBlue,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF101828),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF475467),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: AppColors.brandBlue.withOpacity(0.85),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
