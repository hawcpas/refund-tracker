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
import '../utils/file_kind.dart';

class DropoffDetailScreen extends StatefulWidget {
  final String requestId;
  final VoidCallback? onBack; // AppShell can provide this

  const DropoffDetailScreen({super.key, required this.requestId, this.onBack});

  @override
  State<DropoffDetailScreen> createState() => _DropoffDetailScreenState();
}

class _BulkFile {
  final String fileId;
  final String storagePath;
  final String filename;
  final String? contentType;

  const _BulkFile({
    required this.fileId,
    required this.storagePath,
    required this.filename,
    required this.contentType,
  });
}

class _FileIconTile extends StatelessWidget {
  const _FileIconTile({required this.fileName, required this.contentType});

  final String fileName;
  final String contentType;

  @override
  Widget build(BuildContext context) {
    final meta = resolveFileMeta(fileName: fileName, contentType: contentType);

    return Tooltip(
      message: meta.tooltip,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: meta.color.withOpacity(0.12), // ✅ tinted background
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
        ),
        alignment: Alignment.center,
        child: Icon(meta.icon, color: meta.color, size: 16),
      ),
    );
  }
}

class _DropoffDetailScreenState extends State<DropoffDetailScreen> {
  bool _busy = false;
  final Set<String> _selectedFileIds = <String>{};
  final Map<String, _BulkFile> _selectedFiles = <String, _BulkFile>{};

