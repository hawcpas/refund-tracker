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
import '../screens/otp_verify_screen.dart';
import '../screens/dropoff_detail_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:flutter_svg/flutter_svg.dart';
import '../theme/brand_logo_svg.dart';

const double kTopBarHeight = 48;
const double kUtilityControlHeight = 36;

// Admin routes
const String kAdminUsersRoute = '/admin-users';
const String kAdminAuditRoute = '/admin-audit';
const String kAdminLinksRoute = '/admin-links';

enum _NavSection { admin, home, files, requests }

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

String _sectionTitle(_NavSection s) {
  switch (s) {
    case _NavSection.admin:
      return 'Admin'; // ✅ ADD
    case _NavSection.files:
      return 'File Box';
    case _NavSection.requests:
      return 'Requests';
    case _NavSection.home:
    default:
      return 'Home';
  }
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
  bool _moreExpanded = false;

  bool get _isMoreRoute =>
      _currentRoute == '/shared-files' ||
      _currentRoute == '/resources' ||
      _currentRoute == '/account-settings';

  StreamSubscription<User?>? _tokenSub;

  late String _currentRoute;
  late final AnimationController _avatarAnim;
  late final AnimationController _settingsAnim;
  String? _dropoffDetailsId;
  int? _unreadOverrideCount;
  final LayerLink _avatarLink = LayerLink();
  OverlayEntry? _avatarEntry;

  // =========================
  // Notifications flyout
  // =========================
  Timestamp? _notifViewedOverrideAt;
  final LayerLink _notificationsLink = LayerLink();
  OverlayEntry? _notificationsEntry;
  late final AnimationController _notificationsAnim;

  bool get _isNotificationsOpen => _notificationsEntry != null;

  bool get _isAvatarMenuOpen => _avatarEntry != null;

  final LayerLink _settingsLink = LayerLink();
  OverlayEntry? _settingsEntry;

  bool get _isSettingsMenuOpen => _settingsEntry != null;

  OverlayEntry? _accountSettingsEntry;
  late final AnimationController _accountSettingsAnim;

  bool get _isAccountSettingsOpen => _accountSettingsEntry != null;

  _NavSection _section = _NavSection.home;

  // Controls the BIG right-hand sidebar
  bool _secondaryPaneCollapsed = false;

  _NavSection _sectionForRoute(String route) {
    if (route == kAdminUsersRoute ||
        route == kAdminAuditRoute ||
        route == kAdminLinksRoute) {
      return _NavSection.admin;
    }

    if (route == '/admin-users') return _NavSection.admin; // ✅ ADD THIS

    if (route == '/file-box') return _NavSection.files;

    if (route == '/generate-upload-link' || route == '/dropoff-details') {
      return _NavSection.requests;
    }

    return _NavSection.home;
  }

  String _formatUsPhone10(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) return input.trim();
    final t = digits.substring(digits.length - 10);
    return '${t.substring(0, 3)}-${t.substring(3, 6)}-${t.substring(6)}';
  }

  void _unawaitedMarkAllNotificationsRead() {
    // fire-and-forget on purpose — UI should NOT wait
    FirebaseFunctions.instance
        .httpsCallable('markNotificationsRead')
        .call()
        .catchError((e) {
          debugPrint('markNotificationsRead failed: $e');
        });
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

  Future<void> _markNotificationsRead() async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('markNotificationsRead')
          .call();
    } catch (e) {
      debugPrint('markNotificationsRead failed: $e');
    }
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

  /// ✅ Public API: open a specific Upload Link / Dropoff detail screen
