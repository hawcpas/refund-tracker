import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../widgets/centered_section.dart';

class CreateUploadLinkScreen extends StatefulWidget {
  final VoidCallback? onCancel;
  const CreateUploadLinkScreen({super.key, this.onCancel});

  @override
  State<CreateUploadLinkScreen> createState() => _CreateUploadLinkScreenState();
}

class _CreateUploadLinkScreenState extends State<CreateUploadLinkScreen> {
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

  final firstCtrl = TextEditingController();
  final lastCtrl = TextEditingController();
  final businessCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final msgCtrl = TextEditingController();

  bool _busy = false;

  final List<String> businessNames = [];
  final List<String> clientEmails = [];
  final List<_MessageTemplate> messageTemplates = [];

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
    _loadTemplates();
  }

  Future<void> _loadSuggestions() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final snap = await FirebaseFirestore.instance
        .collection('dropoff_requests')
        .where('createdByUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();

    for (final d in snap.docs) {
      final data = d.data();
      final b = (data['businessName'] ?? '').toString().trim();
      final e = (data['clientEmail'] ?? '').toString().trim();
      if (b.isNotEmpty && !businessNames.contains(b)) businessNames.add(b);
      if (e.isNotEmpty && !clientEmails.contains(e)) clientEmails.add(e);
    }
    if (mounted) setState(() {});
  }

  void _loadTemplates() {
    messageTemplates.addAll([
      _MessageTemplate(
        id: 'tax_docs',
        title: 'Tax documents request',
        body:
            'Dear Client,\n\nPlease upload your tax documents using the secure link below.\n\nThank you,\nAxume & Associates CPAs',
      ),
      _MessageTemplate(
        id: 'general',
        title: 'General document request',
        body:
            'Dear Client,\n\nPlease upload the requested documents using the secure link below.\n\nBest regards,\nAxume & Associates CPAs',
      ),
    ]);
  }

  bool _isValidEmail(String v) {
    if (v.trim().isEmpty) return true;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v);
  }

  Future<void> _create() async {
    final first = firstCtrl.text.trim();
    final last = lastCtrl.text.trim();
    final email = emailCtrl.text.trim();
    final business = businessCtrl.text.trim();
    final msg = msgCtrl.text.trim();

    if (first.isEmpty || last.isEmpty) {
      _toast('Enter first and last name.');
      return;
    }
    if (!_isValidEmail(email)) {
      _toast('Enter a valid email address.');
      return;
    }

    setState(() => _busy = true);
    try {
      final res = await _functions.httpsCallable('createDropoffRequest').call({
        'firstName': first,
        'lastName': last,
        'clientEmail': email,
        'businessName': business,
        'message': msg,
      });

      final url = (res.data['url'] ?? '').toString();
      if (url.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: url));
      }

      if (!mounted) return;
      _toast('Client upload link created and copied.');
      widget.onCancel?.call();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            CenteredSection(
              maxWidth: 900,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black.withOpacity(0.06)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 720;

                    Widget field(Widget child) => ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 340),
                      child: child,
                    );

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ===== Header =====
                        Text(
                          'Create Client Upload Link',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF101828),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Generate a secure upload link for a client to submit documents.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF475467),
                            fontWeight: FontWeight.w600,
                          ),
                        ),

                        const SizedBox(height: 18),
                        Divider(color: Colors.black.withOpacity(0.08)),
                        const SizedBox(height: 18),

                        // ===== Client Info =====
                        _Section('Client information'),

                        Wrap(
                          spacing: 16,
                          runSpacing: 12,
                          children: [
                            field(
                              TextField(
                                controller: firstCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'First name',
                                ),
                              ),
                            ),
                            field(
                              TextField(
                                controller: lastCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Last name',
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        Wrap(
                          spacing: 16,
                          runSpacing: 12,
                          children: [
                            field(
                              Autocomplete<String>(
                                optionsBuilder: (value) {
                                  final q = value.text.toLowerCase();
                                  if (q.isEmpty)
                                    return const Iterable<String>.empty();
                                  return businessNames.where(
                                    (b) => b.toLowerCase().contains(q),
                                  );
                                },
                                onSelected: (v) => businessCtrl.text = v,
                                fieldViewBuilder: (_, ctrl, focusNode, __) {
                                  ctrl.addListener(
                                    () => businessCtrl.text = ctrl.text,
                                  );
                                  return TextField(
                                    controller: ctrl,
                                    focusNode: focusNode,
                                    decoration: const InputDecoration(
                                      labelText: 'Business name (optional)',
                                    ),
                                  );
                                },
                              ),
                            ),
                            field(
                              Autocomplete<String>(
                                optionsBuilder: (value) {
                                  final q = value.text.toLowerCase();
                                  if (q.length < 3)
                                    return const Iterable<String>.empty();
                                  return clientEmails.where(
                                    (e) => e.toLowerCase().contains(q),
                                  );
                                },
                                onSelected: (v) => emailCtrl.text = v,
                                fieldViewBuilder: (_, ctrl, focusNode, __) {
                                  ctrl.addListener(
                                    () => emailCtrl.text = ctrl.text,
                                  );
                                  return TextField(
                                    controller: ctrl,
                                    focusNode: focusNode,
                                    keyboardType: TextInputType.emailAddress,
                                    decoration: const InputDecoration(
                                      labelText: 'Client email (optional)',
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // ===== Message =====
                        _Section('Client message'),

                        field(
                          DropdownButtonFormField<String>(
                            decoration: const InputDecoration(
                              labelText: 'Message template',
                            ),
                            items: messageTemplates
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: t.id,
                                    child: Text(t.title),
                                  ),
                                )
                                .toList(),
                            onChanged: (id) {
                              final t = messageTemplates.firstWhere(
                                (e) => e.id == id,
                              );
                              msgCtrl.text = t.body;
                            },
                          ),
                        ),

                        const SizedBox(height: 12),

                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: TextField(
                            controller: msgCtrl,
                            maxLines: 6,
                            decoration: const InputDecoration(
                              labelText: 'Message',
                              alignLabelWithHint: true,
                            ),
                          ),
                        ),

                        const SizedBox(height: 28),
                        Divider(color: Colors.black.withOpacity(0.08)),
                        const SizedBox(height: 16),

                        // ===== Actions =====
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton(
                              onPressed: widget.onCancel,
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              height: 44,
                              child: FilledButton(
                                onPressed: _busy ? null : _create,
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                child: const Text('Create link'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
        if (_busy)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  const _Section(this.title);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: const Color(0xFF475467),
        ),
      ),
    );
  }
}

class _MessageTemplate {
  final String id;
  final String title;
  final String body;
  _MessageTemplate({required this.id, required this.title, required this.body});
}
