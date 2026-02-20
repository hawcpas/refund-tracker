import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/centered_form.dart';
import '../theme/app_colors.dart';

enum VerifyStatus { idle, checking, notVerified, verified, error, resent }

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _auth = AuthService();

  VerifyStatus _status = VerifyStatus.idle;
  String? _message;

  bool _checking = false;
  bool _resending = false;
  bool _showInitialInfo = true;

  static const int _cooldownTotalSeconds = 60;
  int _resendCooldownSeconds = 0;
  Timer? _resendTimer;

  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  // ✅ Shared layout tokens
  static const double _pageVPad = 28;
  static const double _pageHPad = 18; // show background on sides
  static const double _cardRadius = 18;
  static const double _cardPad = 16;
  static const double _blockGap = 16;
  static const double _buttonH = 46;

  static const double _logoSize = 80;
  static const double _accentH = 4;
  static const double _accentW = 72;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _fadeAnimation =
        CurvedAnimation(parent: _animationController, curve: Curves.easeIn);

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendCooldownSeconds = _cooldownTotalSeconds);

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendCooldownSeconds <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendCooldownSeconds = 0);
      } else {
        setState(() => _resendCooldownSeconds--);
      }
    });
  }

  Future<void> _checkVerified() async {
    setState(() {
      _showInitialInfo = false;
      _checking = true;
      _message = null;
    });

    final verified = await _auth.isEmailVerified();
    if (!mounted) return;

    setState(() => _checking = false);

    if (verified) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/dashboard');
    } else {
      setState(() {
        _status = VerifyStatus.notVerified;
        _message =
            "We haven’t detected a verified email yet. Please check your inbox and try again.";
      });
    }
  }

  Future<void> _resend() async {
    if (_resendCooldownSeconds > 0) return;

    setState(() {
      _showInitialInfo = false;
      _resending = true;
      _message = null;
    });

    final code = await _auth.resendEmailVerification();
    if (!mounted) return;

    setState(() => _resending = false);

    if (code == null) {
      setState(() {
        _status = VerifyStatus.resent;
        _message =
            "A new verification email has been sent. Please check your inbox and spam folder.";
      });
      _startResendCooldown();
    } else {
      setState(() {
        _status = VerifyStatus.error;
        _message =
            "We couldn’t resend the verification email. Please try again.";
      });
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

    Color? bannerBg;
    Color? bannerFg;
    IconData? bannerIcon;

    if (_status == VerifyStatus.notVerified || _status == VerifyStatus.resent) {
      bannerBg = AppColors.brandBlue.withOpacity(0.08);
      bannerFg = AppColors.brandBlue;
      bannerIcon = Icons.info_outline;
    } else if (_status == VerifyStatus.error) {
      bannerBg = Colors.red.withOpacity(0.10);
      bannerFg = Colors.red.shade800;
      bannerIcon = Icons.error_outline;
    }

    return Scaffold(
      backgroundColor: AppColors.pageBackgroundLight,

      // ✅ Paint background behind body
      body: ColoredBox(
        color: AppColors.pageBackgroundLight,
        child: ListView(
          padding: const EdgeInsets.symmetric(
            vertical: _pageVPad,
            horizontal: _pageHPad,
          ),
          children: [
            FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: CenteredForm(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(_cardRadius),
                      border: Border.all(color: Colors.black.withOpacity(0.06)),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const ImageIcon(
                            AssetImage('assets/icons/aa_logo_imageicon_256.png'),
                            size: _logoSize,
                            color: AppColors.brandBlue,
                          ),
                          const SizedBox(height: 14),

                          Container(
                            height: _accentH,
                            width: _accentW,
                            margin: const EdgeInsets.only(bottom: _blockGap),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.brandBlue.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),

                          Text(
                            "Verify your email",
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF101828),
                            ),
                          ),
                          const SizedBox(height: 6),

                          Text(
                            "Check your inbox and click the verification link we sent you.",
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF475467),
                            ),
                          ),
                          const SizedBox(height: _blockGap),

                          if (_showInitialInfo) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.brandBlue.withOpacity(0.07),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                "If you don’t see the email, please check your spam or junk folder.",
                                style:
                                    theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF475467),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: _blockGap),
                          ],

                          if (_message != null && bannerBg != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: bannerBg,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(bannerIcon,
                                      size: 20, color: bannerFg),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _message!,
                                      style: theme
                                          .textTheme.bodySmall
                                          ?.copyWith(
                                        color: bannerFg,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: _blockGap),
                          ],

                          SizedBox(
                            height: _buttonH,
                            child: FilledButton(
                              onPressed:
                                  _checking ? null : _checkVerified,
                              style: FilledButton.styleFrom(
                                backgroundColor:
                                    AppColors.brandBlue,
                                foregroundColor:
                                    AppColors.cardBackground,
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(12),
                                ),
                              ),
                              child: _checking
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color:
                                            AppColors.cardBackground,
                                      ),
                                    )
                                  : const Text(
                                      "I’ve verified my email",
                                    ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          SizedBox(
                            height: _buttonH,
                            child: OutlinedButton(
                              onPressed:
                                  (_resending ||
                                          _resendCooldownSeconds > 0)
                                      ? null
                                      : _resend,
                              style: OutlinedButton.styleFrom(
                                foregroundColor:
                                    AppColors.brandBlue,
                                side: BorderSide(
                                  color: AppColors.brandBlue
                                      .withOpacity(0.55),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(12),
                                ),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              child: _resending
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child:
                                          CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      "Resend verification email",
                                    ),
                            ),
                          ),

                          if (_resendCooldownSeconds > 0) ...[
                            const SizedBox(height: 8),
                            Text(
                              "You can resend another email in ${_resendCooldownSeconds}s",
                              textAlign: TextAlign.center,
                              style: theme
                                  .textTheme.bodySmall
                                  ?.copyWith(
                                color: AppColors.lightGrey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],

                          const SizedBox(height: 14),

                          TextButton(
                            onPressed: _backToLogin,
                            child: const Text(
                              "Back to login",
                              style: TextStyle(
                                color: AppColors.brandBlue,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
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
}