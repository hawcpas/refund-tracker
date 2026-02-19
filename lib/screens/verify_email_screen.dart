import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/centered_form.dart';
import '../widgets/centered_section.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final AuthService _auth = AuthService();

  bool _checking = false;
  bool _resending = false;

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _checkVerified() async {
    setState(() => _checking = true);

    final verified = await _auth.isEmailVerified();

    setState(() => _checking = false);

    if (!mounted) return;

    if (verified) {
      _snack("Email verified. Welcome!");
      Navigator.pushReplacementNamed(context, '/dashboard');
    } else {
      _snack(
        "Not verified yet. Please open the most recent email and try again.",
      );
    }
  }

  Future<void> _resend() async {
    setState(() => _resending = true);

    final code = await _auth.resendEmailVerification();

    if (!mounted) return;
    setState(() => _resending = false);

    if (code == null) {
      _snack("Verification email sent. Please use the most recent email.");
    } else if (code == 'too-many-requests') {
      _snack("Too many requests. Please wait a minute and try again.");
    } else if (code == 'operation-not-allowed') {
      _snack("Email/Password sign-in is not enabled in Firebase Console.");
    } else if (code == 'network-request-failed') {
      _snack("Network error. Check your internet connection.");
    } else if (code == 'no-current-user') {
      _snack("Session expired. Please log in again.");
      Navigator.pushReplacementNamed(context, '/login');
    } else {
      _snack("Could not resend email ($code).");
    }
  }

  Future<void> _backToLogin() async {
    await _auth.logout();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Verify your email"),
      ),

      body: Stack(
        children: [
          // ✅ Soft background for desktop polish
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary.withOpacity(0.15),
                  theme.colorScheme.surface,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          ListView(
            padding: const EdgeInsets.symmetric(vertical: 40),
            children: [
              // ✅ Instruction section (readable width)
              CenteredSection(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.mark_email_unread_outlined,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Check your inbox",
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "We’ve sent you a verification email.\n\n"
                      "If you use Outlook or a corporate email, the verification "
                      "page may show an error — that’s expected. After clicking "
                      "the link, return here and tap “I’ve verified my email”.",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ✅ Action card (form width)
              CenteredForm(
                child: Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: theme.colorScheme.outlineVariant.withOpacity(0.7),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            onPressed:
                                _checking ? null : _checkVerified,
                            child: _checking
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Text("I’ve verified my email"),
                          ),
                        ),

                        const SizedBox(height: 12),

                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton(
                            onPressed:
                                _resending ? null : _resend,
                            child: _resending
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Text("Resend verification email"),
                          ),
                        ),

                        const SizedBox(height: 16),

                        TextButton(
                          onPressed: _backToLogin,
                          child: const Text("Back to login"),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}