import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/gestures.dart';

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
      backgroundColor: const Color(0xFFF9FAFB),
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
            Center(
              child: Text(
                'AXUME & ASSOCIATES CPAs\nTERMS OF SERVICE',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'GeneraGrotesk',
                  fontWeight: FontWeight.w800,
                  fontSize: 38,
                  height: 1.25,
                  letterSpacing: 0.8,
                  color: Color(0xFF111827),
                ),
              ),
            ),

            const SizedBox(height: 16),

            Text(
              'Effective Date: March 2026\nLast Updated: March 2026',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6B7280),
              ),
            ),

            _sectionTitle('Agreement & Acceptance'),
            _paragraph(
              'These Terms of Service (“Terms”) govern your access to and use of the '
              'Axume & Associates CPAs, AAC secure client portal, applications, and '
              'related services (collectively, the “Services”). By accessing or using '
              'the Services, you agree to these Terms.\n\n'
              'If you are using the Services on behalf of a business entity, you '
              'represent that you have authority to bind that entity, and “you” '
              'includes that entity.',
            ),

            _sectionTitle('Relationship to Engagement Letters'),
            _paragraph(
              'Professional services provided by Axume & Associates CPAs, AAC '
              '(including tax, bookkeeping, advisory, compilation, and review '
              'services) are governed by separate written engagement letters and '
              'addenda. If there is any conflict between these Terms and a signed '
              'engagement letter or addendum, the engagement letter controls.\n\n'
              'Our engagement documents include specific limitation‑of‑liability, '
              'consequential damages, indemnification, and reliance provisions '
              'intended to govern professional services risk allocation.',
            ),

            _sectionTitle('Definitions (Portal‑Specific)'),
            _paragraph(
              '• “Portal” — Axume’s secure file intake and client access platform.\n'
              '• “Client Upload Link” — A unique link generated for a specific '
              'client or engagement.\n'
              '• “Content” — Files, data, and materials uploaded or transmitted.\n'
              '• “Account” — A user profile created by invitation or approval.\n'
              '• “Firm Personnel” — Authorized Axume staff and contractors.\n'
              '• “Audit Log / Event Log” — Security and operational records such as '
              'logins, uploads, and administrative actions.',
            ),

            _sectionTitle('Eligibility & Account Creation'),
            _paragraph(
              'Access to the Portal may be provided by invitation and may require '
              'verification steps, including email confirmation and one‑time '
              'passcodes or multi‑factor authentication.\n\n'
              'You are responsible for safeguarding credentials, restricting '
              'device access, and promptly notifying us of any suspected '
              'unauthorized access. We may suspend or terminate access for '
              'security or policy reasons.',
            ),

            _sectionTitle('Permitted Use'),
            _paragraph(
              'You may use the Services solely for lawful purposes, including:\n'
              '• Uploading and retrieving engagement‑related documents\n'
              '• Communicating with firm personnel\n'
              '• Managing account settings',
            ),

            _sectionTitle('Prohibited Use'),
            _paragraph(
              'You agree not to:\n'
              '• Attempt unauthorized access or system probing\n'
              '• Upload malicious or unlawful content\n'
              '• Impersonate others or misrepresent identity\n'
              '• Disrupt service availability\n'
              '• Use the Portal as unrelated general storage',
            ),

            _sectionTitle('Client Upload Links'),
            _paragraph(
              'Client upload links are provided for secure document delivery. '
              'You agree to use only assigned links, not share them publicly, '
              'upload only engagement‑relevant files, and understand that links '
              'may be time‑limited, disabled, or replaced.',
            ),

            _sectionTitle('Content You Upload'),
            _paragraph(
              'You retain ownership of your Content. You grant Axume a limited '
              'right to access, store, and process Content solely to provide '
              'services, maintain security, and operate the Portal.\n\n'
              'You represent that you have the right to upload Content and that '
              'it does not violate law or third‑party rights. Unless required by '
              'a signed engagement, Axume does not audit or independently verify '
              'submitted information.',
            ),

            _sectionTitle('Professional Services Disclaimer'),
            _paragraph(
              'The Portal is a delivery and communication tool and does not itself '
              'provide legal, tax, or accounting advice.\n\n'
              'Unless expressly stated in writing, services accessed through the '
              'Portal do not constitute an audit, attestation, or assurance '
              'engagement.',
            ),

            _sectionTitle('Privacy & Data Protection'),
            _paragraph(
              'Your use of the Services is governed by our Privacy Policy and any '
              'applicable Notice at Collection.\n\n'
              'Axume maintains a security program with administrative, technical, '
              'and physical safeguards, including role‑based access controls, '
              'encryption, audit logs, and incident response procedures aligned '
              'with applicable professional and regulatory standards.',
            ),

            TextButton(
              onPressed: () => _open('https://www.axumecpas.com/privacy'),
              child: const Text('View Privacy Policy'),
            ),

            _sectionTitle('Audit Logs & Monitoring'),
            _paragraph(
              'To maintain security and compliance, Axume may log sign‑ins, uploads, '
              'administrative actions, and security events. These logs may be used '
              'for troubleshooting, investigations, and operational integrity.',
            ),

            _sectionTitle('Electronic Communications'),
            _paragraph(
              'By using the Services, you consent to receive electronic '
              'communications related to account verification, security alerts, '
              'service notices, and engagement communications where permitted.',
            ),

            _sectionTitle('Third‑Party Services'),
            _paragraph(
              'The Portal may link to third‑party services. Such services are '
              'governed by their own terms and privacy practices, and Axume is '
              'not responsible for third‑party services outside its control.',
            ),

            _sectionTitle('Availability & Suspension'),
            _paragraph(
              'We may modify, suspend, or discontinue the Services at any time for '
              'maintenance, security, or operational reasons. Access may be '
              'suspended for violations, security risks, or legal requirements.',
            ),

            _sectionTitle('Disclaimers'),
            _paragraph(
              'The Services are provided “AS IS” and “AS AVAILABLE.” We do not '
              'guarantee uninterrupted or error‑free operation. No system can be '
              'guaranteed 100% secure.',
            ),

            _sectionTitle('Limitation of Liability'),
            _paragraph(
              'To the fullest extent permitted by law, Axume disclaims liability '
              'for indirect, incidental, consequential, or punitive damages. '
              'Liability limitations in signed engagement addenda apply where '
              'applicable.',
            ),

            _sectionTitle('Indemnification'),
            _paragraph(
              'You agree to indemnify and hold harmless Axume and its personnel '
              'from claims arising from misuse of the Services, uploaded Content, '
              'misrepresentations, or breach of these Terms.',
            ),

            _sectionTitle('Dispute Resolution'),
            _paragraph(
              'Any dispute arising from these Terms or the Services may be '
              'resolved by binding arbitration under California law, conducted '
              'in Bakersfield, California, with the prevailing party entitled to '
              'recover reasonable attorneys’ fees and costs, unless otherwise '
              'required by law.',
            ),

            _sectionTitle('Governing Law'),
            _paragraph(
              'These Terms are governed by the laws of the State of California, '
              'without regard to conflict‑of‑law principles.',
            ),

            _sectionTitle('Termination'),
            _paragraph(
              'These Terms remain effective while you use the Services. Upon '
              'termination, access ends and certain provisions survive, '
              'including liability limits and dispute resolution.',
            ),

            _sectionTitle('Contact'),
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: RichText(
                text: TextSpan(
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF1F2937),
                  ),
                  children: [
                    const TextSpan(
                      text:
                          'If you have questions about these Terms, please ',
                    ),
                    TextSpan(
                      text: 'contact us',
                      style: const TextStyle(
                        color: Color(0xFF2563EB),
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () =>
                            _open('https://www.axumecpas.com/contact.php'),
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 36, bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'GeneraGrotesk',
          fontWeight: FontWeight.w800,
          fontSize: 18,
          color: Color(0xFF111827),
        ),
      ),
    );
  }

  Widget _paragraph(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          height: 1.75,
          color: Color(0xFF1F2937),
        ),
      ),
    );
  }
}