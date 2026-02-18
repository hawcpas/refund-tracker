import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();

  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  final AuthService _auth = AuthService();

  bool _isLoading = false;

  // visibility toggles
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  // show validation messages only after submit attempt
  bool _submitted = false;

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
      setState(() {
        _submitted = false; // hides errors until next submit attempt
      });
    }
  }

  String? _validateNewPassword(String? value) {
    if (!_submitted) return null; // don't show while typing
    final v = (value ?? '').trim();
    if (v.length < 6) return "Password must be at least 6 characters";
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (!_submitted) return null; // don't show while typing
    final p1 = newPasswordController.text.trim();
    final p2 = (value ?? '').trim();
    if (p2.isEmpty) return "Please re-enter the new password";
    if (p1 != p2) return "Passwords do not match";
    return null;
  }

  Future<void> _updatePassword() async {
    setState(() => _submitted = true);

    final formOk = _formKey.currentState?.validate() ?? false;
    if (!formOk) {
      _showSnack("Please fix the highlighted fields.");
      return;
    }

    // ✅ NEW: Check verification first
    final verified = await _auth.isEmailVerified();
    if (!mounted) return;

    if (!verified) {
      _showSnack("Please verify your email before changing your password.");
      Navigator.pushReplacementNamed(context, '/verify-email');
      return;
    }

    final newPassword = newPasswordController.text.trim();
    setState(() => _isLoading = true);

    setState(() => _isLoading = false);
    if (!mounted) return;

    final code = await _auth.updatePassword(newPassword);

setState(() => _isLoading = false);
if (!mounted) return;

if (code == null) {
  _showSnack("Password updated successfully", success: true);
  Navigator.pop(context);
} else if (code == 'requires-recent-login') {
  _showSnack("For security, please log in again and then change your password.");
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
      appBar: AppBar(title: const Text("Change Password")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            "Update your password",
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Choose a strong password that you don’t use elsewhere.",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),

          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withOpacity(0.7),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // NEW PASSWORD
                    TextFormField(
                      controller: newPasswordController,
                      obscureText: _obscureNew,
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.visiblePassword,
                      onChanged: (_) => _clearSubmitErrorsOnType(),
                      decoration: InputDecoration(
                        labelText: "New password",
                        helperText: "Minimum 6 characters",
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _obscureNew
                              ? "Show password"
                              : "Hide password",
                          icon: Icon(
                            _obscureNew
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() => _obscureNew = !_obscureNew);
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      validator: _validateNewPassword,
                    ),

                    const SizedBox(height: 14),

                    // CONFIRM PASSWORD
                    TextFormField(
                      controller: confirmPasswordController,
                      obscureText: _obscureConfirm,
                      textInputAction: TextInputAction.done,
                      keyboardType: TextInputType.visiblePassword,
                      onChanged: (_) => _clearSubmitErrorsOnType(),
                      onFieldSubmitted: (_) =>
                          _isLoading ? null : _updatePassword(),
                      decoration: InputDecoration(
                        labelText: "Confirm new password",
                        prefixIcon: const Icon(Icons.lock_reset),
                        suffixIcon: IconButton(
                          tooltip: _obscureConfirm
                              ? "Show password"
                              : "Hide password",
                          icon: Icon(
                            _obscureConfirm
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() => _obscureConfirm = !_obscureConfirm);
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      validator: _validateConfirmPassword,
                    ),

                    const SizedBox(height: 18),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : FilledButton.icon(
                              onPressed: _updatePassword,
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text("Update Password"),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 14),

          Text(
            "Tip: Using a longer password with a mix of letters and numbers improves security.",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
