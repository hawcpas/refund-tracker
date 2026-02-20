import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/centered_form.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  // ✅ EXACT: #08449E (same as other auth screens)
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

  // ✅ Inline errors (professional field highlighting)
  String? _emailError;
  String? _passwordError;
  String? _confirmError;

  // Optional subtle banner error for rare cases
  String? _generalError;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

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
        Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
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

    // Reset old errors
    setState(() {
      _emailError = null;
      _passwordError = null;
      _confirmError = null;
      _generalError = null;
    });

    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();

    // ✅ Field validation with inline errors
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
      // ✅ Use your updated AuthService method that returns Firebase error codes.
      final result =
          await _auth.signupDetailed(email, password).timeout(const Duration(seconds: 15));

      if (!mounted) return;

      // Success
      if (result.code == null && result.data != null) {
        Navigator.pushReplacementNamed(context, '/verify-email');
        return;
      }

      // ✅ Professional, specific handling
      switch (result.code) {
        case 'email-already-in-use':
          setState(() {
            _emailError =
                "This email is already associated with an account. Please log in.";
          });
          emailFocusNode.requestFocus();
          break;

        case 'invalid-email':
          setState(() {
            _emailError = "Enter a valid email address.";
          });
          emailFocusNode.requestFocus();
          break;

        case 'weak-password':
          setState(() {
            _passwordError = "Password is too weak. Use at least 6 characters.";
          });
          passwordFocusNode.requestFocus();
          break;

        case 'operation-not-allowed':
          setState(() {
            _generalError = "Email/password sign-in is not enabled for this app.";
          });
          break;

        case 'too-many-requests':
          setState(() {
            _generalError = "Too many attempts. Please wait a moment and try again.";
          });
          break;

        case 'network-request-failed':
          setState(() {
            _generalError = "Network error. Please check your internet connection.";
          });
          break;

        default:
          setState(() {
            _generalError = "We couldn’t create your account. Please try again.";
          });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _generalError = "Signup timed out. Check your internet connection.";
      });
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final bool showEmailInUseAction = _emailError != null &&
        _emailError!.toLowerCase().contains("already associated");

    // ✅ Same “popping” input theme as other branded screens
    final inputTheme = theme.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: const Color(0xFFF4F7FF),
      prefixIconColor: SignupScreen.brandBlue,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: SignupScreen.brandBlue.withOpacity(0.18),
          width: 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: SignupScreen.brandBlue,
          width: 1.8,
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // ✅ Subtle brand “wash” like Login/Forgot/Verify
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    SignupScreen.brandBlue.withOpacity(0.12),
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
              // ✅ Logo badge header (same look as other screens)
              CenteredForm(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: SignupScreen.brandBlue.withOpacity(0.22),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: SignupScreen.brandBlue.withOpacity(0.18),
                            blurRadius: 22,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: const ImageIcon(
                        AssetImage('assets/icons/aa_logo_imageicon_256.png'),
                        size: 92,
                        color: SignupScreen.brandBlue, // ✅ #08449E
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      height: 6,
                      width: 84,
                      decoration: BoxDecoration(
                        color: SignupScreen.brandBlue.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      "Create Account",
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF101828),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Set up your account to continue",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF475467),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ✅ Signup Card (white, soft shadow, brand border)
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
                            color: SignupScreen.brandBlue.withOpacity(0.12),
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
                            children: [
                              // ✅ General error banner (brand-consistent)
                              if (_generalError != null) ...[
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.10),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.red.withOpacity(0.20),
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
                                const SizedBox(height: 14),
                              ],

                              TextField(
                                controller: emailController,
                                focusNode: emailFocusNode,
                                textInputAction: TextInputAction.next,
                                keyboardType: TextInputType.emailAddress,
                                onChanged: (_) => _clearErrorsOnType(),
                                onSubmitted: (_) => FocusScope.of(context)
                                    .requestFocus(passwordFocusNode),
                                decoration: InputDecoration(
                                  labelText: "Email",
                                  prefixIcon: const Icon(Icons.mail_outline),
                                  errorText: _emailError,
                                ),
                              ),

                              // ✅ Quick action when email already exists
                              if (showEmailInUseAction) ...[
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text(
                                      "Go to login",
                                      style: TextStyle(
                                        color: SignupScreen.brandBlue,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ],

                              const SizedBox(height: 16),

                              TextField(
                                controller: passwordController,
                                focusNode: passwordFocusNode,
                                obscureText: obscurePassword,
                                textInputAction: TextInputAction.next,
                                onChanged: (_) => _clearErrorsOnType(),
                                onSubmitted: (_) => FocusScope.of(context)
                                    .requestFocus(confirmPasswordFocusNode),
                                decoration: InputDecoration(
                                  labelText: "Password",
                                  helperText: "Minimum 6 characters",
                                  errorText: _passwordError,
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      obscurePassword
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: SignupScreen.brandBlue,
                                    ),
                                    onPressed: () => setState(
                                      () => obscurePassword = !obscurePassword,
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              TextField(
                                controller: confirmPasswordController,
                                focusNode: confirmPasswordFocusNode,
                                obscureText: obscureConfirmPassword,
                                textInputAction: TextInputAction.done,
                                onChanged: (_) => _clearErrorsOnType(),
                                onSubmitted: (_) => _signup(),
                                decoration: InputDecoration(
                                  labelText: "Confirm password",
                                  errorText: _confirmError,
                                  prefixIcon: const Icon(Icons.lock_reset),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      obscureConfirmPassword
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: SignupScreen.brandBlue,
                                    ),
                                    onPressed: () => setState(
                                      () => obscureConfirmPassword =
                                          !obscureConfirmPassword,
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 22),

                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: isLoading
                                    ? const Center(
                                        child: CircularProgressIndicator(),
                                      )
                                    : FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: SignupScreen.brandBlue,
                                          foregroundColor: Colors.white,
                                          textStyle: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                        ),
                                        onPressed: _signup,
                                        child: const Text("Create Account"),
                                      ),
                              ),

                              const SizedBox(height: 14),

                              // ✅ Brand divider (adds more blue presence)
                              Row(
                                children: [
                                  Expanded(
                                    child: Divider(
                                      color: SignupScreen.brandBlue.withOpacity(0.18),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    child: Text(
                                      "OR",
                                      style: theme.textTheme.labelMedium?.copyWith(
                                        color: const Color(0xFF667085),
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Divider(
                                      color: SignupScreen.brandBlue.withOpacity(0.18),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 10),

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
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
