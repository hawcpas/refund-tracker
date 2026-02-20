import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/centered_form.dart';
import '../widgets/centered_section.dart';

enum VerifyStatus { idle, checking, notVerified, verified, error, resent }

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final AuthService _auth = AuthService();

  VerifyStatus _status = VerifyStatus.idle;
  String? _message;

  bool _checking = false;
  bool _resending = false;

  // ✅ Show a professional delivery notice only on first view
  bool _showInitialInfo = true;

  // ✅ Resend cooldown
  static const int _cooldownTotalSeconds = 60;
  int _resendCooldownSeconds = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendCooldownSeconds = _cooldownTotalSeconds);

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_resendCooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _resendCooldownSeconds = 0);
      } else {
        setState(() => _resendCooldownSeconds--);
      }
    });
  }

  void _setStatus(VerifyStatus status, [String? message]) {
    setState(() {
      _status = status;
      _message = message;
    });
  }

  Future<void> _checkVerified() async {
    setState(() {
      // ✅ Hide the initial info after the first user action
      _showInitialInfo = false;

      _checking = true;
      _status = VerifyStatus.checking;
      _message = null;
    });

    final verified = await _auth.isEmailVerified();
    if (!mounted) return;

    setState(() => _checking = false);

    if (verified) {
      _setStatus(
        VerifyStatus.verified,
        "Your email has been verified successfully.",
      );

      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/dashboard');
    } else {
      _setStatus(
        VerifyStatus.notVerified,
        "We haven’t detected a verified email yet. "
        "Please open the most recent verification email and try again.",
      );
    }
  }

  Future<void> _resend() async {
    if (_resendCooldownSeconds > 0) return;

    setState(() {
      // ✅ Hide the initial info after the first user action
      _showInitialInfo = false;

      _resending = true;
      _message = null;
    });

    final code = await _auth.resendEmailVerification();
    if (!mounted) return;

    setState(() => _resending = false);

    if (code == null) {
      _setStatus(
        VerifyStatus.resent,
        "A new verification email has been sent. "
        "Please check your inbox and spam folder.",
      );
      _startResendCooldown();
    } else if (code == 'too-many-requests') {
      _setStatus(
        VerifyStatus.error,
        "Too many requests. Please wait before trying again.",
      );
    } else if (code == 'network-request-failed') {
      _setStatus(
        VerifyStatus.error,
        "Network error. Please check your internet connection.",
      );
    } else if (code == 'no-current-user') {
      _setStatus(
        VerifyStatus.error,
        "Your session has expired. Please log in again.",
      );
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    } else {
      _setStatus(
        VerifyStatus.error,
        "We couldn’t resend the verification email. Please try again.",
      );
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

    Color? bannerColor;
    Color? bannerTextColor;
    IconData? bannerIcon;

    switch (_status) {
      case VerifyStatus.notVerified:
        bannerColor = theme.colorScheme.surfaceVariant;
        bannerTextColor = theme.colorScheme.onSurfaceVariant;
        bannerIcon = Icons.info_outline;
        break;
      case VerifyStatus.verified:
        bannerColor = theme.colorScheme.primaryContainer;
        bannerTextColor = theme.colorScheme.onPrimaryContainer;
        bannerIcon = Icons.check_circle_outline;
        break;
      case VerifyStatus.resent:
        bannerColor = theme.colorScheme.primaryContainer;
        bannerTextColor = theme.colorScheme.onPrimaryContainer;
        bannerIcon = Icons.mark_email_read_outlined;
        break;
      case VerifyStatus.error:
        bannerColor = theme.colorScheme.errorContainer;
        bannerTextColor = theme.colorScheme.onErrorContainer;
        bannerIcon = Icons.error_outline;
        break;
      default:
        bannerColor = null;
        bannerTextColor = null;
        bannerIcon = null;
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Verify your email")),
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
              CenteredSection(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.mark_email_unread_outlined,
                        size: 48, color: theme.colorScheme.primary),
                    const SizedBox(height: 16),
                    Text("Check your inbox",
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        )),
                    const SizedBox(height: 8),
                    Text(
                      "We’ve sent you a verification email.\n\n"
                      "After clicking the link, return here and tap "
                      "“I’ve verified my email”.",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
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
                        // ✅ NEW: Professional delivery notice shown only at first
                        if (_showInitialInfo) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 20,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    "Verification emails are usually delivered within a few moments. "
                                    "In some cases, they may appear in your spam or junk folder. "
                                    "If you don’t see it shortly, please check those folders before "
                                    "requesting another email.",
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

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
                                Icon(bannerIcon,
                                    size: 20, color: bannerTextColor),
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

                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            onPressed: _checking ? null : _checkVerified,
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
                                (_resending || _resendCooldownSeconds > 0)
                                    ? null
                                    : _resend,
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

                        if (_resendCooldownSeconds > 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            "You can resend another email in "
                            "${_resendCooldownSeconds}s",
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],

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