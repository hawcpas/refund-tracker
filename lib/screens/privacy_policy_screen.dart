import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';

class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  final Map<String, bool> _expanded = {
    'overview': false,
    'collection': false,
    'usage': false,
    'sharing': false,
    'security': false,
    'retention': false,
    'rights': false,
    'cookies': false,
    'ai': false,
    'children': false,
    'changes': false,
    'contact': false,
  };

  bool get _allExpanded => _expanded.values.every((v) => v);

  void _toggleAll() {
    final expand = !_allExpanded;
    setState(() {
      for (final k in _expanded.keys) {
        _expanded[k] = expand;
      }
    });
  }

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
          'Privacy Policy',
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
                'AXUME & ASSOCIATES CPAs PRIVACY POLICY',
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

            const SizedBox(height: 14),

            Text(
              'Last updated: March 2026',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6B7280),
              ),
            ),

            const SizedBox(height: 24),

            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _toggleAll,
                child: Text(_allExpanded ? 'Collapse all' : 'Expand all'),
              ),
            ),

            const SizedBox(height: 8),

            // 1. Overview / Scope
            _section(
              keyId: 'overview',
              title: '1. Scope & Overview',
              body:
                  'This Privacy Policy explains how Axume & Associates CPAs (“Axume,” '
                  '“we,” “us,” or “our”) collects, uses, discloses, and protects personal '
                  'information when you interact with our websites, secure client portal, '
                  'related web and mobile applications (the “Portal”), communications, '
                  'and professional accounting and tax services (collectively, the '
                  '“Services”).\n\n'
                  'This policy applies when Axume acts as a business or controller. In '
                  'certain engagements, another organization may control the data and '
                  'their privacy terms may apply.',
            ),

            // 2. Information Collected
            _section(
              keyId: 'collection',
              title: '2. Information We Collect',
              body:
                  'The information collected depends on how you use the Services.\n\n'
                  'Information you provide directly may include:\n'
                  '• Name, email address, phone number, and company name\n'
                  '• Login credentials, security verification codes, and account settings\n'
                  '• Client and engagement identifiers\n'
                  '• Communications sent to us\n'
                  '• Documents you upload, including tax, payroll, financial, or '
                  'business records\n\n'
                  'Information collected automatically may include:\n'
                  '• IP address, device and browser type\n'
                  '• Authentication and session logs\n'
                  '• Access timestamps and portal activity (view, upload, admin actions)\n\n'
                  'Sensitive personal information may be processed depending on what you '
                  'upload, including taxpayer identifiers, financial account data, '
                  'government ID information, and authentication security data.',
            ),

            // 3. Use
            _section(
              keyId: 'usage',
              title: '3. How We Use Information',
              body:
                  'Personal information is used for legitimate business purposes, '
                  'including:\n\n'
                  '• Creating and managing portal accounts\n'
                  '• Authenticating users and enforcing role‑based access\n'
                  '• Securely receiving, storing, and delivering client documents\n'
                  '• Maintaining audit logs for uploads, access, and administrative actions\n'
                  '• Monitoring for security incidents and fraud\n'
                  '• Complying with legal, regulatory, and professional obligations\n'
                  '• Providing client communications and support\n'
                  '• Improving portal performance, reliability, and security\n\n'
                  'We do not use automated tools to make tax or legal decisions without '
                  'human oversight.',
            ),

            // 4. Sharing
            _section(
              keyId: 'sharing',
              title: '4. Information Sharing',
              body:
                  'We may share personal information with trusted service providers who '
                  'help operate the Portal and deliver essential services, such as cloud '
                  'hosting, secure storage, email delivery, and security monitoring.\n\n'
                  'We may also disclose information to comply with legal obligations, '
                  'respond to lawful requests, protect rights and safety, or in connection '
                  'with a business transaction.\n\n'
                  'We do not sell personal information, and we do not share personal '
                  'information for cross‑context behavioral advertising.',
            ),

            // 5. Security
            _section(
              keyId: 'security',
              title: '5. Security Measures',
              body:
                  'We maintain administrative, technical, and physical safeguards designed '
                  'to protect personal information. Security measures may include:\n\n'
                  '• Encryption in transit and at rest\n'
                  '• Role‑based access controls\n'
                  '• One‑time passcodes (OTP) or multi‑factor authentication\n'
                  '• Audit logging of file and administrative actions\n'
                  '• Monitoring for suspicious activity\n\n'
                  'These safeguards are designed to align with professional obligations '
                  'and applicable standards such as the FTC Safeguards Rule. No system is '
                  '100% secure, but we work to maintain appropriate protections.',
            ),

            // 6. Retention
            _section(
              keyId: 'retention',
              title: '6. Data Retention',
              body:
                  'Personal information is retained only as long as reasonably necessary '
                  'for the purposes described in this policy, including maintaining '
                  'accounts, providing services, meeting legal and professional record '
                  'retention requirements, resolving disputes, and enforcing agreements.\n\n'
                  'Retention periods may vary based on the type of information and the '
                  'engagement context.',
            ),

            // 7. Rights
            _section(
              keyId: 'rights',
              title: '7. Privacy Rights & Choices',
              body:
                  'Depending on your jurisdiction, including California, you may have '
                  'rights to:\n\n'
                  '• Access or know what personal information we collect\n'
                  '• Request correction or deletion (subject to legal exceptions)\n'
                  '• Opt‑out of selling or sharing (if applicable)\n'
                  '• Limit use of sensitive personal information (if applicable)\n'
                  '• Not be discriminated against for exercising your rights\n\n'
                  'Requests may be submitted via email or our contact form and will be '
                  'verified as required by law.',
            ),

            // 8. Cookies
            _section(
              keyId: 'cookies',
              title: '8. Cookies & Similar Technologies',
              body:
                  'Our websites and Portal may use cookies or local storage to maintain '
                  'sessions, support authentication and security, and improve performance '
                  'and reliability. These technologies are not used for advertising‑based '
                  'profiling unless explicitly stated.',
            ),

            // 9. AI
            _section(
              keyId: 'ai',
              title: '9. Artificial Intelligence',
              body:
                  'We may use automated or AI‑assisted tools to enhance security, '
                  'efficiency, and service delivery. These tools are used under human '
                  'oversight and are not relied upon to make legal or tax determinations '
                  'without professional review.',
            ),

            // 10. Children
            _section(
              keyId: 'children',
              title: '10. Children’s Privacy',
              body:
                  'Our Services are not intended for children under 13, and we do not '
                  'knowingly collect personal information from children. If you believe a '
                  'child has provided information, please contact us.',
            ),

            // 11. Updates
            _section(
              keyId: 'changes',
              title: '11. Policy Updates',
              body:
                  'We may update this Privacy Policy from time to time. When we do, the '
                  '“Last updated” date will be revised and additional notice may be '
                  'provided through the Portal or via email when required.',
            ),

            // 12. Contact
            _section(
              keyId: 'contact',
              title: '12. Contact Us',
              bodyWidget: RichText(
                text: TextSpan(
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF1F2937),
                  ),
                  children: [
                    const TextSpan(
                      text:
                          'If you have questions about this Privacy Policy or our privacy '
                          'practices, please ',
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

  Widget _section({
    required String keyId,
    required String title,
    String? body,
    Widget? bodyWidget,
  }) {
    final expanded = _expanded[keyId] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            title,
            style: const TextStyle(
              fontFamily: 'GeneraGrotesk',
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: Color(0xFF111827),
            ),
          ),
          trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more),
          onTap: () {
            setState(() {
              _expanded[keyId] = !expanded;
            });
          },
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: bodyWidget ??
                Text(
                  body ?? '',
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.75,
                    color: Color(0xFF1F2937),
                  ),
                ),
          ),
      ],
    );
  }
}