import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import '../widgets/centered_section.dart';

class AdminDropoffsScreen extends StatefulWidget {
  const AdminDropoffsScreen({super.key});

  @override
  State<AdminDropoffsScreen> createState() => _AdminDropoffsScreenState();
}

class _AdminDropoffsScreenState extends State<AdminDropoffsScreen> {
  final _db = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

  bool _busy = false;

  Future<void> _showCreatedLinkDialog(String url) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Drop-off link created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Copy and share this link with your client:'),
            const SizedBox(height: 12),
            SelectableText(
              url,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (ctx.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Link copied to clipboard.')),
                );
              }
            },
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  HttpsCallable _callable(String name) => _functions.httpsCallable(name);

  // ✅ IMPORTANT: Use the same region as the rest of your functions
  HttpsCallable get _deleteDropoffCallable =>
      _functions.httpsCallable('deleteDropoffRequest');

  HttpsCallable get _setDropoffStatusCallable =>
      _functions.httpsCallable('setDropoffStatus');

  PreferredSizeWidget _appBar() {
    return AppBar(
      backgroundColor: AppColors.brandBlue,
      foregroundColor: Colors.white,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      elevation: 2,
      title: const Text('Drop-Off Requests'),
      actions: [
        IconButton(
          tooltip: 'Create drop-off link',
          icon: const Icon(Icons.add_link),
          onPressed: _busy ? null : _showCreateDialog,
        ),
      ],
    );
  }

  Future<void> _showCreateDialog() async {
    final firstCtrl = TextEditingController();
    final lastCtrl = TextEditingController();
    final msgCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create drop-off request'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: firstCtrl,
                decoration: const InputDecoration(
                  labelText: 'First name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: lastCtrl,
                decoration: const InputDecoration(
                  labelText: 'Last name',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: msgCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Message / Instructions (optional)',
                  prefixIcon: Icon(Icons.note_alt_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final firstName = firstCtrl.text.trim();
    final lastName = lastCtrl.text.trim();
    final msg = msgCtrl.text.trim();

    if (firstName.isEmpty || lastName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter first and last name.')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final res = await _callable('createDropoffRequest').call({
        'firstName': firstName,
        'lastName': lastName,
        'message': msg,
        // no email
      });

      final data = Map<String, dynamic>.from(res.data as Map);
      final url = (data['url'] ?? '').toString();
      if (url.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: url));
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            url.isNotEmpty
                ? 'Drop-off link created and copied to clipboard.'
                : 'Drop-off request created.',
          ),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Create failed: ${e.code} ${e.message ?? ''}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Create failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
            'Drop-off ${status == "open" ? "enabled" : "disabled"}',
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

  Future<void> _deleteDropoffRequest(String requestId) async {
    setState(() => _busy = true);
    try {
      await _deleteDropoffCallable.call({'requestId': requestId});

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Drop-off deleted.')));
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

  Future<void> _downloadFile({
    required String storagePath,
    required String filename,
  }) async {
    setState(() => _busy = true);
    try {
      // Call Cloud Function to get a signed download URL (admin-only)
      final res = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('getAdminDownloadUrl')
          .call({
            'storagePath': storagePath,
            'filename': filename, // ✅ ADD THIS
          });

      final data = Map<String, dynamic>.from(res.data as Map);
      final url = (data['url'] ?? '').toString();

      if (url.isEmpty) {
        throw Exception('Could not generate download link.');
      }

      final uri = Uri.parse(url);
      final ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );

      if (!ok) {
        throw Exception('Could not launch download URL.');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download completed for $filename')),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final details = e.details == null ? '' : '\nDetails: ${e.details}';
      final msg = 'Download failed: ${e.code} ${e.message ?? ''}$details';
      debugPrint(msg);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _appBar(),
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 1100;
                  return CenteredSection(
                    maxWidth: isWide ? 1400 : 1100,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: _WhiteCard(
                              child: _RequestsList(
                                db: _db,
                                busy: _busy,
                                onSelect: (rid) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => _DropoffDetailScreen(
                                        requestId: rid,
                                        onDownload: _downloadFile,
                                        onDelete: _deleteDropoffRequest,
                                        onSetStatus:
                                            _setDropoffStatus, // ✅ ADD THIS
                                      ),
                                    ),
                                  );
                                },
                                onSetStatus: _setDropoffStatus,
                              ),
                            ),
                          ),
                          if (isWide) ...[
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: _WhiteCard(
                                child: _HelpPanel(
                                  onCreate: _busy ? null : _showCreateDialog,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
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
      backgroundColor: AppColors.pageBackgroundLight,
    );
  }
}

class _RequestsList extends StatelessWidget {
  final FirebaseFirestore db;
  final bool busy;
  final void Function(String requestId) onSelect;

  final Future<void> Function(String requestId, String status) onSetStatus;

  const _RequestsList({
    required this.db,
    required this.busy,
    required this.onSelect,
    required this.onSetStatus, // ✅ ADD THIS
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Drop-Off Requests',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: const Color(0xFF101828),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Select a request to view uploaded files.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF475467),
              height: 1.25,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: db
                  .collection('dropoff_requests')
                  .orderBy('createdAt', descending: true)
                  .limit(100)
                  .snapshots(),
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

                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Center(child: Text('No drop-off requests yet.'));
                }

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) =>
                      Divider(color: Colors.black.withOpacity(0.06)),
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final data = d.data();
                    final email = (data['clientEmail'] ?? '').toString();
                    final name = (data['clientName'] ?? '').toString();
                    final url = (data['url'] ?? '').toString();
                    final status = (data['status'] ?? 'open').toString();
                    final msg = (data['message'] ?? '').toString();

                    final title = name.isNotEmpty ? name : email;
                    final subtitle = name.isNotEmpty ? email : msg;

                    final statusLower = status.toLowerCase().trim();

                    final isOpen = statusLower == 'open';
                    final isClosed = statusLower == 'closed';

                    final rowOpacity = isClosed ? 0.65 : 1.0;
                    final rowBg = isClosed
                        ? Colors.black.withOpacity(0.03)
                        : Colors.transparent;

                    return AnimatedOpacity(
                      opacity: rowOpacity,
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOut,
                      child: Container(
                        decoration: BoxDecoration(
                          color: rowBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 6,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.inbox_outlined,
                              color: AppColors.brandBlue.withOpacity(0.85),
                            ),
                            const SizedBox(width: 12),

                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title.isEmpty ? d.id : title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.brandBlue,
                                    ),
                                  ),
                                  const SizedBox(height: 2),

                                  // existing subtitle
                                  Text(
                                    subtitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: const Color(0xFF667085),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(width: 10),

                            // ✅ Status pill stays visible
                            _StatusPill(status: status),

                            const SizedBox(width: 6),

                            // ✅ Quick Copy icon (not in the menu)
                            if (url.isNotEmpty)
                              Tooltip(
                                message: busy ? 'Working…' : 'Copy link',
                                child: IconButton(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 36,
                                    height: 36,
                                  ),
                                  icon: const Icon(Icons.copy, size: 18),
                                  onPressed: busy
                                      ? null
                                      : () async {
                                          await Clipboard.setData(
                                            ClipboardData(text: url),
                                          );
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Drop-off link copied.',
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                ),
                              ),

                            // ✅ More actions menu (⋯): View details + Enable/Disable only
                            Tooltip(
                              message: busy ? 'Working…' : 'More actions',
                              child: PopupMenuButton<String>(
                                enabled: !busy,
                                tooltip: 'More actions',
                                position: PopupMenuPosition.under,

                                icon: busy
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(
                                        Icons.more_horiz,
                                        color: AppColors.brandBlue.withOpacity(
                                          0.85,
                                        ),
                                      ),

                                onSelected: (value) async {
                                  if (busy) return;

                                  if (value == 'view') {
                                    onSelect(d.id);
                                    return;
                                  }

                                  if (value == 'toggle') {
                                    final nextStatus = isOpen
                                        ? 'closed'
                                        : 'open';

                                    // Toggle immediately (no confirmation popup)
                                    await onSetStatus(d.id, nextStatus);

                                    // Optional: Undo snackbar (recommended)
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).clearSnackBars();
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            nextStatus == 'closed'
                                                ? 'Drop-off link disabled'
                                                : 'Drop-off link enabled',
                                          ),
                                          action: SnackBarAction(
                                            label: 'Undo',
                                            onPressed: () {
                                              // Best effort: revert (don’t await inside SnackBarAction)
                                              onSetStatus(
                                                d.id,
                                                isOpen ? 'open' : 'closed',
                                              );
                                            },
                                          ),
                                          duration: const Duration(seconds: 4),
                                        ),
                                      );
                                    }
                                  }
                                },

                                itemBuilder: (ctx) => [
                                  const PopupMenuItem<String>(
                                    value: 'view',
                                    child: Row(
                                      children: [
                                        Icon(Icons.open_in_new, size: 18),
                                        SizedBox(width: 10),
                                        Text('View details'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuDivider(),
                                  PopupMenuItem<String>(
                                    value: 'toggle',
                                    child: Row(
                                      children: [
                                        Icon(
                                          isOpen ? Icons.link_off : Icons.link,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          isOpen
                                              ? 'Disable link'
                                              : 'Enable link',
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // ✅ Chevron is now a real button for details (no reliance on row tap)
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 36,
                                height: 36,
                              ),
                              tooltip: 'View details',
                              onPressed: busy ? null : () => onSelect(d.id),
                              icon: Icon(
                                Icons.chevron_right,
                                color: AppColors.brandBlue.withOpacity(0.55),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DropoffDetailScreen extends StatelessWidget {
  final String requestId;

  final Future<void> Function({
    required String storagePath,
    required String filename,
  })
  onDownload;

  final Future<void> Function(String requestId) onDelete;

  const _DropoffDetailScreen({
    required this.requestId,
    required this.onDownload,
    required this.onDelete,
    required this.onSetStatus, // ✅ ADD THIS
  });

  final Future<void> Function(String requestId, String status) onSetStatus;

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.pageBackgroundLight,
      appBar: AppBar(title: const Text('Drop-Off Details')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              _WhiteCard(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                  child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: db
                        .collection('dropoff_requests')
                        .doc(requestId)
                        .snapshots(),
                    builder: (context, reqSnap) {
                      final reqData = reqSnap.data?.data() ?? {};
                      final dropoffUrl = (reqData['url'] ?? '')
                          .toString()
                          .trim();
                      final status = (reqData['status'] ?? 'open')
                          .toString()
                          .toLowerCase()
                          .trim();
                      final canDelete =
                          status ==
                          'open'; // ✅ delete only open (adjust if you want)
                      final isOpen = status == 'open';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // =========================
                          // Header / Summary
                          // =========================
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  'Drop-Off Request',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF101828),
                                  ),
                                ),
                              ),
                              _StatusPill(status: status),
                            ],
                          ),

                          const SizedBox(height: 6),

                          Text(
                            'Request ID: $requestId',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF667085),
                              fontWeight: FontWeight.w500,
                            ),
                          ),

                          const SizedBox(height: 16),
                          const Divider(height: 1),
                          const SizedBox(height: 16),

                          // =========================
                          // Drop‑off Link (Read‑only field)
                          // =========================
                          if (dropoffUrl.isNotEmpty) ...[
                            Text(
                              'Drop‑off Link',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF344054),
                              ),
                            ),
                            const SizedBox(height: 6),

                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF9FAFB),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFE4E7EC),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: SelectableText(
                                      dropoffUrl,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFF475467),
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Tooltip(
                                    message: 'Copy link',
                                    child: IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(Icons.copy, size: 18),
                                      onPressed: () async {
                                        await Clipboard.setData(
                                          ClipboardData(text: dropoffUrl),
                                        );
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Drop-off link copied.',
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 24),
                          ],

                          // =========================
                          // Uploaded Files
                          // =========================
                          Text(
                            'Uploaded Files',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF101828),
                            ),
                          ),
                          const SizedBox(height: 8),

                          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: db
                                .collection('dropoff_requests')
                                .doc(requestId)
                                .collection('files')
                                .orderBy('createdAt', descending: true)
                                .snapshots(),
                            builder: (context, snap) {
                              if (snap.hasError) {
                                return Text(
                                  'Failed to load files: ${snap.error}',
                                  style: const TextStyle(color: Colors.red),
                                );
                              }
                              if (!snap.hasData) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(),
                                );
                              }

                              final docs = snap.data!.docs;
                              if (docs.isEmpty) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text(
                                    'No uploads yet for this request.',
                                  ),
                                );
                              }

                              return Column(
                                children: [
                                  for (int i = 0; i < docs.length; i++) ...[
                                    _FileRow(
                                      data: docs[i].data(),
                                      onDownload: (path, name) => onDownload(
                                        storagePath: path,
                                        filename: name,
                                      ),
                                    ),
                                    if (i != docs.length - 1)
                                      Divider(
                                        color: Colors.black.withOpacity(0.06),
                                      ),
                                  ],
                                ],
                              );
                            },
                          ),

                          const SizedBox(height: 24),

                          // =========================
                          // Danger Zone
                          // =========================
                          if (canDelete) ...[
                            const Divider(height: 1),
                            const SizedBox(height: 16),

                            Text(
                              'Danger Zone',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: Colors.red.shade700,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),

                            SizedBox(
                              height: 44,
                              child: OutlinedButton.icon(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                                label: const Text(
                                  'Delete Drop‑Off',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text(
                                        'Delete Drop‑Off Request',
                                      ),
                                      content: const Text(
                                        'This will permanently delete the drop-off request and all uploaded files. This action cannot be undone.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: const Text('Cancel'),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirm != true) return;
                                  await onDelete(requestId);
                                  if (!context.mounted) return;
                                  Navigator.pop(context);
                                },
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileRow extends StatefulWidget {
  final Map<String, dynamic> data;
  final void Function(String storagePath, String filename) onDownload;

  const _FileRow({required this.data, required this.onDownload});

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (widget.data['originalName'] ?? 'Untitled').toString();
    final path = (widget.data['storagePath'] ?? '').toString();
    final size = (widget.data['sizeBytes'] is num)
        ? (widget.data['sizeBytes'] as num).toInt()
        : 0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: path.isEmpty ? null : () => widget.onDownload(path, name),
        hoverColor: Colors.black.withOpacity(0.03),
        splashColor: Colors.black.withOpacity(0.02),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.insert_drive_file_outlined,
                color: AppColors.brandBlue.withOpacity(0.85),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandBlue,
                    decoration: _hovered ? TextDecoration.underline : null,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                size == 0 ? '' : _formatSize(size),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: const Color(0xFF667085),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.download,
                size: 18,
                color: AppColors.brandBlue.withOpacity(_hovered ? 0.75 : 0.55),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _HelpPanel extends StatelessWidget {
  final VoidCallback? onCreate;
  const _HelpPanel({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Create links',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: const Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Use drop-off links to let clients upload files securely without logging in.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF475467),
              height: 1.25,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 46,
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_link),
              label: const Text(
                'Create drop-off link',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'The link will be copied to your clipboard after creation.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF667085),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
        bg = Colors.red.withOpacity(0.14); // ✅ RED for closed
        fg = Colors.red.shade800;
        label = 'Closed';
        break;
      case 'expired':
        bg = Colors.red.withOpacity(0.20); // ✅ slightly stronger red
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
