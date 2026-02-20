import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/local_auth_prefs.dart';
import '../widgets/centered_form.dart';

enum ResetStatus { idle, sending, sent, error }

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  // ✅ EXACT: #08449E (same as LoginScreen)
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

  @override
  void initState() {
    super.initState();
    _prefillEmail();

    // ✅ Same subtle entrance animation style as LoginScreen
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
  void dispose() {
    emailController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // ✅ Same “popping” input theme as LoginScreen
    final inputTheme = theme.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: const Color(0xFFF4F7FF),
      prefixIconColor: ForgotPasswordScreen.brandBlue,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: ForgotPasswordScreen.brandBlue.withOpacity(0.18),
          width: 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: ForgotPasswordScreen.brandBlue,
          width: 1.8,
        ),
      ),
    );

    // ✅ Banner styling aligned to brand look
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
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // ✅ Subtle brand “wash” like login page
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    ForgotPasswordScreen.brandBlue.withOpacity(0.12),
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
              // ✅ Top logo badge (same feel as login)
              CenteredForm(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: ForgotPasswordScreen.brandBlue.withOpacity(0.22),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: ForgotPasswordScreen.brandBlue.withOpacity(0.18),
                            blurRadius: 22,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: const ImageIcon(
                        AssetImage('assets/icons/aa_logo_imageicon_256.png'),
                        size: 92,
                        color: ForgotPasswordScreen.brandBlue, // ✅ #08449E
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      height: 6,
                      width: 84,
                      decoration: BoxDecoration(
                        color: ForgotPasswordScreen.brandBlue.withOpacity(0.22),
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
                    child: Theme(
                      data: theme.copyWith(inputDecorationTheme: inputTheme),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: ForgotPasswordScreen.brandBlue.withOpacity(0.12),
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
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // ✅ Back row like a “light app bar”
                              Row(
                                children: [
                                  IconButton(
                                    onPressed: () => Navigator.pop(context),
                                    icon: const Icon(Icons.arrow_back_rounded),
                                    color: ForgotPasswordScreen.brandBlue,
                                    tooltip: "Back",
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    "Reset password",
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: ForgotPasswordScreen.brandBlue,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              Icon(
                                Icons.lock_reset_outlined,
                                size: 48,
                                color: ForgotPasswordScreen.brandBlue,
                              ),
                              const SizedBox(height: 12),

                              Text(
                                "Forgot your password?",
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF101828),
                                ),
                              ),
                              const SizedBox(height: 8),

                              Text(
                                "Enter your email address and we’ll send you a link to reset your password.",
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: const Color(0xFF475467),
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 20),

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

                              const SizedBox(height: 20),

                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: ForgotPasswordScreen.brandBlue,
                                    foregroundColor: Colors.white,
                                    textStyle: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  onPressed: _status == ResetStatus.sending
                                      ? null
                                      : _sendReset,
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

                              const SizedBox(height: 14),

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
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}