import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/services.dart';
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

  HttpsCallable _callable(String name) => _functions.httpsCallable(name);

  // Admin callables
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
      final res = await _callable(
        'createDropoffRequest',
      ).call({'firstName': firstName, 'lastName': lastName, 'message': msg});

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
    String? contentType,
  }) async {
    setState(() => _busy = true);
    try {
      final res = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('getAdminDownloadUrl')
          .call({
            'storagePath': storagePath,
            'filename': filename,
            'contentType': (contentType ?? '').toString(),
          });

      final data = Map<String, dynamic>.from(res.data as Map);
      final url = (data['url'] ?? '').toString();

      if (url.isEmpty) {
        throw Exception('Could not generate download link.');
      }

      final uri = Uri.parse(url);

      if (!mounted) return;

      // ✅ Safari-safe: second user gesture
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Download ready'),
          content: Text(filename),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                await launchUrl(uri, webOnlyWindowName: '_self');
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Download'),
            ),
          ],
        ),
      );

      final ok = await launchUrl(uri, webOnlyWindowName: '_blank');
      if (!ok) {
        throw Exception('Could not launch download URL.');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Downloading $filename…')));
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
    required this.onSetStatus,
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
              fontWeight: FontWeight.w800,
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

                    final fileCount = (data['fileCount'] is num)
                        ? (data['fileCount'] as num).toInt()
                        : 0;

                    final createdAt = data['createdAt'];
                    final createdText = createdAt is Timestamp
                        ? _formatDate(createdAt.toDate())
                        : '';

                    final title = name.isNotEmpty
                        ? name
                        : (email.isNotEmpty ? email : d.id);
                    final subtitle = name.isNotEmpty
                        ? email
                        : (data['message'] ?? '').toString();

                    final statusLower = status.toLowerCase().trim();
                    final isOpen = statusLower == 'open';

                    return Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 6,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // clickable icon -> view details
                          InkWell(
                            onTap: busy ? null : () => onSelect(d.id),
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(
                                Icons.inbox_outlined,
                                color: AppColors.brandBlue.withOpacity(0.85),
                              ),
                            ),
                          ),

                          const SizedBox(width: 8),

                          // clickable name/meta -> view details
                          Expanded(
                            child: InkWell(
                              onTap: busy ? null : () => onSelect(d.id),
                              borderRadius: BorderRadius.circular(10),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.brandBlue,
                                          ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      subtitle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: const Color(0xFF667085),
                                            fontWeight: FontWeight.w500,
                                          ),
                                    ),
                                    const SizedBox(height: 6),

                                    // metadata: file count + created date
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 4,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.attach_file,
                                              size: 14,
                                              color: Color(0xFF667085),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '$fileCount item${fileCount == 1 ? '' : 's'}',
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                    color: const Color(
                                                      0xFF667085,
                                                    ),
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                          ],
                                        ),
                                        if (createdText.isNotEmpty)
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.calendar_today_outlined,
                                                size: 13,
                                                color: Color(0xFF667085),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Created $createdText',
                                                style: theme
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color: const Color(
                                                        0xFF667085,
                                                      ),
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 10),

                          _StatusPill(status: status),
                          const SizedBox(width: 6),

                          // quick copy
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

                          // more actions: view + toggle
                          Tooltip(
                            message: busy ? 'Working…' : 'More actions',
                            child: PopupMenuButton<String>(
                              enabled: !busy,
                              tooltip: 'More actions',
                              position: PopupMenuPosition.under,
                              icon: Icon(
                                Icons.more_horiz,
                                color: AppColors.brandBlue.withOpacity(0.85),
                              ),
                              onSelected: (value) async {
                                if (busy) return;

                                if (value == 'view') {
                                  onSelect(d.id);
                                  return;
                                }
                                if (value == 'toggle') {
                                  final nextStatus = isOpen ? 'closed' : 'open';
                                  await onSetStatus(d.id, nextStatus);
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
                                      SizedBox(width: 10),
                                      Text(
                                        isOpen ? 'Disable link' : 'Enable link',
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // chevron -> view details
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

  String _formatDate(DateTime dt) {
    return '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.year}';
  }
}

class _DropoffDetailScreen extends StatelessWidget {
  final String requestId;

  final Future<void> Function({
    required String storagePath,
    required String filename,
    String? contentType,
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
      appBar: AppBar(title: const Text('Drop‑Off Details'), elevation: 1),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _WhiteCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: db
                        .collection('dropoff_requests')
                        .doc(requestId)
                        .snapshots(),
                    builder: (context, reqSnap) {
                      if (reqSnap.hasError) {
                        return Text(
                          'Unable to load request details.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }
                      if (!reqSnap.hasData) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 22),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      final reqData = reqSnap.data?.data() ?? {};
                      final dropoffUrl = (reqData['url'] ?? '')
                          .toString()
                          .trim();
                      final status = (reqData['status'] ?? 'open')
                          .toString()
                          .toLowerCase()
                          .trim();
                      final canDelete = status == 'open';

                      // Optional metadata if available (won’t break if missing)
                      final clientName = (reqData['clientName'] ?? '')
                          .toString()
                          .trim();
                      final clientEmail = (reqData['clientEmail'] ?? '')
                          .toString()
                          .trim();
                      final createdAt = reqData['createdAt'];
                      final createdText = createdAt is Timestamp
                          ? _formatDate(createdAt.toDate())
                          : '';

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ===== Header (compact) =====
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  'Drop‑Off Request',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF101828),
                                    height: 1.05,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ),
                              _StatusPill(status: status),
                            ],
                          ),

                          const SizedBox(height: 10),
                          Divider(
                            color: Colors.black.withOpacity(0.06),
                            height: 1,
                          ),
                          const SizedBox(height: 12),

                          // ===== Overview (dense, enterprise) =====
                          if (clientName.isNotEmpty ||
                              clientEmail.isNotEmpty ||
                              createdText.isNotEmpty)
                            _WhiteInset(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (clientName.isNotEmpty)
                                    _KeyValueRow(
                                      label: 'Client',
                                      value: clientName,
                                    ),
                                  if (clientEmail.isNotEmpty)
                                    _KeyValueRow(
                                      label: 'Email',
                                      value: clientEmail,
                                    ),
                                  if (createdText.isNotEmpty)
                                    _KeyValueRow(
                                      label: 'Created',
                                      value: createdText,
                                    ),
                                ],
                              ),
                            ),

                          if (clientName.isNotEmpty ||
                              clientEmail.isNotEmpty ||
                              createdText.isNotEmpty)
                            const SizedBox(height: 12),

                          // ===== Drop-off link (compact, actionable) =====
                          if (dropoffUrl.isNotEmpty) ...[
                            _SectionHeader(
                              title: 'Access link',
                              subtitle:
                                  'Share this link to allow uploads without sign‑in.',
                            ),
                            const SizedBox(height: 8),
                            _WhiteInset(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: SelectableText(
                                      dropoffUrl,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFF475467),
                                            height: 1.2,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Tooltip(
                                    message: 'Copy link',
                                    child: IconButton(
                                      visualDensity: VisualDensity.compact,
                                      constraints:
                                          const BoxConstraints.tightFor(
                                            width: 36,
                                            height: 36,
                                          ),
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
                                              'Link copied to clipboard.',
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],

                          // ===== Uploaded files =====
                          _SectionHeader(
                            title: 'Uploads',
                            subtitle: 'Files submitted for this request.',
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
                                return _InlineMessage(
                                  text: 'Unable to load uploads.',
                                  tone: _InlineTone.error,
                                );
                              }
                              if (!snap.hasData) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }

                              final docs = snap.data!.docs;
                              if (docs.isEmpty) {
                                return _InlineMessage(
                                  text: 'No uploads have been received.',
                                  tone: _InlineTone.neutral,
                                );
                              }

                              return _WhiteInset(
                                padding: EdgeInsets.zero,
                                child: Column(
                                  children: [
                                    for (int i = 0; i < docs.length; i++) ...[
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        child: _FileRow(
                                          data: docs[i].data(),
                                          onDownload:
                                              (path, name, contentType) =>
                                                  onDownload(
                                                    storagePath: path,
                                                    filename: name,
                                                    contentType: contentType,
                                                  ),
                                        ),
                                      ),
                                      if (i != docs.length - 1)
                                        Divider(
                                          color: Colors.black.withOpacity(0.06),
                                          height: 1,
                                        ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 16),

                          // ===== Delete action (compact width, enterprise copy) =====
                          if (canDelete) ...[
                            Divider(
                              color: Colors.black.withOpacity(0.06),
                              height: 1,
                            ),
                            const SizedBox(height: 12),

                            _SectionHeader(
                              title: 'Request administration',
                              subtitle:
                                  'Permanently remove this request and associated uploads.',
                            ),
                            const SizedBox(height: 10),

                            Align(
                              alignment: Alignment.centerLeft,
                              child: IntrinsicWidth(
                                child: SizedBox(
                                  height: 44,
                                  child: OutlinedButton.icon(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                    ),
                                    label: const Text(
                                      'Delete request',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                      side: const BorderSide(color: Colors.red),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                      ),
                                    ),
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('Delete request'),
                                          content: const Text(
                                            'Deleting this request will permanently remove all associated uploads. '
                                            'This action is irreversible.',
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
                              ),
                            ),

                            const SizedBox(height: 10),

                            Text(
                              'Data retention: Deleted requests and their uploads are permanently removed and cannot be recovered.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF667085),
                                fontWeight: FontWeight.w600,
                                height: 1.25,
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

  String _formatDate(DateTime dt) {
    return '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.year}';
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

class _FileRow extends StatefulWidget {
  final Map<String, dynamic> data;
  final void Function(String storagePath, String filename, String? contentType)
  onDownload;

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
    final contentType = (widget.data['contentType'] ?? '').toString();
    final size = (widget.data['sizeBytes'] is num)
        ? (widget.data['sizeBytes'] as num).toInt()
        : 0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: path.isEmpty
            ? null
            : () => widget.onDownload(path, name, contentType),
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
