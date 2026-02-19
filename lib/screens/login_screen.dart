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
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  final emailFocusNode = FocusNode();
  final passwordFocusNode = FocusNode();

  final AuthService _auth = AuthService();

  bool isLoading = false;
  bool obscurePassword = true;

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
    emailFocusNode.dispose();
    passwordFocusNode.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _forgotPassword() async {
    final dialogEmailController = TextEditingController(
      text: emailController.text.trim(),
    );

    final submittedEmail = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
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
      ),
    );

    if (submittedEmail == null || submittedEmail.isEmpty) return;

    setState(() => isLoading = true);
    final code = await _auth.sendPasswordResetEmail(submittedEmail);
    setState(() => isLoading = false);
    if (!mounted) return;

    if (code == null) {
      _showError("Password reset email sent. Check your inbox.");
    } else {
      _showError("Could not send reset email ($code).");
    }
  }

  void _login() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (!email.contains("@")) {
      _showError("Please enter a valid email");
      return;
    }
    if (password.length < 6) {
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

    final verified = await _auth.isEmailVerified();
    if (!mounted) return;

    Navigator.pushReplacementNamed(
      context,
      verified ? '/dashboard' : '/verify-email',
    );
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
      body: Stack(
        children: [
          // ✅ Same background language as other screens
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
              // ✅ Brand header
              CenteredForm(
                child: Column(
                  children: [
                    ImageIcon(
                      const AssetImage(
                        'assets/icons/aa_logo_imageicon_256.png',
                      ),
                      size: 128,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    // Text(
                    //   "Axume & Associates CPAs, AAC",
                    //   style: theme.textTheme.headlineSmall?.copyWith(
                    //     fontWeight: FontWeight.w800,
                    //   ),
                    // ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ✅ Login card
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
                          color: theme.colorScheme.outlineVariant.withOpacity(
                            0.7,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Text(
                              "Login",
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.primary,
                              ),
                            ),

                            const SizedBox(height: 24),

                            TextField(
                              controller: emailController,
                              focusNode: emailFocusNode,
                              textInputAction: TextInputAction.next,
                              onSubmitted: (_) => FocusScope.of(
                                context,
                              ).requestFocus(passwordFocusNode),
                              decoration: const InputDecoration(
                                labelText: "Email",
                                prefixIcon: Icon(Icons.mail_outline),
                              ),
                            ),

                            const SizedBox(height: 16),

                            TextField(
                              controller: passwordController,
                              focusNode: passwordFocusNode,
                              obscureText: obscurePassword,
                              onSubmitted: (_) => _login(),
                              decoration: InputDecoration(
                                labelText: "Password",
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                  onPressed: () => setState(
                                    () => obscurePassword = !obscurePassword,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 20),

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

                            const SizedBox(height: 12),

                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: isLoading
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : FilledButton(
                                      onPressed: _login,
                                      child: const Text("Login"),
                                    ),
                            ),

                            const SizedBox(height: 16),

                            TextButton(
                              onPressed: () =>
                                  Navigator.pushNamed(context, '/signup'),
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
              const SizedBox(height: 48),

              CenteredForm(
                child: Column(
                  children: [
                    Text(
                      "© 2026 Axume & Associates CPAs, AAC",
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Professional accounting and advisory services.\nAll rights reserved.",
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(
                          0.85,
                        ),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
