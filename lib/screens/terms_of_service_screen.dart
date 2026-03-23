import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(
        0xFFF9FAFB,
      ), // Intuit-like document background
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text(
          'Terms of Service',
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
            Text(
              'Axume & Associates CPAs\nTerms of Service',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: const Color(0xFF111827),
              ),
            ),

            const SizedBox(height: 14),

            Text(
              'Last updated: March 2026',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6B7280),
              ),
            ),

            const SizedBox(height: 36),

            _sectionTitle(context, '1. Introduction'),
            _paragraph(
              context,
              'Welcome to Axume & Associates CPAs ("Axume", "we", "us", or "our"). '
              'These Terms of Service ("Terms") govern your access to and use of our '
              'websites, applications, client portals, and related services '
              '(collectively, the "Services").',
            ),
            _paragraph(
              context,
              'By accessing or using the Services, you agree to be bound by these Terms. '
              'If you do not agree, you may not access or use the Services.',
            ),

            _sectionTitle(context, '2. Professional Services Disclaimer'),
            _paragraph(
              context,
              'Axume & Associates CPAs provides accounting, tax, advisory, and related '
              'professional services. Information made available through the Services '
              'is provided for general informational purposes only and does not '
              'constitute legal, tax, or financial advice unless expressly stated in a '
              'written engagement agreement.',
            ),

            _sectionTitle(context, '3. No Assurance or Guarantee'),
            _paragraph(
              context,
              'Unless expressly stated in a written engagement agreement, Axume & '
              'Associates CPAs does not provide any assurance, attestation, audit, '
              'review, or compilation opinions through the Services. Information '
              'provided through the Services should not be relied upon as a substitute '
              'for formal professional services.',
            ),

            _sectionTitle(context, '4. Engagement Agreements'),
            _paragraph(
              context,
              'Professional services provided by Axume & Associates CPAs are governed '
              'by separate written engagement letters or agreements. In the event of '
              'any conflict between these Terms and an engagement agreement, the '
              'terms of the engagement agreement shall control.',
            ),

            _sectionTitle(context, '5. Client Accounts'),
            _paragraph(
              context,
              'Access to certain Services may require an invitation and the creation '
              'of an account. You are responsible for maintaining the confidentiality '
              'of your login credentials and for all activities that occur under your '
              'account.',
            ),

            _sectionTitle(context, '6. Acceptable Use'),
            _paragraph(
              context,
              'You agree not to misuse the Services, interfere with their operation, '
              'attempt unauthorized access, or use the Services in violation of '
              'applicable laws or regulations.',
            ),

            _sectionTitle(context, '7. Data Protection & Privacy'),
            _paragraph(
              context,
              'Your use of the Services is subject to our Privacy Policy, which explains '
              'how we collect, use, store, and protect personal information. While we '
              'implement reasonable administrative, technical, and physical safeguards, '
              'no system can be guaranteed to be completely secure.',
            ),

            TextButton(
              onPressed: () => _open('https://www.axumecpas.com/privacy'),
              child: const Text('View Privacy Policy'),
            ),

            _sectionTitle(context, '8. Confidentiality and Client Information'),
            _paragraph(
              context,
              'Information transmitted through the Services may include sensitive '
              'financial, tax, or personal data. You acknowledge that electronic '
              'transmission of information carries inherent risks, and Axume & '
              'Associates CPAs is not responsible for unauthorized access beyond '
              'our reasonable safeguards.',
            ),

            _sectionTitle(context, '9. Intellectual Property'),
            _paragraph(
              context,
              'All content, trademarks, logos, and materials provided through the '
              'Services are the property of Axume & Associates CPAs or its licensors '
              'and may not be used without prior written permission.',
            ),

            _sectionTitle(context, '10. Limitation of Liability'),
            _paragraph(
              context,
              'To the fullest extent permitted by law, Axume & Associates CPAs shall '
              'not be liable for any indirect, incidental, consequential, special, '
              'or punitive damages arising out of or related to your use of the '
              'Services, even if advised of the possibility of such damages.',
            ),

            _sectionTitle(context, '11. Termination'),
            _paragraph(
              context,
              'We may suspend or terminate access to the Services at any time for '
              'violations of these Terms or applicable law.',
            ),

            _sectionTitle(context, '12. Governing Law'),
            _paragraph(
              context,
              'These Terms are governed by the laws of the State of California, '
              'without regard to conflict of law principles.',
            ),

            _sectionTitle(context, '13. Contact Information'),
            _paragraph(
              context,
              'If you have questions about these Terms, please contact:',
            ),
            _paragraph(
              context,
              'Axume & Associates CPAs\n'
              'Bakersfield, California\n'
              'https://www.axumecpas.com',
            ),
          ],
        ),
      ),
    );
  }

  // ======================
  // Typography helpers
  // ======================

  Widget _sectionTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 36, bottom: 10),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(color: const Color(0xFF111827)),
      ),
    );
  }

  Widget _paragraph(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(color: const Color(0xFF1F2937)),
      ),
    );
  }
}
