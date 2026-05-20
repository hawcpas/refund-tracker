import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import '../widgets/centered_form.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/brand_logo_svg.dart';

class OtpVerifyScreen extends StatefulWidget {
  final String? nextRoute;
  final bool otpAlreadySent;
  final Future<Map<String, dynamic>>? initialOtpSend;

  const OtpVerifyScreen({
    super.key,
    this.nextRoute,
    this.otpAlreadySent = false,
    this.initialOtpSend,
  });

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen>
    with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);

    _textListener = () {
      if (!mounted) return;
      // Rebuild so the button enabled state updates immediately (iOS/web)
      setState(() {});
    };

    _controller.addListener(_textListener!);

    // =========================
    // ✅ SAFE OTP AUTO-SEND
    // =========================
    if (!widget.otpAlreadySent) {
      Future.microtask(() => _sendInitialCode(widget.initialOtpSend));
    }
  }

  Future<void> _sendInitialCode(
    Future<Map<String, dynamic>>? initialOtpSend,
  ) async {
    if (!mounted) return;

    try {
      final data = initialOtpSend != null
          ? await initialOtpSend
          : Map<String, dynamic>.from(
              (await FirebaseFunctions.instanceFor(
                    region: 'us-central1',
                  ).httpsCallable('sendLoginOtp').call()).data
                  as Map,
            );

      final remaining = (data['remainingSeconds'] is num)
          ? (data['remainingSeconds'] as num).toInt()
          : 0;

      if (mounted && remaining > 0) {
        _startCooldown(remaining);
      }
    } catch (_) {
      // Non-blocking: user can still tap "resend".
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!mounted) return;

      FocusScope.of(context).unfocus();
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    if (_loading) return; // ✅ prevents double-tap / rapid taps
    final code = _controller.text.trim();

    if (code.length != 6) {
      setState(() {
        _error = 'Enter the 6-digit code sent to your e-mail.';
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

  String _maskedEmail(String email) {
    final parts = email.trim().split('@');
    if (parts.length != 2 || parts.first.isEmpty || parts.last.isEmpty) {
      return email;
    }

    final local = parts.first;
    final visible = local.length <= 2 ? local[0] : local.substring(0, 3);
    return '$visible******@${parts.last}';
  }

  Future<void> _cancelVerification() async {
    if (_loading) return;
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  Future<void> _openContactPage() async {
    final uri = Uri.parse('https://www.axumecpas.com/contact.php');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
      hintText: 'Enter code',
      errorText: null, // we show errors in the banner for Intuit feel
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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
      hintStyle: TextStyle(
        color: enabled ? const Color(0xFF6B6C72) : const Color(0xFFBABEC5),
        fontSize: 13,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  // =========================
  // FOOTER (matches Login placement & style)
  // =========================
  Widget _legalLinksRow() {
    Widget link(String label, String route) {
      return _HoverUnderlineLink(
        label: label,
        onTap: () => Navigator.pushNamed(context, route),
      );
    }

    return CenteredForm(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          link("Legal", '/legal'),
          const Text("·", style: TextStyle(color: Colors.grey)),
          link("Privacy", '/privacy'),
          const Text("·", style: TextStyle(color: Colors.grey)),
          link("Security", '/security'),
        ],
      ),
    );
  }

  Widget _footer(ThemeData theme) {
    return CenteredForm(
      child: Column(
        children: [
          _legalLinksRow(),
          const SizedBox(height: 12),
          Text(
            "© 2026 Axume & Associates CPAs, AAC",
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.mutedText,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Professional Accounting and Advisory Services.\nAll rights reserved.",
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.mutedText,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // =========================
  // CARD (same sizing & visual language as Login)
  // =========================
  Widget _otpCard(ThemeData theme) {
    final enabled = !_loading && !_resending;
    final email = FirebaseAuth.instance.currentUser?.email?.trim() ?? '';
    final displayEmail = email.isEmpty
        ? 'your registered email address'
        : _maskedEmail(email);

    final verifying = _loading;
    final fieldEnabled = !_resending;
    final canContinue = !verifying && _controller.text.trim().length == 6;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFB8BDC7)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: IgnorePointer(
        ignoring: _loading,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 42,
              padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFD9DCE3))),
              ),
              child: Row(
                children: [
                  SvgPicture.string(
                    kBrandLogoSvg,
                    height: 26,
                    width: 26,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Two-factor authentication',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: const Color(0xFF111827),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Help',
                    onPressed: _showNoCodeSheet,
                    icon: const Icon(Icons.help_outline, size: 19),
                    color: AppColors.brandBlue,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cancel verification',
                    onPressed: _cancelVerification,
                    icon: const Icon(Icons.close, size: 19),
                    color: const Color(0xFF344054),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                children: [
                  Text(
                    'Enter the verification code sent to your registered email address',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF111827),
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    displayEmail,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF111827),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F8FA),
                border: Border.all(color: const Color(0xFFF0F2F5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AbsorbPointer(
                    absorbing: verifying,
                    child: TweenAnimationBuilder<Color?>(
                      duration: const Duration(milliseconds: 100),
                      curve: Curves.easeOutCubic,
                      tween: ColorTween(
                        end: verifying
                            ? const Color(0xFFB0B3B8)
                            : const Color(0xFF393A3D),
                      ),
                      builder: (context, color, _) {
                        return TextField(
                          controller: _controller,
                          enabled: fieldEnabled,
                          readOnly: verifying,
                          showCursor: !verifying,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          maxLength: 6,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          textAlign: TextAlign.left,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                            color: color,
                          ),
                          onChanged: (_) {
                            if (_error != null) {
                              setState(() => _error = null);
                            }
                          },
                          onSubmitted: (_) => canContinue ? _verify() : null,
                          decoration: _codeDecoration(
                            enabled: fieldEnabled,
                          ).copyWith(counterText: ''),
                        );
                      },
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    _ErrorBanner(message: _error!),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 30,
                          child: FilledButton(
                            onPressed: canContinue ? _verify : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.brandBlue,
                              disabledBackgroundColor: const Color(0xFFB9D7EC),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 100),
                              child: _loading
                                  ? const SizedBox(
                                      key: ValueKey('loading'),
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                                    )
                                  : const Text(
                                      'Verify',
                                      key: ValueKey('verify'),
                                    ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 30,
                          child: OutlinedButton(
                            onPressed: _cancelVerification,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.brandBlue,
                              side: BorderSide(color: AppColors.brandBlue),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              color: const Color(0xFFEFF5FF),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      _remainingSeconds > 0
                          ? 'You can request a new code in $_remainingSeconds seconds.'
                          : 'Didn\'t receive a code?',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF344054),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: enabled && _remainingSeconds == 0
                        ? _resendCode
                        : null,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.brandBlue,
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                    child: Text(_resending ? 'Sending...' : 'Resend code'),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 14),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFD9DCE3))),
              ),
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Having trouble signing in? ',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF111827),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  _HoverUnderlineLink(
                    label: 'Contact Us',
                    onTap: _openContactPage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _passwordContextCard(ThemeData theme) {
    final email = FirebaseAuth.instance.currentUser?.email?.trim() ?? '';

    return Opacity(
      opacity: 0.38,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.all(20),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: SvgPicture.string(
                  kBrandLogoSvg2,
                  height: 80,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Enter your password',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF393A3D),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                email.isEmpty ? 'Confirm your password to continue' : email,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF6B6C72),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                height: 46,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFD4D7DC)),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.brandBlue,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _legacyOtpCard(ThemeData theme) {
    final enabled = !_loading && !_resending;
    final email = FirebaseAuth.instance.currentUser?.email?.trim() ?? '';

    final bool verifying = _loading; // verification in progress
    final bool fieldEnabled = !_resending; // keep the field styled as enabled
    final bool canContinue = !verifying && _controller.text.trim().length == 6;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD4D7DC)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 24,
            spreadRadius: 2,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: IgnorePointer(
        ignoring: _loading,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: SvgPicture.string(
                kBrandLogoSvg2,
                height: 80,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 18), // instead of 16, above or below logo

            Text(
              'Verify your identity',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF393A3D),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Enter the 6-digit code sent to your e-mail.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF6B6C72),
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
            if (email.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  border: Border.all(color: const Color(0xFFE4E7EC)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  email,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF393A3D),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),

            AbsorbPointer(
              absorbing:
                  verifying, // ✅ blocks edits while verifying (no visual dim)
              child: TweenAnimationBuilder<Color?>(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                // ✅ Key trick: only set END; Flutter animates from current value smoothly
                tween: ColorTween(
                  end: verifying
                      ? const Color(0xFFB0B3B8) // dimmed digits
                      : const Color(0xFF393A3D), // normal digits
                ),
                builder: (context, color, _) {
                  return TextField(
                    controller: _controller,

                    // ✅ Keep field looking normal (border/label/helper stay consistent)
                    enabled: fieldEnabled,

                    // ✅ Prevent typing + cursor during verification without greying field
                    readOnly: verifying,
                    showCursor: !verifying,

                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    maxLength: 6,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.5,
                      color: color,
                    ),
                    onChanged: (_) {
                      if (_error != null) {
                        setState(() => _error = null);
                      }
                    },
                    onSubmitted: (_) => canContinue ? _verify() : null,
                    decoration: _codeDecoration(
                      enabled: fieldEnabled,
                    ).copyWith(counterText: ''),
                  );
                },
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              _ErrorBanner(message: _error!),
            ],

            const SizedBox(height: 14),

            SizedBox(
              height: 42,
              child: TextButton(
                onPressed: (_loading || _resending) ? null : _showNoCodeSheet,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF6B6C72),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
                child: const Text("I don't have a code"),
              ),
            ),

            const SizedBox(height: 10),

            SizedBox(
              height: 42,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: canContinue ? _verify : null,
                  borderRadius: BorderRadius.circular(6),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 100),
                    child: Container(
                      key: ValueKey(_loading),
                      decoration: BoxDecoration(
                        color: canContinue
                            ? AppColors.brandBlue
                            : AppColors.brandBlue.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
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
          ],
        ),
      ),
    );
  }

  // =========================
  // UI (Login-matching scaffold)
  // =========================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.pageBackgroundSoft,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const double footerBreakpoint = 620;
            final bool pinFooter = constraints.maxHeight >= footerBreakpoint;

            final footerWidget = Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _footer(theme),
            );

            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(
                          height: 88,
                        ), // ✅ same top anchor as Login

                        CenteredForm(
                          maxWidth: 560,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CenteredForm(
                                maxWidth: 380,
                                child: _passwordContextCard(theme),
                              ),
                              _otpCard(theme),
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),

                        if (!pinFooter) ...[
                          const SizedBox(height: 16),
                          footerWidget,
                        ],

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
                if (pinFooter) footerWidget,
              ],
            );
          },
        ),
      ),
    );
  }
}

// =========================
// HOVER UNDERLINE LINK (matches your login footer style)
// =========================
class _HoverUnderlineLink extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _HoverUnderlineLink({required this.label, required this.onTap});

  @override
  State<_HoverUnderlineLink> createState() => _HoverUnderlineLinkState();
}

class _HoverUnderlineLinkState extends State<_HoverUnderlineLink> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 120),
          style: TextStyle(
            color: AppColors.brandBlue,
            fontWeight: FontWeight.w700,
            fontSize: 10,
            decoration: _hovering
                ? TextDecoration.underline
                : TextDecoration.none,
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: SizedBox(), // placeholder, replaced below
          ),
        ),
      ),
    );
  }
}

// Patch: AnimatedDefaultTextStyle needs actual child text; keep it clean:
extension on _HoverUnderlineLinkState {
  Widget buildText() {
    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 120),
      style: TextStyle(
        color: AppColors.brandBlue,
        fontWeight: FontWeight.w700,
        fontSize: 10,
        decoration: _hovering ? TextDecoration.underline : TextDecoration.none,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(widget.label),
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
