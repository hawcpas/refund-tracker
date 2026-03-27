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
import '../screens/otp_verify_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

const double kTopBarHeight = 48;

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.initialRoute = '/dashboard',
    this.deepLinkRid,
  });

  final String initialRoute;
  final String? deepLinkRid;

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> with TickerProviderStateMixin {
  final _auth = AuthService();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _avatarHover = false;
  bool _settingsHover = false;
  bool _sidebarCollapsed = false;
  bool _isAdminUser = false;
  bool _authReady = false;
  bool _otpVerified = false;
  StreamSubscription<User?>? _tokenSub;

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

  OverlayEntry? _accountSettingsEntry;
  late final AnimationController _accountSettingsAnim;

  bool get _isAccountSettingsOpen => _accountSettingsEntry != null;

  String _formatUsPhone10(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) return input.trim();
    final t = digits.substring(digits.length - 10);
    return '${t.substring(0, 3)}-${t.substring(3, 6)}-${t.substring(6)}';
  }

  void _dismissSettingsMenuImmediate() {
    if (_settingsEntry == null) return;
    _settingsAnim.stop();
    _settingsEntry?.remove();
    _settingsEntry = null;
    _settingsAnim.value = 0; // reset
  }

  void _dismissAvatarMenuImmediate() {
    if (_avatarEntry == null) return;
    _avatarAnim.stop();
    _avatarEntry?.remove();
    _avatarEntry = null;
    _avatarAnim.value = 0; // reset
  }

  /// ✅ Public API for opening Account Settings
  void openAccountSettings(BuildContext context) {
    _openAccountSettingsFlyout(context);
  }

  /// ✅ Public API: navigate to Admin screen
  void openAdmin() {
    setState(() {
      _currentRoute = '/admin-users';
    });
  }

  /// ✅ Refresh profile-dependent UI (avatar, menus, etc.)
  /// ✅ Refresh profile-dependent UI (avatar, menus, flyouts)
  Future<void> refreshProfile() async {
    if (!mounted) return;

    // Force shell rebuild (AppBar, avatar, dashboard welcome, etc.)
    setState(() {});

    // ✅ If avatar menu is open, close it so it reopens with fresh data
    if (_isAvatarMenuOpen) {
      _dismissAvatarMenuImmediate();
    }

    // ✅ If account settings flyout is open, close it
    if (_isAccountSettingsOpen) {
      await _closeAccountSettingsFlyout();
    }
  }

  Future<void> _loadMyRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() => _isAdminUser = false);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final data = doc.data() ?? {};
      final role = (data['role'] ?? '').toString().toLowerCase().trim();

      if (!mounted) return;
      setState(() => _isAdminUser = role == 'admin');

      // Safety: if someone is on admin route but not admin, bounce them out
      if (role != 'admin' && _currentRoute == '/admin-users') {
        setState(() => _currentRoute = '/dashboard');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isAdminUser = false);
    }
  }

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
    String wildixExt = '',
    String clearflyNumber = '',
  }) {
    _dismissSettingsMenuImmediate();
    if (_isAvatarMenuOpen) {
      _closeAvatarMenu();
      return;
    }

    final overlay = Overlay.of(ctx);
    if (overlay == null) return;

    _avatarEntry = OverlayEntry(
      builder: (context) {
        final parts = displayName.trim().split(RegExp(r'\s+'));
        final initials = parts.length >= 2
            ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
            : (parts.isNotEmpty ? parts.first[0].toUpperCase() : '?');

        const double appBarHeight = kTopBarHeight;

        return Stack(
          children: [
            // ✅ Click-outside closes ONLY below the AppBar (keeps AppBar clickable)
            Positioned(
              top: appBarHeight,
              left: 0,
              right: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _closeAvatarMenu,
                child: const SizedBox.shrink(),
              ),
            ),

            // ✅ Flyout aligned to bottom of AppBar, right aligned like Microsoft
            Positioned(
              top: appBarHeight,
              right: 12,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 360, // ✅ wider so label/value never collide
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black.withOpacity(0.08)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.14),
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
                        // Top row: Org name + Sign out
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Axume & Associates CPAs, AAC',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  color: Color(0xFF101828),
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
                        const SizedBox(height: 12),

                        // Profile row: big initials left, info right
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _InitialsCircle(initials: initials),
                            const SizedBox(width: 14),

                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      color: Color(0xFF101828),
                                      height: 1.15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),

                                  Text(
                                    email,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: Color(0xFF475467),
                                      height: 1.2,
                                    ),
                                  ),

                                  const SizedBox(height: 8),

                                  // ✅ Side-by-side label/value rows (no overlap)
                                  if (wildixExt.isNotEmpty)
                                    _ProfileMetaInline(
                                      label: 'Wildix extension',
                                      value: wildixExt,
                                    ),

                                  if (clearflyNumber.isNotEmpty)
                                    _ProfileMetaInline(
                                      label: 'Clearfly / eFax',
                                      value: clearflyNumber,
                                    ),

                                  const SizedBox(height: 12),
                                ],
                              ),
                            ),
                          ],
                        ),

                        // ✅ Removed the old duplicate Communication section entirely
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
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
    _accountSettingsAnim.dispose();
    _tokenSub?.cancel();
    super.dispose();
  }

  void _toggleAccountSettingsFlyout(BuildContext context) {
    if (_isAccountSettingsOpen) {
      _closeAccountSettingsFlyout();
    } else {
      _openAccountSettingsFlyout(context);
    }
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

  void _openAccountSettingsFlyout(BuildContext context) {
    // If already open or animating open, do nothing
    if (_isAccountSettingsOpen) return;

    final overlay = Overlay.of(context);
    if (overlay == null) return;

    _accountSettingsEntry = OverlayEntry(
      builder: (ctx) {
        // One controller drives everything.
        final progress = CurvedAnimation(
          parent: _accountSettingsAnim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return RightSideFlyout(
          onClose: _closeAccountSettingsFlyout,
          width: MediaQuery.of(context).size.width < 520
              ? MediaQuery.of(context).size.width
              : 480,
          progress: progress,

          // ✅ This whole child will fade in only in the last quarter (handled by flyout)
          child: Column(
            children: [
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.black.withOpacity(0.08)),
                  ),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Account settings',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: _closeAccountSettingsFlyout,
                    ),
                  ],
                ),
              ),

              // ✅ Defer heavy screen build until animation is ~75% complete (prevents stutter)
              Expanded(
                child: _DeferredBuild(
                  animation: progress,
                  threshold: 0.75,
                  placeholder: const _FlyoutSkeleton(),
                  builder: (_) => const AccountSettingsScreen(embed: true),
                ),
              ),
            ],
          ),
        );
      },
    );

    overlay.insert(_accountSettingsEntry!);

    // ✅ Start animation after insertion
    _accountSettingsAnim.forward(from: 0);
  }

  Future<void> _closeAccountSettingsFlyout() async {
    if (_accountSettingsEntry == null) return;
    await _accountSettingsAnim.reverse();
    _accountSettingsEntry?.remove();
    _accountSettingsEntry = null;
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

  Widget _buildSettingsMenuContent(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () {
            Navigator.pop(context); // close bottom sheet
            _openAccountSettingsFlyout(context);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: const [
                Icon(
                  Icons.settings_outlined,
                  size: 20,
                  color: Color(0xFF101828),
                ),
                SizedBox(width: 12),
                Text(
                  'Settings',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Color(0xFF101828),
                  ),
                ),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: Colors.black.withOpacity(0.06)),
        InkWell(
          onTap: () async {
            Navigator.pop(context); // close bottom sheet
            await _openSupportEmail();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: const [
                Icon(Icons.help_outline, size: 20, color: Color(0xFF101828)),
                SizedBox(width: 12),
                Text(
                  'Support',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Color(0xFF101828),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _toggleSettingsMenu(BuildContext ctx) {
    _dismissAvatarMenuImmediate();

    // ✅ DESKTOP: existing behavior below
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
                offset: const Offset(0, 4),
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
                              offset: const Offset(0, 4),
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
                                _openAccountSettingsFlyout(context);
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
    // ✅ Deep-link support: open specific upload details from email link
    final rid = widget.deepLinkRid;
    if (rid != null &&
        rid.trim().isNotEmpty &&
        _currentRoute == '/generate-upload-link') {
      _dropoffDetailsId = rid.trim();
      _currentRoute = '/dropoff-details';
    }
    _loadMyRole();

    _tokenSub = FirebaseAuth.instance.idTokenChanges().listen((user) async {
      if (!mounted) return;

      if (user == null) {
        setState(() {
          _authReady = true;
          _otpVerified = false;
        });
        return;
      }
      final token = await user.getIdTokenResult(true);
      final claims = token.claims ?? {};
      final otp = claims['otp_verified'] == true;

      final at = claims['otp_verified_at'];
      final atMs = (at is int) ? at : (at is num ? at.toInt() : 0);
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      // ✅ 1 hour validity
      final otpFresh = otp && atMs > 0 && (nowMs - atMs) <= (60 * 60 * 1000);

      setState(() {
        _authReady = true;
        _otpVerified = otpFresh;
      });
    });

    _accountSettingsAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 160),
    );

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

    final encodedSubject = Uri.encodeComponent(subject);
    final encodedBody = Uri.encodeComponent(body);

    final uri = Uri.parse(
      'mailto:support@axumecpas.com'
      '?subject=$encodedSubject'
      '&body=$encodedBody',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _navigate(String route) async {
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.pop(context);
    }
    if (route == '/admin-users' && !_isAdminUser) return;

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

  String _initialsFromProfile({
    required String firstName,
    required String lastName,
    String? fallback,
  }) {
    final f = firstName.trim();
    final l = lastName.trim();

    if (f.isNotEmpty && l.isNotEmpty) {
      return '${f[0]}${l[0]}'.toUpperCase();
    }

    if (f.isNotEmpty) {
      return f[0].toUpperCase();
    }

    if (fallback != null && fallback.trim().isNotEmpty) {
      final parts = fallback.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      }
      return parts[0][0].toUpperCase();
    }

    return '?';
  }

  @override
  Widget build(BuildContext context) {
    // =========================
    // 🔐 OTP / Auth HARD GATE
    // =========================

    // Block rendering until we know auth + claims state
    if (!_authReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Signed in but OTP not verified → force OTP screen
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !_otpVerified) {
      return const OtpVerifyScreen();
    }

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
      backgroundColor: AppColors.pageCanvas, // ✅ Fluent canvas

      appBar: AppBar(
        toolbarHeight: kTopBarHeight,
        titleSpacing: 16, // ✅ tighter horizontal rhythm

        title: Text(
          _titleFor(_currentRoute),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            height: 1.1, // ✅ prevents vertical inflation
          ),
        ),

        leading: leading,

        backgroundColor: isAdminConsole ? Colors.black : AppColors.brandBlue,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,

        actions: [
          IconButton(
            tooltip: 'Account settings',
            icon: const Icon(Icons.settings_outlined, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onPressed: () {
              // ✅ prevent stacked overlays
              _dismissAvatarMenuImmediate();
              _dismissSettingsMenuImmediate();

              // ✅ Toggle Account Settings flyout (open/close)
              if (_isAccountSettingsOpen) {
                _closeAccountSettingsFlyout(); // reverse animation already implemented
              } else {
                _openAccountSettingsFlyout(context);
              }
            },
          ),

          IconButton(
            tooltip: 'Support',
            icon: const Icon(Icons.help_outline, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onPressed: _openSupportEmail,
          ),

          const SizedBox(width: 6),

          // =========================
          // USER AVATAR + PROFILE FLYOUT
          // =========================
          Builder(
            builder: (ctx) {
              final user = FirebaseAuth.instance.currentUser;
              final email = user?.email ?? '';

              return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: user == null
                    ? null
                    : FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .get(),
                builder: (context, snapshot) {
                  String firstName = '';
                  String lastName = '';
                  String fallbackName =
                      user?.displayName?.trim().isNotEmpty == true
                      ? user!.displayName!
                      : email;

                  if (snapshot.hasData && snapshot.data?.data() != null) {
                    final data = snapshot.data!.data()!;
                    firstName = (data['firstName'] ?? '').toString().trim();
                    lastName = (data['lastName'] ?? '').toString().trim();
                  }

                  final initials = _initialsFromProfile(
                    firstName: firstName,
                    lastName: lastName,
                    fallback: fallbackName,
                  );

                  return CompositedTransformTarget(
                    link: _avatarLink,
                    child: FocusableActionDetector(
                      autofocus: false,
                      mouseCursor: SystemMouseCursors.click,
                      onShowHoverHighlight: (hover) =>
                          setState(() => _avatarHover = hover),
                      child: GestureDetector(
                        onTap: () async {
                          final user = FirebaseAuth.instance.currentUser;
                          String wildix = '';
                          String clearfly = '';

                          if (user != null) {
                            try {
                              final doc = await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(user.uid)
                                  .get();

                              final data = doc.data() ?? {};
                              final comms = Map<String, dynamic>.from(
                                data['communications'] ?? {},
                              );
                              wildix = (comms['wildixExtension'] ?? '')
                                  .toString()
                                  .trim();
                              clearfly = _formatUsPhone10(
                                (comms['clearflySmsNumber'] ?? '')
                                    .toString()
                                    .trim(),
                              );
                            } catch (_) {
                              // Keep empty if load fails
                            }
                          }

                          _toggleAvatarMenu(
                            ctx: ctx,
                            displayName:
                                '$firstName $lastName'.trim().isNotEmpty
                                ? '$firstName $lastName'
                                : fallbackName,
                            email: email,
                            wildixExt: wildix,
                            clearflyNumber: clearfly,
                          );
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          margin: const EdgeInsets.only(right: 12),
                          height: 28,
                          width: 28,
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
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
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
                  collapsed: false,
                  onToggleCollapse: () {},
                  showAdmin: _isAdminUser, // ✅ add
                ),
              ),
            )
          : null,

      // Desktop: fixed sidebar + inner navigator
      body: Row(
        children: [
          if (!isMobileShell)
            _SidebarNav(
              currentRoute: _currentRoute,
              onNavigate: _navigate,
              collapsed: _sidebarCollapsed,
              onToggleCollapse: () {
                setState(() => _sidebarCollapsed = !_sidebarCollapsed);
              },
              showAdmin: _isAdminUser, // ✅ add
            ),

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
  const _SidebarNav({
    required this.currentRoute,
    required this.onNavigate,
    required this.collapsed,
    required this.onToggleCollapse,
    required this.showAdmin, // ✅ add
  });

  final String currentRoute;
  final void Function(String route) onNavigate;
  final bool collapsed;
  final VoidCallback onToggleCollapse;
  final bool showAdmin; // ✅ add

  @override
  Widget build(BuildContext context) {
    return Container(
      width: collapsed ? 64 : 210,
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      decoration: BoxDecoration(
        color: AppColors.navRail,
        border: Border(
          right: BorderSide(color: Colors.black.withOpacity(0.06)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            tooltip: collapsed ? 'Expand navigation' : 'Collapse navigation',
            icon: const Icon(Icons.menu),
            onPressed: onToggleCollapse,
          ),
          const SizedBox(height: 12),

          if (showAdmin) ...[
            const SizedBox(height: 10),
            Divider(height: 1, color: Colors.black.withOpacity(0.08)),
            const SizedBox(height: 10),

            if (!collapsed)
              const Padding(
                padding: EdgeInsets.only(left: 8, bottom: 6),
                child: Text(
                  'ADMIN',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: Color(0xFF111827), // ✅ different section color
                  ),
                ),
              ),

            _SidebarNavItem(
              icon: Icons.admin_panel_settings_outlined,
              label: 'Admin Console',
              route: '/admin-users',
              currentRoute: currentRoute,
              onNavigate: onNavigate,
              collapsed: collapsed,

              // ✅ use a distinct accent color for admin
              accentOverride: const Color(0xFF111827),
            ),
          ],

          const SizedBox(height: 6),
          Divider(height: 1, color: Colors.black.withOpacity(0.08)),
          const SizedBox(height: 6),

          _SidebarNavItem(
            icon: Icons.dashboard_outlined,
            label: 'Dashboard',
            route: '/dashboard',
            currentRoute: currentRoute,
            onNavigate: onNavigate,
            collapsed: collapsed,
          ),
          const SizedBox(height: 4),

          _SidebarNavItem(
            icon: Icons.folder_open_outlined,
            label: 'File Box',
            route: '/file-box',
            currentRoute: currentRoute,
            onNavigate: onNavigate,
            collapsed: collapsed,
          ),
          const SizedBox(height: 4),

          _SidebarNavItem(
            icon: Icons.link_outlined,
            label: 'Client Upload Links',
            route: '/generate-upload-link',
            currentRoute: currentRoute,
            onNavigate: onNavigate,
            collapsed: collapsed,
          ),
          const SizedBox(height: 4),

          _SidebarNavItem(
            icon: Icons.folder_shared_outlined,
            label: 'Firm Documents',
            route: '/shared-files',
            currentRoute: currentRoute,
            onNavigate: onNavigate,
            collapsed: collapsed,
          ),
          const SizedBox(height: 4),

          _SidebarNavItem(
            icon: Icons.link_outlined,
            label: 'Websites & Resources',
            route: '/resources',
            currentRoute: currentRoute,
            onNavigate: onNavigate,
            collapsed: collapsed,
          ),
          const SizedBox(height: 4),

          _SidebarNavItem(
            icon: Icons.person_outline,
            label: 'Account Settings',
            route: '/account-settings',
            currentRoute: currentRoute,
            onNavigate: onNavigate,
            collapsed: collapsed,
          ),

          const SizedBox(height: 6),
          Divider(height: 1, color: Colors.black.withOpacity(0.08)),
          const SizedBox(height: 6),

          _SidebarNavItem(
            icon: Icons.logout,
            label: 'Sign out',
            route: '__logout__',
            danger: true,
            currentRoute: currentRoute,
            onNavigate: onNavigate,
            collapsed: collapsed,
          ),
        ],
      ),
    );
  }
}

class _SidebarNavItem extends StatefulWidget {
  const _SidebarNavItem({
    required this.icon,
    required this.label,
    required this.route,
    required this.currentRoute,
    required this.onNavigate,
    required this.collapsed,
    this.danger = false,
    this.accentOverride, // ✅ add
  });

  final IconData icon;
  final String label;
  final String route;
  final String currentRoute;
  final void Function(String route) onNavigate;
  final bool danger;
  final bool collapsed;
  final Color? accentOverride;

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bool isActive = widget.currentRoute == widget.route;

    final Color accent =
        widget.accentOverride ??
        (widget.danger ? const Color(0xFFB42318) : AppColors.brandBlue);

    final Color textColor = widget.danger
        ? const Color(0xFFB42318)
        : const Color(0xFF344054);

    final Color iconColor = widget.danger
        ? const Color(0xFFB42318)
        : const Color(0xFF667085);

    // ✅ Microsoft-style background behavior
    final bool isAdminItem = widget.accentOverride != null;

    final Color backgroundColor = isActive
        ? accent.withOpacity(isAdminItem ? 0.14 : 0.10)
        : _hover
        ? (isAdminItem
              // ✅ subtle purple/gray hover for admin items
              ? const Color(0xFFEDE9FE) // light indigo/purple tint
              : Colors.black.withOpacity(0.06))
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => widget.onNavigate(widget.route),
        child: Container(
          height: 42, // ✅ consistent row height
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(6), // ✅ subtle, not pill
          ),
          child: Row(
            children: [
              // ✅ Left accent bar for active state
              Container(
                width: 3,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: isActive ? accent : Colors.transparent,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(6),
                    bottomLeft: Radius.circular(6),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              Icon(
                widget.icon,
                size: 18,
                color: isActive
                    ? accent
                    : (widget.accentOverride != null && _hover
                          ? accent.withOpacity(0.85)
                          : iconColor),
              ),

              if (!widget.collapsed) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13, // ✅ Microsoft-like size
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                      color: isActive ? accent : textColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class RightSideFlyout extends StatelessWidget {
  final Widget child;
  final VoidCallback onClose;
  final double width;

  /// Progress 0 → 1 controls width + fades.
  final Animation<double> progress;

  const RightSideFlyout({
    super.key,
    required this.child,
    required this.onClose,
    required this.progress,
    this.width = 480,
  });

  @override
  Widget build(BuildContext context) {
    const double appBarHeight = kTopBarHeight;

    return Stack(
      children: [
        // ✅ Click-outside closes ONLY below the AppBar (AppBar stays usable)
        Positioned(
          top: appBarHeight,
          left: 0,
          right: 0,
          bottom: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onClose,
            child: const SizedBox.shrink(),
          ),
        ),

        // ✅ Animated panel: width grows/shrinks (no instant reserved space)
        Positioned(
          top: appBarHeight,
          right: 0,
          bottom: 0,
          child: AnimatedBuilder(
            animation: progress,
            builder: (context, _) {
              final t = progress.value.clamp(0.0, 1.0);
              final w = width * t;

              // Don’t paint anything once it’s essentially closed.
              if (w <= 0.5) return const SizedBox.shrink();

              // Phase A (0 → .75): panel fades in as it expands
              final panelOpacity = (t / 0.75).clamp(0.0, 1.0);

              // Phase B (.75 → 1): content fades in subtly near the end
              final contentOpacity = ((t - 0.75) / 0.25).clamp(0.0, 1.0);

              // Small slide for content during fade-in (very subtle)
              final contentDx = 10 * (1 - contentOpacity);

              return SizedBox(
                width: w,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    // ✅ allows shadow to extend left without clipping
                    padding: const EdgeInsets.only(left: 24),
                    child: GestureDetector(
                      onTap: () {}, // absorb taps inside
                      child: SizedBox(
                        width: width,
                        height: double.infinity,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(panelOpacity),

                            // ✅ Structural left divider
                            border: Border(
                              left: BorderSide(
                                color: Colors.black.withOpacity(
                                  0.10 * panelOpacity,
                                ),
                                width: 1,
                              ),
                            ),

                            // ✅ Enterprise left‑cast shadow (NOW VISIBLE)
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(
                                  0.22 * panelOpacity,
                                ),
                                blurRadius: 32,
                                spreadRadius: 2,
                                offset: const Offset(-8, 0),
                              ),
                              BoxShadow(
                                color: Colors.black.withOpacity(
                                  0.10 * panelOpacity,
                                ),
                                blurRadius: 8,
                                offset: const Offset(-2, 0),
                              ),
                            ],
                          ),
                          child: RepaintBoundary(
                            child: Opacity(
                              opacity: contentOpacity,
                              child: Transform.translate(
                                offset: Offset(contentDx, 0),
                                child: child,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _InitialsCircle extends StatelessWidget {
  final String initials;
  const _InitialsCircle({required this.initials});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      width: 72,
      decoration: BoxDecoration(
        color: AppColors.brandBlue, // ✅ brand blue
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: Colors.white, // ✅ white initials
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ProfileMetaInline extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileMetaInline({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      // ✅ Microsoft uses ~4px between metadata rows
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.2,
                color: Color(0xFF667085),
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.2,
                color: Color(0xFF101828),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeferredBuild extends StatelessWidget {
  final Animation<double> animation;
  final double threshold;
  final Widget placeholder;
  final Widget Function(BuildContext) builder;

  const _DeferredBuild({
    required this.animation,
    required this.threshold,
    required this.placeholder,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (ctx, _) {
        final t = animation.value;
        if (t < threshold) return placeholder;
        return builder(ctx);
      },
    );
  }
}

class _FlyoutSkeleton extends StatelessWidget {
  const _FlyoutSkeleton();

  Widget _line({double w = double.infinity, double h = 14}) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.06),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _line(w: 220, h: 16),
          const SizedBox(height: 10),
          _line(w: 320),
          const SizedBox(height: 24),
          _line(h: 44),
          const SizedBox(height: 12),
          _line(h: 44),
          const SizedBox(height: 12),
          _line(h: 44),
          const SizedBox(height: 12),
          _line(h: 44),
          const SizedBox(height: 24),
          _line(w: 180, h: 44),
        ],
      ),
    );
  }
}
