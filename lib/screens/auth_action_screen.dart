import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_colors.dart';

class AuthActionScreen extends StatefulWidget {
  const AuthActionScreen({super.key});

  @override
  State<AuthActionScreen> createState() => _AuthActionScreenState();
}

class _AuthActionScreenState extends State<AuthActionScreen> {
  bool _loading = true;
  String? _error;

  String? _mode;
  String? _oobCode;

  @override
  void initState() {
    super.initState();
    _initFromUrl();
  }

  void _initFromUrl() async {
    final base = Uri.base;

    // ✅ Flutter Web hash routing support
    Uri effectiveUri;
    if (base.fragment.isNotEmpty) {
      effectiveUri = Uri.parse('https://dummy${base.fragment}');
    } else {
      effectiveUri = base;
    }

    _mode = effectiveUri.queryParameters['mode'];
    _oobCode = effectiveUri.queryParameters['oobCode'];

    // ✅ CRITICAL FIX:
    // If this screen is opened WITHOUT an email action link,
    // silently exit instead of showing an error.
    if (_mode == null || _oobCode == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(context, '/login');
      });
      return;
    }

    try {
      final auth = FirebaseAuth.instance;

      // ✅ Validate the action code
      await auth.checkActionCode(_oobCode!);

      // ✅ Apply immediately for verifyEmail
      if (_mode == 'verifyEmail') {
        await auth.applyActionCode(_oobCode!);
      }

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'This link is invalid, expired, or has already been used.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.pageBackgroundLight,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return _Shell(
        title: 'Unable to continue',
        child: _Banner(tone: _BannerTone.error, message: _error!),
      );
    }

    if (_mode == 'resetPassword') {
      return _ResetPasswordForm(oobCode: _oobCode!);
    }

    if (_mode == 'verifyEmail') {
      return _Shell(
        title: 'Email verified',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Banner(
              tone: _BannerTone.success,
              message: 'Your email address has been verified successfully.',
            ),
            const SizedBox(height: 14),
            Text(
              'You may now return to the portal and sign in.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF475467),
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 46,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
                onPressed: () => Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/login',
                  (_) => false,
                ),
                child: const Text('Go to login'),
              ),
            ),
          ],
        ),
      );
    }

    return _Shell(
      title: 'Unsupported action',
      child: const _Banner(
        tone: _BannerTone.error,
        message: 'This link type is not supported.',
      ),
    );
  }
}

class _ResetPasswordForm extends StatefulWidget {
  final String oobCode;
  const _ResetPasswordForm({required this.oobCode});

  @override
  State<_ResetPasswordForm> createState() => _ResetPasswordFormState();
}

class _ResetPasswordFormState extends State<_ResetPasswordForm> {
  final _pw1 = TextEditingController();
  final _pw2 = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _done = false;

  @override
  void dispose() {
    _pw1.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final p1 = _pw1.text.trim();
    final p2 = _pw2.text.trim();

    if (p1.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (p1 != p2) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await FirebaseAuth.instance.confirmPasswordReset(
        code: widget.oobCode,
        newPassword: p1,
      );
      setState(() => _done = true);
    } catch (_) {
      setState(
        () => _error =
            'Password reset failed. The link may be expired or already used.',
      );
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_done) {
      return _Shell(
        title: 'Password updated',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Banner(
              tone: _BannerTone.success,
              message: 'Your password has been updated successfully.',
            ),
            const SizedBox(height: 14),
            Text(
              'You may now sign in using your new password.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF475467),
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 46,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
                onPressed: () => Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/login',
                  (_) => false,
                ),
                child: const Text('Go to login'),
              ),
            ),
          ],
        ),
      );
    }

    return _Shell(
      title: 'Reset your password',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Enter and confirm a new password to complete the reset request.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF475467),
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _pw1,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'New password',
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pw2,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Confirm new password',
              prefixIcon: Icon(Icons.lock_reset_outlined),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _Banner(tone: _BannerTone.error, message: _error!),
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 46,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Update password'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  final String title;
  final Widget child;
  const _Shell({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.pageBackgroundLight,
      appBar: AppBar(title: Text(title), automaticallyImplyLeading: false),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black.withOpacity(0.05)),
                ),
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: child,
              ),
              const SizedBox(height: 12),
              Text(
                'Axume & Associates CPAs – Firm Portal',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF667085),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _BannerTone { success, error }

class _Banner extends StatelessWidget {
  final _BannerTone tone;
  final String message;
  const _Banner({required this.tone, required this.message});

  const _Banner.success(this.message) : tone = _BannerTone.success;
  const _Banner.error(this.message) : tone = _BannerTone.error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final bg = tone == _BannerTone.success
        ? Colors.green.withOpacity(0.10)
        : Colors.red.withOpacity(0.10);

    final fg = tone == _BannerTone.success
        ? const Color(0xFF067647)
        : const Color(0xFFB42318);

    final icon = tone == _BannerTone.success
        ? Icons.check_circle_outline
        : Icons.error_outline;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