  Future<void> _downloadFile({
    required String storagePath,
    required String filename,
    String? contentType,
    required String requestId,
    required String fileId,
  }) async {
    setState(() => _busy = true);
    try {
      final res = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('getDropoffDownloadUrl')
          .call({
            'storagePath': storagePath,
            'filename': filename,
            'contentType': (contentType ?? '').toString(),
            'requestId': requestId,
            'fileId': fileId,
          });

      final data = Map<String, dynamic>.from(res.data as Map);
      final url = (data['url'] ?? '').toString();
      if (url.isEmpty) throw Exception('Could not generate download link.');

      final uri = Uri.parse(url);

      if (!mounted) return;
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
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showPreparingZipDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // ✅ cannot dismiss
      builder: (_) => AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Preparing ZIP…',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Collecting and packaging selected files for download.',
                    style: TextStyle(
                      color: Color(0xFF667085),
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _closePreparingZipDialog() {
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _bulkDownloadSelected() async {
    if (_selectedFiles.isEmpty) return;

    final files = _selectedFiles.values.toList(growable: false);

    // ✅ If only one file selected → use existing single-download flow
    if (files.length == 1) {
      final f = files.first;
      await _downloadFile(
        storagePath: f.storagePath,
        filename: f.filename,
        contentType: f.contentType,
        requestId: widget.requestId,
        fileId: f.fileId,
      );
      return;
    }

    // ✅ If 2+ files selected → create ZIP on server and download it
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download ZIP'),
        content: Text(
          'Create a ZIP containing ${files.length} files and download it?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Download ZIP (${files.length})'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _busy = true);
    _showPreparingZipDialog();

    try {
      final fileIds = files.map((f) => f.fileId).toList(growable: false);

      final res = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('getDropoffZipDownloadUrl')
          .call({'requestId': widget.requestId, 'fileIds': fileIds});

      _closePreparingZipDialog();

      final data = Map<String, dynamic>.from(res.data as Map);
      final url = (data['url'] ?? '').toString();
      if (url.isEmpty) {
        throw Exception('Could not generate ZIP download link.');
      }

      final uri = Uri.parse(url);

      if (!mounted) return;

      // ✅ Web: open same tab to avoid popup blockers
      if (kIsWeb) {
        await launchUrl(uri, webOnlyWindowName: '_self');
      } else {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }

      final count = (data['fileCount'] ?? files.length).toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloading ZIP ($count files)…')),
      );
    } on FirebaseFunctionsException catch (e) {
      _closePreparingZipDialog();
      if (!mounted) return;

      // ✅ Extract real backend cause
      String? cause;
      final details = e.details;
      if (details is Map && details['cause'] != null) {
        cause = details['cause'].toString();
      }

      debugPrint(
        'ZIP ERROR → code=${e.code}, message=${e.message}, cause=$cause',
      );

      final uiMessage = cause == null || cause.isEmpty
          ? 'ZIP download failed. Please try again.'
          : 'ZIP download failed: $cause';

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(uiMessage)));
    } catch (e) {
      _closePreparingZipDialog();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ZIP download failed: $e')));
    } finally {
      // Always close dialog (even if something threw before closing)
      _closePreparingZipDialog();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteDropoffRequest(String requestId) async {
    setState(() => _busy = true);
    try {
      await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('deleteDropoffRequest').call({'requestId': requestId});
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Request link deleted.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final theme = Theme.of(context);

    return PageScaffold(
      title: 'Request link',
      subtitle: 'View details and manage client uploads',
      wrapInCard: false,
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ Busy indicator (replaces old Positioned)
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),

          // ✅ Optional back button
          if (widget.onBack != null) ...[
            TextButton.icon(
              onPressed: _busy ? null : widget.onBack,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to Request Links'),
            ),
            const SizedBox(height: 12),
          ],

          _WhiteCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: db
                    .collection('dropoff_requests')
                    .doc(widget.requestId)
                    .snapshots(),
                builder: (context, reqSnap) {
                  if (reqSnap.hasError) {
                    return const _InlineMessage(
                      text:
                          'This request link could not be loaded. Please contact your firm.',
                      tone: _InlineTone.error,
                    );
                  }

                  if (!reqSnap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 22),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final doc = reqSnap.data!;
                  if (!doc.exists) {
                    return const _InlineMessage(
                      text:
                          'This request link does not exist or has been deleted.',
                      tone: _InlineTone.error,
                    );
                  }

                  final reqData = doc.data() ?? {};
                  final dropoffUrl = (reqData['url'] ?? '').toString().trim();
                  final statusRaw = (reqData['status'] ?? '').toString().trim();

                  // ❌ HARD FAIL: invalid, deleted, or incomplete request
                  if (dropoffUrl.isEmpty ||
                      statusRaw.isEmpty ||
                      statusRaw == 'deleted') {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      widget.onBack?.call();
                    });

                    return const _InlineMessage(
                      text:
                          'This upload link is unavailable or no longer exists.',
                      tone: _InlineTone.error,
                    );
                  }

                  final status = statusRaw.toLowerCase();
                  final canDelete = status == 'open';

                  final clientName = (reqData['clientName'] ?? '')
                      .toString()
                      .trim();
                  final clientEmail = (reqData['clientEmail'] ?? '')
                      .toString()
                      .trim();
                  final businessName = (reqData['businessName'] ?? '')
                      .toString()
                      .trim();
                  final createdAt = reqData['createdAt'];
                  final createdByUid = (reqData['createdByUid'] ?? '')
                      .toString();
                  final createdText = createdAt is Timestamp
                      ? formatDateTimeCompact(createdAt.toDate())
                      : '';

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionHeader(title: 'Request details'),
                      const SizedBox(height: 10),

                      Row(
                        children: [
                          _StatusPill(status: status),
                          const Spacer(),
                          if (status == 'open' || status == 'closed')
                            SizedBox(
                              height: 32,
                              child: OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        await FirebaseFunctions.instanceFor(
                                              region: 'us-central1',
                                            )
                                            .httpsCallable('setDropoffStatus')
                                            .call({
                                              'requestId': widget.requestId,
                                              'status': status == 'open'
                                                  ? 'closed'
                                                  : 'open',
                                            });
                                      },
                                child: Text(
                                  status == 'open'
                                      ? 'Disable link'
                                      : 'Enable link',
                                ),
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(height: 12),
                      Divider(
                        color: Theme.of(context).extension<AppTheme>()!.divider,
                      ),
                      const SizedBox(height: 12),

                      _WhiteInset(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (clientName.isNotEmpty)
                              _KeyValueRow(label: 'Client', value: clientName),
                            if (businessName.isNotEmpty)
                              _KeyValueRow(
                                label: 'Business',
                                value: businessName,
                              ),
                            if (clientEmail.isNotEmpty)
                              _KeyValueRow(label: 'Email', value: clientEmail),
                            if (createdText.isNotEmpty)
                              _KeyValueRow(
                                label: 'Created',
                                value: createdText,
                              ),
                            if (createdByUid.isNotEmpty)
                              FutureBuilder<String>(
                                future: _resolveCreatedByName(createdByUid),
                                builder: (context, snap) => _KeyValueRow(
                                  label: 'Created by',
                                  value: snap.data ?? 'Loading…',
                                ),
                              ),
                          ],
                        ),
                      ),

                      if (dropoffUrl.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        const _SectionHeader(
                          title: 'Access link',
                          subtitle:
                              'Share this link to allow clients to submit documents securely.',
                        ),
                        const SizedBox(height: 8),
                        _WhiteInset(
                          child: Row(
                            children: [
                              Expanded(child: SelectableText(dropoffUrl)),
                              IconButton(
                                icon: const Icon(Icons.copy, size: 18),
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: dropoffUrl),
                                  );
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Link copied to clipboard.',
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),
                      const _SectionHeader(title: 'Uploads'),
                      const SizedBox(height: 8),

                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: db
                            .collection('dropoff_requests')
                            .doc(widget.requestId)
                            .collection('files')
                            .orderBy('createdAt', descending: true)
                            .snapshots(),
                        builder: (context, snap) {
                          if (snap.hasError) {
                            return const _InlineMessage(
                              text: 'Uploads could not be loaded.',
                              tone: _InlineTone.error,
                            );
                          }

                          if (!snap.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          final docs = snap.data!.docs;

                          // ✅ Build selectable map (only non-deleted with a storagePath)
                          final selectable = <String, _BulkFile>{};

                          for (final doc in docs) {
                            final data = doc.data();
                            final isDeleted = data['deleted'] == true;
                            final path = (data['storagePath'] ?? '')
                                .toString()
                                .trim();

                            if (isDeleted || path.isEmpty) continue;

                            selectable[doc.id] = _BulkFile(
                              fileId: doc.id,
                              storagePath: path,
                              filename: (data['originalName'] ?? 'Untitled')
                                  .toString(),
                              contentType: (data['contentType'] ?? '')
                                  .toString(),
                            );
                          }

                          if (docs.isEmpty || selectable.isEmpty) {
                            return const _InlineMessage(
                              text: 'No uploads have been received.',
                              tone: _InlineTone.neutral,
                            );
                          }

                          for (final doc in docs) {
                            final data = doc.data();
                            final isDeleted = data['deleted'] == true;
                            final path = (data['storagePath'] ?? '')
                                .toString()
                                .trim();

                            if (isDeleted || path.isEmpty) continue;

                            selectable[doc.id] = _BulkFile(
                              fileId: doc.id,
                              storagePath: path,
                              filename: (data['originalName'] ?? 'Untitled')
                                  .toString(),
                              contentType: (data['contentType'] ?? '')
                                  .toString(),
                            );
                          }

                          // ✅ Derived selection helpers
                          final selectableIds = selectable.keys.toSet();

                          _selectedFileIds.removeWhere(
                            (id) => !selectableIds.contains(id),
                          );
                          _selectedFiles.removeWhere(
                            (id, _) => !selectableIds.contains(id),
                          );

                          final allSelected =
                              selectableIds.isNotEmpty &&
                              _selectedFileIds.containsAll(selectableIds);

                          // ✅ KEEP YOUR EXISTING FILE LIST / SELECTION / ZIP CODE HERE
                          return _WhiteInset(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                // ✅ Bulk actions header row
                                Container(
                                  height: 44,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
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
                                        onChanged:
                                            (_busy || selectableIds.isEmpty)
                                            ? null
                                            : (v) {
                                                setState(() {
                                                  if (v == true) {
                                                    _selectedFileIds
                                                      ..clear()
                                                      ..addAll(selectableIds);
                                                    _selectedFiles
                                                      ..clear()
                                                      ..addAll(selectable);
                                                  } else {
                                                    _selectedFileIds.clear();
                                                    _selectedFiles.clear();
                                                  }
                                                });
                                              },
                                      ),
                                      Text(
                                        _selectedFileIds.isEmpty
                                            ? 'Select files'
                                            : '${_selectedFileIds.length} selected',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFF475467),
                                            ),
                                      ),
                                      const Spacer(),
                                      SizedBox(
                                        height: 34,
                                        child: FilledButton.icon(
                                          onPressed:
                                              (_busy || _selectedFiles.isEmpty)
                                              ? null
                                              : _bulkDownloadSelected,
                                          icon: const Icon(
                                            Icons.download_for_offline,
                                            size: 18,
                                          ),
                                          label: Text(
                                            _selectedFiles.length <= 1
                                                ? 'Download'
                                                : 'Download ZIP (${_selectedFiles.length})',
                                          ),
                                          style: FilledButton.styleFrom(
                                            backgroundColor:
                                                AppColors.brandBlue,
                                            foregroundColor: Colors.white,
                                            textStyle: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // ✅ File rows
                                for (int i = 0; i < docs.length; i++) ...[
                                  Builder(
                                    builder: (context) {
                                      final d = docs[i];
                                      final data = d.data();

                                      final isDeleted = data['deleted'] == true;
                                      final path = (data['storagePath'] ?? '')
                                          .toString()
                                          .trim();
                                      final name =
                                          (data['originalName'] ?? 'Untitled')
                                              .toString();
                                      final type = (data['contentType'] ?? '')
                                          .toString();

                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        child: _FileRow(
                                          data: data,
                                          requestId: widget.requestId,
                                          fileId: d.id,
                                          selected: _selectedFileIds.contains(
                                            d.id,
                                          ),
                                          onSelected: (v) {
                                            if (isDeleted || path.isEmpty)
                                              return;

                                            setState(() {
                                              if (v) {
                                                _selectedFileIds.add(d.id);
                                                _selectedFiles[d.id] =
                                                    _BulkFile(
                                                      fileId: d.id,
                                                      storagePath: path,
                                                      filename: name,
                                                      contentType: type,
                                                    );
                                              } else {
                                                _selectedFileIds.remove(d.id);
                                                _selectedFiles.remove(d.id);
                                              }
                                            });
                                          },
                                          onDownload:
                                              (p, n, t, requestId, fileId) =>
                                                  _downloadFile(
                                                    storagePath: p,
                                                    filename: n,
                                                    contentType: t,
                                                    requestId: requestId,
                                                    fileId: fileId,
                                                  ),
                                        ),
                                      );
                                    },
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

                      if (canDelete) ...[
                        const SizedBox(height: 20),
                        Divider(color: Colors.black.withOpacity(0.06)),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('Delete upload link'),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFB42318),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onPressed: _busy
                                ? null
                                : () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Delete upload link'),
                                        content: const Text(
                                          'This will permanently remove the upload link and all associated uploads. This action cannot be undone.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: const Text('Cancel'),
                                          ),
                                          FilledButton(
                                            style: FilledButton.styleFrom(
                                              backgroundColor: const Color(
                                                0xFFB42318,
                                              ),
                                            ),
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );

                                    if (confirm != true) return;

                                    await _deleteDropoffRequest(
                                      widget.requestId,
                                    );
                                    widget.onBack?.call();
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
    );
  }

  Future<String> _resolveCreatedByName(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = snap.data();
      if (data == null) return '—';
      final first = (data['firstName'] ?? '').toString().trim();
      final last = (data['lastName'] ?? '').toString().trim();
      final full = ('$first $last').trim();
      if (full.isNotEmpty) return full;
      final dn = (data['displayName'] ?? '').toString().trim();
      if (dn.isNotEmpty) return dn;
      final email = (data['email'] ?? '').toString().trim();
      if (email.isNotEmpty) return email;
      return '—';
    } catch (_) {
      return '—';
    }
  }
}

class _FileRow extends StatefulWidget {
  final Map<String, dynamic> data;

  final String requestId;
  final String fileId;

  final void Function(
    String storagePath,
    String filename,
    String? contentType,
    String requestId,
    String fileId,
  )
  onDownload;

  // ✅ NEW
  final bool selected;
  final ValueChanged<bool> onSelected;

  const _FileRow({
    required this.data,
    required this.requestId,
    required this.fileId,
    required this.onDownload,

    // ✅ NEW
    required this.selected,
    required this.onSelected,
  });

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final name = (widget.data['originalName'] ?? 'Untitled').toString();
    final isDeleted = widget.data['deleted'] == true;
    final path = (widget.data['storagePath'] ?? '').toString();
    final isActionable = !isDeleted && path.trim().isNotEmpty;
    final contentType = (widget.data['contentType'] ?? '').toString();
    final size = (widget.data['sizeBytes'] is num)
        ? (widget.data['sizeBytes'] as num).toInt()
        : 0;

    final createdAtRaw = widget.data['createdAt'];
    final uploadedAt = createdAtRaw is Timestamp ? createdAtRaw.toDate() : null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: (isDeleted || path.isEmpty)
            ? null
            : () => widget.onDownload(
                path,
                name,
                contentType,
                widget.requestId,
                widget.fileId,
              ),
        hoverColor: isDeleted
            ? Colors.transparent
            : Colors.black.withOpacity(0.03),
        splashColor: isDeleted
            ? Colors.transparent
            : Colors.black.withOpacity(0.02),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),

          child: Row(
            children: [
              // ✅ Selection checkbox (disabled when deleted/unavailable)
              // ✅ Selection checkbox — show ONLY when actionable
              if (isActionable)
                Checkbox(
                  value: widget.selected,
                  onChanged: (v) => widget.onSelected(v ?? false),
                )
              else
                const SizedBox(width: 40), // keeps column alignment clean

              _FileIconTile(fileName: name, contentType: contentType),
              const SizedBox(width: 12),

              // File name + uploaded timestamp (stacked, compact)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,

                              // ✅ Keep blue for active/downloadable items
                              color: isDeleted
                                  ? const Color(
                                      0xFF667085,
                                    ) // enterprise neutral gray
                                  : AppColors.brandBlue,

                              // ✅ Strikethrough when deleted (enterprise record state)
                              decoration: isDeleted
                                  ? TextDecoration.lineThrough
                                  : (isActionable && _hovered
                                        ? TextDecoration.underline
                                        : null),

                              // subtle line color so it doesn’t scream
                              decorationColor: const Color(0xFF98A2B3),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (uploadedAt != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Uploaded ${formatDateTimeCompact(uploadedAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: const Color(0xFF667085),
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                        ),
                      ),
                    ],

                    if (isDeleted)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'This file was removed',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: const Color(0xFF667085), // neutral gray
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Size
              Text(
                size == 0 ? '' : _formatSize(size),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: const Color(0xFF667085),
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(width: 8),

              // ✅ Right-side state / action slot (keeps alignment enterprise-clean)
              SizedBox(
                width: 86, // reserved space so rows align consistently
                child: Align(
                  alignment: Alignment.centerRight,
                  child: isActionable
                      ? Icon(
                          Icons.download,
                          size: 18,
                          color: AppColors.brandBlue.withOpacity(
                            _hovered ? 0.75 : 0.55,
                          ),
                        )
                      : (isDeleted
                            ? _MiniStatePill.deleted()
                            : const SizedBox.shrink()),
                ),
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
            'Use client-upload links to let clients upload files securely without logging in.',
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
                'Create client-upload link',
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
