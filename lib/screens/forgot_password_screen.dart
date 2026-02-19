import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/local_auth_prefs.dart';
import '../widgets/centered_form.dart';

enum ResetStatus { idle, sending, sent, error }

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final AuthService _auth = AuthService();
  final emailController = TextEditingController();

  ResetStatus _status = ResetStatus.idle;
  String? _message;
  String? _emailError;

  @override
  void initState() {
    super.initState();
    _prefillEmail();
  }

  Future<void> _prefillEmail() async {
    final saved = await LocalAuthPrefs.getSavedEmail();
    if (saved != null && mounted) {
      setState(() => emailController.text = saved);
    }
  }

  void _clear() {
    if (_emailError != null || _message != null) {
      setState(() {
        _emailError = null;
        _message = null;
        _status = ResetStatus.idle;
      });
    }
  }

  Future<void> _sendReset() async {
    final email = emailController.text.trim();

    setState(() {
      _emailError = null;
      _message = null;
    });

    if (email.isEmpty || !email.contains("@")) {
      setState(() => _emailError = "Enter a valid email address.");
      return;
    }

    setState(() => _status = ResetStatus.sending);

    final code = await _auth.sendPasswordResetEmail(email);
    if (!mounted) return;

    if (code == null) {
      setState(() {
        _status = ResetStatus.sent;
        _message =
            "If an account exists for this email, a password reset link has been sent.\n\n"
            "Please check your inbox and spam folder.";
      });
    } else if (code == 'too-many-requests') {
      setState(() {
        _status = ResetStatus.error;
        _message = "Too many requests. Please wait a moment and try again.";
      });
    } else if (code == 'network-request-failed') {
      setState(() {
        _status = ResetStatus.error;
        _message = "Network error. Please check your internet connection.";
      });
    } else {
      setState(() {
        _status = ResetStatus.error;
        _message = "We couldn’t send a reset email at this time. Please try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color? bannerColor;
    Color? bannerTextColor;
    IconData? bannerIcon;

    if (_status == ResetStatus.sent) {
      bannerColor = theme.colorScheme.primaryContainer;
      bannerTextColor = theme.colorScheme.onPrimaryContainer;
      bannerIcon = Icons.mark_email_read_outlined;
    } else if (_status == ResetStatus.error) {
      bannerColor = theme.colorScheme.errorContainer;
      bannerTextColor = theme.colorScheme.onErrorContainer;
      bannerIcon = Icons.error_outline;
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Reset password")),
      body: Stack(
        children: [
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
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.lock_reset_outlined,
                            size: 48, color: theme.colorScheme.primary),
                        const SizedBox(height: 12),
                        Text(
                          "Forgot your password?",
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Enter your email address and we’ll send you a link to reset your password.",
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),

                        if (_message != null && bannerColor != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: bannerColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(bannerIcon, size: 20, color: bannerTextColor),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _message!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: bannerTextColor,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        TextField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          onChanged: (_) => _clear(),
                          decoration: InputDecoration(
                            labelText: "Email",
                            prefixIcon: const Icon(Icons.mail_outline),
                            errorText: _emailError,
                          ),
                        ),

                        const SizedBox(height: 24),

                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            onPressed: _status == ResetStatus.sending ? null : _sendReset,
                            child: _status == ResetStatus.sending
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text("Send reset link"),
                          ),
                        ),

                        const SizedBox(height: 16),

                        TextButton(
                          onPressed: () => Navigator.pop(context),
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