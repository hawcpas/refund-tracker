import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class LoginLegalNotice extends StatelessWidget {
  const LoginLegalNotice({super.key});

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    const textColor = Color(0xFF6B6C72);
    const linkColor = Color(0xFF08449E); // your brand blue

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(fontSize: 11.5, height: 1.4, color: textColor),
          children: [
            const TextSpan(text: 'By selecting '),
            const TextSpan(
              text: 'Sign in',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const TextSpan(text: ' for your '),
            TextSpan(
              text: 'Axume & Associates CPAs Account',
              style: const TextStyle(
                color: linkColor,
                fontWeight: FontWeight.w600,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => _open('https://www.axumecpas.com/'),
            ),
            const TextSpan(text: ', you agree to our '),
            TextSpan(
              text: 'Terms',
              style: const TextStyle(
                color: linkColor,
                fontWeight: FontWeight.w600,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => Navigator.of(
                  context,
                  rootNavigator: true,
                ).pushNamed('/terms'),
            ),
            const TextSpan(text: '. Our '),
            TextSpan(
              text: 'Privacy Policy',
              style: const TextStyle(
                color: linkColor,
                fontWeight: FontWeight.w600,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () =>
                    _open('https://www.intuit.com/privacy/statement/'),
            ),
            const TextSpan(text: ' applies to your personal data.'),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
