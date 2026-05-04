import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../theme/app_colors.dart';
import '../widgets/centered_section.dart';

import '../widgets/page_scaffold.dart';
import '../theme/app_theme.dart';
import '../screens/dropoff_detail_screen.dart';

String formatDateTimeCompact(DateTime dt) {
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final y = dt.year.toString();

  int hour = dt.hour;
  final minute = dt.minute.toString().padLeft(2, '0');
  final ampm = hour >= 12 ? 'PM' : 'AM';
  hour = hour % 12;
  if (hour == 0) hour = 12;

  return '$m/$d/$y • $hour:$minute $ampm';
}

/// Sort options for the links list
enum _DropoffSortField {
  clientName,
  createdAt,
  lastUploadedAt,
  fileCount,
  status,
}

enum _LinksView { active, archived }

class GenerateUploadLinkScreen extends StatefulWidget {
  final void Function(String requestId)? onOpenDetails;
  final VoidCallback? onCreate;
  final ValueNotifier<int>? createSignal; // ✅ ADD THIS LINE

  const GenerateUploadLinkScreen({
    super.key,
    this.onOpenDetails,
    this.onCreate,
    this.createSignal,
  });

  @override
  State<GenerateUploadLinkScreen> createState() =>
      _GenerateUploadLinkScreenState();
}

class _FieldHeader extends StatelessWidget {
  final String label;
  final String? helper;

  const _FieldHeader(this.label, {this.helper});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appTheme = theme.extension<AppTheme>()!;

    // Compact typography (enterprise density)
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w800,
      fontSize: 12.5,
      color: const Color(0xFF344054),
      height: 1.1,
    );

    final helperStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: 11.5,
      color: const Color(0xFF667085),
      fontWeight: FontWeight.w600,
      height: 1.15,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: labelStyle),
          if (helper != null && helper!.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(helper!, style: helperStyle),
          ],
        ],
      ),
    );
  }
}

class _GenerateUploadLinkScreenState extends State<GenerateUploadLinkScreen> {
  final _db = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

  // ✅ ADD THIS LINE
  String? _deepLinkRid;

  final List<String> _businessNames = <String>[];
  final List<String> _clientEmails = <String>[];
  final List<_MessageTemplate> _messageTemplates = <_MessageTemplate>[];
  bool _templatesLoaded = false;
  bool _suggestionsLoaded = false;

  static _LinksView _lastView = _LinksView.active;
  late _LinksView _view;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _view = _lastView;
    _loadSuggestions();
    _loadTemplates();

    widget.createSignal?.addListener(() {
      if (mounted) {
        _openCreateRequestDialog();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // ✅ Flutter Web: query params come from Uri.base
    final uri = Uri.base;

    final rid = uri.queryParameters['rid'];

    if (_deepLinkRid != rid) {
      setState(() {
        _deepLinkRid = rid;
      });
    }
  }

  HttpsCallable _callable(String name) => _functions.httpsCallable(name);

  // Admin callables
  HttpsCallable get _deleteDropoffCallable =>
      _functions.httpsCallable('deleteDropoffRequest');

  HttpsCallable get _setDropoffStatusCallable =>
      _functions.httpsCallable('setDropoffStatus');

  HttpsCallable get _purgeDropoffCallable =>
      _functions.httpsCallable('purgeDropoffRequest');

  String _resolveClientName({
    required TextEditingController firstCtrl,
    required TextEditingController lastCtrl,
  }) {
    final first = firstCtrl.text.trim();
    final last = lastCtrl.text.trim();
    final full = ('$first $last').trim();

    if (full.isNotEmpty) return full;
    if (first.isNotEmpty) return first; // fallback
    return 'Client';
  }

  Future<String> _resolveSenderName() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return 'Axume & Associates CPAs';

      final dn = (user.displayName ?? '').trim();
      if (dn.isNotEmpty) return dn;

      // If you store staff names in /users/{uid}
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final data = snap.data();
      if (data != null) {
        final first = (data['firstName'] ?? '').toString().trim();
        final last = (data['lastName'] ?? '').toString().trim();
        final full = ('$first $last').trim();
        if (full.isNotEmpty) return full;

        final displayName = (data['displayName'] ?? '').toString().trim();
        if (displayName.isNotEmpty) return displayName;
      }

      final email = (user.email ?? '').trim();
      if (email.isNotEmpty) return email;

      return 'Axume & Associates CPAs';
    } catch (_) {
      return 'Axume & Associates CPAs';
    }
  }

