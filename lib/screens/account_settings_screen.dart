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

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final AuthService _auth = AuthService();

  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();

  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool _loading = true;
  bool _savingProfile = false;
  bool _savingPassword = false;

  String? _error;

  // ✅ NEW: success message (inline)
  String? _success;

  // ✅ NEW: track whether profile was changed (so dashboard can refresh when user goes back)
  bool _profileChanged = false;

  static const double _maxWidth = 980;
  static const double _formWidth = 720;

  static const double _outerPad = 18;
  static const double _sectionGap = 18;
  static const double _rowGap = 10;
  static const double _dividerGap = 14;

  static const double _btnW = 160;
  static const double _btnH = 40;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    firstNameController.dispose();
    lastNameController.dispose();
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
      firstNameController.text = (data['firstName'] ?? '').toString();
      lastNameController.text = (data['lastName'] ?? '').toString();
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final fn = firstNameController.text.trim();
    final ln = lastNameController.text.trim();

    if (fn.isEmpty || ln.isEmpty) {
      setState(() {
        _error = "First and last name are required.";
        _success = null;
      });
      return;
    }

    setState(() {
      _savingProfile = true;
      _error = null;
      _success = null;
    });

    final displayName = '$fn $ln';

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'firstName': fn,
          'lastName': ln,
          'displayName': displayName,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await user.updateDisplayName(displayName);

      if (!mounted) return;

      // ✅ Stay on page + show success
      setState(() {
        _savingProfile = false;
        _success = "Your name has been updated.";
        _profileChanged = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savingProfile = false;
        _error = "Could not save changes. Please try again.";
        _success = null;
      });
    }
  }

  Future<void> _changePassword() async {
    final newPass = newPasswordController.text.trim();
    final confirmPass = confirmPasswordController.text.trim();

    if (newPass.length < 6) {
      setState(() {
        _error = "Password must be at least 6 characters.";
        _success = null;
      });
      return;
    }
    if (newPass != confirmPass) {
      setState(() {
        _error = "Passwords do not match.";
        _success = null;
      });
      return;
    }

    setState(() {
      _savingPassword = true;
      _error = null;
      _success = null;
    });

    final code = await _auth.updatePassword(newPass);

    if (!mounted) return;
    setState(() => _savingPassword = false);

    if (code == null) {
      newPasswordController.clear();
      confirmPasswordController.clear();
      setState(() => _success = "Your password has been updated.");
      return;
    }

    if (code == 'requires-recent-login') {
      setState(() => _error =
          "For security reasons, please log in again to change your password.");
      await _auth.logout();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      return;
    }

    setState(() => _error = "Failed to update password ($code)");
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget errorBanner(String msg) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.withOpacity(0.20)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline,
                  color: Color(0xFFB42318), size: 18),
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

    // ✅ NEW: success banner
    Widget successBanner(String msg) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.withOpacity(0.25)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.check_circle_outline,
                  color: Colors.green.shade800, size: 18),
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

    Widget sectionTitle(String title, String subtitle) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: const Color(0xFF101828),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF475467),
                height: 1.25,
              ),
            ),
          ],
        );

    Widget primaryButton({
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

    // ✅ Return true to dashboard only when leaving AND profile changed
    return Theme(
      data: localTheme,
      child: PopScope(
        canPop: true,
        onPopInvoked: (didPop) {
          // When user taps back, dashboard can refresh based on the result
          // If the system already popped, nothing else to do.
        },
        child: Scaffold(
          backgroundColor: AppColors.pageBackgroundLight,
          appBar: AppBar(
            title: const Text("Account Settings"),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                Navigator.pop(context, _profileChanged);
              },
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
                            border: Border.all(color: Colors.black.withOpacity(0.06)),
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
                              constraints: const BoxConstraints(maxWidth: _formWidth),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_error != null) ...[
                                    errorBanner(_error!),
                                    const SizedBox(height: _sectionGap),
                                  ],
                                  if (_success != null) ...[
                                    successBanner(_success!),
                                    const SizedBox(height: _sectionGap),
                                  ],

                                  sectionTitle(
                                    "Change your name",
                                    "Update how your name appears across the portal.",
                                  ),
                                  const SizedBox(height: _dividerGap),

                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: firstNameController,
                                          decoration: const InputDecoration(
                                            labelText: "First name",
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: TextField(
                                          controller: lastNameController,
                                          decoration: const InputDecoration(
                                            labelText: "Last name",
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: _rowGap),

                                  primaryButton(
                                    label: "Save",
                                    onPressed: _savingProfile ? null : _saveProfile,
                                    loading: _savingProfile,
                                  ),

                                  const SizedBox(height: _sectionGap),
                                  Divider(color: Colors.black.withOpacity(0.07)),
                                  const SizedBox(height: _sectionGap),

                                  sectionTitle(
                                    "Change your password",
                                    "Update your password to keep your account secure.",
                                  ),
                                  const SizedBox(height: _dividerGap),

                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: newPasswordController,
                                          obscureText: true,
                                          decoration: const InputDecoration(
                                            labelText: "New password",
                                            helperText: "Minimum 6 characters",
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: TextField(
                                          controller: confirmPasswordController,
                                          obscureText: true,
                                          decoration: const InputDecoration(
                                            labelText: "Confirm password",
                                            helperText: " ",
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: _rowGap),

                                  primaryButton(
                                    label: "Update password",
                                    onPressed: _savingPassword ? null : _changePassword,
                                    loading: _savingPassword,
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
      ),
    );
  }
}