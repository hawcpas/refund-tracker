import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class SecurityScreen extends StatelessWidget {
  const SecurityScreen({super.key});

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text(
          'Security',
          style: TextStyle(
            color: Color(0xFF111827),
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF111827)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(40, 36, 40, 56),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _hero(
              title: 'We’re Dedicated to Guarding Your Data',
              subtitle:
                  'Our security technology is built on decades of experience protecting '
                  'sensitive financial and tax information.',
            ),

            _section(
              title: 'How We Keep Your Data Secure',
              body:
                  'We use layered security controls designed to protect your information '
                  'throughout its lifecycle, including account access, document upload, '
                  'storage, and internal handling.\n\n'
                  'Security measures may include:\n'
                  '• Multi‑factor authentication and email verification\n'
                  '• Role‑based access controls\n'
                  '• Encrypted data transmission and storage\n'
                  '• Continuous monitoring and audit logging\n'
                  '• Incident response and breach containment procedures',
            ),

            _section(
              title: 'Security Checklist',
              body:
                  'We protect your data using anti‑fraud and monitoring controls, and '
                  'there are steps you can take to help keep your account secure:\n\n'
                  '• Use a strong, unique password\n'
                  '• Do not share upload links or credentials\n'
                  '• Verify emails and links before clicking\n'
                  '• Sign out of shared or public devices\n'
                  '• Notify us immediately of suspicious activity',
            ),

            _section(
              title: 'Tips for Staying Safe',
              body:
                  'Our security team recommends staying alert online:\n\n'
                  '• Watch for phishing emails that impersonate trusted services\n'
                  '• Avoid downloading attachments from unknown senders\n'
                  '• Keep your device and browser up to date\n'
                  '• Use password managers when possible',
            ),

            _section(
              title: 'Responsible Disclosure',
              body:
                  'We are committed to maintaining secure systems and encourage security '
                  'researchers to responsibly disclose potential vulnerabilities.\n\n'
                  'If you believe you have identified a security issue, please contact us '
                  'with sufficient detail so we can investigate and respond promptly.',
            ),

            TextButton(
              onPressed: () => _open('https://www.axumecpas.com/contact.php'),
              child: const Text('Report a Security Concern'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero({required String title, required String subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'GeneraGrotesk',
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 16,
              height: 1.6,
              color: Color(0xFF374151),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({required String title, required String body}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'GeneraGrotesk',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: const TextStyle(
              fontSize: 16,
              height: 1.75,
              color: Color(0xFF1F2937),
            ),
          ),
        ],
      ),
    );
  }
}