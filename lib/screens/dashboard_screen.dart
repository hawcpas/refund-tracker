import 'package:flutter/material.dart';
import 'package:refund_tracker/widgets/centered_form.dart';
import 'package:refund_tracker/widgets/centered_section.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  static const Color brandBlue = Color(0xFF08449E);
  static const Color pageBg = Color(0xFFF6F7F9);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: pageBg,
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
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        children: [
          // ✅ PROFESSIONAL HEADER (NOT A CARD)
          CenteredSection(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Small brand badge (subtle)
                  Container(
                    height: 36,
                    width: 36,
                    decoration: BoxDecoration(
                      color: brandBlue.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.dashboard_rounded,
                      color: brandBlue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Welcome back",
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

                // ✅ Professional tile: white card + subtle hover darkening ONLY
                _SubtleHoverTile(
                  icon: Icons.lock_reset,
                  title: "Change password",
                  subtitle: "Update your login credentials",
                  onTap: () => Navigator.pushNamed(context, '/change-password'),
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
                      backgroundColor: brandBlue,
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(fontWeight: FontWeight.w900),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "You can change your password any time from Account settings.",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF667085),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
        ],
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
              backgroundColor: brandBlue,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacementNamed(context, '/login');
            },
            child: const Text("Logout"),
          ),
        ],
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

  static const Color brandBlue = DashboardScreen.brandBlue;

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
            color: Colors.white,
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
            // ✅ ONLY slight darkening (professional)
            hoverColor: Colors.black.withOpacity(0.03),
            highlightColor: Colors.black.withOpacity(0.05),
            splashColor: Colors.black.withOpacity(0.04),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  // Brand badge (never purple)
                  Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      color: brandBlue.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(widget.icon, color: brandBlue, size: 22),
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
                    color: brandBlue.withOpacity(0.85),
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