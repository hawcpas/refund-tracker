import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'dart:async';
import '../widgets/centered_form.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

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
      final result = await _auth
          .signupDetailed(email, password)
          .timeout(const Duration(seconds: 15));

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
            _generalError =
                "Email/password sign-in is not enabled for this app.";
          });
          break;

        case 'too-many-requests':
          setState(() {
            _generalError =
                "Too many attempts. Please wait a moment and try again.";
          });
          break;

        case 'network-request-failed':
          setState(() {
            _generalError =
                "Network error. Please check your internet connection.";
          });
          break;

        default:
          setState(() {
            _generalError =
                "We couldn’t create your account. Please try again.";
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

    final bool showEmailInUseAction =
        _emailError != null &&
        _emailError!.toLowerCase().contains("already associated");

    return Scaffold(
      body: Stack(
        children: [
          // ✅ Soft background for desktop polish
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
              // ✅ Header
              CenteredForm(
                child: Column(
                  children: [
                    Icon(Icons.person_add,
                        size: 64, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(
                      "Create Account",
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ✅ Signup Card
              FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: CenteredForm(
                    child: Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerHigh,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(
                          color:
                              theme.colorScheme.outlineVariant.withOpacity(0.7),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            // ✅ Subtle banner for rare/general errors
                            if (_generalError != null) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.errorContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _generalError!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onErrorContainer,
                                    height: 1.3,
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

                            // ✅ Professional quick action when email already exists
                            if (showEmailInUseAction) ...[
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text("Go to login"),
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
                                  icon: Icon(obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility),
                                  onPressed: () => setState(
                                      () => obscurePassword = !obscurePassword),
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
                                  icon: Icon(obscureConfirmPassword
                                      ? Icons.visibility_off
                                      : Icons.visibility),
                                  onPressed: () => setState(() =>
                                      obscureConfirmPassword =
                                          !obscureConfirmPassword),
                                ),
                              ),
                            ),

                            const SizedBox(height: 24),

                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: isLoading
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : FilledButton(
                                      onPressed: _signup,
                                      child: const Text("Create Account"),
                                    ),
                            ),

                            const SizedBox(height: 16),

                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(
                                "Already have an account? Login",
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
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