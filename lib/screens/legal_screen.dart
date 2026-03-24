import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text(
          'Legal',
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
            _section(
              title: 'Legal Information',
              body:
                  'This section contains legal notices, intellectual property '
                  'information, and policies related to Axume & Associates CPAs, AAC.',
            ),

            _section(
              title: 'Trademarks',
              body:
                  'Axume & Associates CPAs, AAC, the Axume name and logo, and related '
                  'product and service names are trademarks or service marks of '
                  'Axume & Associates CPAs, AAC. All other trademarks belong to '
                  'their respective owners.',
            ),

            _section(
              title: 'Copyright',
              body:
                  'The content, design, software, and materials made available through '
                  'our websites and portals are owned by Axume & Associates CPAs, AAC '
                  'or its licensors and are protected by copyright laws.',
            ),

            _section(
              title: 'Intellectual Property Infringement',
              body:
                  'Axume respects the intellectual property rights of others. If you '
                  'believe content made available through our services infringes '
                  'your rights, please notify us with sufficient detail so we can '
                  'review and respond appropriately.',
            ),

            _section(
              title: 'Licensing & Use',
              body:
                  'Use of our services is governed by our Terms of Service and '
                  'engagement agreements. Unauthorized use of our intellectual '
                  'property is prohibited.',
            ),

            TextButton(
              onPressed: () => _open('https://www.axumecpas.com/contact.php'),
              child: const Text('Contact Legal'),
            ),
          ],
        ),
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