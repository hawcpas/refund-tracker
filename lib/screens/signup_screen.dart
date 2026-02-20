import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/centered_form.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  static const Color brandBlue = Color(0xFF08449E);

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with SingleTickerProviderStateMixin {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  final emailFocusNode = FocusNode();
  final passwordFocusNode = FocusNode();
  final confirmPasswordFocusNode = FocusNode();

  final AuthService _auth = AuthService();

  bool isLoading = false;
  bool obscurePassword = true;
  bool obscureConfirmPassword = true;

  String? _emailError;
  String? _passwordError;
  String? _confirmError;
  String? _generalError;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // ✅ SAME TOKENS AS LOGIN / FORGOT
  static const double _pageVPad = 28;
  static const double _cardRadius = 18;
  static const double _cardPad = 16;
  static const double _fieldGap = 12;
  static const double _blockGap = 16;
  static const double _buttonH = 46;
  static const double _footerGap = 24;

  static const double _logoSize = 80;
  static const double _accentH = 4;
  static const double _accentW = 72;

  static const Color _pageBg = Color(0xFFF6F7F9);

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
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    emailFocusNode.dispose();
    passwordFocusNode.dispose();
    confirmPasswordFocusNode.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _clearErrorsOnType() {
    if (_emailError != null ||
        _passwordError != null ||
        _confirmError != null ||
        _generalError != null) {
      setState(() {
        _emailError = null;
        _passwordError = null;
        _confirmError = null;
        _generalError = null;
      });
    }
  }

  Future<void> _signup() async {
    if (isLoading) return;

    setState(() {
      _emailError = null;
      _passwordError = null;
      _confirmError = null;
      _generalError = null;
    });

    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();

    bool ok = true;

    if (email.isEmpty || !email.contains("@")) {
      _emailError = "Enter a valid email address.";
      ok = false;
    }

    if (password.length < 6) {
      _passwordError = "Password must be at least 6 characters.";
      ok = false;
    }

    if (confirmPassword.isEmpty) {
      _confirmError = "Please confirm your password.";
      ok = false;
    } else if (password != confirmPassword) {
      _passwordError = "Passwords do not match.";
      _confirmError = "Passwords do not match.";
      ok = false;
    }

    if (!ok) {
      setState(() {});
      return;
    }

    setState(() => isLoading = true);

    try {
      final result = await _auth
          .signupDetailed(email, password)
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (result.code == null && result.data != null) {
        Navigator.pushReplacementNamed(context, '/verify-email');
        return;
      }

      switch (result.code) {
        case 'email-already-in-use':
          _emailError =
              "This email is already associated with an account. Please log in.";
          emailFocusNode.requestFocus();
          break;
        case 'invalid-email':
          _emailError = "Enter a valid email address.";
          emailFocusNode.requestFocus();
          break;
        case 'weak-password':
          _passwordError = "Password is too weak. Use at least 6 characters.";
          passwordFocusNode.requestFocus();
          break;
        case 'too-many-requests':
          _generalError =
              "Too many attempts. Please wait a moment and try again.";
          break;
        case 'network-request-failed':
          _generalError =
              "Network error. Please check your internet connection.";
          break;
        default:
          _generalError =
              "We couldn’t create your account. Please try again.";
      }
    } on TimeoutException {
      _generalError = "Signup timed out. Check your internet connection.";
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                        // ✅ LOGO INSIDE CARD (NO BOX)
                        const ImageIcon(
                          AssetImage(
                              'assets/icons/aa_logo_imageicon_256.png'),
                          size: _logoSize,
                          color: SignupScreen.brandBlue,
                        ),
                        const SizedBox(height: 14),
                        Container(
                          height: _accentH,
                          width: _accentW,
                          alignment: Alignment.center,
                          margin:
                              const EdgeInsets.only(bottom: _blockGap),
                          decoration: BoxDecoration(
                            color: SignupScreen.brandBlue
                                .withOpacity(0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),

                        Text(
                          "Create account",
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF101828),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Set up your account to continue",
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF475467),
                          ),
                        ),
                        const SizedBox(height: _blockGap),

                        if (_generalError != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.red.withOpacity(0.25),
                              ),
                            ),
                            child: Text(
                              _generalError!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.red.shade800,
                                height: 1.3,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: _blockGap),
                        ],

                        TextField(
                          controller: emailController,
                          focusNode: emailFocusNode,
                          keyboardType: TextInputType.emailAddress,
                          onChanged: (_) => _clearErrorsOnType(),
                          decoration: InputDecoration(
                            labelText: "Email",
                            prefixIcon: const Icon(
                              Icons.mail_outline,
                              color: SignupScreen.brandBlue,
                            ),
                            errorText: _emailError,
                          ),
                        ),
                        const SizedBox(height: _fieldGap),

                        TextField(
                          controller: passwordController,
                          focusNode: passwordFocusNode,
                          obscureText: obscurePassword,
                          onChanged: (_) => _clearErrorsOnType(),
                          decoration: InputDecoration(
                            labelText: "Password",
                            helperText: "Minimum 6 characters",
                            prefixIcon: const Icon(
                              Icons.lock_outline,
                              color: SignupScreen.brandBlue,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: SignupScreen.brandBlue,
                              ),
                              onPressed: () => setState(() {
                                obscurePassword = !obscurePassword;
                              }),
                            ),
                            errorText: _passwordError,
                          ),
                        ),
                        const SizedBox(height: _fieldGap),

                        TextField(
                          controller: confirmPasswordController,
                          focusNode: confirmPasswordFocusNode,
                          obscureText: obscureConfirmPassword,
                          onChanged: (_) => _clearErrorsOnType(),
                          decoration: InputDecoration(
                            labelText: "Confirm password",
                            prefixIcon: const Icon(
                              Icons.lock_reset,
                              color: SignupScreen.brandBlue,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscureConfirmPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: SignupScreen.brandBlue,
                              ),
                              onPressed: () => setState(() {
                                obscureConfirmPassword =
                                    !obscureConfirmPassword;
                              }),
                            ),
                            errorText: _confirmError,
                          ),
                        ),

                        const SizedBox(height: _blockGap),

                        SizedBox(
                          height: _buttonH,
                          child: FilledButton(
                            onPressed: isLoading ? null : _signup,
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  SignupScreen.brandBlue,
                              foregroundColor: Colors.white,
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(12),
                              ),
                            ),
                            child: isLoading
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text("Create account"),
                          ),
                        ),

                        const SizedBox(height: 12),

                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            "Already have an account? Login",
                            style: TextStyle(
                              color: SignupScreen.brandBlue,
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
                  padding:
                      const EdgeInsets.symmetric(vertical: _pageVPad),
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