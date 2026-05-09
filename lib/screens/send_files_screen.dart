import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../utils/file_kind.dart';
import '../widgets/page_scaffold.dart';

class SendFilesScreen extends StatefulWidget {
  const SendFilesScreen({super.key, required this.onOpenFileBox});

  final VoidCallback onOpenFileBox;

  @override
  State<SendFilesScreen> createState() => _SendFilesScreenState();
}

class _SendFilesScreenState extends State<SendFilesScreen> {
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');
  late Future<List<_SecureShareRow>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _loadShares();
  }

  Future<List<_SecureShareRow>> _loadShares() async {
    final res = await _functions.httpsCallable('listSecureFileShares').call();
    final data = Map<String, dynamic>.from(res.data as Map);
    final raw = (data['shares'] is List) ? data['shares'] as List : [];
    return raw
        .map((s) => _SecureShareRow.fromMap(Map<String, dynamic>.from(s)))
        .toList();
  }

  void _refresh() {
    setState(() => _future = _loadShares());
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return '-';
    final loc = MaterialLocalizations.of(context);
    return '${loc.formatShortDate(dt)} ${loc.formatTimeOfDay(TimeOfDay.fromDateTime(dt))}';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return const Color(0xFF067647);
      case 'expired':
        return const Color(0xFFB54708);
      case 'revoked':
        return const Color(0xFFB42318);
      default:
        return const Color(0xFF667085);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return 'Active';
      case 'expired':
        return 'Expired';
      case 'revoked':
        return 'Revoked';
      default:
        return status.isEmpty ? '-' : status;
    }
  }

  Future<void> _copyLink(_SecureShareRow share) async {
    await Clipboard.setData(ClipboardData(text: share.url));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Secure link copied.')));
  }

  Future<void> _revoke(_SecureShareRow share) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke secure share'),
        content: Text(
          'Revoke access for ${share.clientLabel}? The secure link will stop working immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      await _functions.httpsCallable('revokeSecureFileShare').call({
        'shareId': share.shareId,
      });
      _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Secure share revoked.')));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message ?? 'Revoke failed.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showDetails(_SecureShareRow share) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: const Text('Secure share details'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620, maxHeight: 520),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailRow(label: 'Client', value: share.clientLabel),
                  _DetailRow(label: 'Sent by', value: share.senderLabel),
                  _DetailRow(label: 'Sent', value: _fmt(share.createdAt)),
                  _DetailRow(label: 'Expires', value: _fmt(share.expiresAt)),
                  _DetailRow(
                    label: 'Last viewed',
                    value: _fmt(share.lastViewedAt),
                  ),
                  _DetailRow(
                    label: 'Last downloaded',
                    value: _fmt(share.lastDownloadedAt),
                  ),
                  _DetailRow(
                    label: 'Status',
                    value: _statusLabel(share.status),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Files',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: const Color(0xFF344054),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE4E7EC)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: share.files.map((file) {
                        final meta = resolveFileMeta(
                          fileName: file.originalName,
                          contentType: file.contentType,
                        );
                        return ListTile(
                          dense: true,
                          leading: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: meta.color,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              meta.icon,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                          title: Text(
                            file.originalName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () => _copyLink(share),
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy link'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PageScaffold(
      title: 'Send Files',
      subtitle:
          'Create and monitor password-protected file shares sent to clients.',
      wrapInCard: false,
      maxContentWidth: 1400,
      commandBar: FluentCommandBar(
        actions: [
          FluentCommandAction(
            icon: Icons.add_link_outlined,
            label: 'Create secure share',
            onPressed: widget.onOpenFileBox,
            accent: true,
          ),
          FluentCommandAction(
            icon: Icons.refresh,
            label: 'Refresh',
            onPressed: _busy ? null : _refresh,
            accent: false,
          ),
        ],
        overflowActions: const [],
      ),
      child: FutureBuilder<List<_SecureShareRow>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            );
          }

          if (snap.hasError) {
            return _EmptyState(
              icon: Icons.warning_amber_outlined,
              title: 'Unable to load sent files',
              subtitle: 'Please refresh or try again shortly.',
              actionLabel: 'Refresh',
              onAction: _refresh,
            );
          }

          final rows = snap.data ?? const <_SecureShareRow>[];
          if (rows.isEmpty) {
            return _EmptyState(
              icon: Icons.lock_outline,
              title: 'No secure shares yet',
              subtitle:
                  'Select files in File Box and create a secure share to send files to a client.',
              actionLabel: 'Go to File Box',
              onAction: widget.onOpenFileBox,
            );
          }

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 1280,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE4E7EC)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Container(
                      height: 42,
                      color: const Color(0xFFF9FAFB),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: const [
                          Expanded(flex: 2, child: _HeaderText('Client')),
                          SizedBox(width: 96, child: _HeaderText('Files')),
                          SizedBox(width: 170, child: _HeaderText('Sent by')),
                          SizedBox(width: 145, child: _HeaderText('Sent')),
                          SizedBox(width: 145, child: _HeaderText('Expires')),
                          SizedBox(
                            width: 145,
                            child: _HeaderText('Last viewed'),
                          ),
                          SizedBox(width: 96, child: _HeaderText('Status')),
                          SizedBox(
                            width: 116,
                            child: _HeaderText('Actions', alignEnd: true),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE4E7EC)),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: Color(0xFFE4E7EC)),
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        final color = _statusColor(row.status);
                        return InkWell(
                          onTap: () => _showDetails(row),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        row.clientLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: const Color(0xFF101828),
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      if (row.recipientEmail.isNotEmpty)
                                        Text(
                                          row.recipientEmail,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: const Color(0xFF667085),
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 96,
                                  child: Text(
                                    '${row.fileCount}',
                                    style: _cellStyle(theme),
                                  ),
                                ),
                                SizedBox(
                                  width: 170,
                                  child: Text(
                                    row.senderLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: _cellStyle(theme),
                                  ),
                                ),
                                SizedBox(
                                  width: 145,
                                  child: Text(
                                    _fmt(row.createdAt),
                                    style: _cellStyle(theme),
                                  ),
                                ),
                                SizedBox(
                                  width: 145,
                                  child: Text(
                                    _fmt(row.expiresAt),
                                    style: _cellStyle(theme),
                                  ),
                                ),
                                SizedBox(
                                  width: 145,
                                  child: Text(
                                    _fmt(row.lastViewedAt),
                                    style: _cellStyle(theme),
                                  ),
                                ),
                                SizedBox(
                                  width: 96,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.10),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: color.withValues(alpha: 0.22),
                                        ),
                                      ),
                                      child: Text(
                                        _statusLabel(row.status),
                                        style: TextStyle(
                                          color: color,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 116,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      IconButton(
                                        tooltip: 'Copy link',
                                        icon: const Icon(Icons.copy, size: 17),
                                        onPressed: () => _copyLink(row),
                                      ),
                                      IconButton(
                                        tooltip: 'Revoke',
                                        icon: const Icon(
                                          Icons.block_outlined,
                                          size: 17,
                                        ),
                                        onPressed:
                                            (_busy || row.status != 'active')
                                            ? null
                                            : () => _revoke(row),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  TextStyle? _cellStyle(ThemeData theme) {
    return theme.textTheme.bodySmall?.copyWith(
      color: const Color(0xFF475467),
      fontWeight: FontWeight.w700,
    );
  }
}

class _HeaderText extends StatelessWidget {
  const _HeaderText(this.text, {this.alignEnd = false});

  final String text;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: alignEnd ? TextAlign.right : TextAlign.left,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: const Color(0xFF475467),
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.brandBlue, size: 34),
          const SizedBox(height: 12),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: const Color(0xFF101828),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF667085),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.folder_open_outlined, size: 16),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF667085),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF101828),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecureShareRow {
  const _SecureShareRow({
    required this.shareId,
    required this.url,
    required this.recipientName,
    required this.recipientEmail,
    required this.createdByName,
    required this.createdByEmail,
    required this.createdAt,
    required this.expiresAt,
    required this.lastViewedAt,
    required this.lastDownloadedAt,
    required this.status,
    required this.fileCount,
    required this.files,
  });

  final String shareId;
  final String url;
  final String recipientName;
  final String recipientEmail;
  final String createdByName;
  final String createdByEmail;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final DateTime? lastViewedAt;
  final DateTime? lastDownloadedAt;
  final String status;
  final int fileCount;
  final List<_SecureShareFile> files;

  String get clientLabel {
    if (recipientName.trim().isNotEmpty) return recipientName.trim();
    if (recipientEmail.trim().isNotEmpty) return recipientEmail.trim();
    return 'Client';
  }

  String get senderLabel {
    if (createdByName.trim().isNotEmpty) return createdByName.trim();
    if (createdByEmail.trim().isNotEmpty) return createdByEmail.trim();
    return '-';
  }

  factory _SecureShareRow.fromMap(Map<String, dynamic> map) {
    DateTime? date(dynamic v) {
      if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
      return null;
    }

    final rawFiles = (map['files'] is List) ? map['files'] as List : [];
    return _SecureShareRow(
      shareId: (map['shareId'] ?? '').toString(),
      url: (map['url'] ?? '').toString(),
      recipientName: (map['recipientName'] ?? '').toString(),
      recipientEmail: (map['recipientEmail'] ?? '').toString(),
      createdByName: (map['createdByName'] ?? '').toString(),
      createdByEmail: (map['createdByEmail'] ?? '').toString(),
      createdAt: date(map['createdAtMillis']),
      expiresAt: date(map['expiresAtMillis']),
      lastViewedAt: date(map['lastViewedAtMillis']),
      lastDownloadedAt: date(map['lastDownloadedAtMillis']),
      status: (map['status'] ?? '').toString(),
      fileCount: map['fileCount'] is num
          ? (map['fileCount'] as num).toInt()
          : 0,
      files: rawFiles
          .map((f) => _SecureShareFile.fromMap(Map<String, dynamic>.from(f)))
          .toList(),
    );
  }
}

class _SecureShareFile {
  const _SecureShareFile({
    required this.fileId,
    required this.originalName,
    required this.contentType,
    required this.sizeBytes,
  });

  final String fileId;
  final String originalName;
  final String contentType;
  final int sizeBytes;

  factory _SecureShareFile.fromMap(Map<String, dynamic> map) {
    return _SecureShareFile(
      fileId: (map['fileId'] ?? '').toString(),
      originalName: (map['originalName'] ?? 'File').toString(),
      contentType: (map['contentType'] ?? '').toString(),
      sizeBytes: map['sizeBytes'] is num
          ? (map['sizeBytes'] as num).toInt()
          : 0,
    );
  }
}
