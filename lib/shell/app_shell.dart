import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../services/auth_service.dart';

// Content screens (these should NOT contain sidebars/appbars after refactor)
import '../screens/dashboard_screen.dart';
import '../screens/shared_files_screen.dart';
import '../screens/resources_screen.dart';
import '../screens/account_settings_screen.dart';
import '../screens/dropoff_uploads_screen.dart';
import '../screens/view_dropoff_screen.dart';
import '../screens/admin_users_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialRoute = '/dashboard'});

  final String initialRoute;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _auth = AuthService();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _innerNavKey = GlobalKey<NavigatorState>();

  late String _currentRoute;

  @override
  void initState() {
    super.initState();
    _currentRoute = widget.initialRoute;
  }

  // Keeps _currentRoute synced when user presses back within shell
  late final NavigatorObserver _observer = _ShellNavObserver(
    onRouteChanged: (name) {
      if (name == null || name.isEmpty) return;
      if (!mounted) return;
      setState(() => _currentRoute = name);
    },
  );

  String _titleFor(String route) {
    switch (route) {
      case '/shared-files':
        return 'Firm Documents';
      case '/resources':
        return 'Websites & Resources';
      case '/account-settings':
        return 'Account Settings';
      case '/dropoff-uploads':
        return 'File Box';
      case '/view-dropoffs':
        return 'Client Upload Links';
      case '/admin-users':
        return 'Admin Console';
      case '/dashboard':
      default:
        return 'Dashboard';
    }
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

    // Root navigation back to public login
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  void _navigate(String route) async {
    // Close drawer first on mobile
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.pop(context);
    }

    // Logout is an action, not a route
    if (route == '__logout__') {
      await _logout();
      return;
    }

    if (route == _currentRoute) return;

    // Navigate within the *inner* navigator so we do NOT create a new shell
    _innerNavKey.currentState?.pushNamed(route);
  }

  bool get _canPopInner => _innerNavKey.currentState?.canPop() == true;

  @override
  Widget build(BuildContext context) {
    final isMobileShell = MediaQuery.of(context).size.width < 900;
    final isAdminConsole = _currentRoute == '/admin-users';

    // Enterprise behavior:
    // - On mobile: show back if inner stack can pop, else show menu
    // - On desktop: optional back if inner stack can pop
    Widget? leading;
    if (isMobileShell) {
      leading = IconButton(
        icon: Icon(_canPopInner ? Icons.arrow_back : Icons.menu),
        onPressed: () {
          if (_canPopInner) {
            _innerNavKey.currentState?.maybePop();
          } else {
            _scaffoldKey.currentState?.openDrawer();
          }
        },
      );
    } else if (_canPopInner) {
      leading = IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => _innerNavKey.currentState?.maybePop(),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.pageBackgroundLight,

      appBar: AppBar(
        title: Text(_titleFor(_currentRoute)),
        leading: leading,

        // ✅ Admin Console gets black top bar
        backgroundColor: isAdminConsole ? Colors.black : AppColors.brandBlue,
        foregroundColor: Colors.white,

        // ✅ Correct status bar icons (white on dark)
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),

      // Drawer on mobile
      drawer: isMobileShell
          ? Drawer(
              child: SafeArea(
                child: _SidebarNav(
                  currentRoute: _currentRoute,
                  onNavigate: _navigate,
                ),
              ),
            )
          : null,

      // Desktop: fixed sidebar + inner navigator
      body: Row(
        children: [
          if (!isMobileShell)
            _SidebarNav(currentRoute: _currentRoute, onNavigate: _navigate),

          Expanded(
            child: Navigator(
              key: _innerNavKey,
              initialRoute: widget.initialRoute,
              observers: [_observer],
              onGenerateRoute: (settings) {
                final name = settings.name ?? '/dashboard';

                Widget page;
                switch (name) {
                  case '/shared-files':
                    page = const SharedFilesScreen();
                    break;
                  case '/resources':
                    page = const ResourcesScreen();
                    break;
                  case '/account-settings':
                    page = const AccountSettingsScreen();
                    break;
                  case '/dropoff-uploads':
                    page = const DropoffUploadsScreen();
                    break;
                  case '/view-dropoffs':
                    page = const ViewDropoffsScreen();
                    break;
                  case '/admin-users':
                    page = const AdminUsersScreen();
                    break;
                  case '/dashboard':
                  default:
                    page = const DashboardScreen();
                }

                return MaterialPageRoute(
                  settings: settings,
                  builder: (_) => page,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Navigator observer to keep shell state aligned with inner navigation
class _ShellNavObserver extends NavigatorObserver {
  _ShellNavObserver({required this.onRouteChanged});
  final void Function(String? name) onRouteChanged;

  @override
  void didPush(Route route, Route? previousRoute) {
    onRouteChanged(route.settings.name);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    onRouteChanged(previousRoute?.settings.name);
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    onRouteChanged(newRoute?.settings.name);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

/// ============================
/// Sidebar Navigation (single source of truth)
/// ============================
class _SidebarNav extends StatelessWidget {
  const _SidebarNav({required this.currentRoute, required this.onNavigate});

  final String currentRoute;
  final void Function(String route) onNavigate;

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
    return Container(
      width: 210,
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
          Divider(height: 1, color: Colors.black.withOpacity(0.08)),
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
