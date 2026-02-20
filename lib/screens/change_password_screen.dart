import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/centered_form.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  static const Color brandBlue = Color(0xFF08449E);

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();

  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  final AuthService _auth = AuthService();

  bool _isLoading = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _submitted = false;

  // ✅ SAME TOKENS AS OTHER SCREENS
  static const double _pageVPad = 28;
  static const double _cardRadius = 18;
  static const double _cardPad = 16;
  static const double _fieldGap = 12;
  static const double _blockGap = 16;
  static const double _buttonH = 46;

  static const double _logoSize = 80;
  static const double _accentH = 4;
  static const double _accentW = 72;

  static const Color _pageBg = Color(0xFFF6F7F9);

  @override
  void dispose() {
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  void _showSnack(String message, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? Colors.green : null,
      ),
    );
  }

  void _clearSubmitErrorsOnType() {
    if (_submitted) {
      setState(() => _submitted = false);
    }
  }

  String? _validateNewPassword(String? value) {
    if (!_submitted) return null;
    final v = (value ?? '').trim();
    if (v.length < 6) return "Password must be at least 6 characters";
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (!_submitted) return null;
    final p1 = newPasswordController.text.trim();
    final p2 = (value ?? '').trim();
    if (p2.isEmpty) return "Please re-enter the new password";
    if (p1 != p2) return "Passwords do not match";
    return null;
  }

  Future<void> _updatePassword() async {
    setState(() => _submitted = true);

    if (!(_formKey.currentState?.validate() ?? false)) {
      _showSnack("Please fix the highlighted fields.");
      return;
    }

    final verified = await _auth.isEmailVerified();
    if (!mounted) return;

    if (!verified) {
      _showSnack("Please verify your email before changing your password.");
      Navigator.pushReplacementNamed(context, '/verify-email');
      return;
    }

    setState(() => _isLoading = true);
    final code =
        await _auth.updatePassword(newPasswordController.text.trim());
    setState(() => _isLoading = false);

    if (!mounted) return;

    if (code == null) {
      _showSnack("Password updated successfully", success: true);
      Navigator.pop(context);
    } else if (code == 'requires-recent-login') {
      _showSnack(
        "For security, please log in again and then change your password.",
      );
      await _auth.logout();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    } else {
      _showSnack("Failed to update password ($code)");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: _pageBg, // ✅ solid gray
      appBar: AppBar(
        title: const Text("Change Password"),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: _pageVPad),
        children: [
          CenteredForm(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(_cardRadius),
                border: Border.all(
                  color: Colors.black.withOpacity(0.06),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(_cardPad),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ✅ LOGO INSIDE CARD (NO BOX)
                      const ImageIcon(
                        AssetImage(
                          'assets/icons/aa_logo_imageicon_256.png',
                        ),
                        size: _logoSize,
                        color: ChangePasswordScreen.brandBlue,
                      ),
                      const SizedBox(height: 14),
                      Container(
                        height: _accentH,
                        width: _accentW,
                        margin: const EdgeInsets.only(bottom: _blockGap),
                        decoration: BoxDecoration(
                          color: ChangePasswordScreen.brandBlue
                              .withOpacity(0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),

                      Text(
                        "Update your password",
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF101828),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Choose a strong password that you don’t use elsewhere.",
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF475467),
                        ),
                      ),
                      const SizedBox(height: _blockGap),

                      TextFormField(
                        controller: newPasswordController,
                        obscureText: _obscureNew,
                        onChanged: (_) => _clearSubmitErrorsOnType(),
                        decoration: InputDecoration(
                          labelText: "New password",
                          helperText: "Minimum 6 characters",
                          prefixIcon: const Icon(
                            Icons.lock_outline,
                            color: ChangePasswordScreen.brandBlue,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureNew
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: ChangePasswordScreen.brandBlue,
                            ),
                            onPressed: () => setState(
                              () => _obscureNew = !_obscureNew,
                            ),
                          ),
                        ),
                        validator: _validateNewPassword,
                      ),

                      const SizedBox(height: _fieldGap),

                      TextFormField(
                        controller: confirmPasswordController,
                        obscureText: _obscureConfirm,
                        onChanged: (_) => _clearSubmitErrorsOnType(),
                        onFieldSubmitted: (_) =>
                            _isLoading ? null : _updatePassword(),
                        decoration: InputDecoration(
                          labelText: "Confirm new password",
                          prefixIcon: const Icon(
                            Icons.lock_reset,
                            color: ChangePasswordScreen.brandBlue,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirm
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: ChangePasswordScreen.brandBlue,
                            ),
                            onPressed: () => setState(
                              () => _obscureConfirm = !_obscureConfirm,
                            ),
                          ),
                        ),
                        validator: _validateConfirmPassword,
                      ),

                      const SizedBox(height: _blockGap),

                      SizedBox(
                        height: _buttonH,
                        child: _isLoading
                            ? const Center(
                                child: CircularProgressIndicator(),
                              )
                            : FilledButton.icon(
                                onPressed: _updatePassword,
                                icon: const Icon(
                                  Icons.check_circle_outline,
                                ),
                                label: const Text("Update password"),
                                style: FilledButton.styleFrom(
                                  backgroundColor:
                                      ChangePasswordScreen.brandBlue,
                                  foregroundColor: Colors.white,
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(12),
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
        ],
      ),
    );
  }
}