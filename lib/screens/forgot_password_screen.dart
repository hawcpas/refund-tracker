import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/local_auth_prefs.dart';
import '../widgets/centered_form.dart';

enum ResetStatus { idle, sending, sent, error }

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  static const Color brandBlue = Color(0xFF08449E);

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _auth = AuthService();
  final emailController = TextEditingController();

  ResetStatus _status = ResetStatus.idle;
  String? _message;
  String? _emailError;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // ✅ SAME density + tokens as LoginScreen
  static const double _pageVPad = 28;
  static const double _cardRadius = 18;
  static const double _cardPad = 16;
  static const double _fieldGap = 12;
  static const double _blockGap = 16;
  static const double _buttonH = 46;
  static const double _footerGap = 24;

  // ✅ Logo sizing (same as Login)
  static const double _logoSize = 80;
  static const double _accentH = 4;
  static const double _accentW = 72;

  // ✅ Solid background (NO gradient)
  static const Color _pageBg = Color(0xFFF6F7F9);

  @override
  void initState() {
    super.initState();
    _prefillEmail();

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
        _message =
            "We couldn’t send a reset email at this time. Please try again.";
      });
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // ✅ Banner styling (aligned with Login tone)
    Color? bannerBg;
    Color? bannerFg;
    IconData? bannerIcon;

    if (_status == ResetStatus.sent) {
      bannerBg = ForgotPasswordScreen.brandBlue.withOpacity(0.10);
      bannerFg = ForgotPasswordScreen.brandBlue;
      bannerIcon = Icons.mark_email_read_outlined;
    } else if (_status == ResetStatus.error) {
      bannerBg = Colors.red.withOpacity(0.10);
      bannerFg = Colors.red.shade800;
      bannerIcon = Icons.error_outline;
    }

    return Scaffold(
      backgroundColor: _pageBg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool pinFooter = constraints.maxHeight >= 820;

          Widget content = FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: CenteredForm(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(_cardRadius),
                    border:
                        Border.all(color: Colors.black.withOpacity(0.06)),
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
                        // ✅ Logo (inside card, no box)
                        const ImageIcon(
                          AssetImage(
                              'assets/icons/aa_logo_imageicon_256.png'),
                          size: _logoSize,
                          color: ForgotPasswordScreen.brandBlue,
                        ),
                        const SizedBox(height: 14),
                        Container(
                          height: _accentH,
                          width: _accentW,
                          alignment: Alignment.center,
                          margin: const EdgeInsets.only(bottom: _blockGap),
                          decoration: BoxDecoration(
                            color: ForgotPasswordScreen.brandBlue
                                .withOpacity(0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),

                        // ✅ Back row
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.arrow_back_rounded),
                              color: ForgotPasswordScreen.brandBlue,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "Reset password",
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF101828),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        Text(
                          "Forgot your password?",
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF101828),
                          ),
                        ),
                        const SizedBox(height: 6),

                        Text(
                          "Enter your email address and we’ll send you a link to reset your password.",
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF475467),
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: _blockGap),

                        if (_message != null && bannerBg != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: bannerBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color:
                                    bannerFg!.withOpacity(0.25),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(bannerIcon,
                                    size: 20, color: bannerFg),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _message!,
                                    style:
                                        theme.textTheme.bodySmall?.copyWith(
                                      color: bannerFg,
                                      height: 1.35,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: _blockGap),
                        ],

                        TextField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          onChanged: (_) => _clear(),
                          decoration: InputDecoration(
                            labelText: "Email",
                            prefixIcon: const Icon(
                              Icons.mail_outline,
                              color: ForgotPasswordScreen.brandBlue,
                            ),
                            errorText: _emailError,
                          ),
                        ),

                        const SizedBox(height: _blockGap),

                        SizedBox(
                          height: _buttonH,
                          child: FilledButton(
                            onPressed: _status == ResetStatus.sending
                                ? null
                                : _sendReset,
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  ForgotPasswordScreen.brandBlue,
                              foregroundColor: Colors.white,
                              textStyle: const TextStyle(
                                  fontWeight: FontWeight.w900),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(12),
                              ),
                            ),
                            child: _status == ResetStatus.sending
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text("Send reset link"),
                          ),
                        ),

                        const SizedBox(height: 12),

                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            "Back to login",
                            style: TextStyle(
                              color: ForgotPasswordScreen.brandBlue,
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
          );

          if (!pinFooter) {
            return ListView(
              padding:
                  const EdgeInsets.symmetric(vertical: _pageVPad),
              children: [
                content,
                const SizedBox(height: _footerGap),
              ],
            );
          }

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: _pageVPad),
                  children: [content],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}