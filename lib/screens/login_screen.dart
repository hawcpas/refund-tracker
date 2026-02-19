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

  // ✅ Inline validation + auth error state
  String? _emailError;
  String? _passwordError;
  String? _authError;

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

  void _clearInlineErrors() {
    if (_emailError != null || _passwordError != null || _authError != null) {
      setState(() {
        _emailError = null;
        _passwordError = null;
        _authError = null;
      });
    }
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
      _showSnack("Password reset email sent. Check your inbox.");
    } else {
      _showSnack("Could not send reset email ($code).");
    }
  }

  void _login() async {
    // Clear old errors before validating
    setState(() {
      _emailError = null;
      _passwordError = null;
      _authError = null;
    });

    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    // ✅ Inline field validation
    bool ok = true;
    if (email.isEmpty || !email.contains("@")) {
      _emailError = "Enter a valid email address.";
      ok = false;
    }
    if (password.isEmpty || password.length < 6) {
      _passwordError = "Password must be at least 6 characters.";
      ok = false;
    }

    if (!ok) {
      setState(() {}); // paint errors
      return;
    }

    setState(() => isLoading = true);
    final user = await _auth.login(email, password);
    setState(() => isLoading = false);

    if (!mounted) return;

    // ✅ Professional auth error (wrong credentials)
    if (user == null) {
      setState(() {
        // Highlight BOTH fields red; show message under password field.
        _authError = "The email or password you entered is incorrect.";
      });
      return;
    }

    final verified = await _auth.isEmailVerified();
    if (!mounted) return;

    Navigator.pushReplacementNamed(
      context,
      verified ? '/dashboard' : '/verify-email',
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // If auth fails, we want both fields to show an error border.
    final bool showAuthError = _authError != null;

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
                      const AssetImage('assets/icons/aa_logo_imageicon_256.png'),
                      size: 128,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
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
                          color: theme.colorScheme.outlineVariant.withOpacity(0.7),
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

                            // ✅ EMAIL FIELD (red outline on validation OR auth failure)
                            TextField(
                              controller: emailController,
                              focusNode: emailFocusNode,
                              textInputAction: TextInputAction.next,
                              onChanged: (_) => _clearInlineErrors(),
                              onSubmitted: (_) => FocusScope.of(context)
                                  .requestFocus(passwordFocusNode),
                              decoration: InputDecoration(
                                labelText: "Email",
                                prefixIcon: const Icon(Icons.mail_outline),
                                // If auth failed, show border without noisy text.
                                errorText: _emailError ?? (showAuthError ? " " : null),
                                // Keep the placeholder error from taking space.
                                errorStyle: const TextStyle(height: 0.1, fontSize: 0.1),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // ✅ PASSWORD FIELD (shows message on validation OR auth failure)
                            TextField(
                              controller: passwordController,
                              focusNode: passwordFocusNode,
                              obscureText: obscurePassword,
                              onChanged: (_) => _clearInlineErrors(),
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
                                // Prefer specific field validation, otherwise auth error.
                                errorText: _passwordError ?? _authError,
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
                                  ? const Center(child: CircularProgressIndicator())
                                  : FilledButton(
                                      onPressed: _login,
                                      child: const Text("Login"),
                                    ),
                            ),

                            const SizedBox(height: 16),

                            TextButton(
                              onPressed: () => Navigator.pushNamed(context, '/signup'),
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

              // ✅ Footer
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
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(0.85),
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