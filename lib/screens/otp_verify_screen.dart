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
      // Rebuild so the button enabled state updates immediately (iOS/web)
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
        _error = 'Enter the 6-digit verification code.';
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
        setState(() {
          _error =
              'Please wait $remaining seconds before requesting another code.';
        });
      } else {
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
  // “I don't have a code” (Intuit-style help)
  // =========================
  void _showNoCodeSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final canResend = !_loading && !_resending && _remainingSeconds == 0;

        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                "Trouble getting your code?",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF393A3D),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "• Check your spam/junk folder.\n"
                "• Use the most recent code you received.\n"
                "• Keep this screen open while you retrieve the code.",
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: Color(0xFF6B6C72),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: canResend ? _resendCode : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brandBlue,
                    side: BorderSide(
                      color: AppColors.brandBlue.withOpacity(0.6),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  child: Text(
                    _remainingSeconds > 0
                        ? "Resend available in $_remainingSeconds s"
                        : "Resend verification code",
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _loading
                    ? null
                    : () {
                        Navigator.pop(context);
                        Navigator.pushReplacementNamed(context, '/login');
                      },
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF6B6C72),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
                child: const Text("Use a different account"),
              ),
            ],
          ),
        );
      },
    );
  }

  InputDecoration _codeDecoration({required bool enabled}) {
    return InputDecoration(
      labelText: 'Enter the 6-digit code',
      helperText: _remainingSeconds > 0
          ? 'You can request a new code in $_remainingSeconds seconds.'
          : ' ',
      errorText: null, // we show errors in the banner for Intuit feel
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      filled: false,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Color(0xFF8D9096)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Color(0xFF8D9096)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: AppColors.brandBlue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Color(0xFFD52B1E)),
      ),
      labelStyle: TextStyle(
        color: enabled ? const Color(0xFF6B6C72) : const Color(0xFFBABEC5),
        fontWeight: FontWeight.w400,
      ),
      helperStyle: TextStyle(
        color: enabled ? const Color(0xFF6B6C72) : const Color(0xFFBABEC5),
        fontSize: 12,
        height: 1.2,
      ),
    );
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = !_loading && !_resending;

    final bool canContinue = !_loading && _controller.text.trim().length == 6;

    return Scaffold(
      backgroundColor: const Color(0xFFDCDCDC), // matches your login bg
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFD4D7DC)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: IgnorePointer(
                      ignoring: _loading,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const ImageIcon(
                            AssetImage(
                              'assets/icons/aa_logo_imageicon_256.png',
                            ),
                            size: 56,
                            color: AppColors.brandBlue,
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Enter your verification code',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF393A3D),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Enter the 6-digit code sent to your email address.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF6B6C72),
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 18),

                          TextField(
                            controller: _controller,
                            enabled: enabled,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            maxLength: 6,
                            autofillHints: const [AutofillHints.oneTimeCode],
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(6),
                            ],
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2.5,
                              color: Color(0xFF393A3D),
                            ),
                            onChanged: (_) {
                              if (_error != null) {
                                setState(() => _error = null);
                              }
                            },
                            onSubmitted: (_) => canContinue ? _verify() : null,
                            decoration: _codeDecoration(
                              enabled: enabled,
                            ).copyWith(counterText: ''),
                          ),

                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            _ErrorBanner(message: _error!),
                          ],

                          const SizedBox(height: 14),

                          // Tertiary action (Intuit-style)
                          SizedBox(
                            height: 42,
                            child: TextButton(
                              onPressed: (_loading || _resending)
                                  ? null
                                  : _showNoCodeSheet,
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF6B6C72),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              child: const Text("I don't have a code"),
                            ),
                          ),

                          const SizedBox(height: 10),

                          // Primary action (Continue)
                          SizedBox(
                            height: 42,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: canContinue ? _verify : null,
                                borderRadius: BorderRadius.circular(6),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 220),
                                  child: Container(
                                    key: ValueKey(_loading),
                                    decoration: BoxDecoration(
                                      color: canContinue
                                          ? AppColors.brandBlue
                                          : AppColors.brandBlue.withOpacity(
                                              0.45,
                                            ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    alignment: Alignment.center,
                                    child: _loading
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    Colors.white,
                                                  ),
                                            ),
                                          )
                                        : const Text(
                                            'Continue',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 14),

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
                ],
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
