import 'package:flutter/material.dart';
import 'package:refund_tracker/widgets/centered_form.dart';
import 'package:refund_tracker/widgets/centered_section.dart';
import 'package:refund_tracker/widgets/dashboard_widgets.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  // ✅ Brand color (accent only)
  static const Color brandBlue = Color(0xFF08449E);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
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

      body: Stack(
        children: [
          // ✅ Extremely subtle brand wash
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    brandBlue.withOpacity(0.04),
                    Colors.white,
                    Colors.white,
                  ],
                  stops: const [0.0, 0.35, 1.0],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),

          ListView(
            padding: const EdgeInsets.symmetric(vertical: 28),
            children: [
              // ✅ HERO / CONTEXT (white, calm)
              CenteredSection(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: brandBlue.withOpacity(0.15)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 48,
                        width: 48,
                        decoration: BoxDecoration(
                          color: brandBlue.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.dashboard_rounded,
                          color: brandBlue,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Welcome back",
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.2,
                                color: const Color(0xFF101828),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "Manage your account and security settings.",
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFF475467),
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 36),

              // ✅ ACCOUNT SECTION (ONLY real actions)
              CenteredSection(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Account",
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                        color: const Color(0xFF101828),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ✅ Interactive card with professional hover / press feedback
                    // ✅ Interactive card with professional hover / press feedback
                    Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),

                        // ✅ subtle interaction feedback
                        splashColor: brandBlue.withOpacity(0.08),
                        highlightColor: brandBlue.withOpacity(0.06),
                        hoverColor: brandBlue.withOpacity(0.04),

                        onTap: () {
                          Navigator.pushNamed(context, '/change-password');
                        },

                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: brandBlue.withOpacity(0.12),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.035),
                                blurRadius: 18,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),

                          // ✅ NOT const + includes onTap (so your widget compiles)
                          child: SettingsRow(
                            icon: Icons.lock_reset,
                            title: "Change password",
                            subtitle: "Update your login credentials",
                            onTap: () {
                              // Leave this empty OR match the same navigation.
                              // If SettingsRow internally handles taps, keep navigation here and remove InkWell's onTap.
                              Navigator.pushNamed(context, '/change-password');
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // ✅ EXIT / ESCAPE HATCH
              CenteredForm(
                child: Column(
                  children: [
                    FilledButton.icon(
                      onPressed: () => _confirmLogout(context),
                      icon: const Icon(Icons.logout),
                      label: const Text("Logout"),
                      style: FilledButton.styleFrom(
                        backgroundColor: brandBlue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                        textStyle: const TextStyle(fontWeight: FontWeight.w800),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
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

              const SizedBox(height: 24),
            ],
          ),
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
