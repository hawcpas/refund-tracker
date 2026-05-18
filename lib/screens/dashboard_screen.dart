import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/content_text_zoom.dart';
import '../shell/app_shell.dart';
import '../theme/app_theme.dart';
import '../utils/file_kind.dart';

String? _extractIndexUrl(String message) {
  final m = RegExp(r'https?://\S+').firstMatch(message);
  if (m == null) return null;

  // Firestore messages sometimes end URL with a trailing ')' or '.'
  var url = m.group(0) ?? '';
  url = url.replaceAll(RegExp(r'[)\],.]+$'), '');
  return url;
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardActionCard extends StatelessWidget {
  const _DashboardActionCard({
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final appTheme = Theme.of(context).extension<AppTheme>()!;
    return Container(
      constraints: const BoxConstraints(minHeight: 220), // ✅ taller card
      decoration: BoxDecoration(
        color: appTheme.contentBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 6,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ Blue top accent line (Microsoft style)
          Container(
            height: 3,
            decoration: const BoxDecoration(
              color: AppColors.brandBlue,
              borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ✅ Recommended label (no icon)
                const Text(
                  'Recommended',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandBlue,
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: Color(0xFF374151),
                  ),
                ),

                const SizedBox(height: 20),

                // ✅ Button anchored bottom-left
                SizedBox(
                  height: 34,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: onPressed,
                    child: Text(buttonLabel),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StaticSurface extends StatelessWidget {
  const _StaticSurface({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final appTheme = Theme.of(context).extension<AppTheme>()!;

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: appTheme.contentBackground,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: Colors.black.withOpacity(0.12), width: 1),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Column(children: children),
      ),
    );
  }
}

/// ============================
/// FILE TYPE META (MATCHES File Box)
/// ============================

enum _RecentFileFilter { all, today, week, notSent, pdf, client }

class _RecentUploadsFromActivity extends StatefulWidget {
  const _RecentUploadsFromActivity({required this.isAdmin});

  final bool isAdmin;

  @override
  State<_RecentUploadsFromActivity> createState() =>
      _RecentUploadsFromActivityState();
}

class _RecentUploadsFromActivityState extends State<_RecentUploadsFromActivity> {
  _RecentFileFilter _filter = _RecentFileFilter.all;
  final Set<String> _pinnedFileIds = {};

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream(String uid) {
    return FirebaseFirestore.instance
        .collectionGroup('files')
        .where('deleted', isEqualTo: false) // ✅ never show deleted
        .where(
          'requestCreatedByUid',
          isEqualTo: uid,
        ) // ✅ only files from MY requests
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots();
  }

  String _s(dynamic v) => (v ?? '').toString().trim();

  DateTime? _asDate(dynamic ts) => ts is Timestamp ? ts.toDate() : null;

  int _asInt(dynamic v) => v is num ? v.toInt() : 0;

  String _formatSize(int bytes) {
    if (bytes <= 0) return '-';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _filterLabel(_RecentFileFilter filter) {
    switch (filter) {
      case _RecentFileFilter.all:
        return 'All';
      case _RecentFileFilter.today:
        return 'Today';
      case _RecentFileFilter.week:
        return 'This week';
      case _RecentFileFilter.notSent:
        return 'Not sent';
      case _RecentFileFilter.pdf:
        return 'PDFs';
      case _RecentFileFilter.client:
        return 'By client';
    }
  }

  bool _passesFilter(Map<String, dynamic> m, String fileName, String contentType) {
    final createdAt = _asDate(m['createdAt']);
    final now = DateTime.now();
    final client = _s(m['requestClientName']).isNotEmpty ||
        _s(m['requestClientEmail']).isNotEmpty ||
        _s(m['requestBusinessName']).isNotEmpty;
    final lastAction = _s(m['lastActivityAction']).toLowerCase();
    final sentAt = _asDate(m['sentAt']) ?? _asDate(m['lastSentAt']);

    switch (_filter) {
      case _RecentFileFilter.all:
        return true;
      case _RecentFileFilter.today:
        return createdAt != null &&
            createdAt.year == now.year &&
            createdAt.month == now.month &&
            createdAt.day == now.day;
      case _RecentFileFilter.week:
        return createdAt != null &&
            createdAt.isAfter(now.subtract(const Duration(days: 7)));
      case _RecentFileFilter.notSent:
        return sentAt == null && lastAction != 'sent';
      case _RecentFileFilter.pdf:
        return fileName.toLowerCase().endsWith('.pdf') ||
            contentType.toLowerCase().contains('pdf');
      case _RecentFileFilter.client:
        return client;
    }
  }

  Future<void> _downloadFile(
    BuildContext context,
    Map<String, dynamic> m,
    String fileId,
  ) async {
    final storagePath = _s(m['storagePath']);
    final filename = _s(m['originalName']).isEmpty
        ? 'File'
        : _s(m['originalName']);
    if (storagePath.isEmpty) return;

    try {
      final fn = widget.isAdmin ? 'getAdminDownloadUrl' : 'getDropoffDownloadUrl';
      final res = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable(fn)
          .call({
            'storagePath': storagePath,
            'filename': filename,
            'contentType': _s(m['contentType']),
            'requestId': _s(m['requestId']),
            'fileId': fileId,
          });
      final data = Map<String, dynamic>.from(res.data as Map);
      final url = _s(data['url']);
      if (url.isEmpty) throw Exception('No download URL returned.');
      final uri = Uri.parse(url);
      if (kIsWeb) {
        await launchUrl(uri, webOnlyWindowName: '_self');
      } else {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    }
  }

  String _formatDateTime(BuildContext context, DateTime? dt) {
    if (dt == null) return '-';
    final loc = MaterialLocalizations.of(context);
    return '${loc.formatShortDate(dt)} - ${loc.formatTimeOfDay(TimeOfDay.fromDateTime(dt))}';
  }

  String _relativeTime(DateTime? dt) {
    if (dt == null) return 'Just now';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    return '${diff.inDays} d ago';
  }

  String _fileTypeLabel(String fileName, String contentType) {
    final meta = resolveFileMeta(fileName: fileName, contentType: contentType);
    return meta.tooltip.replaceAll(
      RegExp(r'\s+file$', caseSensitive: false),
      '',
    );
  }

  String _activityLabel(String action) {
    switch (action.toLowerCase().trim()) {
      case 'upload':
        return 'Uploaded';
      case 'view':
        return 'Viewed';
      case 'download':
        return 'Downloaded';
      case 'sent':
        return 'Sent';
      case 'delete':
        return 'Deleted';
      default:
        return action.trim().isEmpty ? 'Activity' : action.trim();
    }
  }

  String _actorFor(Map<String, dynamic> e) {
    final type = _s(e['actorType']);
    final name = _s(e['actorName']);
    final email = _s(e['actorEmail']);
    final who = name.isNotEmpty ? name : (email.isNotEmpty ? email : '-');
    if (type.isEmpty) return who;
    return '${type[0].toUpperCase()}${type.substring(1)} - $who';
  }

  Future<void> _logFileDetailsView({
    required String requestId,
    required String fileId,
  }) async {
    if (requestId.isEmpty || fileId.isEmpty) return;
    try {
      await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('logFileActivity').call({
        'requestId': requestId,
        'fileId': fileId,
        'action': 'view',
        'surface': 'home_details',
      });
    } catch (_) {
      // Best-effort audit logging should never block the file details view.
    }
  }

  Future<void> _showFileDetails(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final m = doc.data();

    final fileName = _s(m['originalName']).isEmpty
        ? 'Untitled'
        : _s(m['originalName']);
    final contentType = _s(m['contentType']);
    final meta = resolveFileMeta(fileName: fileName, contentType: contentType);
    final requestId = _s(m['requestId']);
    final sizeBytes = _asInt(m['sizeBytes']);
    final createdAt = _asDate(m['createdAt']);

    final uploadedBy = m['uploadedBy'];
    final uploaderName = uploadedBy is Map && _s(uploadedBy['name']).isNotEmpty
        ? _s(uploadedBy['name'])
        : _s(m['requestCreatedByName']);
    final uploaderEmail =
        uploadedBy is Map && _s(uploadedBy['email']).isNotEmpty
        ? _s(uploadedBy['email'])
        : _s(m['requestCreatedByEmail']).isNotEmpty
        ? _s(m['requestCreatedByEmail'])
        : _s(m['requestClientEmail']);
    final uploaderRole = uploadedBy is Map && _s(uploadedBy['role']).isNotEmpty
        ? _s(uploadedBy['role'])
        : uploadedBy is Map && _s(uploadedBy['type']).isNotEmpty
        ? _s(uploadedBy['type'])
        : _s(m['requestCreatedByRole']);

    Query<Map<String, dynamic>> auditQuery = FirebaseFirestore.instance
        .collection('file_activity')
        .where('fileId', isEqualTo: doc.id)
        .orderBy('occurredAt', descending: true)
        .limit(8);

    if (requestId.isNotEmpty) {
      auditQuery = FirebaseFirestore.instance
          .collection('file_activity')
          .where('fileId', isEqualTo: doc.id)
          .where('requestId', isEqualTo: requestId)
          .orderBy('occurredAt', descending: true)
          .limit(8);
    }

    if (!context.mounted) return;

    Future<void>.microtask(
      () => _logFileDetailsView(requestId: requestId, fileId: doc.id),
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          title: Row(
            children: [
              _LeadingIconTile(
                icon: meta.icon,
                color: meta.color,
                iconColor: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_fileTypeLabel(fileName, contentType)} - ${_formatSize(sizeBytes)}',
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 620),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _FileDetailsCard(
                    title: 'Overview',
                    icon: Icons.info_outline,
                    children: [
                      _FileDetailRow(
                        label: 'Created',
                        value: _formatDateTime(context, createdAt),
                      ),
                      _FileDetailRow(
                        label: 'Uploaded by',
                        value: uploaderName.isNotEmpty ? uploaderName : '-',
                        secondary: [
                          if (uploaderEmail.isNotEmpty) uploaderEmail,
                          if (uploaderRole.isNotEmpty) uploaderRole,
                        ].join(' - '),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _FileDetailsCard(
                    title: 'Audit activity',
                    icon: Icons.manage_search_outlined,
                    children: [
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: auditQuery.snapshots(),
                        builder: (context, snap) {
                          if (snap.hasError) {
                            return const _AuditEmptyState(
                              text: 'Activity is not available yet.',
                            );
                          }
                          if (!snap.hasData) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 14),
                              child: LinearProgressIndicator(minHeight: 2),
                            );
                          }

                          final events = snap.data!.docs;
                          if (events.isEmpty) {
                            return const _AuditEmptyState(
                              text: 'No tracked activity for this file yet.',
                            );
                          }

                          return Column(
                            children: events.map((event) {
                              final e = event.data();
                              final action = _activityLabel(_s(e['action']));
                              final at = _asDate(e['occurredAt']);
                              final surface = _s(e['surface']);
                              return _AuditEventRow(
                                action: action,
                                actor: _actorFor(e),
                                when: _formatDateTime(context, at),
                                surface: surface,
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.pushNamed(context, '/file-box');
              },
              icon: const Icon(Icons.folder_open_outlined, size: 16),
              label: const Text('Open in File Box'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream(uid),
      builder: (context, snap) {
        if (snap.hasError) {
          final errText = snap.error.toString();
          final url = _extractIndexUrl(errText);
          final projectId = Firebase.app().options.projectId;

          return _DashboardListSection(
            title: 'Recent files',
            subtitle: 'Only files currently visible in File Box.',
            children: [
              _DashboardListRow(
                leadingIcon: Icons.warning_amber_outlined,
                title: 'Failed to load recent files',
                subtitle: url != null
                    ? 'Index required • project: $projectId (tap to copy)'
                    : 'Unexpected error (tap to copy)',
                onTap: () async {
                  final toCopy = url ?? errText;
                  await Clipboard.setData(ClipboardData(text: toCopy));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Error copied to clipboard'),
                      ),
                    );
                  }
                },
              ),
            ],
          );
        }

        if (!snap.hasData) {
          return _DashboardListSection(
            title: 'Recent files',
            subtitle: 'Only files currently visible in File Box.',
            children: const [
              Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Loading…',
                      style: TextStyle(
                        color: Color(0xFF667085),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        final docs = snap.data!.docs;

        if (docs.isEmpty) {
          return _DashboardListSection(
            title: 'Recent files',
            subtitle: 'Only files currently visible in File Box.',
            children: [
              _DashboardListRow(
                leadingIcon: Icons.inbox_outlined,
                title: 'No recent files',
                subtitle: 'No active (non-deleted) files found.',
                onTap: () {},
                enabled: false,
              ),
            ],
          );
        }

        final visibleDocs = docs.where((d) {
          final m = d.data();
          final fileName = _s(m['originalName']).isEmpty
              ? 'Untitled'
              : _s(m['originalName']);
          final contentType = _s(m['contentType']);
          return _passesFilter(m, fileName, contentType);
        }).toList()
          ..sort((a, b) {
            final aPinned = _pinnedFileIds.contains(a.id);
            final bPinned = _pinnedFileIds.contains(b.id);
            if (aPinned == bPinned) return 0;
            return aPinned ? -1 : 1;
          });

        if (visibleDocs.isEmpty) {
          return _DashboardListSection(
            title: 'Recent files',
            subtitle: 'Filter: ${_filterLabel(_filter)}',
            headerTrailing: _RecentFileFilterBar(
              selected: _filter,
              labelFor: _filterLabel,
              onChanged: (value) => setState(() => _filter = value),
            ),
            children: [
              _DashboardListRow(
                leadingIcon: Icons.filter_alt_off_outlined,
                title: 'No matching files',
                subtitle: 'Try a different recent file filter.',
                onTap: () {},
                enabled: false,
              ),
              _DashboardFooterAction(
                label: 'View all in File Box',
                icon: Icons.folder_open_outlined,
                onPressed: () => Navigator.pushNamed(context, '/file-box'),
              ),
            ],
          );
        }

        // Build rows from live file docs (same source as File Box)
        final rows = visibleDocs.map((d) {
          final m = d.data();

          final fileName = _s(m['originalName']).isEmpty
              ? 'Untitled'
              : _s(m['originalName']);
          final contentType = _s(m['contentType']);
          final meta = resolveFileMeta(
            fileName: fileName,
            contentType: contentType,
          );

          final business = _s(m['requestBusinessName']);

          // uploadedBy: { type: "client", name: requestClientName }
          // set in finalizeDropoffUpload [2](https://axumecpa-my.sharepoint.com/personal/guillermo_axumecpas_com/Documents/Personal_Files/Other/Microsoft%20Related/Microsoft%20Copilot%20Chat%20Files/index.js)
          final uploadedBy = m['uploadedBy'];
          final clientName = (uploadedBy is Map) ? _s(uploadedBy['name']) : '';

          final createdAt = _asDate(m['createdAt']);
          final lastActionRaw = _s(m['lastActivityAction']);
          final lastAction = lastActionRaw.isEmpty
              ? 'Uploaded'
              : _activityLabel(lastActionRaw);
          final lastActivityAt = _asDate(m['lastActivityAt']) ?? createdAt;
          final sentAt = _asDate(m['sentAt']) ?? _asDate(m['lastSentAt']);
          final downloadedAt = _asDate(m['lastDownloadedAt']);
          final reviewedAt = _asDate(m['lastViewedAt']);
          final status = downloadedAt != null
              ? 'Downloaded'
              : sentAt != null || lastActionRaw.toLowerCase() == 'sent'
              ? 'Sent'
              : reviewedAt != null || lastActionRaw.toLowerCase() == 'view'
              ? 'Reviewed'
              : 'Not reviewed';
          final pinned = _pinnedFileIds.contains(d.id);
          final subtitleParts = <String>[
            if (clientName.isNotEmpty) 'From $clientName' else 'From Client',
            if (business.isNotEmpty) business,
            '$lastAction ${_relativeTime(lastActivityAt)}',
          ];

          return Tooltip(
            message: meta.tooltip,
            child: _DashboardListRow(
              leadingIcon: meta.icon,
              iconColor: Colors.white,
              leadingColor: meta.color,
              title: fileName,
              subtitle: subtitleParts.join(' • '),
              onTap: () => _showFileDetails(context, d),
              badges: [
                if (pinned) const _StatusBadge(label: 'Pinned'),
                _StatusBadge(label: status),
              ],
              trailing: _DashboardRowMenu(
                actions: [
                  _DashboardMenuAction(
                    icon: pinned ? Icons.star : Icons.star_border_outlined,
                    label: pinned ? 'Unpin file' : 'Pin file',
                    onPressed: () {
                      setState(() {
                        if (pinned) {
                          _pinnedFileIds.remove(d.id);
                        } else {
                          _pinnedFileIds.add(d.id);
                        }
                      });
                    },
                  ),
                  _DashboardMenuAction(
                    icon: Icons.visibility_outlined,
                    label: 'View details',
                    onPressed: () => _showFileDetails(context, d),
                  ),
                  _DashboardMenuAction(
                    icon: Icons.download_outlined,
                    label: 'Download',
                    onPressed: () => _downloadFile(context, m, d.id),
                  ),
                  _DashboardMenuAction(
                    icon: Icons.send_outlined,
                    label: 'Send file',
                    onPressed: () =>
                        Navigator.pushNamed(context, '/send-files/new'),
                  ),
                  if (_s(m['requestId']).isNotEmpty)
                    _DashboardMenuAction(
                      icon: Icons.open_in_new_outlined,
                      label: 'Open request',
                      onPressed: () => Navigator.pushNamed(
                        context,
                        '/generate-upload-link',
                      ),
                    ),
                ],
              ),
            ),
          );
        }).toList();

        // ✅ Hard cap visual height with internal scroll
        return _DashboardListSection(
          title: 'Recent files',
          subtitle: 'Uploaded files with quick actions and activity status.',
          headerTrailing: _RecentFileFilterBar(
            selected: _filter,
            labelFor: _filterLabel,
            onChanged: (value) => setState(() => _filter = value),
          ),
          children: [
            ...rows,
            _DashboardFooterAction(
              label: 'View all in File Box',
              icon: Icons.folder_open_outlined,
              onPressed: () => Navigator.pushNamed(context, '/file-box'),
            ),
          ],
        );
      },
    );
  }
}

String _dashS(dynamic v) => (v ?? '').toString().trim();

DateTime? _dashDate(dynamic v) => v is Timestamp ? v.toDate() : null;

DateTime _startOfToday() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

String _dashRelative(DateTime? dt) {
  if (dt == null) return 'No activity yet';
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  return '${diff.inDays} d ago';
}

class _NeedsAttentionSection extends StatefulWidget {
  const _NeedsAttentionSection({
    required this.uid,
    required this.hasDropoffAccess,
  });

  final String uid;
  final bool hasDropoffAccess;

  @override
  State<_NeedsAttentionSection> createState() => _NeedsAttentionSectionState();
}

class _NeedsAttentionSectionState extends State<_NeedsAttentionSection> {
  late Future<List<_AttentionMetric>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _NeedsAttentionSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid ||
        oldWidget.hasDropoffAccess != widget.hasDropoffAccess) {
      _future = _load();
    }
  }

  Future<List<_AttentionMetric>> _load() async {
    if (!widget.hasDropoffAccess) return const [];

    final filesFuture = FirebaseFirestore.instance
        .collectionGroup('files')
        .where('deleted', isEqualTo: false)
        .where('requestCreatedByUid', isEqualTo: widget.uid)
        .limit(50)
        .get()
        .timeout(const Duration(seconds: 10));
    final requestsFuture = FirebaseFirestore.instance
        .collection('dropoff_requests')
        .where('createdByUid', isEqualTo: widget.uid)
        .where('status', isEqualTo: 'open')
        .limit(50)
        .get()
        .timeout(const Duration(seconds: 10));
    final sharesFuture = _loadShareRows();

    final results = await Future.wait([
      filesFuture,
      requestsFuture,
      sharesFuture,
    ]).timeout(const Duration(seconds: 12));
    final files = (results[0] as QuerySnapshot<Map<String, dynamic>>).docs;
    final requests = (results[1] as QuerySnapshot<Map<String, dynamic>>).docs;
    final shares = results[2] as List<Map<String, dynamic>>;

    final notReviewed = files.where((doc) {
      final m = doc.data();
      final action = _dashS(m['lastActivityAction']).toLowerCase();
      return action != 'view' && action != 'download' && action != 'sent';
    }).length;

    final expiringSoon = shares.where((raw) {
      final m = raw;
      final ms = m['expiresAtMillis'];
      if (ms is! num) return false;
      final expires = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
      final diff = expires.difference(DateTime.now());
      return _dashS(m['status']).toLowerCase() == 'active' &&
          !diff.isNegative &&
          diff.inHours <= 24;
    }).length;

    final openedNotDownloaded = shares.where((raw) {
      final m = raw;
      return m['lastViewedAtMillis'] is num &&
          m['lastDownloadedAtMillis'] is! num &&
          _dashS(m['status']).toLowerCase() == 'active';
    }).length;

    final openNoFiles = requests.where((doc) {
      final m = doc.data();
      final count = m['fileCount'] ?? m['filesCount'] ?? m['uploadCount'];
      return count is! num || count.toInt() == 0;
    }).length;

    return [
      _AttentionMetric(
        icon: Icons.mark_email_unread_outlined,
        label: 'Files not reviewed',
        value: notReviewed,
        route: '/file-box',
      ),
      _AttentionMetric(
        icon: Icons.hourglass_top_outlined,
        label: 'Links expiring soon',
        value: expiringSoon,
        route: '/send-files',
      ),
      _AttentionMetric(
        icon: Icons.visibility_outlined,
        label: 'Opened, not downloaded',
        value: openedNotDownloaded,
        route: '/send-files',
      ),
      _AttentionMetric(
        icon: Icons.upload_file_outlined,
        label: 'Requests with no files',
        value: openNoFiles,
        route: '/generate-upload-link',
      ),
    ];
  }

  Future<List<Map<String, dynamic>>> _loadShareRows() async {
    try {
      final res = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('listSecureFileShares')
          .call()
          .timeout(const Duration(seconds: 10));
      final sharesData = Map<String, dynamic>.from(res.data as Map);
      final shares = (sharesData['shares'] is List)
          ? sharesData['shares'] as List
          : const [];
      return shares.map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_AttentionMetric>>(
      future: _future,
      builder: (context, snap) {
        final metrics = snap.data ?? const <_AttentionMetric>[];
        return _DashboardListSection(
          title: 'Needs attention',
          subtitle: 'A quick view of items that may need follow-up today.',
          children: snap.hasError
              ? [
                  _DashboardListRow(
                    leadingIcon: Icons.warning_amber_outlined,
                    title: 'Needs attention is unavailable',
                    subtitle: 'Open File Box, Sent Files, or Requests directly.',
                    onTap: () => setState(() => _future = _load()),
                    trailing: TextButton(
                      onPressed: () => setState(() => _future = _load()),
                      child: const Text('Retry'),
                    ),
                  ),
                ]
              : snap.hasData
              ? metrics
                    .map(
                      (m) => _MetricRow(
                        metric: m,
                        onTap: () => Navigator.pushNamed(context, m.route),
                      ),
                    )
                    .toList()
              : const [
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                ],
        );
      },
    );
  }
}

class _AttentionMetric {
  const _AttentionMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.route,
  });

  final IconData icon;
  final String label;
  final int value;
  final String route;
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.metric, required this.onTap});

  final _AttentionMetric metric;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _DashboardListRow(
      leadingIcon: metric.icon,
      title: metric.label,
      subtitle: metric.value == 0 ? 'Nothing waiting right now' : 'Review these items',
      onTap: onTap,
      badges: [_StatusBadge(label: metric.value.toString())],
    );
  }
}

class _RecentSentLinksSection extends StatelessWidget {
  const _RecentSentLinksSection({required this.hasDropoffAccess});

  final bool hasDropoffAccess;

  Future<List<Map<String, dynamic>>> _load() async {
    if (!hasDropoffAccess) return const [];
    final res = await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('listSecureFileShares')
        .call();
    final data = Map<String, dynamic>.from(res.data as Map);
    final raw = (data['shares'] is List) ? data['shares'] as List : const [];
    return raw.take(5).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _load(),
      builder: (context, snap) {
        final rows = snap.data ?? const <Map<String, dynamic>>[];
        return _DashboardListSection(
          title: 'Recently sent',
          subtitle: 'File links sent to clients and their latest access status.',
          children: snap.hasData
              ? [
                  if (rows.isEmpty)
                    _DashboardListRow(
                      leadingIcon: Icons.send_outlined,
                      title: 'No sent links yet',
                      subtitle: 'Create a file link when you are ready to send files.',
                      onTap: () => Navigator.pushNamed(context, '/send-files/new'),
                      enabled: hasDropoffAccess,
                    )
                  else
                    ...rows.map((m) {
                      final name = _dashS(m['recipientName']).isNotEmpty
                          ? _dashS(m['recipientName'])
                          : _dashS(m['recipientEmail']).isNotEmpty
                          ? _dashS(m['recipientEmail'])
                          : 'Client';
                      final lastViewed = m['lastViewedAtMillis'] is num
                          ? DateTime.fromMillisecondsSinceEpoch(
                              (m['lastViewedAtMillis'] as num).toInt(),
                            )
                          : null;
                      final lastDownloaded = m['lastDownloadedAtMillis'] is num
                          ? DateTime.fromMillisecondsSinceEpoch(
                              (m['lastDownloadedAtMillis'] as num).toInt(),
                            )
                          : null;
                      final activity = lastDownloaded != null
                          ? 'Downloaded ${_dashRelative(lastDownloaded)}'
                          : lastViewed != null
                          ? 'Viewed ${_dashRelative(lastViewed)}'
                          : 'Never opened';
                      return _DashboardListRow(
                        leadingIcon: Icons.link_outlined,
                        title: name,
                        subtitle:
                            '${_dashS(m['recipientEmail'])} - $activity',
                        onTap: () => Navigator.pushNamed(context, '/send-files'),
                        badges: [_StatusBadge(label: _dashS(m['status']).isEmpty ? 'Active' : _dashS(m['status']))],
                        trailing: _DashboardRowMenu(
                          actions: [
                            _DashboardMenuAction(
                              icon: Icons.copy_outlined,
                              label: 'Copy link',
                              onPressed: () => Clipboard.setData(
                                ClipboardData(text: _dashS(m['url'])),
                              ),
                            ),
                            _DashboardMenuAction(
                              icon: Icons.open_in_new_outlined,
                              label: 'Open Send Files',
                              onPressed: () =>
                                  Navigator.pushNamed(context, '/send-files'),
                            ),
                          ],
                        ),
                      );
                    }),
                  _DashboardFooterAction(
                    label: 'View all sent links',
                    icon: Icons.send_outlined,
                    onPressed: () => Navigator.pushNamed(context, '/send-files'),
                  ),
                ]
              : const [
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                ],
        );
      },
    );
  }
}

class _OpenRequestsSection extends StatelessWidget {
  const _OpenRequestsSection({
    required this.uid,
    required this.hasDropoffAccess,
  });

  final String uid;
  final bool hasDropoffAccess;

  @override
  Widget build(BuildContext context) {
    if (!hasDropoffAccess) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('dropoff_requests')
          .where('createdByUid', isEqualTo: uid)
          .where('status', isEqualTo: 'open')
          .limit(5)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const [];
        return _DashboardListSection(
          title: 'Open requests',
          subtitle: 'Active client upload requests that may need follow-up.',
          children: snap.hasData
              ? [
                  if (docs.isEmpty)
                    _DashboardListRow(
                      leadingIcon: Icons.task_alt_outlined,
                      title: 'No open requests',
                      subtitle: 'All file requests are currently quiet.',
                      onTap: () => Navigator.pushNamed(
                        context,
                        '/generate-upload-link',
                      ),
                    )
                  else
                    ...docs.map((doc) {
                      final m = doc.data();
                      final client = _dashS(m['clientName']).isNotEmpty
                          ? _dashS(m['clientName'])
                          : _dashS(m['clientEmail']).isNotEmpty
                          ? _dashS(m['clientEmail'])
                          : 'Client request';
                      final expires = _dashDate(m['expiresAt']);
                      final count = m['fileCount'] ?? m['filesCount'] ?? m['uploadCount'];
                      final fileCount = count is num ? count.toInt() : 0;
                      return _DashboardListRow(
                        leadingIcon: Icons.request_page_outlined,
                        title: client,
                        subtitle:
                            '$fileCount files received - expires ${_dashRelative(expires)}',
                        onTap: () => Navigator.pushNamed(
                          context,
                          '/generate-upload-link',
                        ),
                        trailing: _DashboardRowMenu(
                          actions: [
                            _DashboardMenuAction(
                              icon: Icons.copy_outlined,
                              label: 'Copy upload link',
                              onPressed: () => Clipboard.setData(
                                ClipboardData(text: _dashS(m['url'])),
                              ),
                            ),
                            _DashboardMenuAction(
                              icon: Icons.open_in_new_outlined,
                              label: 'Open request',
                              onPressed: () => Navigator.pushNamed(
                                context,
                                '/generate-upload-link',
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  _DashboardFooterAction(
                    label: 'Create or manage requests',
                    icon: Icons.request_page_outlined,
                    onPressed: () =>
                        Navigator.pushNamed(context, '/generate-upload-link'),
                  ),
                ]
              : const [
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                ],
        );
      },
    );
  }
}

class _ActivityTodaySection extends StatelessWidget {
  const _ActivityTodaySection({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    if (!isAdmin) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('file_activity')
          .where('occurredAt', isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfToday()))
          .orderBy('occurredAt', descending: true)
          .limit(8)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const [];
        return _DashboardListSection(
          title: 'Activity today',
          subtitle: 'Recent file events across sends, opens, and downloads.',
          children: snap.hasData
              ? [
                  if (docs.isEmpty)
                    _DashboardListRow(
                      leadingIcon: Icons.timeline_outlined,
                      title: 'No activity yet today',
                      subtitle: 'New activity will appear here as it happens.',
                      onTap: () => Navigator.pushNamed(context, '/admin-audit'),
                    )
                  else
                    ...docs.map((doc) {
                      final m = doc.data();
                      final action = _dashS(m['action']).isEmpty
                          ? 'Activity'
                          : _dashS(m['action']);
                      final actor = _dashS(m['actorName']).isNotEmpty
                          ? _dashS(m['actorName'])
                          : _dashS(m['actorEmail']);
                      final file = _dashS(m['fileName']).isNotEmpty
                          ? _dashS(m['fileName'])
                          : _dashS(m['originalName']);
                      return _DashboardListRow(
                        leadingIcon: Icons.timeline_outlined,
                        title: '${action[0].toUpperCase()}${action.substring(1)}',
                        subtitle: [
                          if (actor.isNotEmpty) actor,
                          if (file.isNotEmpty) file,
                          _dashRelative(_dashDate(m['occurredAt'])),
                        ].join(' - '),
                        onTap: () => Navigator.pushNamed(context, '/admin-audit'),
                      );
                    }),
                  _DashboardFooterAction(
                    label: 'Open full audit timeline',
                    icon: Icons.manage_search_outlined,
                    onPressed: () => Navigator.pushNamed(context, '/admin-audit'),
                  ),
                ]
              : const [
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                ],
        );
      },
    );
  }
}

class _FileDetailsCard extends StatelessWidget {
  const _FileDetailsCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFD),
        border: Border.all(color: const Color(0xFFE4E7EC)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF6F9FF),
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
              border: Border(
                bottom: BorderSide(color: Color(0xFFE4E7EC), width: 1),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 17, color: AppColors.brandBlue),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF253858),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _FileDetailRow extends StatelessWidget {
  const _FileDetailRow({
    required this.label,
    required this.value,
    this.secondary = '',
  });

  final String label;
  final String value;
  final String secondary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF667085),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value.isEmpty ? '-' : value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (secondary.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    secondary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditEventRow extends StatelessWidget {
  const _AuditEventRow({
    required this.action,
    required this.actor,
    required this.when,
    required this.surface,
  });

  final String action;
  final String actor;
  final String when;
  final String surface;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: const Color(0xFFD6E8FF)),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.timeline_outlined,
              color: AppColors.brandBlue,
              size: 15,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (actor.isNotEmpty) actor,
                    if (surface.isNotEmpty) surface,
                  ].join(' - '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            when,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditEmptyState extends StatelessWidget {
  const _AuditEmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF667085),
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DashboardListSection extends StatelessWidget {
  const _DashboardListSection({
    required this.title,
    required this.subtitle,
    required this.children,
    this.headerTrailing,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _StaticSurface(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF111827),
                  ),
                ),
              ),
              if (headerTrailing != null) headerTrailing!,
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF6B7280),
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Divider(height: 1, color: Colors.black.withOpacity(0.08)),
        ..._withDividers(children),
      ],
    );
  }

  List<Widget> _withDividers(List<Widget> kids) {
    final out = <Widget>[];
    for (int i = 0; i < kids.length; i++) {
      out.add(kids[i]);
      if (i != kids.length - 1) {
        out.add(Divider(height: 1, color: Colors.black.withOpacity(0.08)));
      }
    }
    return out;
  }
}

class _DashboardListRow extends StatelessWidget {
  const _DashboardListRow({
    required this.leadingIcon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.leadingColor = const Color(0xFFF1F5F9),
    this.iconColor = AppColors.brandBlue,
    this.trailing,
    this.badges = const [],
    this.enabled = true,
  });

  final IconData leadingIcon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  final Color leadingColor;
  final Color iconColor;
  final Widget? trailing;
  final List<Widget> badges;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(4),

      // ✅ Match your chrome hover language (same as AppShell IconButtons)
      overlayColor: MaterialStateProperty.resolveWith<Color?>((states) {
        if (states.contains(MaterialState.pressed)) {
          return const Color(0xFFE2E8F0); // slightly stronger pressed
        }
        if (states.contains(MaterialState.hovered)) {
          return const Color(0xFFF1F5F9); // matches your command/icon hover
        }
        return null;
      }),

      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            _LeadingIconTile(
              icon: leadingIcon,
              color: leadingColor,
              iconColor: enabled ? iconColor : const Color(0xFFB0B7C3),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: enabled
                                ? const Color(0xFF111827)
                                : const Color(0xFF98A2B3),
                          ),
                        ),
                      ),
                      if (badges.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        ...badges,
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: enabled
                          ? const Color(0xFF6B7280)
                          : const Color(0xFFB0B7C3),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            trailing ??
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: enabled
                      ? const Color(0xFF9CA3AF)
                      : const Color(0xFFD1D5DB),
                ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final normalized = label.toLowerCase();
    final color = normalized == 'new' || normalized == 'not reviewed'
        ? AppColors.brandBlue
        : normalized == 'sent'
        ? const Color(0xFF7A5AF8)
        : normalized == 'downloaded'
        ? const Color(0xFF067647)
        : normalized == 'reviewed'
        ? const Color(0xFF475467)
        : normalized == 'pinned'
        ? const Color(0xFFB54708)
        : const Color(0xFF667085);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

class _DashboardMenuAction {
  const _DashboardMenuAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
}

class _DashboardRowMenu extends StatelessWidget {
  const _DashboardRowMenu({required this.actions});

  final List<_DashboardMenuAction> actions;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_DashboardMenuAction>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_horiz, size: 20),
      onSelected: (action) => action.onPressed(),
      itemBuilder: (context) => actions
          .map(
            (action) => PopupMenuItem<_DashboardMenuAction>(
              value: action,
              child: Row(
                children: [
                  Icon(action.icon, size: 18, color: const Color(0xFF475467)),
                  const SizedBox(width: 10),
                  Text(action.label),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _DashboardFooterAction extends StatelessWidget {
  const _DashboardFooterAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: TextButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 16),
          label: Text(label),
        ),
      ),
    );
  }
}

class _RecentFileFilterBar extends StatelessWidget {
  const _RecentFileFilterBar({
    required this.selected,
    required this.labelFor,
    required this.onChanged,
  });

  final _RecentFileFilter selected;
  final String Function(_RecentFileFilter) labelFor;
  final ValueChanged<_RecentFileFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_RecentFileFilter>(
      tooltip: 'Filter recent files',
      onSelected: onChanged,
      itemBuilder: (context) => _RecentFileFilter.values
          .map(
            (filter) => PopupMenuItem<_RecentFileFilter>(
              value: filter,
              child: Row(
                children: [
                  if (filter == selected)
                    const Icon(Icons.check, size: 16, color: AppColors.brandBlue)
                  else
                    const SizedBox(width: 16),
                  const SizedBox(width: 8),
                  Text(labelFor(filter)),
                ],
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFE4E7EC)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.filter_list, size: 15, color: Color(0xFF475467)),
            const SizedBox(width: 6),
            Text(
              labelFor(selected),
              style: const TextStyle(
                color: Color(0xFF344054),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeadingIconTile extends StatelessWidget {
  const _LeadingIconTile({
    required this.icon,
    required this.color,
    required this.iconColor,
  });

  final IconData icon;
  final Color color;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      width: 28,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 16, color: iconColor),
    );
  }
}

class _PrimaryActionsPanel extends StatelessWidget {
  const _PrimaryActionsPanel({required this.children, this.header});

  final String? header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _SurfaceTable(
      children: [
        if (header != null && header!.trim().isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Text(
              header!,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF374151),
                letterSpacing: 0.2,
              ),
            ),
          ),
          Divider(height: 1, color: Colors.black.withOpacity(0.08)),
        ],
        ..._withDividers(children),
      ],
    );
  }

  List<Widget> _withDividers(List<Widget> kids) {
    final out = <Widget>[];
    for (int i = 0; i < kids.length; i++) {
      out.add(kids[i]);
      if (i != kids.length - 1) {
        out.add(Divider(height: 1, color: Colors.black.withOpacity(0.08)));
      }
    }
    return out;
  }
}

class _PrimaryActionRow extends StatefulWidget {
  const _PrimaryActionRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.meta,
    required this.buttonLabel,
    required this.onPressed,
    this.enabled = true,
    this.accentColor = AppColors.brandBlue,
  });

  final IconData icon;
  final String title;
  final String description;
  final String meta;
  final String buttonLabel;
  final VoidCallback onPressed;
  final bool enabled;
  final Color accentColor;

  @override
  State<_PrimaryActionRow> createState() => _PrimaryActionRowState();
}

class _PrimaryActionRowState extends State<_PrimaryActionRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 620;

    final bg = !widget.enabled
        ? Colors.transparent
        : _hover
        ? const Color(0xFFF6F7F9)
        : Colors.transparent;

    final titleColor = widget.enabled
        ? const Color(0xFF111827)
        : const Color(0xFF98A2B3);
    final descColor = widget.enabled
        ? const Color(0xFF475467)
        : const Color(0xFFB0B7C3);
    final metaColor = widget.enabled
        ? const Color(0xFF667085)
        : const Color(0xFFB0B7C3);
    final iconColor = widget.enabled
        ? widget.accentColor
        : const Color(0xFFB0B7C3);

    final row = InkWell(
      onTap: widget.enabled
          ? widget.onPressed
          : null, // ✅ entire row acts like entry point
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        color: bg,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: isNarrow
            ? _buildNarrow(context, iconColor, titleColor, descColor, metaColor)
            : _buildWide(context, iconColor, titleColor, descColor, metaColor),
      ),
    );

    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: widget.enabled ? (_) => setState(() => _hover = true) : null,
      onExit: widget.enabled ? (_) => setState(() => _hover = false) : null,
      child: row,
    );
  }

  Widget _buildWide(
    BuildContext context,
    Color iconColor,
    Color titleColor,
    Color descColor,
    Color metaColor,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(widget.icon, size: 22, color: iconColor),
        const SizedBox(width: 14),

        // Left: title + description
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: titleColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.description,
                style: TextStyle(
                  fontSize: 12.8,
                  height: 1.35,
                  color: descColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 16),

        // Right: meta + CTA
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 240, maxWidth: 320),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  widget.meta,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.25,
                    color: metaColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 34,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.enabled
                        ? widget.accentColor
                        : const Color(0xFFE5E7EB),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: widget.enabled ? widget.onPressed : null,
                  child: Text(widget.buttonLabel),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNarrow(
    BuildContext context,
    Color iconColor,
    Color titleColor,
    Color descColor,
    Color metaColor,
  ) {
    // Mobile / narrow: stack meta + full-width button
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(widget.icon, size: 22, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: titleColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          widget.description,
          style: TextStyle(
            fontSize: 12.8,
            height: 1.35,
            color: descColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          widget.meta,
          style: TextStyle(
            fontSize: 12.5,
            color: metaColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 40,
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: widget.enabled
                  ? widget.accentColor
                  : const Color(0xFFE5E7EB),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            onPressed: widget.enabled ? widget.onPressed : null,
            child: Text(widget.buttonLabel),
          ),
        ),
      ],
    );
  }
}

