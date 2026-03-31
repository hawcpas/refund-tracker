import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../theme/app_colors.dart';
import '../services/auth_service.dart';

import '../widgets/page_scaffold.dart';
import '../shell/app_shell.dart';

class AccountSettingsScreen extends StatefulWidget {
  final bool embed;

  const AccountSettingsScreen({super.key, this.embed = false});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsSkeleton extends StatelessWidget {
  const _AccountSettingsSkeleton();

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _line(w: 240, h: 18), // title
        const SizedBox(height: 10),
        _line(w: 360), // subtitle

        const SizedBox(height: 24),

        _line(w: 180), // tabs
        const SizedBox(height: 16),

        // Form fields
        _line(h: 44),
        const SizedBox(height: 12),
        _line(h: 44),
        const SizedBox(height: 12),
        _line(h: 44),
        const SizedBox(height: 12),
        _line(h: 44),

        const SizedBox(height: 24),

        _line(w: 180, h: 44), // button
      ],
    );
  }
}

class AccountSettingsContent extends StatelessWidget {
  const AccountSettingsContent({
    super.key,
    required this.loading,
    required this.error,
    required this.success,
    required this.tabController,
    required this.onSavePersonal,
    required this.onChangePassword,
    required this.isAdmin,
    required this.savingPersonal,
    required this.savingPassword,
    required this.firstNameController,
    required this.lastNameController,
    required this.emailController,
    required this.phoneController,
    required this.currentPasswordController,
    required this.newPasswordController,
    required this.confirmPasswordController,
    required this.tabsBar,
    required this.personalInfoPanel,
    required this.passwordPanel,
  });

  final bool loading;
  final String? error;
  final String? success;

  final TabController tabController;

  final bool isAdmin;
  final bool savingPersonal;
  final bool savingPassword;

  final VoidCallback onSavePersonal;
  final VoidCallback onChangePassword;

  final TextEditingController firstNameController;
  final TextEditingController lastNameController;
  final TextEditingController emailController;
  final TextEditingController phoneController;

  final TextEditingController currentPasswordController;
  final TextEditingController newPasswordController;
  final TextEditingController confirmPasswordController;

  /// Injected builders from the screen (keeps logic intact)
  final Widget Function(ThemeData) tabsBar;
  final Widget Function(ThemeData) personalInfoPanel;
  final Widget Function(ThemeData) passwordPanel;