  String _applyTemplateTokens(
    String text, {
    required String senderName,
    required String clientName,
    required String clientFirstName,
  }) {
    return text
        .replaceAll('{{senderName}}', senderName)
        .replaceAll('{{clientName}}', clientName)
        .replaceAll('{{clientFirstName}}', clientFirstName);
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _loadDropoff(String rid) {
    return _db.collection('dropoff_requests').doc(rid).get();
  }

  Future<void> _setDropoffStatus(String requestId, String status) async {
    setState(() => _busy = true);
    try {
      await _setDropoffStatusCallable.call({
        'requestId': requestId,
        'status': status, // "open" or "closed"
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Request link ${status == "open" ? "enabled" : "disabled"}',
          ),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final details = e.details == null ? '' : '\nDetails: ${e.details}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Status update failed: ${e.code} ${e.message ?? ''}$details',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Status update failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _loadTemplates() {
    _messageTemplates
      ..clear()
      ..addAll([
        _MessageTemplate(
          id: 'tax_docs',
          title: 'Tax documents request',
          body:
              'Dear {{clientFirstName}},\n\n'
              'Please upload your tax documents using the \'Add Files\' button located at the bottom of this page.\n\n'
              'Best regards,\n'
              '{{senderName}}\n',
        ),
        _MessageTemplate(
          id: 'general',
          title: 'General document request',
          body:
              'Dear {{clientFirstName}},\n\n'
              'Please upload the requested documents using the \'Add Files\' button located at the bottom of this page.\n\n'
              'Best regards,\n'
              '{{senderName}}\n',
        ),
      ]);

    setState(() => _templatesLoaded = true);
  }

  Future<void> _loadSuggestions() async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      final snap = await FirebaseFirestore.instance
          .collection('dropoff_requests')
          .where('createdByUid', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      final business = <String>{};
      final emails = <String>{};

      for (final d in snap.docs) {
        final data = d.data();
        final b = (data['businessName'] ?? '').toString().trim();
        final e = (data['clientEmail'] ?? '').toString().trim();

        if (b.isNotEmpty) business.add(b);
        if (e.isNotEmpty) emails.add(e);
      }

      if (!mounted) return;
      setState(() {
        _businessNames
          ..clear()
          ..addAll(business);
        _clientEmails
          ..clear()
          ..addAll(emails);
        _suggestionsLoaded = true;
      });
    } catch (_) {
      // Best-effort only (never block modal)
      if (!mounted) return;
      setState(() => _suggestionsLoaded = true);
    }
  }

  Future<void> _purgeDropoffRequest(String requestId) async {
    setState(() => _busy = true);
    try {
      await _purgeDropoffCallable.call({'requestId': requestId});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Archived link permanently deleted.')),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Permanent delete failed')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Permanent delete failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteDropoffRequest(String requestId) async {
    setState(() => _busy = true);
    try {
      await _deleteDropoffCallable.call({'requestId': requestId});

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Request link deleted.')));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message ?? 'Delete failed')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Bulk delete: uses same callable, but holds busy state once (enterprise feel)
  Future<void> _bulkDeleteDropoffRequests(
    List<String> requestIds, {
    required bool isArchived,
  }) async {
    if (requestIds.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete selected links'),
        content: Text(
          isArchived
              ? 'Permanently delete ${requestIds.length} archived request link(s)? '
                    'This action cannot be undone.'
              : 'Delete ${requestIds.length} Request link(s)? '
                    'This will remove the request and all associated uploads.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      // Execute sequentially (safer for rate limits + audit readability)
      for (final id in requestIds) {
        if (isArchived) {
          await _purgeDropoffCallable.call({'requestId': id});
        } else {
          await _deleteDropoffCallable.call({'requestId': id});
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isArchived
                ? 'Permanently deleted ${requestIds.length} archived link(s).'
                : 'Archived ${requestIds.length} link(s).',
          ),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bulk delete failed: ${e.code} ${e.message ?? ''}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Bulk delete failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openCreateRequestDialog() async {
    final firstCtrl = TextEditingController();
    final lastCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final businessCtrl = TextEditingController();
    final messageCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    int expirationDays = 14;

    bool triedSubmit = false; // controls when errors appear

    String? selectedTemplateId;
    bool submitting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !submitting,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final appTheme = theme.extension<AppTheme>()!;

        Widget sectionLabel(String text) => Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Text(
            text.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 0.8,
              color: const Color(0xFF667085),
              fontWeight: FontWeight.w800,
            ),
          ),
        );

        String _resolveClientFirstName({
          required TextEditingController firstCtrl,
        }) {
          final first = firstCtrl.text.trim();
          return first.isNotEmpty ? first : 'there';
        }

        Future<void> submit(StateSetter setLocalState) async {
          final first = firstCtrl.text.trim();
          final last = lastCtrl.text.trim();
          final email = emailCtrl.text.trim().toLowerCase();
          final business = businessCtrl.text.trim();
          final senderName = await _resolveSenderName();
          final clientName = _resolveClientName(
            firstCtrl: firstCtrl,
            lastCtrl: lastCtrl,
          );
          final clientFirstName = _resolveClientFirstName(firstCtrl: firstCtrl);

          final message = _applyTemplateTokens(
            messageCtrl.text.trim(),
            senderName: senderName,
            clientName: clientName,
            clientFirstName: clientFirstName,
          );

          if (first.isEmpty || last.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('First and last name are required.'),
              ),
            );
            return;
          }

          if (email.isNotEmpty && !email.contains('@')) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Enter a valid client email (or leave it blank).',
                ),
              ),
            );
            return;
          }

          setLocalState(() => submitting = true);
          setState(() => _busy = true);

          try {
            final callable = FirebaseFunctions.instanceFor(
              region: 'us-central1',
            ).httpsCallable('createDropoffRequest');

            final res = await callable.call({
              'firstName': first,
              'lastName': last,
              'clientEmail': email,
              'businessName': business,
              'message': message,
              'expirationDays': expirationDays,
            });

            final data = Map<String, dynamic>.from(res.data as Map);
            final requestId = (data['requestId'] ?? '').toString().trim();
            final url = (data['url'] ?? '').toString().trim();
            final urlController = TextEditingController(text: url);

            Future<void> _showShareLinkDialog(
              BuildContext context,
              String url,
            ) async {
              final theme = Theme.of(context);
              final appTheme = theme.extension<AppTheme>()!;

              await showDialog<void>(
                context: context,
                builder: (ctx) {
                  return Dialog(
                    backgroundColor: appTheme.contentBackground,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    insetPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 24,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Share this link with your client',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w900,
                                          color: const Color(0xFF101828),
                                        ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Close',
                                  onPressed: () => Navigator.pop(ctx),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),

                            const SizedBox(height: 4),

                            Text(
                              'Anyone with this link can upload files securely.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF667085),
                                fontWeight: FontWeight.w600,
                              ),
                            ),

                            const SizedBox(height: 10),

                            // Link box (fixed width, truncated like Dropbox)
                            Row(
                              children: [
                                // ✅ URL field (single rectangle only)
                                Expanded(
                                  child: Container(
                                    height: 44,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: appTheme.contentBackground,
                                      border: Border.all(
                                        color: appTheme.divider,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.03),
                                          blurRadius: 2,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                    alignment: Alignment.centerLeft,
                                    child: Focus(
                                      onFocusChange: (hasFocus) {
                                        if (hasFocus) {
                                          urlController.selection =
                                              TextSelection(
                                                baseOffset: 0,
                                                extentOffset:
                                                    urlController.text.length,
                                              );
                                        }
                                      },
                                      child: TextField(
                                        controller: urlController,
                                        readOnly: true,
                                        maxLines: 1,
                                        enableInteractiveSelection: true,
                                        showCursor: false,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: const Color(0xFF101828),
                                            ),
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          border: InputBorder.none,
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(width: 10),

                                // ✅ Copy button OUTSIDE the rectangle
                                SizedBox(
                                  height: 44,
                                  child: OutlinedButton(
                                    onPressed: () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: url),
                                      );
                                      if (!ctx.mounted) return;
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Link copied to clipboard',
                                          ),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      side: BorderSide(color: appTheme.divider),
                                      textStyle: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    child: const Text('Copy'),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 18),

                            // Footer
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Done'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            }

            if (!mounted) return;
            Navigator.pop(ctx);

            if (url.isNotEmpty) {
              await _showShareLinkDialog(context, url);
            }
          } on FirebaseFunctionsException catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Create failed: ${e.code} ${e.message ?? ''}'),
              ),
            );
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Create failed: $e')));
          } finally {
            if (mounted) setState(() => _busy = false);
            setLocalState(() => submitting = false);
          }
        }

        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            final canCreate =
                firstCtrl.text.trim().isNotEmpty &&
                lastCtrl.text.trim().isNotEmpty &&
                !submitting;
            return Theme(
              data: theme.copyWith(
                // Compact text inside the dialog only
                textTheme: theme.textTheme.copyWith(
                  bodyMedium: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                  ),
                  bodySmall: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                  labelSmall: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                  ),
                ),
                // Compact input styling for all fields in this dialog
                inputDecorationTheme: theme.inputDecorationTheme.copyWith(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: appTheme.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: appTheme.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: AppColors.brandBlue.withOpacity(0.90),
                      width: 1.2,
                    ),
                  ),
                ),
              ),
              child: Dialog(
                backgroundColor:
                    appTheme.contentBackground, // ✅ app theme surface
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header row with close "X"
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Create new request',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  color: const Color(0xFF101828),
                                  height: 1.1,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close',
                              onPressed: submitting
                                  ? null
                                  : () => Navigator.pop(ctx),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Divider(
                          color: appTheme.divider, // ✅ app theme divider token
                          height: 1,
                        ),
                        const SizedBox(height: 14),

                        // Form
                        // ✅ Form (scrollable area so footer stays visible)
                        Flexible(
                          child: SingleChildScrollView(
                            child: Form(
                              key: formKey,
                              autovalidateMode: triedSubmit
                                  ? AutovalidateMode.onUserInteraction
                                  : AutovalidateMode.disabled,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const _FieldHeader(
                                              'Client first name',
                                            ),
                                            TextFormField(
                                              controller: firstCtrl,
                                              textInputAction:
                                                  TextInputAction.next,
                                              decoration: const InputDecoration(
                                                hintText: 'Enter first name',
                                              ),
                                              validator: (v) {
                                                if ((v ?? '').trim().isEmpty) {
                                                  return 'First name is required.';
                                                }
                                                return null;
                                              },
                                              onChanged: (_) =>
                                                  setLocalState(() {}),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const _FieldHeader(
                                              'Client last name',
                                            ),
                                            TextFormField(
                                              controller: lastCtrl,
                                              textInputAction:
                                                  TextInputAction.next,
                                              decoration: const InputDecoration(
                                                hintText: 'Enter last name',
                                              ),
                                              validator: (v) {
                                                if ((v ?? '').trim().isEmpty) {
                                                  return 'Last name is required.';
                                                }
                                                return null;
                                              },
                                              onChanged: (_) =>
                                                  setLocalState(() {}),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 10),

                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _FieldHeader(
                                        'Business name (optional)',
                                        helper: _suggestionsLoaded
                                            ? 'Start typing to see suggestions'
                                            : null,
                                      ),
                                      Autocomplete<String>(
                                        optionsBuilder: (value) {
                                          final q = value.text.toLowerCase();
                                          if (q.isEmpty)
                                            return const Iterable<
                                              String
                                            >.empty();
                                          return _businessNames.where(
                                            (b) => b.toLowerCase().contains(q),
                                          );
                                        },
                                        onSelected: (v) {
                                          businessCtrl.text = v;
                                          FocusScope.of(ctx).nextFocus();
                                        },
                                        fieldViewBuilder:
                                            (_, ctrl, focusNode, __) {
                                              ctrl.addListener(
                                                () => businessCtrl.text =
                                                    ctrl.text,
                                              );
                                              if (ctrl.text !=
                                                  businessCtrl.text) {
                                                ctrl.text = businessCtrl.text;
                                                ctrl.selection =
                                                    TextSelection.collapsed(
                                                      offset: ctrl.text.length,
                                                    );
                                              }
                                              return TextField(
                                                controller: ctrl,
                                                focusNode: focusNode,
                                                textInputAction:
                                                    TextInputAction.next,
                                                enabled: !submitting,
                                                decoration: const InputDecoration(
                                                  hintText:
                                                      'Business / entity name',
                                                ),
                                              );
                                            },
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 10),

                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _FieldHeader(
                                        'Client email (optional)',
                                        helper: _suggestionsLoaded
                                            ? 'Type 3+ characters to see suggestions'
                                            : null,
                                      ),
                                      Autocomplete<String>(
                                        optionsBuilder: (value) {
                                          final q = value.text.toLowerCase();
                                          if (q.length < 3)
                                            return const Iterable<
                                              String
                                            >.empty();
                                          return _clientEmails.where(
                                            (e) => e.toLowerCase().contains(q),
                                          );
                                        },
                                        onSelected: (v) {
                                          emailCtrl.text = v;
                                          FocusScope.of(ctx).nextFocus();
                                        },
                                        fieldViewBuilder:
                                            (_, ctrl, focusNode, __) {
                                              ctrl.addListener(
                                                () =>
                                                    emailCtrl.text = ctrl.text,
                                              );
                                              if (ctrl.text != emailCtrl.text) {
                                                ctrl.text = emailCtrl.text;
                                                ctrl.selection =
                                                    TextSelection.collapsed(
                                                      offset: ctrl.text.length,
                                                    );
                                              }
                                              return TextField(
                                                controller: ctrl,
                                                focusNode: focusNode,
                                                keyboardType:
                                                    TextInputType.emailAddress,
                                                textInputAction:
                                                    TextInputAction.next,
                                                enabled: !submitting,
                                                decoration:
                                                    const InputDecoration(
                                                      hintText:
                                                          'name@domain.com',
                                                    ),
                                              );
                                            },
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 10),

                                  const _FieldHeader('Link expiration'),
                                  DropdownButtonFormField<int>(
                                    value: expirationDays,
                                    decoration: const InputDecoration(
                                      hintText: 'Choose expiration',
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 7,
                                        child: Text('7 days'),
                                      ),
                                      DropdownMenuItem(
                                        value: 14,
                                        child: Text('14 days'),
                                      ),
                                      DropdownMenuItem(
                                        value: 30,
                                        child: Text('30 days'),
                                      ),
                                      DropdownMenuItem(
                                        value: 60,
                                        child: Text('60 days'),
                                      ),
                                      DropdownMenuItem(
                                        value: 90,
                                        child: Text('90 days'),
                                      ),
                                    ],
                                    onChanged: submitting
                                        ? null
                                        : (v) {
                                            if (v == null) return;
                                            expirationDays = v;
                                            setLocalState(() {});
                                          },
                                  ),

                                  const SizedBox(height: 14),
                                  Divider(color: appTheme.divider),
                                  const SizedBox(height: 12),
                                  sectionLabel('Message'),

                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _FieldHeader(
                                        'Message template',
                                        helper: _templatesLoaded
                                            ? 'Select a template to auto-fill the description'
                                            : null,
                                      ),
                                      DropdownButtonFormField<String>(
                                        value: selectedTemplateId,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                          hintText: 'Choose a template',
                                        ),
                                        items: [
                                          const DropdownMenuItem<String>(
                                            value: '__none__',
                                            child: Text('— No template —'),
                                          ),
                                          ..._messageTemplates.map(
                                            (t) => DropdownMenuItem<String>(
                                              value: t.id,
                                              child: Text(t.title),
                                            ),
                                          ),
                                        ],
                                        onChanged: submitting
                                            ? null
                                            : (id) async {
                                                if (id == null) return;

                                                if (id == '__none__') {
                                                  selectedTemplateId = null;
                                                  setLocalState(() {});
                                                  return;
                                                }

                                                selectedTemplateId = id;

                                                final t = _messageTemplates
                                                    .firstWhere(
                                                      (e) => e.id == id,
                                                    );

                                                // ✅ Build token values
                                                final senderName =
                                                    await _resolveSenderName();
                                                final clientName =
                                                    _resolveClientName(
                                                      firstCtrl: firstCtrl,
                                                      lastCtrl: lastCtrl,
                                                    );
                                                final clientFirstName =
                                                    _resolveClientFirstName(
                                                      firstCtrl: firstCtrl,
                                                    );

                                                // ✅ Fill from the TEMPLATE BODY (not from current text)
                                                final filled =
                                                    _applyTemplateTokens(
                                                      t.body,
                                                      senderName: senderName,
                                                      clientName: clientName,
                                                      clientFirstName:
                                                          clientFirstName,
                                                    );

                                                // ✅ Only overwrite if user hasn't typed anything
                                                if (messageCtrl.text
                                                    .trim()
                                                    .isEmpty) {
                                                  messageCtrl.text = filled;
                                                }

                                                setLocalState(() {});
                                              },
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 10),

                                  // ✅ Give Description more visible space
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const _FieldHeader(
                                        'Description (optional)',
                                      ),
                                      TextField(
                                        controller: messageCtrl,
                                        minLines: 6,
                                        maxLines: 10,
                                        decoration: const InputDecoration(
                                          hintText:
                                              'Explain what documents are needed',
                                          alignLabelWithHint: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),
                        Divider(
                          color: appTheme.divider, // ✅ app theme divider token
                          height: 1,
                        ),
                        const SizedBox(height: 12),

                        // Actions
                        Row(
                          children: [
                            Text(
                              submitting ? 'Creating…' : '',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF667085),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: submitting
                                  ? null
                                  : () => Navigator.pop(ctx),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              height: 36,
                              child: FilledButton(
                                onPressed: canCreate
                                    ? () => submit(setLocalState)
                                    : null,
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.brandBlue,
                                  foregroundColor: theme.colorScheme.onPrimary,
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text('Create'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    firstCtrl.dispose();
    lastCtrl.dispose();
    emailCtrl.dispose();
    businessCtrl.dispose();
    messageCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rid = _deepLinkRid;

    // ✅ DEEP‑LINK HANDLER
    if (rid != null && rid.trim().isNotEmpty) {
      return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: _loadDropoff(rid),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (snap.hasError) {
            return const _InvalidRequestLinkState();
          }

          if (!snap.hasData || !snap.data!.exists) {
            return const _InvalidRequestLinkState();
          }

          final data = snap.data!.data() ?? {};
          final url = (data['url'] ?? '').toString().trim();
          final status = (data['status'] ?? '').toString().toLowerCase().trim();

          // ✅ Treat incomplete / deleted requests as invalid links
          if (url.isEmpty || status == 'deleted') {
            return const _InvalidRequestLinkState();
          }

          // ✅ Valid
          return DropoffDetailScreen(requestId: rid);
        },
      );
    }

    // ✅ NORMAL LIST VIEW (your existing UI)
    return PageScaffold(
      title: 'Link Requests',
      subtitle: 'View, manage, and share secure upload links with clients.',
      wrapInCard: false,
      scrollable: false,
      maxContentWidth: 1400,
      child: Expanded(
        child: Stack(
          children: [
            Positioned.fill(
              child: _WhiteCard(
                child: _RequestsList(
                  db: _db,
                  busy: _busy,
                  view: _view,
                  onViewChanged: (v) => setState(() {
                    _view = v;
                    _lastView = v;
                  }),
                  onSelect: (rid) {
                    if (widget.onOpenDetails != null) {
                      widget.onOpenDetails!(rid);
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DropoffDetailScreen(requestId: rid),
                      ),
                    );
                  },
                  onSetStatus: _setDropoffStatus,
                  onBulkDelete: _bulkDeleteDropoffRequests,
                  onArchive: _deleteDropoffRequest,
                  onPurge: _purgeDropoffRequest,
                  onCreate: _busy ? null : _openCreateRequestDialog,
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
      ),
    );
  }
}

class _RequestsList extends StatefulWidget {
  final FirebaseFirestore db;
  final bool busy;
  final _LinksView view;
  final ValueChanged<_LinksView> onViewChanged;

  final VoidCallback? onCreate; // ✅ ADD
  final void Function(String requestId) onSelect;
  final Future<void> Function(String requestId, String status) onSetStatus;
  final Future<void> Function(
    List<String> requestIds, {
    required bool isArchived,
  })
  onBulkDelete;
  final Future<void> Function(String requestId) onArchive;
  final Future<void> Function(String requestId) onPurge;

  const _RequestsList({
    required this.db,
    required this.busy,
    required this.view,
    required this.onViewChanged,
    required this.onSelect,
    required this.onSetStatus,
    required this.onBulkDelete,

    // ✅ ADD THESE
    required this.onArchive,
    required this.onPurge,
    this.onCreate, // ✅ ADD
  });

  @override
  State<_RequestsList> createState() => _RequestsListState();
}

class _RequestsListState extends State<_RequestsList> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _q = '';

  // Multi-select
  final Set<String> _selected = {};

  // Sorting (local sort to avoid new indexes)
  _DropoffSortField _sortField = _DropoffSortField.createdAt;
  bool _sortAsc = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleSort(_DropoffSortField field) {
    setState(() {
      if (_sortField == field) {
        _sortAsc = !_sortAsc;
      } else {
        _sortField = field;
        // default direction: created/lastUpload desc, others asc
        _sortAsc =
            !(field == _DropoffSortField.createdAt ||
                field == _DropoffSortField.lastUploadedAt);
      }
    });
  }

  String _formatDate(DateTime dt) {
    return '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.year}';
  }

  String _formatDateTime(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final y = dt.year.toString();

    int hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    hour = hour % 12;
    if (hour == 0) hour = 12;

    return '$m/$d/$y • $hour:$minute $ampm';
  }

  DateTime? _asDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return null;
  }

  Widget _searchField() {
    return SizedBox(
      width: 360,
      height: 36,
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() {
          _q = v.trim().toLowerCase();
          _selected.clear();
        }),
        decoration: InputDecoration(
          hintText: 'Search requests',
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: _q.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() {
                      _q = '';
                      _selected.clear();
                    });
                  },
                ),
          isDense: true,
          filled: true,
          fillColor: const Color(0xFFF9FAFB),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE4E7EC)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE4E7EC)),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  Widget _bulkBar(ThemeData theme) {
    final count = _selected.length;

    return Row(
      mainAxisSize: MainAxisSize.min, // ✅ prevents taking the whole row
      children: [
        Text(
          '$count selected',
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFF667085),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 36,
          child: FilledButton.icon(
            onPressed: widget.busy
                ? null
                : () async {
                    final ids = _selected.toList(growable: false);
                    if (ids.isEmpty) return;

                    await widget.onBulkDelete(
                      ids,
                      isArchived: widget.view == _LinksView.archived,
                    );

                    if (!mounted) return;
                    setState(() => _selected.clear());

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Delete requested for ${ids.length} link(s).',
                        ),
                      ),
                    );
                  },
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(
              widget.view == _LinksView.archived
                  ? 'Delete permanently ($count)'
                  : 'Delete ($count)',
            ),
          ),
        ),
      ],
    );
  }

  Widget _sortBar(ThemeData theme) {
    return Row(
      children: [
        Text(
          'Sort:',
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFF667085),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        DropdownButton<_DropoffSortField>(
          value: _sortField,
          underline: const SizedBox.shrink(),
          onChanged: (v) {
            if (v == null) return;
            _toggleSort(v);
          },
          items: const [
            DropdownMenuItem(
              value: _DropoffSortField.clientName,
              child: Text('Client name'),
            ),
            DropdownMenuItem(
              value: _DropoffSortField.createdAt,
              child: Text('Date created'),
            ),
            DropdownMenuItem(
              value: _DropoffSortField.lastUploadedAt,
              child: Text('Latest upload'),
            ),
            DropdownMenuItem(
              value: _DropoffSortField.fileCount,
              child: Text('File count'),
            ),
            DropdownMenuItem(
              value: _DropoffSortField.status,
              child: Text('Status'),
            ),
          ],
        ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: _sortAsc ? 'Ascending' : 'Descending',
          onPressed: () => setState(() => _sortAsc = !_sortAsc),
          icon: Icon(
            _sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
            size: 18,
            color: const Color(0xFF475467),
          ),
        ),
      ],
    );
  }

  Widget _searchFieldFullWidth() {
    return SizedBox(height: 36, width: double.infinity, child: _searchField());
  }

  Widget _buildToolbar(ThemeData theme, bool isMobile) {
    final hasSelection = _selected.isNotEmpty;

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sortBar(theme),
          const SizedBox(height: 10),
          _searchFieldFullWidth(), // ✅ better on mobile
          if (hasSelection) ...[const SizedBox(height: 10), _bulkBar(theme)],
        ],
      );
    }

    // Desktop layout: Sort + Search adjacent, bulk on far right
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _sortBar(theme),
        const SizedBox(width: 12),

        // ✅ Search directly next to Sort, but can shrink if needed
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: _searchField(),
          ),
        ),

        const Spacer(),

        // ✅ Bulk actions on the same row (right side)
        if (hasSelection) _bulkBar(theme),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = MediaQuery.of(context).size.width < 600;

    final uid = FirebaseAuth.instance.currentUser!.uid;

    final isArchivedView = widget.view == _LinksView.archived;

    final Query<Map<String, dynamic>> query = isArchivedView
        ? widget.db
              .collection('dropoff_requests')
              .where('createdByUid', isEqualTo: uid)
              .where('status', isEqualTo: 'deleted')
              .orderBy(
                'deletedAt',
                descending: true,
              ) // best: shows recently archived first
              .limit(100)
        : widget.db
              .collection('dropoff_requests')
              .where('createdByUid', isEqualTo: uid)
              .where('status', whereIn: ['open', 'closed', 'expired'])
              .orderBy('createdAt', descending: true)
              .limit(100);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─────────────────────────────────────
              // Row 1: Create + View toggles
              // ─────────────────────────────────────
              Row(
                children: [
                  SizedBox(
                    height: 36,
                    child: FilledButton.icon(
                      onPressed: widget.busy ? null : widget.onCreate,
                      icon: const Icon(Icons.add_link, size: 18),
                      label: const Text(
                        'Create link',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brandBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),

                  Wrap(
                    spacing: 10,
                    children: [
                      ChoiceChip(
                        label: const Text('Active'),
                        selected: widget.view == _LinksView.active,
                        onSelected: (v) {
                          if (!v) return;
                          widget.onViewChanged(_LinksView.active);
                          setState(() {
                            _selected.clear();
                            _q = '';
                            _searchCtrl.clear();
                          });
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Archived'),
                        selected: widget.view == _LinksView.archived,
                        onSelected: (v) {
                          if (!v) return;
                          widget.onViewChanged(_LinksView.archived);
                          setState(() {
                            _selected.clear();
                            _q = '';
                            _searchCtrl.clear();
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ─────────────────────────────────────
              // Row 2: Sort + Search
              // ─────────────────────────────────────
              // ─────────────────────────────────────
              // Row 2: Unified toolbar (Sort + Search + Bulk)
              // ─────────────────────────────────────
              _buildToolbar(theme, isMobile),

              const SizedBox(height: 10),
            ],
          ),

          const SizedBox(height: 10),

          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: query.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Text(
                    'Failed to load: ${snap.error}',
                    style: const TextStyle(color: Colors.red),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allDocs = snap.data!.docs;

                // Filter
                final docs = _q.isEmpty
                    ? allDocs
                    : allDocs.where((doc) {
                        final data = doc.data();

                        final name = (data['clientName'] ?? '')
                            .toString()
                            .toLowerCase();
                        final email = (data['clientEmail'] ?? '')
                            .toString()
                            .toLowerCase();
                        final business = (data['businessName'] ?? '')
                            .toString()
                            .toLowerCase();
                        final id = doc.id.toLowerCase();
                        return name.contains(_q) ||
                            email.contains(_q) ||
                            business.contains(_q) ||
                            id.contains(_q);
                      }).toList();

                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      _q.isEmpty
                          ? 'No request links yet.'
                          : 'No results found.',
                      style: const TextStyle(color: Color(0xFF667085)),
                    ),
                  );
                }

                // Normalize rows
                final rows = docs.map((d) {
                  final data = d.data();
                  final email = (data['clientEmail'] ?? '').toString();
                  final name = (data['clientName'] ?? '').toString();
                  final url = (data['url'] ?? '').toString();
                  final status = (data['status'] ?? 'open').toString();
                  final isArchived = status.toLowerCase().trim() == 'deleted';
                  final businessName = (data['businessName'] ?? '').toString();

                  final fileCount = (data['fileCount'] is num)
                      ? (data['fileCount'] as num).toInt()
                      : 0;

                  final createdAt = _asDate(data['createdAt']);
                  final lastUploadedAt = _asDate(data['lastUploadedAt']);

                  final title = name.isNotEmpty
                      ? name
                      : (email.isNotEmpty ? email : d.id);

                  return _DropoffRowModel(
                    id: d.id,
                    title: title,
                    email: email,
                    businessName: businessName,
                    url: url,
                    status: status,
                    fileCount: fileCount,
                    createdAt: createdAt,
                    lastUploadedAt: lastUploadedAt,
                  );
                }).toList();

                // Sort (local)
                int cmpString(String a, String b) =>
                    a.toLowerCase().compareTo(b.toLowerCase());

                int cmpDate(DateTime? a, DateTime? b) {
                  if (a == null && b == null) return 0;
                  if (a == null) return -1;
                  if (b == null) return 1;
                  return a.compareTo(b);
                }

                rows.sort((a, b) {
                  int res;
                  switch (_sortField) {
                    case _DropoffSortField.clientName:
                      res = cmpString(a.title, b.title);
                      break;
                    case _DropoffSortField.createdAt:
                      res = cmpDate(a.createdAt, b.createdAt);
                      break;
                    case _DropoffSortField.lastUploadedAt:
                      res = cmpDate(a.lastUploadedAt, b.lastUploadedAt);
                      break;
                    case _DropoffSortField.fileCount:
                      res = a.fileCount.compareTo(b.fileCount);
                      break;
                    case _DropoffSortField.status:
                      res = cmpString(a.status, b.status);
                      break;
                  }
                  return _sortAsc ? res : -res;
                });

                final visibleIds = rows.map((e) => e.id).toSet();
                final allSelected =
                    rows.isNotEmpty && _selected.containsAll(visibleIds);

                // Header line: Select all (enterprise)
                return Column(
                  children: [
                    Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.black.withOpacity(0.06),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Checkbox(
                            value: allSelected,
                            onChanged: widget.busy
                                ? null
                                : (v) {
                                    setState(() {
                                      if (v == true) {
                                        _selected.addAll(visibleIds);
                                      } else {
                                        _selected.removeAll(visibleIds);
                                      }
                                    });
                                  },
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Client',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF475467),
                              ),
                            ),
                          ),
                          if (!isMobile) ...[
                            SizedBox(
                              width: 110,
                              child: Text(
                                'Files',
                                textAlign: TextAlign.right,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF475467),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 140,
                              child: Text(
                                'Created',
                                textAlign: TextAlign.right,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF475467),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 150,
                              child: Text(
                                'Latest upload',
                                textAlign: TextAlign.right,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF475467),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          const SizedBox(width: 78), // actions area
                        ],
                      ),
                    ),

                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(0),
                        itemCount: rows.length,
                        itemBuilder: (context, i) {
                          final r = rows[i];
                          final selected = _selected.contains(r.id);

                          final createdText = r.createdAt != null
                              ? _formatDate(r.createdAt!)
                              : '';
                          final lastUploadText = r.lastUploadedAt != null
                              ? _formatDate(r.lastUploadedAt!)
                              : '';

                          final rowIsArchived =
                              r.status.toLowerCase().trim() == 'deleted';

                          return _DenseRequestRow(
                            busy: widget.busy,
                            archived: rowIsArchived,
                            selected: selected,
                            onSelected: (v) {
                              setState(() {
                                if (v) {
                                  _selected.add(r.id);
                                } else {
                                  _selected.remove(r.id);
                                }
                              });
                            },
                            onTap: () => widget.onSelect(r.id),
                            statusColor: _statusAccent(
                              r.status.toLowerCase().trim(),
                            ),
                            title: r.title,
                            email: r.email,
                            businessName: r.businessName,
                            fileCount: r.fileCount,
                            createdText: createdText,
                            lastUploadText: lastUploadText,
                            url: r.url,
                            status: r.status,

                            onToggleStatus: (nextStatus) =>
                                widget.onSetStatus(r.id, nextStatus),

                            // ✅ ADD THESE TWO
                            requestId: r.id,
                            onDelete: (isArchived) async {
                              if (isArchived) {
                                await widget.onPurge(r.id);
                              } else {
                                await widget.onArchive(r.id);
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DropoffRowModel {
  final String id;
  final String title; // clientName (primary)
  final String email; // clientEmail
  final String businessName; // businessName (optional)
  final String url;
  final String status;
  final int fileCount;
  final DateTime? createdAt;
  final DateTime? lastUploadedAt;

  _DropoffRowModel({
    required this.id,
    required this.title,
    required this.email,
    required this.businessName,
    required this.url,
    required this.status,
    required this.fileCount,
    required this.createdAt,
    required this.lastUploadedAt,
  });
}

class _DenseRequestRow extends StatefulWidget {
  final bool busy;
  final bool selected;
  final bool archived;
  final ValueChanged<bool> onSelected;

  final VoidCallback onTap;
  final Color statusColor;
  final String title;
  final String email;
  final String businessName;
  final int fileCount;
  final String createdText;
  final String lastUploadText;
  final String url;
  final String status;
  final String requestId;
  final Future<void> Function(bool isArchived) onDelete;

  final Future<void> Function(String nextStatus) onToggleStatus;

  const _DenseRequestRow({
    required this.busy,
    required this.archived,
    required this.selected,
    required this.onSelected,
    required this.onTap,
    required this.statusColor,
    required this.title,
    required this.email,
    required this.businessName,
    required this.fileCount,
    required this.createdText,
    required this.lastUploadText,
    required this.url,
    required this.status,
    required this.onToggleStatus,
    required this.requestId,
    required this.onDelete,
  });

  @override
  State<_DenseRequestRow> createState() => _DenseRequestRowState();
}

class _DenseRequestRowState extends State<_DenseRequestRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = MediaQuery.of(context).size.width < 600;

    final hoverBg = const Color(0xFF101828).withOpacity(0.10);
    final normalBg = Colors.transparent;

    final statusLower = widget.status.toLowerCase().trim();
    final isOpen = statusLower == 'open';
    final isExpired = statusLower == 'expired';

    final isArchived = widget.archived;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.busy ? null : widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            height: isMobile ? 54 : 46,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _hover ? hoverBg : normalBg,
              border: Border(
                bottom: BorderSide(color: Colors.black.withOpacity(0.05)),
              ),
            ),
            child: Row(
              children: [
                Checkbox(
                  value: widget.selected,
                  onChanged: widget.busy
                      ? null
                      : (v) => widget.onSelected(v ?? false),
                ),
                const SizedBox(width: 12),

                // Status dot
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.statusColor,
                  ),
                ),
                const SizedBox(width: 10),

                // Client name + email (mobile-friendly)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final subBits = <String>[
                        if (widget.businessName.trim().isNotEmpty)
                          widget.businessName.trim(),
                        if (widget.email.trim().isNotEmpty) widget.email.trim(),
                      ];

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF101828),
                            ),
                          ),

                          if (subBits.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              subBits.join(
                                ' • ',
                              ), // "Acme LLC • client@email.com"
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: const Color(0xFF667085),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),

                if (!isMobile) ...[
                  SizedBox(
                    width: 110,
                    child: Text(
                      '${widget.fileCount}',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF475467),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 140,
                    child: Text(
                      widget.createdText,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF667085),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 150,
                    child: Text(
                      widget.lastUploadText.isEmpty
                          ? '—'
                          : widget.lastUploadText,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF667085),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],

                const SizedBox(width: 8),

                // Copy link
                IconButton(
                  tooltip: 'Copy link',
                  icon: const Icon(Icons.copy, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 34,
                    height: 34,
                  ),
                  onPressed:
                      (widget.busy ||
                          isArchived ||
                          isExpired ||
                          widget.url.isEmpty)
                      ? null
                      : () async {
                          await Clipboard.setData(
                            ClipboardData(text: widget.url),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Request link copied.'),
                              ),
                            );
                          }
                        },
                ),

                // Actions
                SizedBox(
                  width: 34,
                  height: 34,
                  child: Center(
                    child: PopupMenuButton<String>(
                      tooltip: 'Actions',
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.more_horiz, size: 18),
                      onSelected: (value) async {
                        if (widget.busy) return;

                        if (value == 'view') {
                          widget.onTap();
                          return;
                        }

                        if (value == 'toggle') {
                          await widget.onToggleStatus(
                            isOpen ? 'closed' : 'open',
                          );
                          return;
                        }

                        if (value == 'delete') {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Delete upload link'),
                              content: const Text(
                                'This will permanently remove the upload link and all associated uploads.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () {
                                    if (Navigator.of(context).canPop()) {
                                      Navigator.pop(context);
                                    } else {
                                      Navigator.of(
                                        context,
                                      ).pushNamedAndRemoveUntil(
                                        '/generate-upload-link',
                                        (route) => false,
                                      );
                                    }
                                  },

                                  child: const Text('Back to request links'),
                                ),
                              ],
                            ),
                          );

                          if (confirm != true) return;

                          // If already archived → permanently delete, else archive
                          await widget.onDelete(isArchived);
                          return;
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'view',
                          child: Text('View details'),
                        ),
                        if (!isArchived)
                          PopupMenuItem(
                            value: 'toggle',
                            child: Text(
                              isOpen ? 'Disable link' : 'Enable link',
                            ),
                          ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            'Delete link',
                            style: TextStyle(color: Color(0xFFB42318)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ======= Enterprise helpers (compact, reusable) =======

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _SectionHeader({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF101828),
            height: 1.05,
          ),
        ),
        if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF667085),
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ],
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  final String label;
  final String value;
  const _KeyValueRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: const Color(0xFF667085),
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.labelMedium?.copyWith(
                color: const Color(0xFF344054),
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _InlineTone { neutral, error }

class _InlineMessage extends StatelessWidget {
  final String text;
  final _InlineTone tone;
  const _InlineMessage({required this.text, required this.tone});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = tone == _InlineTone.error
        ? Colors.red.shade700
        : const Color(0xFF667085);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          height: 1.25,
        ),
      ),
    );
  }
}

