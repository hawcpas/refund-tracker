import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../services/auth_service.dart';

// Content screens (these should NOT contain sidebars/appbars after refactor)
import '../screens/dashboard_screen.dart';
import '../screens/shared_files_screen.dart';
import '../screens/resources_screen.dart';
import '../screens/account_settings_screen.dart';
import '../screens/file_box.dart';
import '../screens/generate_upload_link.dart';
import '../screens/admin_users_screen.dart';
import '../screens/create_upload_link_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialRoute = '/dashboard'});

  final String initialRoute;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with TickerProviderStateMixin {
  final _auth = AuthService();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _avatarHover = false;
  bool _settingsHover = false;

  late String _currentRoute;
  late final AnimationController _avatarAnim;
  late final AnimationController _settingsAnim;
  String? _dropoffDetailsId;
  final LayerLink _avatarLink = LayerLink();
  OverlayEntry? _avatarEntry;

  bool get _isAvatarMenuOpen => _avatarEntry != null;

  final LayerLink _settingsLink = LayerLink();
  OverlayEntry? _settingsEntry;

  bool get _isSettingsMenuOpen => _settingsEntry != null;

  Future<void> _closeSettingsMenu() async {
    if (_settingsEntry == null) return;

    await _settingsAnim.reverse();
    _settingsEntry?.remove();
    _settingsEntry = null;
  }

  Future<void> _closeAvatarMenu() async {
    if (_avatarEntry == null) return;

    await _avatarAnim.reverse();
    _avatarEntry?.remove();
    _avatarEntry = null;
  }

  void _toggleAvatarMenu({
    required BuildContext ctx,
    required String displayName,
    required String email,
  }) {
    if (_isAvatarMenuOpen) {
      _closeAvatarMenu();
      return;
    }

    final overlay = Overlay.of(ctx);
    if (overlay == null) return;

    _avatarEntry = OverlayEntry(
      builder: (context) {
        // Full-screen "tap outside to close" barrier + anchored menu
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _closeAvatarMenu,
          child: Stack(
            children: [
              CompositedTransformFollower(
                link: _avatarLink,
                showWhenUnlinked: false,
                targetAnchor: Alignment.bottomRight,
                followerAnchor: Alignment.topRight,
                offset: const Offset(0, 8),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: 280,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black.withOpacity(0.08)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Axume & Associates CPAs',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: Color(0xFF101828), // high contrast
                                  ),
                                ),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.brandBlue,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                onPressed: () async {
                                  _closeAvatarMenu();
                                  await _logout();
                                },
                                child: const Text('Sign out'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Divider(
                            height: 1,
                            color: Colors.black.withOpacity(0.08),
                          ),
                          const SizedBox(height: 10),

                          Center(
                            child: Column(
                              children: [
                                Text(
                                  displayName,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: Color(0xFF101828),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  email,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF475467), // readable slate
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    overlay.insert(_avatarEntry!);
    _avatarAnim.forward(from: 0);
  }

  @override
  void dispose() {
    _closeAvatarMenu();
    _closeSettingsMenu();
    _avatarAnim.dispose();
    _settingsAnim.dispose();
    super.dispose();
  }

  void _openDropoffDetails(String requestId) {
    setState(() {
      _dropoffDetailsId = requestId;
      _currentRoute = '/dropoff-details';
    });
  }

  void _openCreateUploadLink() {
    setState(() {
      _currentRoute = '/create-upload-link';
    });
  }

  void _closeCreateUploadLink() {
    setState(() {
      _currentRoute = '/generate-upload-link';
    });
  }

  void _closeDropoffDetails() {
    setState(() {
      _currentRoute = '/generate-upload-link';
      _dropoffDetailsId = null;
    });
  }

  void _toggleSettingsMenu(BuildContext ctx) {
    if (_isSettingsMenuOpen) {
      _closeSettingsMenu();
      return;
    }

    final overlay = Overlay.of(ctx);
    if (overlay == null) return;

    _settingsEntry = OverlayEntry(
      builder: (context) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _closeSettingsMenu,
          child: Stack(
            children: [
              CompositedTransformFollower(
                link: _settingsLink,
                showWhenUnlinked: false,
                targetAnchor: Alignment.bottomRight,
                followerAnchor: Alignment.topRight,
                offset: const Offset(0, 8), // ✅ directly below ⋯
                child: Material(
                  color: Colors.transparent,
                  child: FadeTransition(
                    opacity: CurvedAnimation(
                      parent: _settingsAnim,
                      curve: Curves.easeOutCubic,
                    ),
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.96, end: 1.0).animate(
                        CurvedAnimation(
                          parent: _settingsAnim,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                      alignment: Alignment.topRight,
                      child: Container(
                        width: 200,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.black.withOpacity(0.08),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.12),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // ✅ Settings
                            InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () {
                                _closeSettingsMenu();
                                _navigate('/account-settings');
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: const [
                                    Icon(
                                      Icons.settings_outlined,
                                      size: 18,
                                      color: Color(0xFF101828),
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      'Settings',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF101828),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            Divider(
                              height: 1,
                              color: Colors.black.withOpacity(0.06),
                            ),

                            // ✅ Support (email)
                            InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () async {
                                _closeSettingsMenu();
                                await _openSupportEmail();
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: const [
                                    Icon(
                                      Icons.help_outline,
                                      size: 18,
                                      color: Color(0xFF101828),
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      'Support',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF101828),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    overlay.insert(_settingsEntry!);
    _settingsAnim.forward(from: 0);
  }

  @override
  void initState() {
    super.initState();
    _currentRoute = widget.initialRoute;

    _avatarAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      reverseDuration: const Duration(milliseconds: 90),
    );

    _settingsAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      reverseDuration: const Duration(milliseconds: 90),
    );
  }

  String _titleFor(String route) {
    switch (route) {
      case '/shared-files':
        return 'Firm Documents';
      case '/create-upload-link':
        return 'Create Client Upload Link';
      case '/resources':
        return 'Websites & Resources';
      case '/account-settings':
        return 'Account Settings';
      case '/file-box':
        return 'File Box';
      case '/generate-upload-link':
        return 'Client Upload Links';
      case '/admin-users':
        return 'Admin Console';
      case '/dropoff-details':
        return 'Upload Link Details';
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

  Future<void> _openSupportEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    final userEmail = user?.email ?? 'Unknown';

    final now = DateTime.now();
    final timestamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final screenTitle = _titleFor(_currentRoute);

    final subject = 'Portal Support Request';

    final body =
        '''
User Email: $userEmail
Timestamp: $timestamp
Current Screen: $screenTitle

Please describe the issue below:

''';

    final uri = Uri(
      scheme: 'mailto',
      path: 'support@axumecpas.com',
      queryParameters: {'subject': subject, 'body': body},
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _navigate(String route) async {
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.pop(context);
    }

    if (route == '__logout__') {
      await _logout();
      return;
    }

    if (route == _currentRoute) return;

    // ✅ Swap content only — do NOT touch Navigator
    setState(() => _currentRoute = route);
  }

  Widget _buildContent() {
    switch (_currentRoute) {
      case '/dropoff-details':
        return DropoffDetailScreen(
          requestId: _dropoffDetailsId!,
          onBack: _closeDropoffDetails,
        );
      case '/shared-files':
        return const SharedFilesScreen();
      case '/resources':
        return const ResourcesScreen();
      case '/account-settings':
        return const AccountSettingsScreen();
      case '/file-box':
        return const FileBoxScreen();
      case '/generate-upload-link':
        return GenerateUploadLinkScreen(
          onOpenDetails: _openDropoffDetails,
          onCreate: _openCreateUploadLink,
        );
      case '/create-upload-link':
        return CreateUploadLinkScreen(
          onCancel: () => _navigate('/generate-upload-link'),
        );
      case '/admin-users':
        return const AdminUsersScreen();
      case '/dashboard':
      default:
        return const DashboardScreen();
    }
  }

  String _initialsFromName(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final isMobileShell = MediaQuery.of(context).size.width < 900;
    final isAdminConsole = _currentRoute == '/admin-users';

    // Enterprise behavior:
    // - On mobile: show back if inner stack can pop, else show menu
    // - On desktop: optional back if inner stack can pop
    Widget? leading;

    final isBackRoute =
        _currentRoute == '/dropoff-details' ||
        _currentRoute == '/create-upload-link';

    if (isMobileShell) {
      leading = IconButton(
        icon: Icon(isBackRoute ? Icons.arrow_back : Icons.menu),
        onPressed: () {
          if (_currentRoute == '/dropoff-details') {
            _closeDropoffDetails();
          } else if (_currentRoute == '/create-upload-link') {
            _closeCreateUploadLink();
          } else {
            _scaffoldKey.currentState?.openDrawer();
          }
        },
      );
    } else {
      leading = isBackRoute
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _currentRoute == '/dropoff-details'
                  ? _closeDropoffDetails
                  : _closeCreateUploadLink,
            )
          : null;
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.pageBackgroundLight,

      appBar: AppBar(
        title: Text(_titleFor(_currentRoute)),
        leading: leading,

        backgroundColor: isAdminConsole ? Colors.black : AppColors.brandBlue,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,

        actions: [
          // =========================
          // ⋯ SETTINGS FLYOUT (ICON ONLY — trigger)
          // =========================
          MouseRegion(
            onEnter: (_) => setState(() => _settingsHover = true),
            onExit: (_) => setState(() => _settingsHover = false),
            child: CompositedTransformTarget(
              link: _settingsLink,
              child: IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.more_vert, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: _settingsHover
                      ? Colors.white.withOpacity(0.15)
                      : Colors.transparent,
                ),
                onPressed: () => _toggleSettingsMenu(context),
              ),
            ),
          ),

          const SizedBox(width: 6),

          // =========================
          // USER AVATAR + PROFILE FLYOUT
          // =========================
          Builder(
            builder: (ctx) {
              final user = FirebaseAuth.instance.currentUser;
              final email = user?.email ?? '';
              final displayName = user?.displayName?.trim().isNotEmpty == true
                  ? user!.displayName!
                  : email;

              final initials = _initialsFromName(displayName);

              return CompositedTransformTarget(
                link: _avatarLink,
                child: FocusableActionDetector(
                  autofocus: false,
                  mouseCursor: SystemMouseCursors.click,
                  onShowHoverHighlight: (hover) =>
                      setState(() => _avatarHover = hover),
                  child: GestureDetector(
                    onTap: () {
                      _toggleAvatarMenu(
                        ctx: ctx,
                        displayName: displayName,
                        email: email,
                      );
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      margin: const EdgeInsets.only(right: 12),
                      height: 32,
                      width: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _avatarHover
                            ? Colors.white.withOpacity(0.15)
                            : Colors.white,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initials,
                        style: TextStyle(
                          color: isAdminConsole
                              ? Colors.black
                              : AppColors.brandBlue,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
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

          Expanded(child: _buildContent()),
        ],
      ),
    );
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
            icon: Icons.folder_open_outlined,
            label: 'File Box',
            route: '/file-box',
          ),
          const SizedBox(height: 4),

          _item(
            icon: Icons.link_outlined,
            label: 'Client Upload Links',
            route: '/generate-upload-link',
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