void openDropoffDetails(String requestId) {
  setState(() {
    _dropoffDetailsId = requestId;
    _currentRoute = '/dropoff-details';
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

        const double appBarHeight = _ContentUtilityBar.height;

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
                child: Builder(
                  builder: (_) {
                    final anim = CurvedAnimation(
                      parent: _avatarAnim,
                      curve: Curves.easeOutCubic,
                      reverseCurve: Curves.easeInCubic,
                    );

                    return FadeTransition(
                      opacity: anim,
                      child: ScaleTransition(
                        scale: Tween<double>(
                          begin: 0.96,
                          end: 1.0,
                        ).animate(anim),
                        alignment: Alignment.topRight,
                        child: Container(
                          width: 360, // ✅ wider so label/value never collide
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: (_avatarHover || _isAvatarMenuOpen)
                                  ? AppColors.brandBlue.withOpacity(
                                      0.45,
                                    ) // ✅ active ring
                                  : Colors.black.withOpacity(0.12),
                              width: 1.25,
                            ),
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
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
    _notificationsAnim.dispose();
    _tokenSub?.cancel();
    super.dispose();
  }

  void _toggleAccountSettingsFlyout(BuildContext context) {
    // ✅ prevent overlay stacking
    _dismissAvatarMenuImmediate();
    _dismissSettingsMenuImmediate();

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
                  builder: (_) => const Scaffold(
                    backgroundColor: Colors.transparent,
                    body: AccountSettingsScreen(embed: true),
                  ),
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

  void _toggleNotificationsMenu(BuildContext ctx) async {
    _dismissAvatarMenuImmediate();
    _dismissSettingsMenuImmediate();

    if (_isNotificationsOpen) {
      _closeNotificationsMenu();
      return;
    }

    // ✅ Immediately clear badge locally (instant UI)
    setState(() {
      _notifViewedOverrideAt = Timestamp.now();
    });

    // ✅ Persist "bell opened" cursor (serverTimestamp)
    FirebaseFunctions.instance
        .httpsCallable('markNotificationsViewed')
        .call()
        .catchError((e) {
          debugPrint('markNotificationsViewed failed: $e');
        });

    // ❌ IMPORTANT: do NOT mark read here
    // _unawaitedMarkAllNotificationsRead();   <-- remove / do not call

    final overlay = Overlay.of(ctx);
    if (overlay == null) return;

    const double appBarHeight = _ContentUtilityBar.height;

    _notificationsEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            // ✅ click-outside closes ONLY below AppBar
            Positioned(
              top: appBarHeight,
              left: 0,
              right: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _closeNotificationsMenu,
                child: const SizedBox.shrink(),
              ),
            ),

            // ✅ anchored flyout (matches avatar/settings)
            Positioned(
              top: appBarHeight,
              right: 72, // 👈 aligns left of avatar
              child: Material(
                color: Colors.transparent,
                child: FadeTransition(
                  opacity: CurvedAnimation(
                    parent: _notificationsAnim,
                    curve: Curves.easeOutCubic,
                    reverseCurve: Curves.easeInCubic,
                  ),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.96, end: 1.0).animate(
                      CurvedAnimation(
                        parent: _notificationsAnim,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                    alignment: Alignment.topRight,
                    child: Container(
                      width: 360,
                      constraints: const BoxConstraints(maxHeight: 420),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.black.withOpacity(0.12),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.14),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: _NotificationsPanel(
                        onOpenRequest: (rid) {
                          _closeNotificationsMenu();
                          _openDropoffDetails(rid);
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_notificationsEntry!);
    _notificationsAnim.forward(from: 0);
  }

  Future<void> _closeNotificationsMenu() async {
    if (_notificationsEntry == null) return;
    await _notificationsAnim.reverse();
    _notificationsEntry?.remove();
    _notificationsEntry = null;
  }

  @override
  void initState() {
    super.initState();
    _currentRoute = widget.initialRoute;
    _section = _sectionForRoute(_currentRoute);
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

      // Signed out
      if (user == null) {
        if (_authReady != true || _otpVerified != false) {
          setState(() {
            _authReady = true;
            _otpVerified = false;
          });
        }
        return;
      }

      // ✅ IMPORTANT: Do NOT force-refresh inside idTokenChanges (no recursion)
      final token = await user.getIdTokenResult(); // <-- no "true"
      final claims = token.claims ?? {};

      final otp = claims['otp_verified'] == true;

      // otp_verified_at (ms)
      final at = claims['otp_verified_at'];
      final otpAtMs = (at is int) ? at : (at is num ? at.toInt() : 0);

      // auth_time (seconds since epoch) -> ms
      final authTime = claims['auth_time'];
      final authMs = (authTime is int)
          ? authTime * 1000
          : (authTime is num ? authTime.toInt() * 1000 : 0);

      final nowMs = DateTime.now().millisecondsSinceEpoch;

      // OTP must be after this login (allow 5s skew)
      final otpAfterThisLogin = authMs == 0 || otpAtMs >= (authMs - 5000);

      // 1 hour validity
      final otpFresh =
          otp &&
          otpAtMs > 0 &&
          otpAfterThisLogin &&
          (nowMs - otpAtMs) <= (60 * 60 * 1000);

      // ✅ Only setState when values actually change (prevents churn)
      if (!_authReady || _otpVerified != otpFresh) {
        setState(() {
          _authReady = true;
          _otpVerified = otpFresh;
        });
      }
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

    _notificationsAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      reverseDuration: const Duration(milliseconds: 90),
    );
  }

  String _titleFor(String route) {
    switch (route) {
      case '/shared-files':
        return 'Firm Documents';
      case '/resources':
        return 'Websites & Resources';
      case '/account-settings':
        return 'Account Settings';
      case '/file-box':
        return 'File Box';
      case '/generate-upload-link':
        return 'Requests';
      case '/admin-users':
        return 'Admin Console';
      case '/dropoff-details':
        return 'Upload Link Details';
      case '/dashboard':
      default:
        return 'Home';
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
    // ✅ prevent accidental navigation to "coming soon" admin pages
    if (route == kAdminAuditRoute || route == kAdminLinksRoute) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Coming soon.')));
      return;
    }

    if (route == '/admin-users' && !_isAdminUser) return;

    // Auto-open "More" when navigating to one of its routes (desktop + mobile)
    if (route == '/shared-files' ||
        route == '/resources' ||
        route == '/account-settings') {
      _moreExpanded = true;
    }

    if (route == '__logout__') {
      await _logout();
      return;
    }

    if (route == _currentRoute) return;

    if (route == '/account-settings') {
      // Prevent stale loading loop when re-entering
      FocusManager.instance.primaryFocus?.unfocus();
    }

    // ✅ Swap content only — do NOT touch Navigator
    setState(() {
      _currentRoute = route;
      _section = _sectionForRoute(route);
    });
  }

  VoidCallback? _currentCreateHandler;

  void _onGlobalSearch(String query) {
    // Temporary stub – safe and intentional
    final q = query.trim();
    if (q.isEmpty) return;

    debugPrint('Global search: $q');

    // ✅ Later this will:
    // - Query files
    // - Query upload links
    // - Query activity / metadata
    // - Show overlay results
  }

  Widget _buildContent() {
    switch (_currentRoute) {
      case '/dropoff-details':
        return DropoffDetailScreen(
          requestId: _dropoffDetailsId!,
          onBack: _closeDropoffDetails,
        );
      case kAdminAuditRoute:
        return const Center(child: Text('Admin audit view (coming soon)'));

      case kAdminLinksRoute:
        return const Center(child: Text('Admin upload links (coming soon)'));

      case '/shared-files':
        return const SharedFilesScreen();
      case '/resources':
        return const ResourcesScreen();
      case '/account-settings':
        return const AccountSettingsScreen();
      case '/file-box':
        return const FileBoxScreen();
      case '/generate-upload-link':
        return GenerateUploadLinkScreen(onOpenDetails: _openDropoffDetails);
      case '/admin-users':
        return const AdminUsersScreen();
      case '/dashboard':
      default:
        return const DashboardScreen();
    }
  }

  Widget _buildAvatarButton(bool isAdminConsole) {
    return Builder(
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
            String fallbackName = user?.displayName?.trim().isNotEmpty == true
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
                mouseCursor: SystemMouseCursors.click,
                onShowHoverHighlight: (hover) =>
                    setState(() => _avatarHover = hover),
                child: GestureDetector(
                  onTap: () async {
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
                          (comms['clearflySmsNumber'] ?? '').toString().trim(),
                        );
                      } catch (_) {}
                    }

                    _toggleAvatarMenu(
                      ctx: ctx,
                      displayName: '$firstName $lastName'.trim().isNotEmpty
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
                          ? const Color(0xFFEFF4FF) // ✅ soft blue hover
                          : const Color(
                              0xFFF1F5F9,
                            ), // ✅ visible neutral surface
                      border: Border.all(color: Colors.black.withOpacity(0.08)),
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
    );
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
    debugPrint('🔁 AppShell BUILD');
    // =========================
    // 🔐 OTP / Auth HARD GATE
    // =========================

    // Block rendering until we know auth + claims state
    if (!_authReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Signed in but OTP not verified → force OTP screen
    final user = FirebaseAuth.instance.currentUser;

    // ✅ Signed out → hard redirect (no UID usage allowed)
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // ✅ Signed in but OTP not verified
    if (!_otpVerified) {
      return const OtpVerifyScreen();
    }

    final uid = user.uid; // ✅ now SAFE
    final isMobileShell = MediaQuery.of(context).size.width < 900;
    final isAdminConsole = _currentRoute == '/admin-users';

    // Enterprise behavior:
    // - On mobile: show back if inner stack can pop, else show menu
    // - On desktop: optional back if inner stack can pop
    Widget? leading;

    final isBackRoute = _currentRoute == '/dropoff-details';

    if (isMobileShell) {
      leading = IconButton(
        icon: Icon(isBackRoute ? Icons.arrow_back : Icons.menu),
        onPressed: () {
          if (_currentRoute == '/dropoff-details') {
            _closeDropoffDetails();
          } else {
            _scaffoldKey.currentState?.openDrawer();
          }
        },
      );
    } else {
      leading = isBackRoute
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _closeDropoffDetails,
            )
          : null;
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.pageCanvas, // ✅ Fluent canvas
      // Drawer on mobile
      drawer: isMobileShell
          ? Drawer(
              child: SafeArea(
                child: _SidebarNav(
                  currentRoute: _currentRoute,
                  onNavigate: _navigate,
                  collapsed: false,
                  onToggleCollapse: () {},
                  showAdmin: _isAdminUser,
                  moreExpanded: _moreExpanded,
                  onToggleMore: () =>
                      setState(() => _moreExpanded = !_moreExpanded),
                ),
              ),
            )
          : null,

      // Desktop: fixed sidebar + inner navigator
      body: Row(
        children: [
          if (!isMobileShell)
            _TwoPaneNav(
              currentRoute: _currentRoute,
              section: _section,
              onSelectSection: (s) {
                setState(() {
                  _section = s;
                  _secondaryPaneCollapsed = false;
                });

                switch (s) {
                  case _NavSection.home:
                    _navigate('/dashboard');
                    break;
                  case _NavSection.files:
                    _navigate('/file-box');
                    break;
                  case _NavSection.requests:
                    _navigate('/generate-upload-link');
                    break;
                  case _NavSection.admin:
                    setState(() {
                      _secondaryPaneCollapsed = false;
                      _moreExpanded = false;
                    });
                    _navigate(kAdminUsersRoute);
                    break;
                }
              },
              secondaryCollapsed: _secondaryPaneCollapsed,
              onToggleSecondary: () {
                setState(
                  () => _secondaryPaneCollapsed = !_secondaryPaneCollapsed,
                );
              },
              onNavigate: _navigate,
              showAdmin: _isAdminUser,
              onLogoTap: () => _navigate('/dashboard'),
            ),

          Expanded(
            child: Container(
              color: AppColors.contentCanvas,
              child: Stack(
                children: [
                  Column(
                    children: [
                      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .snapshots(),
                        builder: (context, userSnap) {
                          final userCursor =
                              (userSnap.data
                                      ?.data()?['lastNotificationsViewedAt']
                                  as Timestamp?) ??
                              Timestamp(0, 0);

                          // ✅ Use local override so badge clears instantly when bell is opened
                          final userCursorMs =
                              userCursor.millisecondsSinceEpoch;
                          final overrideMs =
                              _notifViewedOverrideAt?.millisecondsSinceEpoch ??
                              -1;

                          final effectiveCursor = (overrideMs > userCursorMs)
                              ? _notifViewedOverrideAt!
                              : userCursor;

                          // ✅ Auto-release override once Firestore cursor catches up
                          if (_notifViewedOverrideAt != null &&
                              userCursorMs >= overrideMs) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                setState(() => _notifViewedOverrideAt = null);
                              }
                            });
                          }

                          return StreamBuilder<
                            QuerySnapshot<Map<String, dynamic>>
                          >(
                            stream: FirebaseFirestore.instance
                                .collection('notifications')
                                .where('userUid', isEqualTo: uid)
                                .where(
                                  'createdAt',
                                  isGreaterThan: effectiveCursor,
                                )
                                .orderBy(
                                  'createdAt',
                                  descending: true,
                                ) // ✅ match panel index direction
                                .limit(200) // ✅ safety cap
                                .snapshots(),
                            builder: (context, snap) {
                              // ✅ IMPORTANT: surface Firestore errors instead of silently showing 0
                              if (snap.hasError) {
                                debugPrint(
                                  '🔴 badge query failed: ${snap.error}',
                                );

                                return _ContentUtilityBar(
                                  leading: leading,
                                  onSearch: _onGlobalSearch,
                                  onCreateNew: () =>
                                      _navigate('/generate-upload-link'),
                                  onOpenSettings: () =>
                                      _toggleAccountSettingsFlyout(context),
                                  onOpenSupport: _openSupportEmail,
                                  onOpenNotifications: () =>
                                      _toggleNotificationsMenu(context),
                                  notificationCount: 0, // safe fallback
                                  avatar: _buildAvatarButton(isAdminConsole),
                                );
                              }

                              int newUploadCount = 0;

                              if (snap.hasData) {
                                for (final d in snap.data!.docs) {
                                  final data = d.data();
                                  final type = (data['type'] ?? '').toString();

                                  if (type == 'dropoff_upload') {
                                    final fc = data['fileCount'];
                                    final n = (fc is int)
                                        ? fc
                                        : (fc is num ? fc.toInt() : 1);
                                    newUploadCount += (n <= 0 ? 1 : n);
                                  } else {
                                    newUploadCount += 1;
                                  }
                                }
                              }

                              return _ContentUtilityBar(
                                leading: leading,
                                onSearch: _onGlobalSearch,
                                onCreateNew: () =>
                                    _navigate('/generate-upload-link'),
                                onOpenSettings: () =>
                                    _toggleAccountSettingsFlyout(context),
                                onOpenSupport: _openSupportEmail,
                                onOpenNotifications: () =>
                                    _toggleNotificationsMenu(context),
                                notificationCount: newUploadCount,
                                avatar: _buildAvatarButton(isAdminConsole),
                              );
                            },
                          );
                        },
                      ),
                      Expanded(child: _buildContent()),
                    ],
                  ),

                  // Notifications overlay
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContentUtilityBar extends StatelessWidget {
  const _ContentUtilityBar({
    required this.onSearch,
    required this.onCreateNew,
    required this.onOpenSettings,
    required this.onOpenSupport,
    required this.onOpenNotifications,
    required this.notificationCount, // ✅ ADD
    required this.avatar,
    this.leading,
  });

  final int notificationCount; // ✅ ADD
  final Widget? leading; // ✅ ADD
  final VoidCallback onOpenNotifications;
  final ValueChanged<String> onSearch;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenSupport;
  final VoidCallback onCreateNew;
  final Widget avatar;

  static const double height = 68; // ✅ adds top breathing room

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(32, 12, 24, 8),
      //        left  top right bottom
      decoration: const BoxDecoration(
        color: AppColors.contentCanvas, // ✅ exact same white
      ),

      child: Row(
        children: [
          // ✅ Mobile leading button (menu / back)
          if (leading != null) ...[leading!, const SizedBox(width: 12)],

          // LEFT: New + Search (bounded so it can't push actions away)
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Row(
                  children: [
                    // ✅ + New
                    PopupMenuButton<String>(
                      tooltip: 'Create new',
                      offset: const Offset(0, 40),
                      onSelected: (v) {
                        if (v == 'request') onCreateNew();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'request',
                          child: Row(
                            children: [
                              Icon(Icons.request_page_outlined, size: 18),
                              SizedBox(width: 10),
                              Text(
                                'Request link',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],
                      child: SizedBox(
                        height: kUtilityControlHeight,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            // ✅ subtle brand‑tinted surface
                            color: AppColors.brandBlue.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(10),

                            // ✅ stronger outline so it reads as an action
                            border: Border.all(
                              color: AppColors.brandBlue.withOpacity(0.35),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Icons.add,
                                  size: 18,
                                  color:
                                      AppColors.brandBlue, // ✅ brand emphasis
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'New',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF101828),
                                  ),
                                ),
                                SizedBox(width: 4),
                                Icon(
                                  Icons.expand_more,
                                  size: 18,
                                  color: Color(0xFF667085),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // ✅ Search (bounded width + expands nicely)
                    Expanded(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: SizedBox(
                          height: kUtilityControlHeight,
                          child: TextField(
                            onChanged: onSearch,
                            textAlignVertical: TextAlignVertical.center,
                            decoration: InputDecoration(
                              hintText: 'Search files, requests, links…',
                              hintStyle: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF667085),
                              ),
                              prefixIcon: const Icon(
                                Icons.search,
                                size: 18,
                                color: Color(0xFF667085),
                              ),
                              isDense: true,
                              filled: true,

                              // ✅ Slightly brighter than canvas so it reads as a control
                              fillColor: const Color(0xFFF8FAFC),

                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),

                              // ✅ Default outline (always visible)
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: Colors.black.withOpacity(0.14),
                                ),
                              ),

                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: Colors.black.withOpacity(0.14),
                                ),
                              ),

                              // ✅ Focused = brand blue (clear affordance)
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: AppColors.brandBlue,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.notifications_outlined,
                  size: 20,
                  color: AppColors.iconNeutral,
                ),
                splashRadius: 20,
                hoverColor: const Color(0xFFF1F5F9),
                onPressed: onOpenNotifications,
              ),

              if (notificationCount > 0)
                Positioned(
                  right: 3,
                  bottom: 3,
                  child: IgnorePointer(
                    ignoring: true,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD92D20),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$notificationCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),

          IconButton(
            icon: const Icon(
              Icons.settings_outlined,
              size: 20,
              color: AppColors.iconNeutral,
            ),
            splashRadius: 20,
            hoverColor: const Color(0xFFF1F5F9),
            onPressed: onOpenSettings,
          ),

          IconButton(
            icon: const Icon(
              Icons.help_outline,
              size: 20,
              color: AppColors.iconNeutral,
            ),
            splashRadius: 20,
            hoverColor: const Color(0xFFF1F5F9),
            onPressed: onOpenSupport,
          ),
          const SizedBox(width: 8),
          avatar,
        ],
      ),
    );
  }
}

class _TwoPaneNav extends StatelessWidget {
  const _TwoPaneNav({
    required this.currentRoute,
    required this.section,
    required this.onSelectSection,
    required this.secondaryCollapsed,
    required this.onToggleSecondary,
    required this.onNavigate,
    required this.onLogoTap,
    required this.showAdmin,
  });

  final String currentRoute;
  final _NavSection section;
  final ValueChanged<_NavSection> onSelectSection;

  final bool secondaryCollapsed;
  final VoidCallback onToggleSecondary;

  final void Function(String route) onNavigate;
  final VoidCallback onLogoTap;
  final bool showAdmin;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MiniRail(
          active: section,
          onSelect: onSelectSection,
          onLogoTap: onLogoTap,
          onToggleSecondary: onToggleSecondary,
          secondaryCollapsed: secondaryCollapsed,
          showAdmin: showAdmin, // ✅ PASS IT THROUGH
        ),
        if (!secondaryCollapsed)
          _SecondaryPane(
            title: _sectionTitle(section),
            section: section,
            currentRoute: currentRoute,
            onNavigate: onNavigate,
            showAdmin: showAdmin,
          ),
      ],
    );
  }
}

class _MiniRail extends StatelessWidget {
  const _MiniRail({
    required this.active,
    required this.onSelect,
    required this.onLogoTap,
    required this.onToggleSecondary,
    required this.secondaryCollapsed,
    required this.showAdmin, // ✅ ADD THIS
  });

  final _NavSection active;
  final ValueChanged<_NavSection> onSelect;
  final VoidCallback onLogoTap;
  final VoidCallback onToggleSecondary;
  final bool secondaryCollapsed;
  final bool showAdmin; // ✅ ADD THIS

  static const double _w = 80;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _w,
      decoration: BoxDecoration(
        color: AppColors.navigationCanvas,
        border: Border(right: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 10),

            // ✅ Clickable logo (go home)
            InkWell(
              onTap: onLogoTap,
              borderRadius: BorderRadius.circular(14),
              hoverColor: Colors.black.withOpacity(0.06),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: SizedBox(
                  height: 48,
                  width: 48,
                  child: SvgPicture.string(
                    kBrandLogoSvg,
                    height: 44,
                    fit: BoxFit.contain,
                    allowDrawingOutsideViewBox: true,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            if (showAdmin) ...[
              const SizedBox(height: 6),
              Divider(height: 1, color: Colors.black.withOpacity(0.08)),
              const SizedBox(height: 6),

              _MiniTile(
                icon: Icons.admin_panel_settings_outlined,
                label: 'Admin',
                active: active == _NavSection.admin,
                onTap: () => onSelect(_NavSection.admin),
                accentOverride: const Color(
                  0xFF111827,
                ), // ✅ neutral “system” accent
              ),

              const SizedBox(height: 10),
              Divider(height: 1, color: Colors.black.withOpacity(0.08)),
            ],

            _MiniTile(
              icon: Icons.home_outlined,
              label: 'Home',
              active: active == _NavSection.home,
              onTap: () => onSelect(_NavSection.home),
            ),
            const SizedBox(height: 6),

            _MiniTile(
              icon: Icons.inventory_2_outlined,
              label: 'File Box',
              active: active == _NavSection.files,
              onTap: () => onSelect(_NavSection.files),
            ),
            const SizedBox(height: 6),

            _MiniTile(
              icon: Icons.request_page_outlined,
              label: 'Requests',
              active: active == _NavSection.requests,
              onTap: () => onSelect(_NavSection.requests),
            ),

            const Spacer(),

            // ✅ Collapse / Expand the secondary pane
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: IconButton(
                tooltip: secondaryCollapsed ? 'Expand menu' : 'Collapse menu',
                icon: Icon(
                  secondaryCollapsed ? Icons.chevron_right : Icons.chevron_left,
                ),
                onPressed: onToggleSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniTile extends StatelessWidget {
  const _MiniTile({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.accentOverride, // ✅ ADD
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color? accentOverride; // ✅ ADD

  @override
  Widget build(BuildContext context) {
    final accent = accentOverride ?? AppColors.brandBlue; // ✅
    final bg = active ? accent.withOpacity(0.12) : Colors.transparent;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 64,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: active ? accent : const Color(0xFF667085),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                color: active ? accent : const Color(0xFF475467),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryPane extends StatelessWidget {
  const _SecondaryPane({
    required this.title,
    required this.section,
    required this.currentRoute,
    required this.onNavigate,
    required this.showAdmin,
  });

  final String title;
  final _NavSection section;
  final String currentRoute;
  final void Function(String route) onNavigate;
  final bool showAdmin;

  static const double _w = 220;

  @override
  Widget build(BuildContext context) {
    List<_PaneItem> items;

    switch (section) {
      case _NavSection.admin:
        items = const [
          // ✅ ONLY clickable admin page
          _PaneItem('Users', Icons.people_outline, kAdminUsersRoute),

          // 🚫 Disabled (coming soon)
          _PaneItem(
            'Activity & Audit',
            Icons.receipt_long_outlined,
            kAdminAuditRoute,
            enabled: false,
            disabledHint: 'Coming soon',
          ),

          // 🚫 Disabled (coming soon)
          _PaneItem(
            'Upload Links',
            Icons.link_outlined,
            kAdminLinksRoute,
            enabled: false,
            disabledHint: 'Coming soon',
          ),
        ];
        break;
      case _NavSection.files:
        items = const [
          _PaneItem('File Box', Icons.folder_open_outlined, '/file-box'),
          _PaneItem(
            'Upload Requests',
            Icons.request_page_outlined,
            '/generate-upload-link',
          ),
        ];
        break;

      case _NavSection.requests:
        items = const [
          _PaneItem(
            'Link requests',
            Icons.link_outlined,
            '/generate-upload-link',
          ),
        ];
        break;

      case _NavSection.home:
      default:
        items = const [
          _PaneItem('Dashboard', Icons.home_outlined, '/dashboard'),
          _PaneItem(
            'Firm documents',
            Icons.folder_shared_outlined,
            '/shared-files',
          ),
          _PaneItem(
            'Websites & Resources',
            Icons.public_outlined,
            '/resources',
          ),
          _PaneItem(
            'Account settings',
            Icons.person_outline,
            '/account-settings',
          ),
        ];
        break;
    }

    return Container(
      width: _w,
      decoration: BoxDecoration(
        color: AppColors.navigationCanvas,
        border: Border(
          right: BorderSide(color: Colors.black.withOpacity(0.06)),
        ),
      ),

      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24), // ✅ matches reference spacing

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16, // ✅ slightly smaller
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF101828),
                ),
              ),
            ),

            const SizedBox(height: 8),
            Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 4),

            // Section items
            ...items.map((it) {
              final active = currentRoute == it.route;

              return _PaneNavRow(
                label: it.label,
                icon: it.icon,
                active: active,
                enabled: it.enabled, // ✅ pass through
                disabledHint: it.disabledHint, // ✅ pass through
                onTap: () => onNavigate(it.route),
              );
            }),

            const Spacer(),

            Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 6),

            _PaneNavRow(
              label: 'Sign out',
              icon: Icons.logout,
              active: false,
              onTap: () => onNavigate('__logout__'),
              danger: true,
            ),

            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

class _PaneItem {
  final String label;
  final IconData icon;
  final String route;

  // ✅ new
  final bool enabled;
  final String? disabledHint;

  const _PaneItem(
    this.label,
    this.icon,
    this.route, {
    this.enabled = true,
    this.disabledHint,
  });
}

class _PaneNavRow extends StatefulWidget {
  const _PaneNavRow({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.enabled = true, // ✅ add
    this.disabledHint, // ✅ add
    this.danger = false,
    this.accentOverride,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  final bool enabled; // ✅ add
  final String? disabledHint; // ✅ add

  final bool danger;
  final Color? accentOverride;

  @override
  State<_PaneNavRow> createState() => _PaneNavRowState();
}

class _PaneNavRowState extends State<_PaneNavRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.enabled;

    final accent =
        widget.accentOverride ??
        (widget.danger ? const Color(0xFFB42318) : AppColors.brandBlue);

    // Disabled palette (enterprise subtle)
    final disabledFg = const Color(0xFF98A2B3);
    final disabledIcon = const Color(0xFFB0B7C3);

    final bg = !enabled
        ? Colors.transparent
        : widget.active
        ? accent.withOpacity(0.10)
        : _hover
        ? Colors.black.withOpacity(0.04)
        : Colors.transparent;

    final fg = !enabled
        ? disabledFg
        : widget.danger
        ? const Color(0xFFB42318)
        : (widget.active ? accent : const Color(0xFF344054));

    final iconColor = !enabled
        ? disabledIcon
        : widget.danger
        ? const Color(0xFFB42318)
        : (widget.active ? accent : const Color(0xFF667085));

    final row = InkWell(
      onTap: enabled ? widget.onTap : null, // ✅ disables click
      child: Container(
        height: 36,
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(widget.icon, size: 18, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: widget.active ? FontWeight.w700 : FontWeight.w500,
                  color: fg,
                ),
              ),
            ),

            // ✅ optional "coming soon" hint
            if (!enabled)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.lock_outline,
                  size: 16,
                  color: Color(0xFFB0B7C3),
                ),
              ),
          ],
        ),
      ),
    );

    // ✅ no hover behavior when disabled
    final wrapped = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: enabled ? (_) => setState(() => _hover = true) : null,
      onExit: enabled ? (_) => setState(() => _hover = false) : null,
      child: row,
    );

    // ✅ optional tooltip for disabled rows (nice enterprise cue)
    if (!enabled && (widget.disabledHint?.trim().isNotEmpty ?? false)) {
      return Tooltip(message: widget.disabledHint!, child: wrapped);
    }

    return wrapped;
  }
}

class _SidebarNav extends StatelessWidget {
  const _SidebarNav({
    required this.currentRoute,
    required this.onNavigate,
    required this.collapsed,
    required this.onToggleCollapse,
    required this.showAdmin,
    required this.moreExpanded,
    required this.onToggleMore,
  });

  final String currentRoute;
  final void Function(String route) onNavigate;
  final bool collapsed;
  final VoidCallback onToggleCollapse;
  final bool showAdmin;

  final bool moreExpanded;
  final VoidCallback onToggleMore;

  @override
  Widget build(BuildContext context) {
    final bool isMoreActive =
        currentRoute == '/shared-files' ||
        currentRoute == '/resources' ||
        currentRoute == '/account-settings';

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

          // ======================
          // ADMIN (optional)
          // ======================
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
                    color: Color(0xFF111827),
                  ),
                ),
              ),

            _SidebarNavItem(
              icon: Icons.admin_panel_settings_outlined,
              label: 'Admin',
              route: '/admin-users',
              currentRoute: currentRoute,
              onNavigate: onNavigate,
              collapsed: collapsed,
              accentOverride: const Color(0xFF111827),
            ),
          ],

          const SizedBox(height: 6),
          Divider(height: 1, color: Colors.black.withOpacity(0.08)),
          const SizedBox(height: 6),

          // ======================
          // PRIMARY
          // ======================
          _SidebarNavItem(
            icon: Icons.home_outlined, // ✅ better semantic fit
            label: 'Home',
            route: '/dashboard',
            currentRoute: currentRoute,
            onNavigate: onNavigate,
            collapsed: collapsed,
          ),
          const SizedBox(height: 4),

          _SidebarNavItem(
            icon: Icons.folder_open_outlined, // ✅ Files icon
            label: 'File Box',
            route: '/file-box',
            currentRoute: currentRoute,
            onNavigate: onNavigate,
            collapsed: collapsed,
          ),
          const SizedBox(height: 4),

          _SidebarNavItem(
            icon: Icons.request_page_outlined, // ✅ Request icon
            label: 'Requests',
            route: '/generate-upload-link',
            currentRoute: currentRoute,
            onNavigate: onNavigate,
            collapsed: collapsed,
          ),
          const SizedBox(height: 4),

          // ======================
          // MORE (expands / popup)
          // ======================
          _SidebarMoreEntry(
            collapsed: collapsed,
            active: isMoreActive,
            expanded: moreExpanded,
            onToggleExpanded: onToggleMore,
            onNavigate: onNavigate,
          ),

          if (!collapsed && moreExpanded) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 18),
              child: Column(
                children: [
                  _SidebarNavItem(
                    icon: Icons.folder_shared_outlined,
                    label: 'Firm documents',
                    route: '/shared-files',
                    currentRoute: currentRoute,
                    onNavigate: onNavigate,
                    collapsed: false,
                  ),
                  _SidebarNavItem(
                    icon: Icons.public_outlined,
                    label: 'Websites & Resources',
                    route: '/resources',
                    currentRoute: currentRoute,
                    onNavigate: onNavigate,
                    collapsed: false,
                  ),
                  _SidebarNavItem(
                    icon: Icons.person_outline,
                    label: 'Account settings',
                    route: '/account-settings',
                    currentRoute: currentRoute,
                    onNavigate: onNavigate,
                    collapsed: false,
                  ),
                ],
              ),
            ),
          ],

          const Spacer(),

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

class _SidebarMoreEntry extends StatefulWidget {
  const _SidebarMoreEntry({
    required this.collapsed,
    required this.active,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onNavigate,
  });

  final bool collapsed;
  final bool active;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final void Function(String route) onNavigate;

  @override
  State<_SidebarMoreEntry> createState() => _SidebarMoreEntryState();
}

class _SidebarMoreEntryState extends State<_SidebarMoreEntry> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.brandBlue;
    final bg = widget.active
        ? accent.withOpacity(0.10)
        : _hover
        ? Colors.black.withOpacity(0.06)
        : Colors.transparent;

    // When collapsed, show a popup menu instead of expanding
    if (widget.collapsed) {
      return MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Container(
          height: 42,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: PopupMenuButton<String>(
            tooltip: 'More',
            padding: EdgeInsets.zero,
            offset: const Offset(56, 0),
            onSelected: (v) => widget.onNavigate(v),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: '/shared-files',
                child: Text('Firm documents'),
              ),
              PopupMenuItem(
                value: '/resources',
                child: Text('Websites & Resources'),
              ),
              PopupMenuItem(
                value: '/account-settings',
                child: Text('Account settings'),
              ),
            ],
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: widget.active ? accent : Colors.transparent,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(6),
                      bottomLeft: Radius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.more_horiz,
                  size: 18,
                  color: widget.active ? accent : const Color(0xFF667085),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Expanded sidebar: toggle open/close
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onToggleExpanded,
        child: Container(
          height: 42,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Container(
                width: 3,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: widget.active ? accent : Colors.transparent,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(6),
                    bottomLeft: Radius.circular(6),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.more_horiz,
                size: 18,
                color: widget.active ? accent : const Color(0xFF667085),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'More',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF344054),
                  ),
                ),
              ),
              Icon(
                widget.expanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: const Color(0xFF667085),
              ),
              const SizedBox(width: 10),
            ],
          ),
        ),
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
    const double appBarHeight = _ContentUtilityBar.height;

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
                    child: IgnorePointer(
                      ignoring: false,
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
                            child: Material(
                              color: Colors.transparent,
                              elevation: 0,
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
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ============================================================
// Notifications flyout panel (top app-bar bell)
// ============================================================

class _NotificationsPanel extends StatelessWidget {
  const _NotificationsPanel({required this.onOpenRequest, super.key});

  final void Function(String requestId) onOpenRequest;

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream() {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return FirebaseFirestore.instance
        .collection('notifications')
        .where('userUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true) // ✅ newest first
        .limit(50)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ===== Header =====
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Notifications',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF101828),
                  ),
                ),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    await FirebaseFunctions.instance
                        .httpsCallable('markNotificationsRead')
                        .call();
                  } catch (_) {}
                },
                child: const Text(
                  'Mark all as read',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: Colors.black.withOpacity(0.08)),

        // ===== List =====
        SizedBox(
          height: 320,
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _stream(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Failed to load notifications.\n\n${snapshot.error}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFFB42318),
                    ),
                  ),
                );
              }

              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data!.docs;

              if (docs.isEmpty) {
                return const Center(
                  child: Text(
                    'No notifications',
                    style: TextStyle(fontSize: 13, color: Color(0xFF667085)),
                  ),
                );
              }

              final Map<String, List<QueryDocumentSnapshot>> grouped = {};

              for (final d in docs) {
                final type = (d['type'] ?? 'generic').toString();
                grouped.putIfAbsent(type, () => []).add(d);
              }

              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final data = doc.data();

                  final bool unread = data['readAt'] == null;

                  final String type = (data['type'] ?? '').toString();
                  final String rawTitle = (data['title'] ?? '')
                      .toString()
                      .trim();

                  final String fromName =
                      (data['clientName'] ?? data['fromName'] ?? '')
                          .toString()
                          .trim();

                  // Optional: if you store a request/link label in the notification doc
                  final String requestLabel =
                      (data['requestName'] ??
                              data['requestTitle'] ??
                              data['linkName'] ??
                              '')
                          .toString()
                          .trim();

                  // File count (you already use this pattern in the badge)
                  final fc = data['fileCount'];
                  final int fileCount = (fc is int)
                      ? fc
                      : (fc is num ? fc.toInt() : 0);

                  // Total bytes (support a few possible field names)
                  final tb =
                      data['totalBytes'] ??
                      data['totalSizeBytes'] ??
                      data['sizeBytes'];
                  final int totalBytes = (tb is int)
                      ? tb
                      : (tb is num ? tb.toInt() : 0);

                  // ----- Compose title + meta -----

                  final int safeCount = (fileCount <= 0) ? 1 : fileCount;
                  final String countLabel =
                      '$safeCount ${safeCount == 1 ? 'file' : 'files'}';

                  // Normalize request label capitalization
                  final String requestName = requestLabel.isNotEmpty
                      ? requestLabel
                      : 'Request Link';

                  final bool isDropoffUpload = type == 'dropoff_upload';

                  // Right side count text
                  final String titleRight = isDropoffUpload ? countLabel : '';

                  // Left side title text (your requested wording)
                  final String titleLeft = isDropoffUpload
                      ? 'Request Link Upload'
                      : (rawTitle.isNotEmpty ? rawTitle : 'Notification');

                  // Prefer a real uploader name if present (supports future backend fields)
                  final String uploaderCandidate =
                      (data['uploaderName'] ??
                              data['uploadedByName'] ??
                              data['senderName'] ??
                              data['clientName'] ??
                              data['fromName'] ??
                              '')
                          .toString()
                          .trim();

                  final bool uploaderLooksLikeRequest =
                      uploaderCandidate.isNotEmpty &&
                      requestName.isNotEmpty &&
                      uploaderCandidate.toLowerCase() ==
                          requestName.toLowerCase();

                  final String fromText =
                      (!uploaderLooksLikeRequest &&
                          uploaderCandidate.isNotEmpty)
                      ? uploaderCandidate
                      : 'Client';

                  final Timestamp? ts = data['createdAt'] as Timestamp?;

                  // Second row left/right
                  final String metaLeft = 'From $fromText';
                  final String metaRight = _relativeTime(ts);

                  final bgColor = unread
                      ? AppColors.brandBlue.withOpacity(0.06)
                      : Colors.transparent;

                  final leftAccent = unread
                      ? AppColors.brandBlue
                      : Colors.transparent;

                  return MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: InkWell(
                      onTap: () {
                        // Fire-and-forget: do NOT block navigation
                        FirebaseFunctions.instance
                            .httpsCallable('markNotificationsRead')
                            .call({'notificationId': doc.id})
                            .catchError((e) {
                              debugPrint(
                                'markNotificationsRead(single) failed: $e',
                              );
                            });

                        final requestId = data['requestId'];
                        if (requestId is String && requestId.isNotEmpty) {
                          onOpenRequest(
                            requestId,
                          ); // closes flyout + opens details immediately
                        }
                      },
                      child: Container(
                        margin: EdgeInsets.zero,
                        decoration: BoxDecoration(
                          color: unread
                              ? const Color(0xFFF8FAFF)
                              : Colors.white,
                          border: Border(
                            bottom: BorderSide(
                              color: Colors.black.withOpacity(0.08),
                              width: 1,
                            ),
                            left: BorderSide(
                              color: unread
                                  ? AppColors.brandBlue
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Row 1: Title left + count right
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    titleLeft,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: unread
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                      color: const Color(0xFF101828),
                                    ),
                                  ),
                                ),
                                if (titleRight.isNotEmpty) ...[
                                  const SizedBox(width: 12),
                                  Text(
                                    titleRight,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: unread
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                      color: const Color(0xFF475467),
                                    ),
                                  ),
                                ],
                              ],
                            ),

                            const SizedBox(height: 4),

                            // Row 2: From left + time right
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    metaLeft,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: Color(0xFF475467),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  metaRight,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: Color(0xFF667085),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  String _relativeTime(Timestamp? ts) {
    if (ts == null) return 'Just now';

    final dt = ts.toDate();
    final diff = DateTime.now().difference(dt);

    if (diff.inMinutes < 1) return 'Just now';

    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return '$m ${m == 1 ? 'minute' : 'minutes'} ago';
    }

    if (diff.inHours < 24) {
      final h = diff.inHours;
      return '$h ${h == 1 ? 'hour' : 'hours'} ago';
    }

    final d = diff.inDays;
    return '$d ${d == 1 ? 'day' : 'days'} ago';
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
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