class _WhiteInset extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const _WhiteInset({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: child,
    );
  }
}

class _MiniStatePill extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final Color border;

  const _MiniStatePill({
    required this.label,
    required this.bg,
    required this.fg,
    required this.border,
  });

  factory _MiniStatePill.deleted() => const _MiniStatePill(
    label: 'Deleted',
    bg: Color(0xFFF2F4F7),
    fg: Color(0xFF667085),
    border: Color(0xFFD0D5DD),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w800,
          fontSize: 11,
          height: 1.0,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase().trim();
    Color bg;
    Color fg;
    String label;

    switch (s) {
      case 'open':
        bg = Colors.green.withOpacity(0.12);
        fg = Colors.green.shade800;
        label = 'Open';
        break;
      case 'closed':
        bg = Colors.red.withOpacity(0.14);
        fg = Colors.red.shade800;
        label = 'Closed';
        break;
      case 'expired':
        bg = Colors.red.withOpacity(0.20);
        fg = const Color.fromARGB(255, 128, 10, 10);
        label = 'Expired';
        break;
      default:
        bg = Colors.amber.withOpacity(0.18);
        fg = Colors.amber.shade900;
        label = status.isEmpty ? '—' : status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 12),
      ),
    );
  }
}

Color _statusAccent(String statusLower) {
  switch (statusLower) {
    case 'open':
      return Colors.green.shade700;
    case 'closed':
      return Colors.red.shade700;
    case 'deleted':
      return Colors.grey.shade600; // ✅ archived
    case 'expired':
      return Colors.red.shade900;
    default:
      return Colors.amber.shade800;
  }
}

class _WhiteCard extends StatelessWidget {
  final Widget child;
  const _WhiteCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: child,
    );
  }
}

class _MessageTemplate {
  final String id;
  final String title;
  final String body;

  _MessageTemplate({required this.id, required this.title, required this.body});
}

class _InvalidRequestLinkState extends StatelessWidget {
  const _InvalidRequestLinkState();

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Upload link unavailable',
      subtitle: 'This link may have been deleted or is invalid.',
      wrapInCard: true,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link_off, size: 48, color: Color(0xFF98A2B3)),
            const SizedBox(height: 16),
            Text(
              'This upload link is no longer available',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please contact your firm if you believe this is an error.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                // ✅ Clear the deep-link from the URL (important on web)
                final uri = Uri(path: '/generate-upload-link');

                // ✅ Replace browser URL + navigator stack
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil(uri.toString(), (route) => false);
              },
              child: const Text('Back to request links'),
            ),
          ],
        ),
      ),
    );
  }
}
