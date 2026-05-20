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
import 'package:flutter/services.dart';

enum LoginStep {
  email,
  password,
  resetOptions,
  resetCodeSent,
  resetUpdatePassword,
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  static const Color brandBlue = Color(0xFF08449E);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with WidgetsBindingObserver {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final resetCodeController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  final emailFocusNode = FocusNode();
  final passwordFocusNode = FocusNode();

  final AuthService _auth = AuthService();

  bool isLoading = false;
  bool obscurePassword = true;
  bool obscureNewPassword = true;
  bool obscureConfirmPassword = true;
  bool _rememberMe = true; // Intuit defaults this ON
  bool _pageReady = true;

  LoginStep _step = LoginStep.email;

  String? _emailError;
  String? _passwordError;
  String? _authError;

  bool _checkingEmail = false;
  bool _noAccountBanner = false;
  bool _sendingReset = false;
  bool _verifyingReset = false;
  String? _resetMessage;
  String? _resetToken;

  // Refined density for the login card.
  static const double _cardRadius = 18;
  static const double _cardPad = 16;
  static const double _fieldGap = 12;
  static const double _blockGap = 16;
  static const double _buttonH = 46;

  // Logo inside card.
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

    // Load saved login preferences after first paint so the card appears quickly.
    Future.microtask(_loadSavedEmail);
  }

