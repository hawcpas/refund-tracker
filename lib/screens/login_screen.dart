import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/local_auth_prefs.dart';
import '../widgets/centered_form.dart';
import '../theme/app_colors.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

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

  String? _emailError;
  String? _passwordError;
  String? _authError;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // ✅ Refined density (matches your “less bulky” direction)
  static const double _pageVPad = 28;
  static const double _cardRadius = 18;
  static const double _cardPad = 16;
  static const double _fieldGap = 12;
  static const double _blockGap = 16;
  static const double _buttonH = 46;
  static const double _footerGap = 24;

  // ✅ Logo inside card (Intuit-style)
  // ✅ Logo inside card (larger, no box)
  static const double _logoSize = 80; // ⬆️ was 56
  static const double _logoPad = 10;
  static const double _accentH = 4;
  static const double _accentW = 72; // ⬆️ match visual weight

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
        Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(
          CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
        );

    _animationController.forward();
    _loadSavedEmail();
  }

  Future<void> _loadSavedEmail() async {
    final savedEmail = await LocalAuthPrefs.getSavedEmail();
    if (savedEmail != null && mounted) {
      setState(() => emailController.text = savedEmail);
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
      setState(
        () => _authError = "The email or password you entered is incorrect.",
      );
      return;
    }

    await LocalAuthPrefs.saveEmail(email);

    final verified = await _auth.isEmailVerified();
    if (!mounted) return;

    Navigator.pushReplacementNamed(
      context,
      verified ? '/dashboard' : '/verify-email',
    );
  }

  Widget _loginCard(ThemeData theme, bool showAuthError) {
    // If you choose solid brand blue background, flip these for contrast.
    final bool darkBg = AppColors.pageBackgroundLight == AppColors.brandBlue;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: CenteredForm(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.cardBackground, // ✅ pure white card
              borderRadius: BorderRadius.circular(_cardRadius),
              border: Border.all(color: Colors.black.withOpacity(0.06)),
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
                children: [
                  // ✅ LOGO INSIDE CARD (Intuit-style)
                  // ✅ Logo without a boxed container
                  // ✅ Logo without a boxed container
                  const ImageIcon(
                    AssetImage('assets/icons/aa_logo_imageicon_256.png'),
                    size: _logoSize,
                    color: AppColors.brandBlue,
                  ),
                  const SizedBox(height: 10),

                  // ✅ Subtle accent rule (optional; keep or remove)
                  Container(
                    height: _accentH,
                    width: _accentW,
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),

                  const SizedBox(height: _blockGap),

                  Text(
                    "Login",
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF101828),
                      letterSpacing: -0.15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Welcome back — sign in to continue",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF475467),
                    ),
                  ),
                  const SizedBox(height: _blockGap),

                  TextField(
                    controller: emailController,
                    focusNode: emailFocusNode,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => _clearInlineErrors(),
                    onSubmitted: (_) =>
                        FocusScope.of(context).requestFocus(passwordFocusNode),
                    decoration: InputDecoration(
                      labelText: "Email",
                      prefixIcon: const Icon(
                        Icons.mail_outline,
                        color: AppColors.brandBlue,
                      ),
                      errorText: _emailError ?? (showAuthError ? " " : null),
                      errorStyle: const TextStyle(height: 0.1, fontSize: 0.1),
                    ),
                  ),
                  const SizedBox(height: _fieldGap),

                  TextField(
                    controller: passwordController,
                    focusNode: passwordFocusNode,
                    obscureText: obscurePassword,
                    onChanged: (_) => _clearInlineErrors(),
                    onSubmitted: (_) => _login(),
                    decoration: InputDecoration(
                      labelText: "Password",
                      prefixIcon: const Icon(
                        Icons.lock_outline,
                        color: AppColors.brandBlue,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: AppColors.brandBlue,
                        ),
                        onPressed: () => setState(() {
                          obscurePassword = !obscurePassword;
                        }),
                      ),
                      errorText: _passwordError ?? _authError,
                    ),
                  ),
                  const SizedBox(height: _fieldGap),

                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, '/forgot-password'),
                      child: const Text(
                        "Forgot password?",
                        style: TextStyle(
                          color: AppColors.brandBlue,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 6),

                  SizedBox(
                    width: double.infinity,
                    height: _buttonH,
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.brandBlue,
                              foregroundColor: AppColors.cardBackground,
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _login,
                            child: const Text("Login"),
                          ),
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: Divider(color: Colors.black.withOpacity(0.10)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          "OR",
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: AppColors.lightGrey,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Divider(color: Colors.black.withOpacity(0.10)),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  TextButton(
                    onPressed: () => Navigator.pushNamed(context, '/signup'),
                    child: const Text(
                      "Create a new account",
                      style: TextStyle(
                        color: AppColors.brandBlue,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),

                  if (darkBg) ...[
                    // If you ever switch to solid blue background and want extra contrast,
                    // you can optionally add a subtle divider or note here.
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _footer(ThemeData theme) {
    // If background becomes solid blue, you may want white footer text.
    final bool darkBg = AppColors.pageBackgroundLight == AppColors.brandBlue;
    final Color footerColor = darkBg
        ? AppColors.cardBackground.withOpacity(0.86)
        : AppColors.mutedText;

    return CenteredForm(
      child: Column(
        children: [
          Text(
            "© 2026 Axume & Associates CPAs, AAC",
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: footerColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Professional Accounting and Advisory Services.\nAll rights reserved.",
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: darkBg
                  ? AppColors.cardBackground.withOpacity(0.78)
                  : AppColors.mutedText,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool showAuthError = _authError != null;

    return Scaffold(
      backgroundColor: AppColors.pageBackgroundLight, // ✅ SOLID BACKGROUND (no gradient)
      body: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bool pinFooter = constraints.maxHeight >= 820;

                if (!pinFooter) {
                  return ListView(
                    padding: const EdgeInsets.symmetric(vertical: _pageVPad),
                    children: [
                      const SizedBox(height: 8),
                      _loginCard(theme, showAuthError),
                      const SizedBox(height: _footerGap),
                      _footer(theme),
                    ],
                  );
                }

                return Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(
                          vertical: _pageVPad,
                        ),
                        children: [
                          const SizedBox(height: 8),
                          _loginCard(theme, showAuthError),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _footer(theme),
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