class _DashboardIntroHeader extends StatelessWidget {
  const _DashboardIntroHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF111827),
            letterSpacing: -0.2,
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF6B7280),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loadingProfile = true;
  bool _hasDropoffAccess = false;

  String _fullName = '';
  String _role = '';
  String _wildixExt = '';
  String _clearflyNumber = '';

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.authStateChanges().where((u) => u != null).first.then(
      (u) {
        if (!mounted) return;
        _loadProfile(u!);
      },
    );
  }

  Future<void> _loadProfile(User user) async {
    setState(() => _loadingProfile = true);

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final data = doc.data() ?? {};
    final first = (data['firstName'] ?? '').toString().trim();
    final last = (data['lastName'] ?? '').toString().trim();
    final display = (data['displayName'] ?? '').toString().trim();
    final name = ('$first $last').trim().isNotEmpty ? '$first $last' : display;

    final role = (data['role'] ?? '').toString().toLowerCase().trim();
    final hasDropoffs =
        role == 'admin' || (data['capabilities']?['dropoffs'] == true);

    final comms = Map<String, dynamic>.from(data['communications'] ?? {});
    final wildix = (comms['wildixExtension'] ?? '').toString().trim();
    final clearfly = (comms['clearflySmsNumber'] ?? '').toString().trim();

    if (!mounted) return;
    setState(() {
      _fullName = name;
      _role = role;
      _hasDropoffAccess = hasDropoffs;
      _wildixExt = wildix;
      _clearflyNumber = _formatUsPhone10(clearfly);
      _loadingProfile = false;
    });
  }

  String _formatUsPhone10(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) return input.trim();
    final t = digits.substring(digits.length - 10);
    return '${t.substring(0, 3)}-${t.substring(3, 6)}-${t.substring(6)}';
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isAdmin = !_loadingProfile && _role == 'admin';
    final welcomeText = _fullName.isNotEmpty
        ? 'Welcome, $_fullName'
        : 'Welcome';

    if (uid.isEmpty) return const SizedBox.shrink();

    return PageScaffold(
      title: '',
      hideHeader: true,
      wrapInCard: false,

      // ✅ Welcome text ABOVE command bar (new slot)
      preCommandBar: _DashboardIntroHeader(
        title: welcomeText, // "Welcome, Guillermo"
        subtitle: 'Choose a common workflow or review recent activity.',
      ),

      child: ContentTextZoom(
        scale: 1.1, // ✅ TEST HERE (try 1.05–1.12)

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _NeedsAttentionSection(
              uid: uid,
              hasDropoffAccess: _hasDropoffAccess,
            ),
            const SizedBox(height: 14),
            _RecentUploadsFromActivity(isAdmin: isAdmin),
            const SizedBox(height: 14),
            _RecentSentLinksSection(hasDropoffAccess: _hasDropoffAccess),
            const SizedBox(height: 14),
            _OpenRequestsSection(uid: uid, hasDropoffAccess: _hasDropoffAccess),
            const SizedBox(height: 14),
            _ActivityTodaySection(isAdmin: isAdmin),

            if (!_hasDropoffAccess)
              _SurfaceTable(
                children: const [
                  _InfoRow(
                    text:
                        'You do not currently have access to Files or Request links. '
                        'Please contact an administrator if this is unexpected.',
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// ============================
/// Office 365 style components
/// ============================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: const Color(0xFF374151),
        letterSpacing: 0.2,
      ),
    );
  }
}

class _SurfaceTable extends StatefulWidget {
  const _SurfaceTable({required this.children, this.enableHover = true});

  final List<Widget> children;
  final bool enableHover;

  @override
  State<_SurfaceTable> createState() => _SurfaceTableState();
}

class _SurfaceTableState extends State<_SurfaceTable> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final appTheme = Theme.of(context).extension<AppTheme>()!;

    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: widget.enableHover && _hover
            ? const Color(0xFFF0F0F0)
            : appTheme.contentBackground,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: widget.enableHover && _hover
              ? Colors.black.withOpacity(0.28)
              : Colors.black.withOpacity(0.12),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: widget.enableHover && _hover
                ? const Color(0x33000000)
                : const Color(0x1A000000),
            blurRadius: widget.enableHover && _hover ? 8 : 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(children: widget.children),
    );

    if (!widget.enableHover) {
      return child; // ✅ no MouseRegion at all
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: child,
    );
  }
}

class _RowItem extends StatelessWidget {
  const _RowItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.brandBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6B7280),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF111827),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: const Color(0xFF6B7280),
          height: 1.4,
        ),
      ),
    );
  }
}