  Future<void> _loadSavedEmail() async {
    final results = await Future.wait<Object?>([
      LocalAuthPrefs.getRememberMe(),
      LocalAuthPrefs.getSavedEmail(),
    ]);

    final remember = results[0] as bool;
    final savedEmail = results[1] as String?;

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
      // iOS Safari fix: force pointer and focus restoration.
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
    resetCodeController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    emailFocusNode.dispose();
    passwordFocusNode.dispose();
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
        _resetMessage = null;
        _noAccountBanner = false;
      });
    }
  }

  void _showResetOptions() {
    final email = emailController.text.trim().toLowerCase();
    setState(() {
      _step = LoginStep.resetOptions;
      _emailError = email.isEmpty || !email.contains('@')
          ? 'Enter your email address first.'
          : null;
      _passwordError = null;
      _authError = null;
      _resetMessage = null;
    });
  }

  Future<void> _sendPasswordResetCode() async {
    final email = emailController.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _emailError = 'Enter a valid email address.');
      return;
    }

    setState(() {
      _sendingReset = true;
      _emailError = null;
      _resetMessage = null;
    });

    final result = await _auth.requestPasswordResetCode(email);
    if (!mounted) return;

    setState(() {
      _sendingReset = false;
      if (result.isSuccess) {
        resetCodeController.clear();
        _resetToken = null;
        _step = LoginStep.resetCodeSent;
      } else if (result.code == 'resource-exhausted') {
        _resetMessage =
            'Too many requests. Please wait a moment and try again.';
      } else {
        _resetMessage =
            result.message ??
            'We could not send a reset code right now. Please try again.';
      }
    });
  }

  Future<void> _verifyResetCode() async {
    final email = emailController.text.trim().toLowerCase();
    final code = resetCodeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _resetMessage = 'Enter the 6-digit code from your email.');
      return;
    }

    setState(() {
      _verifyingReset = true;
      _resetMessage = null;
    });

    final result = await _auth.verifyPasswordResetCode(
      email: email,
      code: code,
    );
    if (!mounted) return;

    setState(() {
      _verifyingReset = false;
      if (result.isSuccess && (result.data ?? '').isNotEmpty) {
        _resetToken = result.data;
        newPasswordController.clear();
        confirmPasswordController.clear();
        obscureNewPassword = true;
        obscureConfirmPassword = true;
        _step = LoginStep.resetUpdatePassword;
      } else {
        _resetMessage =
            result.message ?? 'The verification code is invalid or expired.';
      }
    });
  }

  Future<void> _completeResetAndLogin() async {
    final email = emailController.text.trim().toLowerCase();
    final token = _resetToken ?? '';
    final p1 = newPasswordController.text.trim();
    final p2 = confirmPasswordController.text.trim();

    if (p1.length < 8) {
      setState(() => _resetMessage = 'Password must be at least 8 characters.');
      return;
    }
    if (p1 != p2) {
      setState(() => _resetMessage = 'Passwords do not match.');
      return;
    }

    setState(() {
      _sendingReset = true;
      _resetMessage = null;
    });

    final result = await _auth.completePasswordResetWithCode(
      email: email,
      resetToken: token,
      newPassword: p1,
    );
    if (!mounted) return;

    if (!result.isSuccess) {
      setState(() {
        _sendingReset = false;
        _resetMessage =
            result.message ??
            'Unable to update password. Please request a new code.';
      });
      return;
    }

    setState(() => _sendingReset = false);
    final initialOtpSend = _auth.sendLoginOtp();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => OtpVerifyScreen(initialOtpSend: initialOtpSend),
      ),
    );
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
      _step = LoginStep.password;
    });

    Future<void>.microtask(() async {
      await LocalAuthPrefs.setRememberMe(_rememberMe);
      if (_rememberMe) {
        await LocalAuthPrefs.saveEmail(email);
      } else {
        await LocalAuthPrefs.clearEmail();
      }
    });

    Future.delayed(const Duration(milliseconds: 60), () {
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

    // Keep the spinner visible just long enough to avoid flicker.
    final startedAt = DateTime.now();
    const minSpinnerMs = 120;

    setState(() => isLoading = true);

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
        MaterialPageRoute(builder: (_) => const VerifyEmailScreen()),
      );
      return;
    }

    final nextRoute = pendingPostLoginRoute;
    pendingPostLoginRoute = null;
    final initialOtpSend = _auth.sendLoginOtp();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => OtpVerifyScreen(
          nextRoute: nextRoute,
          initialOtpSend: initialOtpSend,
        ),
      ),
    );
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
                  "We can't find an account with what you entered.",
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

  Widget _loginCard(
    ThemeData theme,
    bool showAuthError, {
    bool showLogo = true,
    double maxWidth = 380,
  }) {
    final VoidCallback? primaryAction = (isLoading || _checkingEmail)
        ? null
        : (_step == LoginStep.password
              ? _login
              : _step == LoginStep.email
              ? _continueToPassword
              : null);

    final title = switch (_step) {
      LoginStep.email => 'Sign in',
      LoginStep.password => 'Enter your password',
      LoginStep.resetOptions => "Verify it's you",
      LoginStep.resetCodeSent => 'Check your email',
      LoginStep.resetUpdatePassword => 'Update your password',
    };

    final subtitle = switch (_step) {
      LoginStep.email => 'Use your Axume & Associates account',
      LoginStep.password => emailController.text.trim(),
      LoginStep.resetOptions => 'Choose how you want to verify your identity.',
      LoginStep.resetCodeSent =>
        'To protect your account, we sent a 6-digit verification code to:',
      LoginStep.resetUpdatePassword =>
        'Create a new password for ${emailController.text.trim().toLowerCase()}',
    };

    return CenteredForm(
      maxWidth: maxWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
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
                  if (showLogo) ...[
                    Center(
                      child: SvgPicture.string(
                        kBrandLogoSvg2,
                        height: 80,
                        fit: BoxFit.contain,
                      ),
                    ),

                    const SizedBox(height: 18),
                  ],

                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF393A3D),
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _step == LoginStep.password
                          ? const Color(0xFF60646C)
                          : const Color(0xFF6B6C72),
                      fontWeight: _step == LoginStep.password
                          ? FontWeight.w600
                          : FontWeight.w500,
                      height: 1.25,
                    ),
                  ),
                  if (_step == LoginStep.resetCodeSent) ...[
                    const SizedBox(height: 8),
                    Text(
                      emailController.text.trim().toLowerCase(),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF111827),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],

                  SizedBox(height: _step == LoginStep.password ? 14 : 20),

                  _step == LoginStep.email
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

                            // Remember-me placement.
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
                      : _step == LoginStep.password
                      ? Column(
                          key: const ValueKey('password-step'),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Centered identity block.
                            Column(
                              children: [
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

                            const SizedBox(height: 18),

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
                                        () =>
                                            obscurePassword = !obscurePassword,
                                      ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.center,
                              child: _HoverUnderlineLink(
                                label: 'Forgot password?',
                                onTap: isLoading ? () {} : _showResetOptions,
                              ),
                            ),
                          ],
                        )
                      : _step == LoginStep.resetOptions
                      ? _resetOptionsStep()
                      : _step == LoginStep.resetCodeSent
                      ? _resetCodeSentStep(theme)
                      : _resetUpdatePasswordStep(theme),

                  if (_step == LoginStep.email ||
                      _step == LoginStep.password) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 42,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: primaryAction,
                          borderRadius: BorderRadius.circular(6),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 100),
                            child: Container(
                              key: ValueKey('${_step}_$isLoading'),
                              decoration: BoxDecoration(
                                color: AppColors.brandBlue,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              alignment: Alignment.center,
                              child: (isLoading || _checkingEmail)
                                  ? const SizedBox(
                                      height: 18,
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
                  ],

                  if (_step == LoginStep.email) ...[
                    const SizedBox(height: 12),
                    const LoginLegalNotice(),
                  ],

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
        ],
      ),
    );
  }

  Widget _resetOptionsStep() {
    return Column(
      key: const ValueKey('reset-options-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_emailError != null) ...[
          _InlineBanner(tone: _InlineBannerTone.error, message: _emailError!),
          const SizedBox(height: 12),
        ],
        if (_resetMessage != null) ...[
          _InlineBanner(tone: _InlineBannerTone.error, message: _resetMessage!),
          const SizedBox(height: 12),
        ],
        _ResetOptionTile(
          icon: Icons.mail_outline,
          title: 'Email a code',
          subtitle: emailController.text.trim().toLowerCase(),
          busy: _sendingReset,
          onTap: _sendingReset ? null : _sendPasswordResetCode,
        ),
        const SizedBox(height: 12),
        _ResetOptionTile(
          icon: Icons.lock_outline,
          title: 'Try password again',
          onTap: _sendingReset
              ? null
              : () {
                  setState(() {
                    _step = LoginStep.password;
                    _resetMessage = null;
                  });
                  Future.delayed(const Duration(milliseconds: 60), () {
                    if (mounted) {
                      FocusScope.of(context).requestFocus(passwordFocusNode);
                    }
                  });
                },
        ),
        const SizedBox(height: 12),
        _ResetOptionTile(
          icon: Icons.verified_user_outlined,
          title: 'Verify identity a different way',
          subtitle: 'Contact our office for help with access.',
          onTap: () => _openLink('https://www.axumecpas.com/contact.php'),
        ),
      ],
    );
  }

  Widget _resetCodeSentStep(ThemeData theme) {
    return Column(
      key: const ValueKey('reset-code-sent-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.mark_email_read_outlined,
          color: AppColors.brandBlue,
          size: 50,
        ),
        const SizedBox(height: 14),
        if (_resetMessage != null) ...[
          _InlineBanner(tone: _InlineBannerTone.error, message: _resetMessage!),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: resetCodeController,
          enabled: !_verifyingReset,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          onChanged: (_) {
            if (_resetMessage != null) {
              setState(() => _resetMessage = null);
            }
          },
          onSubmitted: (_) => _verifyResetCode(),
          decoration: const InputDecoration(
            labelText: 'Verification code',
            prefixIcon: Icon(Icons.pin_outlined),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 42,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
            onPressed: _verifyingReset ? null : _verifyResetCode,
            child: Text(_verifyingReset ? 'Verifying...' : 'Continue'),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _sendingReset ? null : _sendPasswordResetCode,
          child: Text(_sendingReset ? 'Sending...' : "I didn't get an email"),
        ),
        TextButton(
          onPressed: () {
            setState(() {
              _step = LoginStep.email;
              _resetMessage = null;
            });
          },
          child: const Text('Use different email'),
        ),
      ],
    );
  }

  Widget _resetUpdatePasswordStep(ThemeData theme) {
    return Column(
      key: const ValueKey('reset-update-password-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_resetMessage != null) ...[
          _InlineBanner(tone: _InlineBannerTone.error, message: _resetMessage!),
          const SizedBox(height: 12),
        ],
        IntuitTextField(
          controller: newPasswordController,
          label: 'New password',
          enabled: !_sendingReset,
          obscureText: obscureNewPassword,
          textInputAction: TextInputAction.next,
          onChanged: (_) {
            if (_resetMessage != null) {
              setState(() => _resetMessage = null);
            }
          },
          suffixIcon: IconButton(
            icon: Icon(
              obscureNewPassword ? Icons.visibility_off : Icons.visibility,
              size: 20,
            ),
            onPressed: _sendingReset
                ? null
                : () =>
                      setState(() => obscureNewPassword = !obscureNewPassword),
          ),
        ),
        const SizedBox(height: 12),
        IntuitTextField(
          controller: confirmPasswordController,
          label: 'Confirm new password',
          enabled: !_sendingReset,
          obscureText: obscureConfirmPassword,
          textInputAction: TextInputAction.done,
          onSubmitted: _completeResetAndLogin,
          onChanged: (_) {
            if (_resetMessage != null) {
              setState(() => _resetMessage = null);
            }
          },
          suffixIcon: IconButton(
            icon: Icon(
              obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
              size: 20,
            ),
            onPressed: _sendingReset
                ? null
                : () => setState(
                    () => obscureConfirmPassword = !obscureConfirmPassword,
                  ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 42,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
            onPressed: _sendingReset ? null : _completeResetAndLogin,
            child: Text(_sendingReset ? 'Updating...' : 'Update password'),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _sendingReset
              ? null
              : () {
                  setState(() {
                    _step = LoginStep.password;
                    _resetMessage = null;
                    _resetToken = null;
                  });
                },
          child: const Text('Try password again'),
        ),
      ],
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
        // Read-only email.
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
        spacing: 6,
        children: [
          link(context, "Legal", () {
            Navigator.pushNamed(context, '/legal');
          }),
          const Text("|", style: TextStyle(color: Colors.grey)),
          link(context, "Privacy", () {
            Navigator.pushNamed(context, '/privacy');
          }),
          const Text("|", style: TextStyle(color: Colors.grey)),
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
          // Keep legal links above copyright.
          _legalLinksRow(),

          const SizedBox(height: 12),

          Text(
            "(c) 2026 Axume & Associates CPAs, AAC",
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

  Widget _mobileLoginExperience(ThemeData theme, bool showAuthError) {
    final isResetFlow =
        _step == LoginStep.resetOptions ||
        _step == LoginStep.resetCodeSent ||
        _step == LoginStep.resetUpdatePassword;

    return Scaffold(
      backgroundColor: Colors.white,
      body: AbsorbPointer(
        absorbing: !_pageReady,
        child: _pageReady
            ? SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final topHeight = isResetFlow ? 190.0 : 330.0;
                    final overlap = isResetFlow ? -58.0 : -78.0;
                    final footerLift = isResetFlow ? -38.0 : -56.0;

                    return SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          children: [
                            Container(
                              height: topHeight,
                              width: double.infinity,
                              color: AppColors.brandBlue,
                              alignment: Alignment.topCenter,
                              padding: const EdgeInsets.only(top: 52),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.10),
                                      blurRadius: 18,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: SvgPicture.string(
                                  kBrandLogoSvg2,
                                  height: 58,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            Transform.translate(
                              offset: Offset(0, overlap),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                ),
                                child: _loginCard(
                                  theme,
                                  showAuthError,
                                  showLogo: false,
                                  maxWidth: 520,
                                ),
                              ),
                            ),
                            Transform.translate(
                              offset: Offset(0, footerLift),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  0,
                                  18,
                                  20,
                                ),
                                child: _footer(theme),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              )
            : const _LoginLoadingScreen(key: ValueKey('login-loading-mobile')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool showAuthError = _authError != null;
    final isMobile = MediaQuery.of(context).size.width < 700;

    if (isMobile) {
      return _mobileLoginExperience(theme, showAuthError);
    }

    return Scaffold(
      backgroundColor: AppColors.pageBackgroundSoft,
      body: AbsorbPointer(
        absorbing: !_pageReady, // Prevent interaction while loading.
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeIn,
          child: _pageReady
              ? SafeArea(
                  key: const ValueKey('login-ui'),
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
              : const _LoginLoadingScreen(key: ValueKey('login-loading')),
        ),
      ),
    );
  }
}

enum _InlineBannerTone { info, error }

class _InlineBanner extends StatelessWidget {
  const _InlineBanner({required this.tone, required this.message});

  final _InlineBannerTone tone;
  final String message;

  @override
  Widget build(BuildContext context) {
    final isError = tone == _InlineBannerTone.error;
    final bg = isError
        ? const Color(0xFFFFF5F5)
        : AppColors.brandBlue.withOpacity(0.08);
    final fg = isError ? const Color(0xFFB42318) : AppColors.brandBlue;
    final icon = isError ? Icons.error_outline : Icons.info_outline;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: fg.withOpacity(0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isError
                    ? const Color(0xFF7A271A)
                    : const Color(0xFF344054),
                height: 1.35,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResetOptionTile extends StatelessWidget {
  const _ResetOptionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE4E7EC)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                height: 38,
                width: 38,
                decoration: const BoxDecoration(
                  color: Color(0xFFF0F2F5),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: busy
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(icon, size: 20, color: const Color(0xFF111827)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    if (subtitle != null && subtitle!.trim().isNotEmpty)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF667085),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Color(0xFF98A2B3),
                size: 20,
              ),
            ],
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
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
