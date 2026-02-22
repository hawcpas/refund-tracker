import 'package:flutter/material.dart';
import 'package:animated_background/animated_background.dart'; // ✅ ADD
import '../services/auth_service.dart';
import '../services/local_auth_prefs.dart';
import '../widgets/centered_form.dart';
import '../theme/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  static const Color brandBlue = Color(0xFF08449E);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
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

  // ✅ Logo inside card (larger, no box)
  static const double _logoSize = 80;
  static const double _logoPad = 10;
  static const double _accentH = 4;
  static const double _accentW = 72;

  // ✅ Particle options (tuned for “professional + subtle”)
  // Based on the ParticleOptions fields shown in examples/docs. [1](https://www.geeksforgeeks.org/flutter/animated-background-in-flutter/)[2](https://pub.dev/documentation/animated_background/latest/)
  final ParticleOptions _particles = const ParticleOptions(
    baseColor: AppColors.brandBlue,
    spawnOpacity: 0.0,
    opacityChangeRate: 0.25,
    minOpacity: 0.06,
    maxOpacity: 0.20,
    particleCount: 55,
    spawnMaxRadius: 10.0,
    spawnMinRadius: 3.0,
    spawnMaxSpeed: 55.0,
    spawnMinSpeed: 18.0,
  );

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  }

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
    final bool darkBg = AppColors.pageBackgroundLight == AppColors.brandBlue;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: CenteredForm(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
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
                  const ImageIcon(
                    AssetImage('assets/icons/aa_logo_imageicon_256.png'),
                    size: _logoSize,
                    color: AppColors.brandBlue,
                  ),
                  const SizedBox(height: 10),

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

                  Text(
                    "Accounts are created by invitation only.",
                    style: TextStyle(
                      color: AppColors.mutedText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // ✅ PARTICLE BACKGROUND LAYER
          // AnimatedBackground usage pattern + vsync requirement per docs/examples. [2](https://pub.dev/documentation/animated_background/latest/)[1](https://www.geeksforgeeks.org/flutter/animated-background-in-flutter/)
          Positioned.fill(
            child: AnimatedBackground(
              vsync: this,
              behaviour: RandomParticleBehaviour(options: _particles),
              child: const SizedBox.expand(),
            ),
          ),

          // ✅ subtle overlay so particles never fight readability
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.pageBackgroundLight.withOpacity(0.70),
                    AppColors.pageBackgroundLight.withOpacity(0.60),
                    AppColors.pageBackgroundLight.withOpacity(0.72),
                  ],
                ),
              ),
            ),
          ),

          // ✅ YOUR EXISTING UI ON TOP
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const double footerBreakpoint = 620;
                final bool pinFooter =
                    constraints.maxHeight >= footerBreakpoint;

                final footerWidget = Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _footer(theme),
                );

                return Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                        child: Column(
                          children: [
                            _loginCard(theme, showAuthError),
                            const SizedBox(height: 12),
                            _legalLinksRow(),
                            if (!pinFooter) ...[
                              const SizedBox(height: 16),
                              footerWidget,
                            ],
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
        ],
      ),
    );
  }
}
