import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/local_auth_prefs.dart';
import '../widgets/centered_form.dart';
import '../theme/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/post_login_route.dart';
import '../widgets/intuit_text_field.dart';
import '../widgets/login_legal_notice.dart';

enum LoginStep { email, password }

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

  late final AnimationController _signinController;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _liftAnim;

  bool isLoading = false;
  bool obscurePassword = true;
  bool _rememberMe = true; // Intuit defaults this ON

  LoginStep _step = LoginStep.email;

  String? _emailError;
  String? _passwordError;
  String? _authError;

  // ✅ Refined density (matches your “less bulky” direction)
  static const double _cardRadius = 18;
  static const double _cardPad = 16;
  static const double _fieldGap = 12;
  static const double _blockGap = 16;
  static const double _buttonH = 46;

  // ✅ Logo inside card (larger, no box)
  static const double _logoSize = 80;
  static const double _accentH = 4;
  static const double _accentW = 72;

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();

    _signinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    _fadeAnim = CurvedAnimation(
      parent: _signinController,
      curve: Curves.easeOut,
    );

    _liftAnim = Tween<double>(begin: 0, end: -4).animate(
      CurvedAnimation(parent: _signinController, curve: Curves.easeOutCubic),
    );
  }

  Future<void> _loadSavedEmail() async {
    final remember = await LocalAuthPrefs.getRememberMe();
    final savedEmail = await LocalAuthPrefs.getSavedEmail();

    if (!mounted) return;

    setState(() {
      _rememberMe = remember;
      if (remember && savedEmail != null) {
        emailController.text = savedEmail;
      }
    });
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    emailFocusNode.dispose();
    passwordFocusNode.dispose();
    _signinController.dispose();
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

  Future<void> _continueToPassword() async {
    final email = emailController.text.trim().toLowerCase();

    if (email.isEmpty || !email.contains("@")) {
      setState(() {
        _emailError = "Enter a valid email address.";
      });
      return;
    }

    // ✅ STEP 4 — Persist Remember Me choice BEFORE UI transition
    await LocalAuthPrefs.setRememberMe(_rememberMe);

    if (_rememberMe) {
      await LocalAuthPrefs.saveEmail(email);
    } else {
      await LocalAuthPrefs.clearEmail();
    }

    // ✅ Now transition to password screen
    setState(() {
      _emailError = null;
      _step = LoginStep.password;
    });

    // ✅ Focus password after animation settles
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) {
        FocusScope.of(context).requestFocus(passwordFocusNode);
      }
    });
  }

  void _login() async {
    setState(() {
      _emailError = null;
      _passwordError = null;
      _authError = null;
    });

    final email = emailController.text.trim().toLowerCase();
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

    // ✅ spinner visible at least briefly
    final startedAt = DateTime.now();
    const minSpinnerMs = 300;

    setState(() => isLoading = true);
    _signinController.forward();

    final user = await _auth.login(email, password);

    if (!mounted) return;

    // keep spinner visible a moment (prevents flicker on fast logins)
    final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
    final remaining = minSpinnerMs - elapsed;
    if (remaining > 0) {
      await Future.delayed(Duration(milliseconds: remaining));
      if (!mounted) return;
    }

    setState(() => isLoading = false);
    _signinController.reverse();

    if (user == null) {
      setState(() {
        _authError = "The email or password you entered is incorrect.";
      });
      return;
    }

    await LocalAuthPrefs.saveEmail(email);

    await user.reload();
    final verified = user.emailVerified;
    if (!mounted) return;

    if (!verified) {
      Navigator.pushReplacementNamed(context, '/verify-email');
      return;
    }

    // ✅ Let AuthGate decide the final destination (OTP / deep link / dashboard)
    Navigator.pushReplacementNamed(
      context,
      pendingPostLoginRoute ?? '/dashboard',
    );
    pendingPostLoginRoute = null;
  }

  Widget _loginCard(ThemeData theme, bool showAuthError) {
    final VoidCallback? primaryAction = isLoading
        ? null
        : (_step == LoginStep.password ? _login : _continueToPassword);

    return CenteredForm(
      maxWidth: 380,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedBuilder(
            animation: _signinController,
            builder: (context, child) {
              return Opacity(
                opacity: 1 - (_fadeAnim.value * 0.08),
                child: Transform.translate(
                  offset: Offset(0, _liftAnim.value),
                  child: child,
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFD4D7DC)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),

              child: IgnorePointer(
                ignoring: isLoading,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ✅ Logo INSIDE card (Intuit-style)
                    Center(
                      child: ImageIcon(
                        const AssetImage(
                          'assets/icons/aa_logo_imageicon_256.png',
                        ),
                        size: 56,
                        color: AppColors.brandBlue,
                      ),
                    ),

                    const SizedBox(height: 16),
                    Text(
                      _step == LoginStep.password
                          ? "Enter your password"
                          : "Sign in",
                      textAlign: TextAlign.center, // ✅ CENTERED
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF393A3D),
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      "Use your Axume & Associates account",
                      textAlign: TextAlign.center, // ✅ CENTERED
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF6B6C72),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ✅ Intuit-style screen swap
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 320),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) {
                        return SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.04, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                        );
                      },
                      child: _step == LoginStep.email
                          ? Column(
                              key: const ValueKey('email-step'),
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                IntuitTextField(
                                  controller: emailController,
                                  focusNode: emailFocusNode,
                                  label: "Email",
                                  enabled: !isLoading,
                                  textInputAction: TextInputAction.done,
                                  onChanged: (_) => _clearInlineErrors(),
                                  onSubmitted: _continueToPassword,
                                  errorText: _emailError,
                                ),

                                // ✅ REMEMBER ME — EXACT PLACEMENT
                                const SizedBox(height: 8),

                                Row(
                                  children: [
                                    Checkbox(
                                      value: _rememberMe,
                                      onChanged: isLoading
                                          ? null
                                          : (val) {
                                              setState(() {
                                                _rememberMe = val ?? true;
                                              });
                                            },
                                      activeColor: AppColors.brandBlue,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    const SizedBox(width: 4),
                                    const Text(
                                      "Remember me",
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF6B6C72),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          : Column(
                              key: const ValueKey('password-step'),
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // ✅ Centered identity block (polished)
                                Column(
                                  children: [
                                    Text(
                                      emailController.text,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF393A3D),
                                      ),
                                    ),

                                    const SizedBox(height: 2),

                                    TextButton(
                                      onPressed: isLoading
                                          ? null
                                          : () {
                                              setState(() {
                                                _step = LoginStep.email;
                                                passwordController.clear();
                                              });
                                            },
                                      style: TextButton.styleFrom(
                                        foregroundColor: const Color(
                                          0xFF6B6C72,
                                        ),
                                        textStyle: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      child: const Text(
                                        "Use a different account",
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 12),

                                IntuitTextField(
                                  controller: passwordController,
                                  focusNode: passwordFocusNode,
                                  label: "Password",
                                  enabled: !isLoading,
                                  obscureText: obscurePassword,
                                  onChanged: (_) => _clearInlineErrors(),
                                  onSubmitted: _login,
                                  errorText: _passwordError ?? _authError,
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      obscurePassword
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      size: 20,
                                    ),
                                    onPressed: isLoading
                                        ? null
                                        : () => setState(
                                            () => obscurePassword =
                                                !obscurePassword,
                                          ),
                                  ),
                                ),
                              ],
                            ),
                    ),

                    const SizedBox(height: 12),

                    SizedBox(
                      height: 42,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: primaryAction,
                          borderRadius: BorderRadius.circular(6),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: Container(
                              key: ValueKey('${_step}_$isLoading'),
                              decoration: BoxDecoration(
                                color: AppColors.brandBlue,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              alignment: Alignment.center,
                              child: isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                                    )
                                  : Text(
                                      _step == LoginStep.password
                                          ? "Sign in"
                                          : "Continue",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),
                    const LoginLegalNotice(),

                    const SizedBox(height: 16),

                    Text(
                      "Accounts are created by invitation only.",
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF6B6C72),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emailStep() {
    return Column(
      key: const ValueKey("email-step"),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntuitTextField(
          controller: emailController,
          focusNode: emailFocusNode,
          label: "Email",
          enabled: !isLoading,
          textInputAction: TextInputAction.done,
          onChanged: (_) => _clearInlineErrors(),
          onSubmitted: _continueToPassword,
          errorText: _emailError,
        ),
      ],
    );
  }

  Widget _passwordStep() {
    return Column(
      key: const ValueKey("password-step"),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ✅ Read‑only email (Intuit style)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            emailController.text,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF393A3D),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: isLoading
                ? null
                : () {
                    setState(() {
                      _step = LoginStep.email;
                      passwordController.clear();
                    });
                  },
            child: const Text("Use a different account"),
          ),
        ),

        const SizedBox(height: 12),

        IntuitTextField(
          controller: passwordController,
          focusNode: passwordFocusNode,
          label: "Password",
          enabled: !isLoading,
          obscureText: obscurePassword,
          onChanged: (_) => _clearInlineErrors(),
          onSubmitted: _login,
          errorText: _passwordError ?? _authError,
          suffixIcon: IconButton(
            icon: Icon(
              obscurePassword ? Icons.visibility_off : Icons.visibility,
              size: 20,
            ),
            onPressed: isLoading
                ? null
                : () => setState(() => obscurePassword = !obscurePassword),
          ),
        ),
      ],
    );
  }

  Widget _legalLinksRow() {
    TextStyle linkStyle = const TextStyle(
      color: AppColors.brandBlue,
      fontWeight: FontWeight.w700,
      fontSize: 10,
    );

    Widget link(String label, String url) {
      return InkWell(
        onTap: () => _openLink(url),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(label, style: linkStyle),
        ),
      );
    }

    return CenteredForm(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          link("Website", "https://www.axumecpas.com/"),
          const Text("·", style: TextStyle(color: Colors.grey)),
          link(
            "ShareFile",
            "https://auth.sharefile.io/axumecpas/login?returnUrl=%2fconnect%2fauthorize%2fcallback%3fclient_id%3dDzi4UPUAg5l8beKdioecdcnmHUTWWln6%26state%3doPhvHV46Gj6A7JJhyll3ww--%26acr_values%3dtenant%253Aaxumecpas%26response_type%3dcode%26redirect_uri%3dhttps%253A%252F%252Faxumecpas.sharefile.com%252Flogin%252Foauthlogin%26scope%3dsharefile%253Arestapi%253Av3%2520sharefile%253Arestapi%253Av3-internal%2520offline_access%2520openid",
          ),
          const Text("·", style: TextStyle(color: Colors.grey)),
          link(
            "SecureSend",
            "https://www.securefirmportal.com/Account/Login/119710",
          ),
        ],
      ),
    );
  }

  Widget _footer(ThemeData theme) {
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
      backgroundColor: const Color(0xFFDCDCDC), // ✅ #dcdcdc
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const double footerBreakpoint = 620;
            final bool pinFooter = constraints.maxHeight >= footerBreakpoint;

            final footerWidget = Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _footer(theme),
            );

            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(
                          height: 88,
                        ), // ✅ ~1 inch from top (key line)

                        _loginCard(theme, showAuthError),

                        const SizedBox(height: 12),
                        _legalLinksRow(),

                        if (!pinFooter) ...[
                          const SizedBox(height: 16),
                          footerWidget,
                        ],

                        const SizedBox(height: 32), // bottom breathing room
                      ],
                    ),
                  ),
                ),
                if (pinFooter) footerWidget,
              ],
            );
          },
        ),
      ),
    );
  }
}
