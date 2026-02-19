import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../widgets/centered_form.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  final FocusNode emailFocusNode = FocusNode();
  final FocusNode passwordFocusNode = FocusNode();
  final FocusNode confirmPasswordFocusNode = FocusNode();

  final AuthService _auth = AuthService();

  bool isLoading = false;
  bool obscurePassword = true;
  bool obscureConfirmPassword = true;

  /// ONLY controls whether the red error UI is visible.
  /// This is turned on ONLY when Sign Up is pressed and passwords mismatch.
  bool showPasswordMismatchError = false;

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
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    emailFocusNode.dispose();
    passwordFocusNode.dispose();
    confirmPasswordFocusNode.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Desired behavior:
  /// - If the mismatch error is showing and the user types in EITHER field,
  ///   hide the red immediately (even if still mismatched).
  void _clearPasswordMismatchUIOnType() {
    if (showPasswordMismatchError) {
      setState(() {
        showPasswordMismatchError = false;
      });
    }
  }

  Future<void> _signup() async {
    if (isLoading) return; // prevent double taps

    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();

    // Validation
    if (email.isEmpty || !email.contains("@")) {
      _showError("Please enter a valid email");
      return;
    }
    if (password.length < 6) {
      _showError("Password must be at least 6 characters");
      return;
    }
    if (password != confirmPassword) {
      setState(() => showPasswordMismatchError = true);
      _showError("Passwords do not match");
      return;
    }

    setState(() => isLoading = true);

    try {
      // Attempt signup (AuthService should send verification email inside signup)
      final user = await _auth
          .signup(email, password)
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (user != null) {
        // Don't show snackbar on the old route right before navigation.
        // Navigate first, then show message on the verify screen (better UX).
        Navigator.pushReplacementNamed(context, '/verify-email');
      } else {
        _showError("Signup failed");
      }
    } on FirebaseAuthException catch (e) {
      // Firebase gives helpful codes
      if (!mounted) return;

      if (e.code == 'email-already-in-use') {
        _showError("User already exists");
      } else if (e.code == 'weak-password') {
        _showError("Password is too weak");
      } else if (e.code == 'invalid-email') {
        _showError("Please enter a valid email");
      } else if (e.code == 'operation-not-allowed') {
        _showError("Email/password sign-in is not enabled in Firebase Console");
      } else if (e.code == 'too-many-requests') {
        _showError("Too many attempts. Try again later.");
      } else {
        _showError(e.message ?? "Signup error");
      }
    } on TimeoutException {
      if (!mounted) return;
      _showError("Signup timed out. Check your internet connection.");
    } catch (e) {
      if (!mounted) return;
      _showError("Unexpected error: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Only show error text/border when the submit-triggered flag is true
    final String? passwordErrorText = showPasswordMismatchError
        ? "Passwords do not match"
        : null;

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            // HEADER
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 60),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.primary.withOpacity(0.7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Column(
                children: [
                  Icon(Icons.person_add, size: 80, color: Colors.white),
                  SizedBox(height: 12),
                  Text(
                    "Create Account",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // ANIMATED SIGNUP CARD
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: CenteredForm(
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          children: [
                            Text(
                              "Sign Up",
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),

                            const SizedBox(height: 30),

                            // EMAIL FIELD
                            TextField(
                              controller: emailController,
                              focusNode: emailFocusNode,
                              textInputAction: TextInputAction.next,
                              onSubmitted: (_) {
                                FocusScope.of(
                                  context,
                                ).requestFocus(passwordFocusNode);
                              },
                              decoration: InputDecoration(
                                labelText: "Email",
                                filled: true,
                                fillColor: Colors.grey.shade100,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),

                            const SizedBox(height: 20),

                            // PASSWORD FIELD
                            TextField(
                              controller: passwordController,
                              focusNode: passwordFocusNode,
                              obscureText: obscurePassword,
                              textInputAction: TextInputAction.next,
                              onChanged: (_) =>
                                  _clearPasswordMismatchUIOnType(),
                              onSubmitted: (_) {
                                FocusScope.of(
                                  context,
                                ).requestFocus(confirmPasswordFocusNode);
                              },
                              decoration: InputDecoration(
                                labelText: "Password",
                                filled: true,
                                fillColor: Colors.grey.shade100,
                                errorText: passwordErrorText,
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Colors.red,
                                  ),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Colors.red,
                                  ),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      obscurePassword = !obscurePassword;
                                    });
                                  },
                                ),
                              ),
                            ),

                            const SizedBox(height: 20),

                            // CONFIRM PASSWORD FIELD
                            TextField(
                              controller: confirmPasswordController,
                              focusNode: confirmPasswordFocusNode,
                              obscureText: obscureConfirmPassword,
                              textInputAction: TextInputAction.done,
                              onChanged: (_) =>
                                  _clearPasswordMismatchUIOnType(),
                              onSubmitted: (_) => _signup(),
                              decoration: InputDecoration(
                                labelText: "Re-enter Password",
                                filled: true,
                                fillColor: Colors.grey.shade100,
                                errorText: passwordErrorText,
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Colors.red,
                                  ),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Colors.red,
                                  ),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    obscureConfirmPassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      obscureConfirmPassword =
                                          !obscureConfirmPassword;
                                    });
                                  },
                                ),
                              ),
                            ),

                            const SizedBox(height: 30),

                            // SIGNUP BUTTON OR LOADING
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: isLoading
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : FilledButton(
                                      onPressed: _signup,
                                      child: const Text("Create Account"),
                                    ),
                            ),

                            const SizedBox(height: 20),

                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                              },
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
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
