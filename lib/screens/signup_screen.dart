import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/centered_form.dart';
import '../theme/app_colors.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with SingleTickerProviderStateMixin {
  // Name controllers
  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  // Focus nodes
  final firstNameFocusNode = FocusNode();
  final lastNameFocusNode = FocusNode();

  final emailFocusNode = FocusNode();
  final passwordFocusNode = FocusNode();
  final confirmPasswordFocusNode = FocusNode();

  final AuthService _auth = AuthService();

  bool isLoading = false;
  bool obscurePassword = true;
  bool obscureConfirmPassword = true;

  // Errors
  String? _firstNameError;
  String? _lastNameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmError;
  String? _generalError;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // UI tokens
  static const double _pageVPad = 28;
  static const double _pageHPad = 18;
  static const double _cardRadius = 18;
  static const double _cardPad = 16;
  static const double _fieldGap = 12;
  static const double _blockGap = 16;
  static const double _buttonH = 46;
  static const double _footerGap = 24;

  static const double _logoSize = 80;
  static const double _accentH = 4;
  static const double _accentW = 72;

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
  }

  @override
  void dispose() {
    firstNameController.dispose();
    lastNameController.dispose();
    firstNameFocusNode.dispose();
    lastNameFocusNode.dispose();

    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();

    emailFocusNode.dispose();
    passwordFocusNode.dispose();
    confirmPasswordFocusNode.dispose();

    _animationController.dispose();
    super.dispose();
  }

  void _clearErrorsOnType() {
    if (_firstNameError != null ||
        _lastNameError != null ||
        _emailError != null ||
        _passwordError != null ||
        _confirmError != null ||
        _generalError != null) {
      setState(() {
        _firstNameError = null;
        _lastNameError = null;
        _emailError = null;
        _passwordError = null;
        _confirmError = null;
        _generalError = null;
      });
    }
  }

  Future<void> _signup() async {
    if (isLoading) return;

    setState(() {
      _firstNameError = null;
      _lastNameError = null;
      _emailError = null;
      _passwordError = null;
      _confirmError = null;
      _generalError = null;
    });

    final firstName = firstNameController.text.trim();
    final lastName = lastNameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();

    bool ok = true;

    if (firstName.isEmpty) {
      _firstNameError = "Enter your first name.";
      ok = false;
    }
    if (lastName.isEmpty) {
      _lastNameError = "Enter your last name.";
      ok = false;
    }

    if (email.isEmpty || !email.contains("@")) {
      _emailError = "Enter a valid email address.";
      ok = false;
    }

    if (password.length < 6) {
      _passwordError = "Password must be at least 6 characters.";
      ok = false;
    }

    if (confirmPassword.isEmpty) {
      _confirmError = "Please confirm your password.";
      ok = false;
    } else if (password != confirmPassword) {
      _passwordError = "Passwords do not match.";
      _confirmError = "Passwords do not match.";
      ok = false;
    }

    if (!ok) {
      setState(() {});
      return;
    }

    setState(() => isLoading = true);

    try {
      final result = await _auth.signupDetailed(
        email,
        password,
        firstName: firstName,
        lastName: lastName,
      );

      if (!mounted) return;

      if (result.code == null && result.data != null) {
        Navigator.pushReplacementNamed(context, '/verify-email');
        return;
      }

      switch (result.code) {
        case 'email-already-in-use':
          _emailError =
              "This email is already associated with an account. Please log in.";
          emailFocusNode.requestFocus();
          break;
        case 'invalid-email':
          _emailError = "Enter a valid email address.";
          emailFocusNode.requestFocus();
          break;
        case 'weak-password':
          _passwordError = "Password is too weak. Use at least 6 characters.";
          passwordFocusNode.requestFocus();
          break;
        case 'too-many-requests':
          _generalError =
              "Too many attempts. Please wait a moment and try again.";
          break;
        case 'network-request-failed':
          _generalError =
              "Network error. Please check your internet connection.";
          break;
        default:
          _generalError =
              "Signup failed (${result.code ?? 'unknown'}). ${result.message ?? ''}";
      }

      setState(() {});
    } on TimeoutException {
      setState(() {
        _generalError = "Signup timed out. Check your internet connection.";
      });
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Widget content = FadeTransition(
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ImageIcon(
                    AssetImage('assets/icons/aa_logo_imageicon_256.png'),
                    size: _logoSize,
                    color: AppColors.brandBlue,
                  ),
                  const SizedBox(height: 14),

                  Container(
                    height: _accentH,
                    width: _accentW,
                    alignment: Alignment.center,
                    margin: const EdgeInsets.only(bottom: _blockGap),
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),

                  Text(
                    "Create account",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF101828),
                    ),
                  ),
                  const SizedBox(height: 6),

                  Text(
                    "Set up your account to continue",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF475467),
                    ),
                  ),
                  const SizedBox(height: _blockGap),

                  if (_generalError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withOpacity(0.25)),
                      ),
                      child: Text(
                        _generalError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.red.shade800,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: _blockGap),
                  ],

                  TextField(
                    controller: firstNameController,
                    focusNode: firstNameFocusNode,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => _clearErrorsOnType(),
                    onSubmitted: (_) =>
                        FocusScope.of(context).requestFocus(lastNameFocusNode),
                    decoration: const InputDecoration(
                      labelText: "First name",
                      prefixIcon: Icon(
                        Icons.person_outline,
                        color: AppColors.brandBlue,
                      ),
                    ).copyWith(errorText: _firstNameError),
                  ),
                  const SizedBox(height: _fieldGap),

                  TextField(
                    controller: lastNameController,
                    focusNode: lastNameFocusNode,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => _clearErrorsOnType(),
                    onSubmitted: (_) =>
                        FocusScope.of(context).requestFocus(emailFocusNode),
                    decoration: const InputDecoration(
                      labelText: "Last name",
                      prefixIcon: Icon(
                        Icons.badge_outlined,
                        color: AppColors.brandBlue,
                      ),
                    ).copyWith(errorText: _lastNameError),
                  ),
                  const SizedBox(height: _fieldGap),

                  TextField(
                    controller: emailController,
                    focusNode: emailFocusNode,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => _clearErrorsOnType(),
                    onSubmitted: (_) =>
                        FocusScope.of(context).requestFocus(passwordFocusNode),
                    decoration: const InputDecoration(
                      labelText: "Email",
                      prefixIcon: Icon(
                        Icons.mail_outline,
                        color: AppColors.brandBlue,
                      ),
                    ).copyWith(errorText: _emailError),
                  ),
                  const SizedBox(height: _fieldGap),

                  TextField(
                    controller: passwordController,
                    focusNode: passwordFocusNode,
                    obscureText: obscurePassword,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => _clearErrorsOnType(),
                    onSubmitted: (_) => FocusScope.of(
                      context,
                    ).requestFocus(confirmPasswordFocusNode),
                    decoration:
                        const InputDecoration(
                          labelText: "Password",
                          helperText: "Minimum 6 characters",
                          prefixIcon: Icon(
                            Icons.lock_outline,
                            color: AppColors.brandBlue,
                          ),
                        ).copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: AppColors.brandBlue,
                            ),
                            onPressed: () => setState(
                              () => obscurePassword = !obscurePassword,
                            ),
                          ),
                          errorText: _passwordError,
                        ),
                  ),
                  const SizedBox(height: _fieldGap),

                  TextField(
                    controller: confirmPasswordController,
                    focusNode: confirmPasswordFocusNode,
                    obscureText: obscureConfirmPassword,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => _clearErrorsOnType(),
                    onSubmitted: (_) => isLoading ? null : _signup(),
                    decoration:
                        const InputDecoration(
                          labelText: "Confirm password",
                          prefixIcon: Icon(
                            Icons.lock_reset,
                            color: AppColors.brandBlue,
                          ),
                        ).copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscureConfirmPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: AppColors.brandBlue,
                            ),
                            onPressed: () => setState(
                              () => obscureConfirmPassword =
                                  !obscureConfirmPassword,
                            ),
                          ),
                          errorText: _confirmError,
                        ),
                  ),

                  const SizedBox(height: _blockGap),

                  SizedBox(
                    height: _buttonH,
                    child: FilledButton(
                      onPressed: isLoading ? null : _signup,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brandBlue,
                        foregroundColor: AppColors.cardBackground,
                        textStyle: const TextStyle(fontWeight: FontWeight.w900),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isLoading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.cardBackground,
                              ),
                            )
                          : const Text("Create account"),
                    ),
                  ),

                  const SizedBox(height: 12),

                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      "Already have an account? Login",
                      style: TextStyle(
                        color: AppColors.brandBlue,
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
    );

    return Scaffold(
      backgroundColor: AppColors.pageBackgroundLight,
      body: ColoredBox(
        color: AppColors.pageBackgroundLight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool pinFooter = constraints.maxHeight >= 820;

            if (!pinFooter) {
              return ListView(
                padding: const EdgeInsets.symmetric(
                  vertical: _pageVPad,
                  horizontal: _pageHPad,
                ),
                children: [
                  content,
                  const SizedBox(height: _footerGap),
                ],
              );
            }

            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      vertical: _pageVPad,
                      horizontal: _pageHPad,
                    ),
                    children: [content],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
