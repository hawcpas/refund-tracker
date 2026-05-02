import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/local_auth_prefs.dart';
import '../widgets/centered_form.dart';
import '../theme/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/post_login_route.dart';
import '../widgets/intuit_text_field.dart';
import '../widgets/login_legal_notice.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/verify_email_screen.dart';
import '../screens/otp_verify_screen.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/brand_logo_svg.dart';

enum LoginStep { email, password }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  static const Color brandBlue = Color(0xFF08449E);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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
  bool _pageReady = false;

  LoginStep _step = LoginStep.email;

  String? _emailError;
  String? _passwordError;
  String? _authError;

  bool _checkingEmail = false;
  bool _noAccountBanner = false;

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
    WidgetsBinding.instance.addObserver(this);

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

    // ✅ Load async data, then show page
    Future.microtask(() async {
      await _loadSavedEmail();

      if (!mounted) return;

      // Small intentional delay = smoother first paint
      await Future.delayed(const Duration(milliseconds: 180));

      if (!mounted) return;
      setState(() => _pageReady = true);
    });
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // ✅ iOS Safari fix: force pointer + focus restoration
      if (!mounted) return;

      FocusScope.of(context).unfocus();

      // Force a rebuild to re-enable hit testing
      setState(() {});
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    emailFocusNode.dispose();
    passwordFocusNode.dispose();
    _signinController.dispose();
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  void _clearInlineErrors() {
    if (_emailError != null ||
        _passwordError != null ||
        _authError != null ||
        _noAccountBanner) {
      setState(() {
        _emailError = null;
        _passwordError = null;
        _authError = null;
        _noAccountBanner = false;
      });
    }
  }

  Future<void> _continueToPassword() async {
    final email = emailController.text.trim().toLowerCase();

    if (email.isEmpty || !email.contains("@")) {
      setState(() {
        _emailError = "Enter a valid email address.";
        _noAccountBanner = false;
      });
      return;
    }

    setState(() {
      _emailError = null;
      _noAccountBanner = false;
      _checkingEmail = true;
    });

    try {
      final exists = await _auth.emailExists(email);
      if (!mounted) return;

      if (!exists) {
        setState(() {
          _checkingEmail = false;
          _noAccountBanner = true; // ✅ Show Intuit-style warning box
        });
        return;
      }

      // ✅ Persist Remember Me ONLY after email is confirmed to exist
      await LocalAuthPrefs.setRememberMe(_rememberMe);
      if (_rememberMe) {
        await LocalAuthPrefs.saveEmail(email);
      } else {
        await LocalAuthPrefs.clearEmail();
      }

      if (!mounted) return;

      setState(() {
        _checkingEmail = false;
        _step = LoginStep.password;
      });

      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) {
          FocusScope.of(context).requestFocus(passwordFocusNode);
        }
      });
    } on FirebaseAuthException catch (_) {
      if (!mounted) return;
      setState(() {
        _checkingEmail = false;
        _emailError = "Unable to verify email right now. Please try again.";
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checkingEmail = false;
        _emailError = "Unable to verify email right now. Please try again.";
      });
    }
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
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 420),

          pageBuilder: (_, __, ___) => OtpVerifyScreen(
            nextRoute: pendingPostLoginRoute,
            otpAlreadySent: true, // ✅ ONLY place this should be set
          ),

          transitionsBuilder: (_, animation, __, child) {
            final fade = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );

            final slide = Tween<Offset>(
              begin: const Offset(0, 0.02),
              end: Offset.zero,
            ).animate(fade);

            return FadeTransition(
              opacity: fade,
              child: SlideTransition(position: slide, child: child),
            );
          },
        ),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, __, ___) =>
            OtpVerifyScreen(nextRoute: pendingPostLoginRoute),
        transitionsBuilder: (_, animation, __, child) {
          final fade = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );

          final slide = Tween<Offset>(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(fade);

          return FadeTransition(
            opacity: fade,
            child: SlideTransition(position: slide, child: child),
          );
        },
      ),
    );

    pendingPostLoginRoute = null;
  }

  Widget _noAccountBox() {
    const border = Color(0xFFDC2626); // red
    const bg = Color(0xFFFFF5F5); // very light red

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: 1),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded, // triangle warning icon
            color: border,
            size: 20,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Double check your info',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'We can’t find an account with what you entered.',
                  style: TextStyle(
                    color: Color(0xFF374151),
                    height: 1.35,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _loginCard(ThemeData theme, bool showAuthError) {
    final VoidCallback? primaryAction = (isLoading || _checkingEmail)
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
                    const SizedBox(height: 12), // ✅ NEW: extra space above logo
                    // ✅ Logo INSIDE card (Intuit-style)
                    Center(
                      child: SvgPicture.string(
                        kBrandLogoSvg2,
                        height: 80,
                        fit: BoxFit.contain,
                      ),
                    ),

                    const SizedBox(
                      height: 20,
                    ), // instead of 16, above or below logo

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
                                if (_noAccountBanner) _noAccountBox(),
                                IntuitTextField(
                                  controller: emailController,
                                  focusNode: emailFocusNode,
                                  label: "Email",
                                  enabled: !isLoading && !_checkingEmail,
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

                                    _HoverUnderlineLink(
                                      label: "Use a different account",
                                      onTap: isLoading
                                          ? () {}
                                          : () {
                                              setState(() {
                                                _step = LoginStep.email;
                                                passwordController.clear();
                                              });
                                            },
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
                              child: (isLoading || _checkingEmail)
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
    Widget link(BuildContext context, String label, VoidCallback onTap) {
      return _HoverUnderlineLink(label: label, onTap: onTap);
    }

    return CenteredForm(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6, // ✅ closer together
        children: [
          link(context, "Legal", () {
            Navigator.pushNamed(context, '/legal');
          }),
          const Text("·", style: TextStyle(color: Colors.grey)),
          link(context, "Privacy", () {
            Navigator.pushNamed(context, '/privacy');
          }),
          const Text("·", style: TextStyle(color: Colors.grey)),
          link(context, "Security", () {
            Navigator.pushNamed(context, '/security');
          }),
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
          // ✅ ALWAYS above copyright (Intuit-style)
          _legalLinksRow(),

          const SizedBox(height: 12),

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
      backgroundColor: AppColors.pageBackgroundSoft,
      body: AbsorbPointer(
        absorbing: !_pageReady, // ✅ prevent interaction while loading
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeIn,
          child: _pageReady
              ? SafeArea(
                  key: const ValueKey(
                    'login-ui',
                  ), // ✅ required for AnimatedSwitcher
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const double footerBreakpoint = 620;
                      final bool pinFooter =
                          constraints.maxHeight >= footerBreakpoint;

                      final footerWidget = Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _footer(Theme.of(context)),
                      );

                      return Column(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const SizedBox(height: 88),
                                  _loginCard(
                                    Theme.of(context),
                                    _authError != null,
                                  ),
                                  const SizedBox(height: 12),
                                  if (!pinFooter) ...[
                                    const SizedBox(height: 16),
                                    footerWidget,
                                  ],
                                  const SizedBox(height: 32),
                                ],
                              ),
                            ),
                          ),
                          if (pinFooter) footerWidget,
                        ],
                      );
                    },
                  ),
                )
              : const _LoginLoadingScreen(
                  key: ValueKey(
                    'login-loading',
                  ), // ✅ required for AnimatedSwitcher
                ),
        ),
      ),
    );
  }
}

class _HoverUnderlineLink extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _HoverUnderlineLink({required this.label, required this.onTap});

  @override
  State<_HoverUnderlineLink> createState() => _HoverUnderlineLinkState();
}

class _HoverUnderlineLinkState extends State<_HoverUnderlineLink> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 120),
          style: TextStyle(
            color: AppColors.brandBlue,
            fontWeight: FontWeight.w700,
            fontSize: 10,
            decoration: _hovering
                ? TextDecoration.underline
                : TextDecoration.none,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 4, // ✅ tighter than before
              vertical: 2,
            ),
            child: Text(widget.label),
          ),
        ),
      ),
    );
  }
}

class _LoginLoadingScreen extends StatelessWidget {
  const _LoginLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.pageBackgroundSoft,
      alignment: Alignment.center,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.9, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (context, scale, child) {
          return Transform.scale(scale: scale, child: child);
        },
        child: const SizedBox(
          height: 28,
          width: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.brandBlue),
          ),
        ),
      ),
    );
  }
}