  static const double _sectionGap = 18;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (loading) {
      return const _AccountSettingsSkeleton();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (error != null) ...[
          _errorBanner(theme, error!),
          const SizedBox(height: _sectionGap),
        ],
        if (success != null) ...[
          _successBanner(theme, success!),
          const SizedBox(height: _sectionGap),
        ],

        tabsBar(theme),
        const SizedBox(height: 16),

        SizedBox(
          height: 420,
          child: IndexedStack(
            index: tabController.index,
            children: [personalInfoPanel(theme), passwordPanel(theme)],
          ),
        ),
      ],
    );
  }

  // ✅ Copied helpers so behavior stays identical
  Widget _errorBanner(ThemeData theme, String msg) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.red.withOpacity(0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.red.withOpacity(0.20)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, color: Color(0xFFB42318), size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            msg,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFFB42318),
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _successBanner(ThemeData theme, String msg) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.green.withOpacity(0.10),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.green.withOpacity(0.25)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.check_circle_outline,
          color: Colors.green.shade800,
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            msg,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.green.shade800,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
        ),
      ],
    ),
  );
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _auth = AuthService();

  // Personal Info
  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();

  // Password
  final currentPasswordController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool _loading = true;
  bool _savingPersonal = false;
  bool _savingPassword = false;
  bool _isAdmin = false;

  String? _error;
  String? _success;

  bool _profileChanged = false;
  bool _didLoadOnce = false;

  late final TabController _tabController;

  static const double _maxWidth = 980;
  static const double _formWidth = 720;

  static const double _sectionGap = 18;

  static const double _btnW = 180;
  static const double _btnH = 44;

  // ✅ controls how wide the input fields are (so they don’t stretch)
  static const double _fieldMaxWidth = 320;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 2, vsync: this);

    _tabController.addListener(() {
      if (!mounted) return;
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });

    // ✅ Load profile once after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_didLoadOnce) return;
      _didLoadOnce = true;
      _loadProfile();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();

    firstNameController.dispose();
    lastNameController.dispose();
    emailController.dispose();
    phoneController.dispose();

    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();

    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      // ✅ Give Firebase Auth a moment to hydrate when navigating via shell
      if (FirebaseAuth.instance.currentUser == null) {
        await Future.delayed(const Duration(milliseconds: 50));
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        // Still null after delay → bail gracefully
        return;
      }

      // 1) Get Firestore profile
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final data = Map<String, dynamic>.from(doc.data() ?? {});

      // 2) Determine admin
      final role = (data['role'] ?? '').toString().toLowerCase().trim();
      _isAdmin = role == 'admin';

      // 3) Reload Auth user so email reflects verification changes
      await user.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser;
      final authEmail = (refreshedUser?.email ?? '').trim();

      // 4) Sync pending email if verified
      final pendingEmail = (data['pendingEmail'] ?? '').toString().trim();
      if (pendingEmail.isNotEmpty &&
          authEmail.isNotEmpty &&
          authEmail == pendingEmail) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'email': authEmail,
          'pendingEmail': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        data['email'] = authEmail;
        data.remove('pendingEmail');
      }

      // ✅ Step 2 — show pending email verification banner
      final stillPending = (data['pendingEmail'] ?? '').toString().trim();
      if (stillPending.isNotEmpty) {
        _success =
            'A verification email was sent to $stillPending. '
            'Your login email will update after verification.';
      }

      // 5) Names
      final firstName = (data['firstName'] ?? '').toString().trim();
      final lastName = (data['lastName'] ?? '').toString().trim();
      final displayName = (data['displayName'] ?? '').toString().trim();

      if (firstName.isEmpty && lastName.isEmpty && displayName.isNotEmpty) {
        final parts = displayName.split(RegExp(r'\s+'));
        firstNameController.text = parts.isNotEmpty ? parts.first : '';
        lastNameController.text = parts.length > 1
            ? parts.sublist(1).join(' ')
            : '';
      } else {
        firstNameController.text = firstName;
        lastNameController.text = lastName;
      }

      // 6) Email
      final pendingAfter = (data['pendingEmail'] ?? '').toString().trim();
      emailController.text = (data['email'] ?? authEmail ?? '')
          .toString()
          .trim();

      // 7) Phone
      phoneController.text = (data['phone'] ?? '').toString().trim();
    } catch (e) {
      _error = 'Failed to load account settings.';
    } finally {
      if (!mounted) return;
      setState(() => _loading = false); // ✅ ALWAYS clear loading
    }
  }

  // ---------- UI helpers ----------
  void _setBanner({String? error, String? success}) {
    setState(() {
      _error = error;
      _success = success;
    });
  }

  Widget _errorBanner(ThemeData theme, String msg) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.red.withOpacity(0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.red.withOpacity(0.20)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, color: Color(0xFFB42318), size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            msg,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFFB42318),
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _successBanner(ThemeData theme, String msg) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.green.withOpacity(0.10),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.green.withOpacity(0.25)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.check_circle_outline,
          color: Colors.green.shade800,
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            msg,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.green.shade800,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _primaryButton({
    required String label,
    required VoidCallback? onPressed,
    required bool loading,
  }) {
    return SizedBox(
      width: _btnW,
      height: _btnH,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brandBlue,
          foregroundColor: AppColors.cardBackground,
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: loading
            ? const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.cardBackground,
                ),
              )
            : Text(label),
      ),
    );
  }

  // ---------- Actions ----------

  Future<void> _savePersonalInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final newEmail = emailController.text.trim();
    final currentEmail = (user.email ?? '').trim();

    final wantsEmailChange =
        _isAdmin && newEmail.isNotEmpty && newEmail != currentEmail;

    // ✅ Start UI feedback immediately (no dead air)
    setState(() {
      _savingPersonal = true;
      _error = null;
      _success = wantsEmailChange
          ? 'Sending verification email…'
          : 'Saving changes…';
    });

    final updates = <String, dynamic>{
      'phone': phoneController.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // ✅ Email change path: show progress immediately, then confirm "sent"
    if (wantsEmailChange) {
      try {
        final fn = FirebaseFunctions.instance.httpsCallable(
          'requestEmailChange',
        );

        // Cloud Function can be slow (cold start) — UI already shows “Sending…”
        await fn.call({'email': newEmail});

        updates['pendingEmail'] = newEmail;

        // ✅ As soon as the function completes, upgrade the message immediately
        if (mounted) {
          setState(() {
            _success =
                'A verification email was sent to $newEmail. '
                'Your login email will update after verification.';
          });
        }
      } on FirebaseAuthException catch (e) {
        // Stop spinner here because we’re bailing out
        if (mounted) setState(() => _savingPersonal = false);

        if (e.code == 'requires-recent-login') {
          _setBanner(
            error:
                'For security reasons, please log in again to change your email.',
            success: null,
          );
          await _auth.logout();
          if (!mounted) return;
          Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
          return;
        }

        _setBanner(
          error:
              'Email verification could not be sent (${e.code}). ${e.message ?? ''}',
          success: null,
        );
        return;
      } catch (e) {
        if (mounted) setState(() => _savingPersonal = false);
        _setBanner(
          error: 'Email verification could not be sent. Please try again.',
          success: null,
        );
        return;
      }
    }

    // ✅ Persist updates (email pending + phone) after the email request
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(updates, SetOptions(merge: true));

      if (!mounted) return;

      // ✅ Finish spinner quickly — message already shown
      setState(() {
        _savingPersonal = false;

        final pending = updates['pendingEmail'];
        _success = pending != null
            ? 'A verification email was sent to $pending. '
                  'Your login email will update after verification.'
            : 'Profile updated successfully.';

        _profileChanged = true;
      });

      // ✅ Refresh AppShell UI (avatar + flyouts), but after spinner stops
      final shell = context.findAncestorStateOfType<AppShellState>();
      await shell?.refreshProfile();
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingPersonal = false);

      final msg = e.toString().contains('permission-denied')
          ? 'You do not have permission to update this profile.'
          : 'Could not save changes. Please try again.';

      _setBanner(error: msg, success: null);
    }
  }

  Future<void> _changePasswordWithCurrent() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final currentPass = currentPasswordController.text.trim();
    final newPass = newPasswordController.text.trim();
    final confirmPass = confirmPasswordController.text.trim();

    if (currentPass.isEmpty) {
      _setBanner(error: 'Enter your current password.', success: null);
      return;
    }
    if (newPass.length < 6) {
      _setBanner(
        error: 'New password must be at least 6 characters.',
        success: null,
      );
      return;
    }
    if (newPass != confirmPass) {
      _setBanner(error: 'New passwords do not match.', success: null);
      return;
    }

    setState(() {
      _savingPassword = true;
      _error = null;
      _success = null;
    });

    try {
      final email = user.email;
      if (email == null || email.isEmpty) {
        throw FirebaseAuthException(
          code: 'no-email',
          message: 'No email found for current user.',
        );
      }

      final credential = EmailAuthProvider.credential(
        email: email,
        password: currentPass,
      );
      await user.reauthenticateWithCredential(credential);

      final code = await _auth.updatePassword(newPass);

      if (!mounted) return;
      setState(() => _savingPassword = false);

      if (code == null) {
        currentPasswordController.clear();
        newPasswordController.clear();
        confirmPasswordController.clear();
        setState(() {
          _success = 'Your password has been updated.';
          _profileChanged = true;
        });
        return;
      }

      if (code == 'requires-recent-login') {
        _setBanner(
          error:
              'For security reasons, please log in again to change your password.',
          success: null,
        );
        await _auth.logout();
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
        return;
      }

      _setBanner(error: 'Failed to update password ($code)', success: null);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _savingPassword = false);

      if (e.code == 'wrong-password') {
        _setBanner(error: 'Current password is incorrect.', success: null);
        return;
      }

      if (e.code == 'requires-recent-login') {
        _setBanner(
          error:
              'For security reasons, please log in again to change your password.',
          success: null,
        );
        await _auth.logout();
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
        return;
      }

      _setBanner(error: 'Password change failed (${e.code}).', success: null);
    } catch (_) {
      if (!mounted) return;
      setState(() => _savingPassword = false);
      _setBanner(
        error: 'Could not update password. Please try again.',
        success: null,
      );
    }
  }

  // ✅ Segmented control UI (NO animation)
  Widget _tabsBar(ThemeData theme) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        labelColor: AppColors.brandBlue,
        unselectedLabelColor: const Color(0xFF475467),
        labelStyle: const TextStyle(fontWeight: FontWeight.w900),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w800),
        indicatorColor: AppColors.brandBlue,
        indicatorWeight: 3,
        indicatorSize: TabBarIndicatorSize.label,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        dividerColor: Colors.black.withOpacity(0.10),
        tabs: const [
          Tab(
            icon: Icon(Icons.person_outline, size: 18),
            text: 'Personal Information',
          ),
          Tab(icon: Icon(Icons.lock_outline, size: 18), text: 'Password'),
        ],
      ),
    );
  }

  Widget _fieldColumn({required List<Widget> children}) {
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _fieldMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _personalInfoPanel(ThemeData theme) {
    return _fieldColumn(
      children: [
        Text(
          'Change your Personal Information',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: const Color(0xFF101828),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: firstNameController,
          enabled: _isAdmin,
          decoration: InputDecoration(
            labelText: _isAdmin
                ? 'First name'
                : 'First name (request an admin to change)',
            prefixIcon: const Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: lastNameController,
          enabled: _isAdmin,
          decoration: InputDecoration(
            labelText: _isAdmin
                ? 'Last name'
                : 'Last name (request an admin to change)',
            prefixIcon: const Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: emailController,
          enabled: _isAdmin,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: _isAdmin
                ? 'Email'
                : 'Email (request an admin to change)',
            prefixIcon: const Icon(Icons.mail_outline),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Phone',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
        ),
        const SizedBox(height: 16),
        _primaryButton(
          label: 'Save changes',
          onPressed: _savingPersonal ? null : _savePersonalInfo,
          loading: _savingPersonal,
        ),
      ],
    );
  }

  Widget _passwordPanel(ThemeData theme) {
    return _fieldColumn(
      children: [
        Text(
          'Change your Password',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: const Color(0xFF101828),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: currentPasswordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Current Password',
            prefixIcon: Icon(Icons.lock_outline),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: newPasswordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'New Password',
            helperText: 'Minimum 6 characters',
            prefixIcon: Icon(Icons.lock_reset),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: confirmPasswordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Repeat New Password',
            prefixIcon: Icon(Icons.lock_reset_outlined),
          ),
        ),
        const SizedBox(height: 16),
        _primaryButton(
          label: 'Update password',
          onPressed: _savingPassword ? null : _changePasswordWithCurrent,
          loading: _savingPassword,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final localTheme = theme.copyWith(
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: const Color(0xFFF4F7FF),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppColors.brandBlue.withOpacity(0.28),
            width: 1.2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.brandBlue, width: 2.0),
        ),
      ),
    );

    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) {
        // no-op: AppShell handles chrome
      },
      child: PageScaffold(
        title: 'Account Settings',
        subtitle: widget.embed
            ? null
            : 'Update your personal details and password.',
        hideHeader: widget.embed,
        wrapInCard: !widget.embed,
        scrollable: !widget.embed,

        backgroundColor: widget.embed ? Colors.white : null,
        child: Theme(
          data: localTheme, // ✅ affects only the form controls
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: AccountSettingsContent(
                loading: _loading,
                error: _error,
                success: _success,
                tabController: _tabController,
                isAdmin: _isAdmin,
                savingPersonal: _savingPersonal,
                savingPassword: _savingPassword,
                onSavePersonal: _savePersonalInfo,
                onChangePassword: _changePasswordWithCurrent,
                firstNameController: firstNameController,
                lastNameController: lastNameController,
                emailController: emailController,
                phoneController: phoneController,
                currentPasswordController: currentPasswordController,
                newPasswordController: newPasswordController,
                confirmPasswordController: confirmPasswordController,
                tabsBar: _tabsBar,
                personalInfoPanel: _personalInfoPanel,
                passwordPanel: _passwordPanel,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
