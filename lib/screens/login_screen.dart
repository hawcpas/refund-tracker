import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/centered_form.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  final FocusNode emailFocusNode = FocusNode();
  final FocusNode passwordFocusNode = FocusNode();

  final AuthService _auth = AuthService();

  bool isLoading = false;
  bool obscurePassword = true;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  Future<void> _forgotPassword() async {
    final email = emailController.text.trim();

    // If email field is empty, ask for it via dialog input
    final TextEditingController dialogEmailController = TextEditingController(
      text: email,
    );

    final submittedEmail = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Reset password"),
          content: TextField(
            controller: dialogEmailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: "Email",
              hintText: "you@example.com",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, dialogEmailController.text.trim()),
              child: const Text("Send reset link"),
            ),
          ],
        );
      },
    );

    if (submittedEmail == null || submittedEmail.isEmpty) return;

    setState(() => isLoading = true);
    final code = await _auth.sendPasswordResetEmail(submittedEmail);
    setState(() => isLoading = false);
    if (!mounted) return;

    if (code == null) {
      _showError("Password reset email sent. Check your inbox.");
    } else if (code == 'invalid-email') {
      _showError("Please enter a valid email address.");
    } else if (code == 'too-many-requests') {
      _showError("Too many requests. Please wait a minute and try again.");
    } else {
      // Note: some platforms/projects may not reveal user-not-found (enumeration protection),
      // so keep this generic for security.
      _showError("Could not send reset email ($code).");
    }
  }

  @override
  void initState() {
    super.initState();

    // Animation setup
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
    emailFocusNode.dispose();
    passwordFocusNode.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _login() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    // Basic validation (keep your existing checks)
    if (email.isEmpty || !email.contains("@")) {
      _showError("Please enter a valid email");
      return;
    }
    if (password.isEmpty || password.length < 6) {
      _showError("Password must be at least 6 characters");
      return;
    }

    setState(() => isLoading = true);
    final user = await _auth.login(email, password);
    setState(() => isLoading = false);

    if (user == null) {
      _showError("Invalid email or password");
      return;
    }

    // NEW: Route based on verification status
    final verified = await _auth.isEmailVerified();
    if (!mounted) return;

    if (verified) {
      Navigator.pushReplacementNamed(context, '/dashboard');
    } else {
      Navigator.pushReplacementNamed(context, '/verify-email');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                  Icon(
                    Icons.account_balance_wallet,
                    size: 80,
                    color: Colors.white,
                  ),
                  SizedBox(height: 12),
                  Text(
                    "Refund Tracker",
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

            // ANIMATED LOGIN CARD
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
                              "Login",
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

                            // PASSWORD FIELD WITH TOGGLE
                            TextField(
                              controller: passwordController,
                              focusNode: passwordFocusNode,
                              obscureText: obscurePassword,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _login(),
                              decoration: InputDecoration(
                                labelText: "Password",
                                filled: true,
                                fillColor: Colors.grey.shade100,
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

                            const SizedBox(height: 30),

                            // FORGOT PASSWORD BUITON
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: isLoading ? null : _forgotPassword,
                                child: Text(
                                  "Forgot password?",
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),

                            // LOGIN BUTTON OR LOADING SPINNER
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: isLoading
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : FilledButton(
                                      onPressed: _login,
                                      child: const Text("Login"),
                                    ),
                            ),

                            const SizedBox(height: 20),

                            TextButton(
                              onPressed: () {
                                Navigator.pushNamed(context, '/signup');
                              },
                              child: Text(
                                "Create a new account",
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
