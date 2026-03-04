import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';

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

  PreferredSizeWidget _appBar() {
    return AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      elevation: 2,
      title: const Text(
        'Drop-Off Requests',
        style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.2),
      ),
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
      final ref = FirebaseStorage.instance.ref(storagePath);
      final url = await ref.getDownloadURL();

      await Clipboard.setData(ClipboardData(text: url));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download link copied for $filename')),
      );
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
                                      ),
                                    ),
                                  );
                                },
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

  const _RequestsList({
    required this.db,
    required this.busy,
    required this.onSelect,
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

                    return InkWell(
                      onTap: busy ? null : () => onSelect(d.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
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
                            _StatusPill(status: status),
                            const SizedBox(width: 6),

                            // ✅ PASTE THIS RIGHT HERE
                            if (url.isNotEmpty)
                              IconButton(
                                tooltip: 'Copy drop-off link',
                                icon: const Icon(Icons.copy),
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: url),
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Drop-off link copied.'),
                                      ),
                                    );
                                  }
                                },
                              ),

                            Icon(
                              Icons.chevron_right,
                              color: AppColors.brandBlue.withOpacity(0.55),
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
  });

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

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Uploaded Files',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF101828),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Request ID: $requestId',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF667085),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const SizedBox(height: 10),

                          // ✅ Drop-off link section (copyable)
                          if (dropoffUrl.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.brandBlue.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.brandBlue.withOpacity(0.18),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.link,
                                    color: AppColors.brandBlue,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Drop-off Link',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w900,
                                                color: const Color(0xFF101828),
                                              ),
                                        ),
                                        const SizedBox(height: 6),
                                        SelectableText(
                                          dropoffUrl,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                                color: const Color(0xFF475467),
                                                height: 1.25,
                                              ),
                                        ),
                                        const SizedBox(height: 10),
                                        SizedBox(
                                          height: 40,
                                          child: FilledButton.icon(
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
                                            icon: const Icon(
                                              Icons.copy,
                                              size: 18,
                                            ),
                                            label: const Text(
                                              'Copy Link',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            style: FilledButton.styleFrom(
                                              backgroundColor:
                                                  AppColors.brandBlue,
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                          ] else ...[
                            // Optional: show something for older requests created before url was stored
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.amber.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.amber.withOpacity(0.25),
                                ),
                              ),
                              child: Text(
                                'No stored link found for this request (older requests may not have a saved URL).',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                          // ✅ DELETE BUTTON (Step B) — only when open
                          if (canDelete) ...[
                            SizedBox(
                              height: 44,
                              child: OutlinedButton.icon(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                                label: const Text(
                                  'Delete Drop-Off',
                                  style: TextStyle(fontWeight: FontWeight.w900),
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
                                        'Delete Drop-Off Request',
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
                                  Navigator.pop(context); // back to list
                                },
                              ),
                            ),
                            const SizedBox(height: 14),
                          ] else ...[
                            const SizedBox(height: 14),
                          ],

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
                                return const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(16),
                                    child: CircularProgressIndicator(),
                                  ),
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
        bg = Colors.grey.withOpacity(0.14);
        fg = Colors.grey.shade800;
        label = 'Closed';
        break;
      case 'expired':
        bg = Colors.red.withOpacity(0.14);
        fg = Colors.red.shade800;
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
