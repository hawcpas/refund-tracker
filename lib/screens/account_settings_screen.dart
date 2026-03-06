import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../theme/app_colors.dart';
import '../services/auth_service.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _auth = AuthService();

  // Personal Info
  final nameController = TextEditingController();
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

  late final TabController _tabController;

  static const double _maxWidth = 980;
  static const double _formWidth = 720;

  static const double _outerPad = 18;
  static const double _sectionGap = 18;

  static const double _btnW = 180;
  static const double _btnH = 44;

  // ✅ controls how wide the input fields are (so they don’t stretch)
  static const double _fieldMaxWidth = 320;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // ✅ Keep segmented control in sync when index changes
    _tabController.addListener(() {
      if (!mounted) return;
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });

    _loadProfile();
  }

  @override
  void dispose() {
    _tabController.dispose();

    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();

    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();

    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server));

      final data = doc.data() ?? {};

      final role = (data['role'] ?? '').toString().toLowerCase().trim();
      _isAdmin = role == 'admin';
      final firstName = (data['firstName'] ?? '').toString().trim();
      final lastName = (data['lastName'] ?? '').toString().trim();
      final displayName = (data['displayName'] ?? '').toString().trim();

      final bestName = ('$firstName $lastName').trim().isNotEmpty
          ? ('$firstName $lastName').trim()
          : displayName;

      nameController.text = bestName;
      emailController.text = ((data['email'] ?? user.email) ?? '')
          .toString()
          .trim();
      phoneController.text = (data['phone'] ?? '').toString().trim();
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
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

    final updates = <String, dynamic>{
      'phone': phoneController.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (_isAdmin) {
      final newEmail = emailController.text.trim();

      if (newEmail.isNotEmpty && newEmail != (user.email ?? '')) {
        // ✅ Modern Firebase approach: verification-required update
        await user.verifyBeforeUpdateEmail(newEmail);

        // IMPORTANT: do NOT immediately overwrite Firestore email
        // because Auth email won't change until the link is clicked.
        // Instead, store pendingEmail and show message.
        updates['pendingEmail'] = newEmail;
      }

      final newName = nameController.text.trim();
      if (newName.isNotEmpty) {
        final parts = newName.split(' ');
        updates['firstName'] = parts.first;
        updates['lastName'] = parts.length > 1
            ? parts.sublist(1).join(' ')
            : '';
        updates['displayName'] = newName;
      }
    }

    setState(() {
      _savingPersonal = true;
      _error = null;
      _success = null;
    });

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(updates, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _savingPersonal = false;

        final pending = updates['pendingEmail'];
        _success = pending != null
            ? 'Name/phone updated. Verification email sent to $pending. '
                  'Your login email will update after verification.'
            : 'Profile updated successfully.';

        _profileChanged = true;
      });
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

  // ------- Panels (so build stays tidy) -------
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
          controller: nameController,
          enabled: _isAdmin,
          decoration: InputDecoration(
            labelText: _isAdmin ? 'Name' : 'Name (admin only)',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: emailController,
          enabled: _isAdmin,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: _isAdmin ? 'Email' : 'Name (admin only)',
            prefixIcon: Icon(Icons.mail_outline),
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

    return Theme(
      data: localTheme,
      child: Scaffold(
        backgroundColor: AppColors.pageBackgroundLight,
        appBar: AppBar(
          title: const Text("Account Settings"),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _profileChanged),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxWidth),
                  child: ListView(
                    padding: const EdgeInsets.all(_outerPad),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.black.withOpacity(0.06),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 14,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: _formWidth,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_error != null) ...[
                                  _errorBanner(theme, _error!),
                                  const SizedBox(height: _sectionGap),
                                ],
                                if (_success != null) ...[
                                  _successBanner(theme, _success!),
                                  const SizedBox(height: _sectionGap),
                                ],
                                Text(
                                  "Account Settings",
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF101828),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  "Update your personal details and password.",
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFF475467),
                                    height: 1.25,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Divider(color: Colors.black.withOpacity(0.07)),
                                const SizedBox(height: 12),

                                _tabsBar(theme),
                                const SizedBox(height: 16),

                                // ✅ NO SLIDE: IndexedStack swaps instantly
                                SizedBox(
                                  height: 420,
                                  child: IndexedStack(
                                    index: _tabController.index,
                                    children: [
                                      _personalInfoPanel(theme),
                                      _passwordPanel(theme),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
