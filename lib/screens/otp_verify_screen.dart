import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';

class OtpVerifyScreen extends StatefulWidget {
  final String? nextRoute;
  const OtpVerifyScreen({super.key, this.nextRoute});

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen> {
  final _controller = TextEditingController();

  bool _loading = false;
  bool _resending = false;
  String? _error;

  static const int _cooldownSeconds = 60;
  int _remainingSeconds = 0;
  Timer? _timer;
  VoidCallback? _textListener;

  @override
  void initState() {
    super.initState();

    _textListener = () {
      if (!mounted) return;
      // Rebuild so the button enabled state updates immediately on iOS
      setState(() {});
    };

    _controller.addListener(_textListener!);
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_textListener != null) {
      _controller.removeListener(_textListener!);
    }
    _controller.dispose();
    super.dispose();
  }

  // =========================
  // VERIFY CODE
  // =========================
  Future<void> _verify() async {
    final code = _controller.text.trim();

    if (code.length != 6) {
      setState(() {
        _error = 'Enter the 6‑digit verification code.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('verifyLoginOtp').call({'code': code});

      // 🔄 Refresh token to receive otp_verified claim
      await FirebaseAuth.instance.currentUser!.getIdToken(true);

      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        (widget.nextRoute != null && widget.nextRoute!.isNotEmpty)
            ? widget.nextRoute!
            : '/dashboard',
      );
    } catch (_) {
      setState(() {
        _error = 'The verification code is invalid or has expired.';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // =========================
  // RESEND CODE
  // =========================
  Future<void> _resendCode() async {
    if (_remainingSeconds > 0 || _resending) return;

    setState(() {
      _resending = true;
      _error = null;
    });

    try {
      final res = await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('sendLoginOtp').call();

      final data = Map<String, dynamic>.from(res.data as Map);

      final remaining = (data['remainingSeconds'] is num)
          ? (data['remainingSeconds'] as num).toInt()
          : _cooldownSeconds;

      // ✅ Start countdown using server-provided remaining seconds
      _startCooldown(remaining.clamp(0, _cooldownSeconds));

      if (data['throttled'] == true) {
        // Optional: show a friendly message
        setState(() {
          _error =
              'Please wait $remaining seconds before requesting another code.';
        });
      } else {
        // Optional: show success feedback
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('A new verification code has been sent.'),
            ),
          );
        }
      }
    } catch (_) {
      setState(() {
        _error = 'Unable to resend the code. Please try again shortly.';
      });
    } finally {
      if (mounted) {
        setState(() => _resending = false);
      }
    }
  }

  void _startCooldown([int? seconds]) {
    _timer?.cancel();

    final start = (seconds ?? _cooldownSeconds).clamp(0, _cooldownSeconds);
    setState(() => _remainingSeconds = start);

    if (_remainingSeconds <= 0) return;

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 1) {
        timer.cancel();
        if (mounted) setState(() => _remainingSeconds = 0);
      } else {
        if (mounted) setState(() => _remainingSeconds--);
      }
    });
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      // ✅ Same neutral background as Resources / Dashboard pages
      backgroundColor: AppColors.pageBackgroundLight,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black.withOpacity(0.06)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ===== Header =====
                    Text(
                      'Two‑factor verification',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF101828),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'For security, enter the 6‑digit code sent to your email address.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF475467),
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 22),

                    // ===== Code field =====
                    TextField(
                      controller: _controller,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      onChanged: (_) {
                        if (_error != null) {
                          setState(() => _error = null);
                        }
                      },
                      decoration: const InputDecoration(
                        labelText: 'Verification code',
                        prefixIcon: Icon(Icons.lock_outline),
                        counterText: '',
                      ),
                      onSubmitted: (_) => _loading ? null : _verify(),
                    ),

                    // ===== Error =====
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      _ErrorBanner(message: _error!),
                    ],

                    const SizedBox(height: 22),

                    // ===== Primary CTA =====
                    SizedBox(
                      height: 46,
                      child: FilledButton(
                        onPressed: (_loading || _controller.text.length != 6)
                            ? null
                            : _verify,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.brandBlue,
                          foregroundColor: Colors.white,
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w900,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Verify and continue'),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ===== Resend =====
                    Center(
                      child: TextButton(
                        onPressed: (_remainingSeconds > 0 || _resending)
                            ? null
                            : _resendCode,
                        child: Text(
                          _remainingSeconds > 0
                              ? 'Resend code in $_remainingSeconds s'
                              : 'Resend verification code',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ===== Footer =====
                    Text(
                      'Axume & Associates CPAs · Secure Portal',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF667085),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =========================
// ERROR BANNER
// =========================
class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFB42318), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFB42318),
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
