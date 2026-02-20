import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/local_auth_prefs.dart';
import '../widgets/centered_form.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  // ✅ EXACT: #08449E
  static const Color brandBlue = Color(0xFF08449E);

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
    _loadSavedEmail();
  }

  Future<void> _loadSavedEmail() async {
    final savedEmail = await LocalAuthPrefs.getSavedEmail();
    if (savedEmail != null && mounted) {
      setState(() {
        emailController.text = savedEmail;
      });
    }
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

  void _login() async {
    // Clear old errors
    setState(() {
      _emailError = null;
      _passwordError = null;
      _authError = null;
    });

    final email = emailController.text.trim();
    final password = passwordController.text.trim();

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
      setState(() {});
      return;
    }

    setState(() => isLoading = true);
    final user = await _auth.login(email, password);
    setState(() => isLoading = false);

    if (!mounted) return;

    if (user == null) {
      setState(() {
        _authError = "The email or password you entered is incorrect.";
      });
      return;
    }

    // ✅ Save email AFTER successful login
    await LocalAuthPrefs.saveEmail(email);

    final verified = await _auth.isEmailVerified();
    if (!mounted) return;

    Navigator.pushReplacementNamed(
      context,
      verified ? '/dashboard' : '/verify-email',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool showAuthError = _authError != null;

    // ✅ Local “popping” input style for THIS page
    final inputTheme = theme.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: const Color(0xFFF4F7FF), // subtle blue-tinted white
      prefixIconColor: LoginScreen.brandBlue,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: LoginScreen.brandBlue.withOpacity(0.18),
          width: 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: LoginScreen.brandBlue,
          width: 1.8,
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white, // ✅ WHITE background
      body: Stack(
        children: [
          // ✅ subtle brand “wash” at the top so the page pops without losing white
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    LoginScreen.brandBlue.withOpacity(0.12),
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

          // ✅ FIX: Use LayoutBuilder + Positioned.fill to prevent Stack shrink sizing,
// and pin footer ONLY when there's enough vertical space (web).
Positioned.fill(
  child: LayoutBuilder(
    builder: (context, constraints) {
      // Heuristic: if the viewport is tall enough, pin footer.
      final bool pinFooter = constraints.maxHeight >= 820;

      if (!pinFooter) {
        // ✅ Small screens: keep your original scrolling behavior
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 40),
          children: [
            // ✅ Logo at top (tinted #08449E)
            CenteredForm(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: LoginScreen.brandBlue.withOpacity(0.22),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: LoginScreen.brandBlue.withOpacity(0.18),
                          blurRadius: 22,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: const ImageIcon(
                      AssetImage('assets/icons/aa_logo_imageicon_256.png'),
                      size: 92,
                      color: LoginScreen.brandBlue,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    height: 6,
                    width: 84,
                    decoration: BoxDecoration(
                      color: LoginScreen.brandBlue.withOpacity(0.22),
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
                          color: LoginScreen.brandBlue.withOpacity(0.12),
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
                            // ✅ KEEP your existing login form content here exactly as-is
                            // (Login title, fields, buttons, etc.)
                            // ----------------------------------------------------------
                            Text(
                              "Login",
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: LoginScreen.brandBlue,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "Welcome back — sign in to continue",
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFF475467),
                              ),
                            ),
                            const SizedBox(height: 22),

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
                                errorText:
                                    _emailError ?? (showAuthError ? " " : null),
                                errorStyle: const TextStyle(
                                  height: 0.1,
                                  fontSize: 0.1,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

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
                                    color: LoginScreen.brandBlue,
                                  ),
                                  onPressed: () => setState(
                                    () => obscurePassword = !obscurePassword,
                                  ),
                                ),
                                errorText: _passwordError ?? _authError,
                              ),
                            ),
                            const SizedBox(height: 16),

                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () =>
                                    Navigator.pushNamed(context, '/forgot-password'),
                                child: const Text(
                                  "Forgot password?",
                                  style: TextStyle(
                                    color: LoginScreen.brandBlue,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 10),

                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: isLoading
                                  ? const Center(child: CircularProgressIndicator())
                                  : FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: LoginScreen.brandBlue,
                                        foregroundColor: Colors.white,
                                        textStyle: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                      ),
                                      onPressed: _login,
                                      child: const Text("Login"),
                                    ),
                            ),

                            const SizedBox(height: 14),

                            Row(
                              children: [
                                Expanded(
                                  child: Divider(
                                    color: LoginScreen.brandBlue.withOpacity(0.18),
                                  ),
                                ),
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 10),
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
                                    color: LoginScreen.brandBlue.withOpacity(0.18),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 10),

                            TextButton(
                              onPressed: () =>
                                  Navigator.pushNamed(context, '/signup'),
                              child: const Text(
                                "Create a new account",
                                style: TextStyle(
                                  color: LoginScreen.brandBlue,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            // ----------------------------------------------------------
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 48),

            // ✅ Footer in scroll on small screens
            CenteredForm(
              child: Column(
                children: [
                  Text(
                    "© 2026 Axume & Associates CPAs, AAC",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF667085),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Professional Accounting and Advisory Services.\nAll rights reserved.",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF667085).withOpacity(0.88),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      }

      // ✅ Tall screens (web): pin footer using Column + Expanded scroll
      return Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 40),
              children: [
                // (Same content as above, but WITHOUT the footer)
                CenteredForm(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: LoginScreen.brandBlue.withOpacity(0.22),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: LoginScreen.brandBlue.withOpacity(0.18),
                              blurRadius: 22,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: const ImageIcon(
                          AssetImage('assets/icons/aa_logo_imageicon_256.png'),
                          size: 92,
                          color: LoginScreen.brandBlue,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        height: 6,
                        width: 84,
                        decoration: BoxDecoration(
                          color: LoginScreen.brandBlue.withOpacity(0.22),
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
                              color: LoginScreen.brandBlue.withOpacity(0.12),
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
                                // ✅ KEEP your existing login form content here exactly as-is
                                // (same as the form block above)
                                Text(
                                  "Login",
                                  style: theme.textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: LoginScreen.brandBlue,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  "Welcome back — sign in to continue",
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: const Color(0xFF475467),
                                  ),
                                ),
                                const SizedBox(height: 22),

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
                                    errorText:
                                        _emailError ?? (showAuthError ? " " : null),
                                    errorStyle: const TextStyle(
                                      height: 0.1,
                                      fontSize: 0.1,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

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
                                        color: LoginScreen.brandBlue,
                                      ),
                                      onPressed: () => setState(
                                        () => obscurePassword = !obscurePassword,
                                      ),
                                    ),
                                    errorText: _passwordError ?? _authError,
                                  ),
                                ),
                                const SizedBox(height: 16),

                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () => Navigator.pushNamed(
                                        context, '/forgot-password'),
                                    child: const Text(
                                      "Forgot password?",
                                      style: TextStyle(
                                        color: LoginScreen.brandBlue,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 10),

                                SizedBox(
                                  width: double.infinity,
                                  height: 52,
                                  child: isLoading
                                      ? const Center(
                                          child: CircularProgressIndicator(),
                                        )
                                      : FilledButton(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: LoginScreen.brandBlue,
                                            foregroundColor: Colors.white,
                                            textStyle: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                          ),
                                          onPressed: _login,
                                          child: const Text("Login"),
                                        ),
                                ),

                                const SizedBox(height: 14),

                                Row(
                                  children: [
                                    Expanded(
                                      child: Divider(
                                        color: LoginScreen.brandBlue
                                            .withOpacity(0.18),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10),
                                      child: Text(
                                        "OR",
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                          color: const Color(0xFF667085),
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Divider(
                                        color: LoginScreen.brandBlue
                                            .withOpacity(0.18),
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 10),

                                TextButton(
                                  onPressed: () =>
                                      Navigator.pushNamed(context, '/signup'),
                                  child: const Text(
                                    "Create a new account",
                                    style: TextStyle(
                                      color: LoginScreen.brandBlue,
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
          ),

          // ✅ Pinned footer (only on tall screens)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: CenteredForm(
              child: Column(
                children: [
                  Text(
                    "© 2026 Axume & Associates CPAs, AAC",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF667085),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Professional Accounting and Advisory Services.\nAll rights reserved.",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF667085).withOpacity(0.88),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  ),
),
        ],
      ),
    );
  }
}