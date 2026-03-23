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
    const linkColor = Color(0xFF08449E);

    TextStyle base = const TextStyle(
      fontSize: 11.5,
      height: 1.4,
      color: textColor,
    );

    TextStyle link = const TextStyle(
      fontSize: 11.5,
      height: 1.4,
      color: linkColor,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
    );

    Widget linkText(String label, VoidCallback onTap) {
      return InkWell(
        onTap: onTap,
        child: Text(label, style: link),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Center(
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 0,
          runSpacing: 0,
          children: [
            Text('By selecting ', style: base),
            Text('Sign in', style: base.copyWith(fontWeight: FontWeight.w600)),
            Text(' for your ', style: base),

            linkText(
              'Axume & Associates CPAs Account',
              () => _open('https://www.axumecpas.com/'),
            ),

            Text(', you agree to our ', style: base),

            linkText(
              'Terms',
              () => Navigator.of(context, rootNavigator: true).pushNamed('/terms'),
            ),

            Text('. Our ', style: base),

            linkText(
              'Privacy Policy',
              () => Navigator.of(context, rootNavigator: true).pushNamed('/privacy'),
            ),

            Text(' applies to your personal data.', style: base),
          ],
        ),
      ),
    );
  }
}