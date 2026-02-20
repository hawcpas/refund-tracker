import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/centered_form.dart';

enum VerifyStatus { idle, checking, notVerified, verified, error, resent }

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  // ✅ EXACT: #08449E (same as Login + Forgot Password)
  static const Color brandBlue = Color(0xFF08449E);

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

  // ✅ Show a professional delivery notice only on first view
  bool _showInitialInfo = true;

  // ✅ Resend cooldown
  static const int _cooldownTotalSeconds = 60;
  int _resendCooldownSeconds = 0;
  Timer? _resendTimer;

  // ✅ Entrance animation (matches your other branded screens)
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
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

    // ✅ Brand-aligned banners (more #08449E inside the page)
    Color? bannerBg;
    Color? bannerFg;
    IconData? bannerIcon;

    switch (_status) {
      case VerifyStatus.notVerified:
        bannerBg = VerifyEmailScreen.brandBlue.withOpacity(0.08);
        bannerFg = VerifyEmailScreen.brandBlue;
        bannerIcon = Icons.info_outline;
        break;
      case VerifyStatus.verified:
        bannerBg = VerifyEmailScreen.brandBlue.withOpacity(0.12);
        bannerFg = VerifyEmailScreen.brandBlue;
        bannerIcon = Icons.check_circle_outline;
        break;
      case VerifyStatus.resent:
        bannerBg = VerifyEmailScreen.brandBlue.withOpacity(0.12);
        bannerFg = VerifyEmailScreen.brandBlue;
        bannerIcon = Icons.mark_email_read_outlined;
        break;
      case VerifyStatus.error:
        bannerBg = Colors.red.withOpacity(0.10);
        bannerFg = Colors.red.shade800;
        bannerIcon = Icons.error_outline;
        break;
      default:
        bannerBg = null;
        bannerFg = null;
        bannerIcon = null;
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // ✅ same subtle “brand wash” as login/forgot screens
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    VerifyEmailScreen.brandBlue.withOpacity(0.12),
                    Colors.white,
                    Colors.white,
                  ],
                  stops: const [0.0, 0.35, 1.0],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),

          ListView(
            padding: const EdgeInsets.symmetric(vertical: 40),
            children: [
              // ✅ Logo badge at top (same as other screens)
              CenteredForm(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: VerifyEmailScreen.brandBlue.withOpacity(0.22),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: VerifyEmailScreen.brandBlue.withOpacity(0.18),
                            blurRadius: 22,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: const ImageIcon(
                        AssetImage('assets/icons/aa_logo_imageicon_256.png'),
                        size: 92,
                        color: VerifyEmailScreen.brandBlue, // ✅ #08449E
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      height: 6,
                      width: 84,
                      decoration: BoxDecoration(
                        color: VerifyEmailScreen.brandBlue.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: CenteredForm(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: VerifyEmailScreen.brandBlue.withOpacity(0.12),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ✅ Light “header row” (instead of heavy AppBar)
                            Row(
                              children: [
                                IconButton(
                                  onPressed: _backToLogin,
                                  icon: const Icon(Icons.arrow_back_rounded),
                                  color: VerifyEmailScreen.brandBlue,
                                  tooltip: "Back to login",
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  "Verify your email",
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: VerifyEmailScreen.brandBlue,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            Icon(
                              Icons.mark_email_unread_outlined,
                              size: 48,
                              color: VerifyEmailScreen.brandBlue,
                            ),
                            const SizedBox(height: 12),

                            Text(
                              "Check your inbox",
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF101828),
                              ),
                            ),
                            const SizedBox(height: 8),

                            Text(
                              "We’ve sent you a verification email.\n\n"
                              "After clicking the link, return here and tap "
                              "“I’ve verified my email”.",
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFF475467),
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 18),

                            // ✅ Initial professional delivery notice (brand styled)
                            if (_showInitialInfo) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: VerifyEmailScreen.brandBlue.withOpacity(0.07),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: VerifyEmailScreen.brandBlue.withOpacity(0.18),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      size: 20,
                                      color: VerifyEmailScreen.brandBlue,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        "Verification emails are usually delivered within a few moments. "
                                        "In some cases, they may appear in your spam or junk folder. "
                                        "If you don’t see it shortly, please check those folders before "
                                        "requesting another email.",
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: const Color(0xFF475467),
                                          height: 1.35,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],

                            // ✅ Status banner (brand + error)
                            if (_message != null && bannerBg != null) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: bannerBg,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: (bannerFg ?? Colors.transparent)
                                        .withOpacity(0.25),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(bannerIcon, size: 20, color: bannerFg),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _message!,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: bannerFg,
                                          height: 1.35,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],

                            // ✅ Primary brand button
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: VerifyEmailScreen.brandBlue,
                                  foregroundColor: Colors.white,
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: _checking ? null : _checkVerified,
                                child: _checking
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text("I’ve verified my email"),
                              ),
                            ),

                            const SizedBox(height: 12),

                            // ✅ Brand outlined button
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: VerifyEmailScreen.brandBlue,
                                  side: BorderSide(
                                    color: VerifyEmailScreen.brandBlue.withOpacity(0.55),
                                    width: 1.2,
                                  ),
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: (_resending || _resendCooldownSeconds > 0)
                                    ? null
                                    : _resend,
                                child: _resending
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text("Resend verification email"),
                              ),
                            ),

                            if (_resendCooldownSeconds > 0) ...[
                              const SizedBox(height: 8),
                              Text(
                                "You can resend another email in ${_resendCooldownSeconds}s",
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF667085),
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
                                  color: VerifyEmailScreen.brandBlue,
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
        ],
      ),
    );
  }
}