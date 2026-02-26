import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class EmailCheckerScreen extends StatefulWidget {
  const EmailCheckerScreen({super.key});

  @override
  State<EmailCheckerScreen> createState() => _EmailCheckerScreenState();
}

class _EmailCheckerScreenState extends State<EmailCheckerScreen> {
  bool _busy = false;

  final _subjectCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

  Map<String, dynamic>? _result;
  String? _error;

  HttpsCallable _callable(String name) {
    return FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(name);
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  PreferredSizeWidget _appBar() {
    return AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      elevation: 2,
      title: const Text(
        'Email Checker',
        style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.2),
      ),
      actions: [
        IconButton(
          tooltip: 'Clear',
          icon: const Icon(Icons.refresh),
          onPressed: _busy
              ? null
              : () {
                  setState(() {
                    _subjectCtrl.clear();
                    _bodyCtrl.clear();
                    _result = null;
                    _error = null;
                  });
                },
        ),
      ],
    );
  }

  Future<void> _analyze() async {
    final subject = _subjectCtrl.text.trim();
    final body = _bodyCtrl.text.trim();

    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });

    try {
      final res = await _callable('analyzeEmail').call({
        'subject': subject,
        'body': body,
      });

      final data = Map<String, dynamic>.from(res.data as Map);
      if (!mounted) return;

      setState(() {
        _result = data;
        _busy = false;
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Analyze failed: ${e.code} ${e.message ?? ''}'.trim();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Analyze failed: $e';
      });
    }
  }

  // --- Cyberphilearn-style result UI ---
  Widget _contentOnlyResult(Map<String, dynamic> r) {
    final verdict = (r['verdict'] ?? 'Likely Phishing').toString();
    final message = (r['message'] ?? '⚠️ This email is likely phishing.').toString();

    final reasons = (r['reasons'] is List)
        ? List<String>.from((r['reasons'] as List).map((e) => e.toString()))
        : <String>[];

    final domains = (r['domains'] is List)
        ? List<Map<String, dynamic>>.from((r['domains'] as List).map((e) => Map<String, dynamic>.from(e as Map)))
        : <Map<String, dynamic>>[];

    Color verdictColor = Colors.orange.shade800;
    IconData verdictIcon = Icons.warning_amber_rounded;

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              Icon(verdictIcon, color: verdictColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: verdictColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Text(
            'Reasons:',
            style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF111827)),
          ),
          const SizedBox(height: 6),
          if (reasons.isEmpty)
            const Text(
              'No strong phishing phrases detected, but remain cautious.',
              style: TextStyle(color: Color(0xFF374151), height: 1.35),
            )
          else
            ...reasons.map((x) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('• $x',
                      style: const TextStyle(
                        color: Color(0xFF374151),
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      )),
                )),

          const SizedBox(height: 14),
          Divider(color: Colors.black.withOpacity(0.08)),
          const SizedBox(height: 12),

          Text(
            'Domains found in email content:',
            style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF111827)),
          ),
          const SizedBox(height: 8),

          if (domains.isEmpty)
            const Text(
              'No domains detected in the email body.',
              style: TextStyle(color: Color(0xFF374151), height: 1.35),
            )
          else
            ...domains.map((d) {
              final domain = (d['domain'] ?? '').toString();
              final status = (d['status'] ?? 'Unknown').toString();

              final bool isBad = status.toLowerCase() == 'malicious' || status.toLowerCase() == 'suspicious';
              final Color fg = isBad ? Colors.red.shade800 : const Color(0xFF374151);
              final IconData icon = isBad ? Icons.report : Icons.public;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 18, color: fg),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isBad
                            ? '⚠️ $domain\nStatus: $status'
                            : '$domain\nStatus: $status',
                        style: TextStyle(
                          color: fg,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),

          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withOpacity(0.06)),
            ),
            child: const Text(
              'Tip: For strongest verification, always confirm the sender via a known channel and avoid clicking links in unexpected emails.',
              style: TextStyle(
                color: Color(0xFF4B5563),
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _inputCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text(
            'Paste the email content below',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF111827)),
          ),
          const SizedBox(height: 6),
          const Text(
            'Enter subject + body. This tool will provide a phishing likelihood summary.',
            style: TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _subjectCtrl,
            decoration: const InputDecoration(
              labelText: 'Subject',
              hintText: 'Paste the email subject here…',
              prefixIcon: Icon(Icons.subject_outlined),
            ),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _bodyCtrl,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: 'Email body',
              hintText: 'Paste the email body here…',
              prefixIcon: Icon(Icons.text_snippet_outlined),
            ),
          ),

          const SizedBox(height: 16),
          SizedBox(
            height: 46,
            child: FilledButton.icon(
              onPressed: _busy ? null : _analyze,
              icon: const Icon(Icons.search),
              label: const Text(
                'Analyze Email',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mode = (_result?['mode'] ?? '').toString();

    return Scaffold(
      appBar: _appBar(),
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _inputCard(),
                      const SizedBox(height: 12),

                      if (_error != null)
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.error_outline, color: Color(0xFFB42318)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(
                                      color: Color(0xFFB42318),
                                      fontWeight: FontWeight.w700,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      if (_result != null) ...[
                        const SizedBox(height: 12),
                        if (mode == 'content-only')
                          _contentOnlyResult(_result!)
                        else
                          // fallback: show content-only style if backend didn't set mode
                          _contentOnlyResult(_result!),

                        const SizedBox(height: 12),

                        OutlinedButton.icon(
                          onPressed: () async {
                            final uri = Uri.parse('https://tools.cyberphilearn.com/email-checker/');
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          },
                          icon: const Icon(Icons.open_in_new),
                          label: const Text(
                            'Run external email check (Cyberphilearn)',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

          if (_busy)
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    );
  }
}