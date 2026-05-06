import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../widgets/page_scaffold.dart';
import '../utils/file_kind.dart';

enum _SortField { name, client, size, date }

enum _TypeFilter { all, pdf, doc, xls, img, txt, other }

enum _DateFilter { all, today, last7, last30 }

class FileBoxScreen extends StatefulWidget {
  const FileBoxScreen({super.key});

  @override
  State<FileBoxScreen> createState() => _FileBoxScreenState();
}

class _FileBoxScreenState extends State<FileBoxScreen> {
  final _searchCtrl = TextEditingController();
  String _q = '';

  String? _role;
  bool _loadingRole = true;
  List<_UploadDoc> _selectedDocsCache = const [];

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _uploadsStream;

  final Set<String> _selected = {};
  _SortField _sortField = _SortField.date;
  bool _sortAsc = false;

  _TypeFilter _typeFilter = _TypeFilter.all;
  _DateFilter _dateFilter = _DateFilter.all;

  static const int _pageSize = 50;
  int _visibleCount = _pageSize;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _initRole();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _initRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _role = '';
      _loadingRole = false;
      if (mounted) setState(() {});
      return;
    }

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    _role = (snap.data()?['role'] ?? '').toString().toLowerCase().trim();
    final isAdmin = _role == 'admin';

    _uploadsStream = isAdmin
        ? FirebaseFirestore.instance
              .collectionGroup('files')
              .where('deleted', isEqualTo: false) // ✅ HIDE deleted at source
              .orderBy('createdAt', descending: true)
              .limit(500)
              .snapshots()
        : FirebaseFirestore.instance
              .collectionGroup('files')
              .where('requestCreatedByRole', isEqualTo: 'associate')
              .where('deleted', isEqualTo: false) // ✅ HIDE deleted at source
              .orderBy('createdAt', descending: true)
              .limit(500)
              .snapshots();

    _loadingRole = false;
    if (mounted) setState(() {});
  }

  String _s(dynamic v) => (v ?? '').toString().trim();

  String _fmt(BuildContext c, DateTime d) {
    final loc = MaterialLocalizations.of(c);
    return '${loc.formatShortDate(d)} • ${loc.formatTimeOfDay(TimeOfDay.fromDateTime(d))}';
  }

  DateTime? _asDate(dynamic createdAt) {
    if (createdAt is Timestamp) return createdAt.toDate();
    return null;
  }

  _TypeFilter _inferTypeFilter(String name, String contentType) {
    final kind = detectFileKind(fileName: name, contentType: contentType);

    switch (kind) {
      case FileKind.pdf:
        return _TypeFilter.pdf;
      case FileKind.word:
        return _TypeFilter.doc;
      case FileKind.excel:
        return _TypeFilter.xls;
      case FileKind.image:
        return _TypeFilter.img;
      case FileKind.text:
        return _TypeFilter.txt;
      default:
        return _TypeFilter.other;
    }
  }

  bool _passesDateFilter(DateTime? when) {
    if (_dateFilter == _DateFilter.all) return true;
    if (when == null) return false;

    final now = DateTime.now();
    DateTime start;

    switch (_dateFilter) {
      case _DateFilter.today:
        start = DateTime(now.year, now.month, now.day);
        break;
      case _DateFilter.last7:
        start = now.subtract(const Duration(days: 7));
        break;
      case _DateFilter.last30:
        start = now.subtract(const Duration(days: 30));
        break;
      case _DateFilter.all:
        return true;
    }
    return when.isAfter(start);
  }

  Future<void> _downloadFile({
    required bool isAdmin,
    required String storagePath,
    required String filename,
    String? contentType,
    String? requestId,
    String? fileId,
  }) async {
    if (storagePath.trim().isEmpty) return;

    setState(() => _busy = true);
    try {
      final fn = isAdmin ? 'getAdminDownloadUrl' : 'getDropoffDownloadUrl';

      final res = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable(fn)
          .call({
            'storagePath': storagePath,
            'filename': filename,
            'contentType': (contentType ?? '').toString(),
            'requestId': (requestId ?? '').toString(),
            'fileId': (fileId ?? '').toString(),
          });

      final data = Map<String, dynamic>.from(res.data as Map);
      final url = (data['url'] ?? '').toString();

      if (url.isEmpty) {
        throw Exception('Could not generate download link.');
      }

      final uri = Uri.parse(url);

      if (!mounted) return;

      // ✅ iOS/Safari-friendly: user taps a button → navigation allowed
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
                // Web (including iPhone Safari Flutter web): use same-tab navigation
                if (kIsWeb) {
                  await launchUrl(uri, webOnlyWindowName: '_self');
                } else {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Download'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Downloading $filename…')));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final msg = 'Download failed: ${e.code} ${e.message ?? ''}';
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

  Future<void> _logFileView({
    required _UploadDoc doc,
    required String surface, // 'details' or 'history'
  }) async {
    try {
      final requestId = (doc.data['requestId'] ?? '').toString().trim();
      if (requestId.isEmpty) return;

      await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('logFileActivity').call({
        'requestId': requestId,
        'fileId': doc.id,
        'action': 'view',
        'surface': surface,
      });
    } catch (_) {
      // Best-effort only: never block UI for logging
    }
  }

  Future<void> _showActivityHistoryDialog({required _UploadDoc doc}) async {
    if (_role != 'admin') return;
    await _logFileView(doc: doc, surface: 'history');
    final m = doc.data;
    final requestId = (m['requestId'] ?? '').toString().trim();

    // Query: events for this file (requires an index: fileId + occurredAt)
    final q = FirebaseFirestore.instance
        .collection('file_activity')
        .where('fileId', isEqualTo: doc.id)
        .where('requestId', isEqualTo: requestId)
        .orderBy('occurredAt', descending: true)
        .limit(50);

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Activity history'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 420),
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: q.snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Text(
                  snap.error.toString(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFB42318),
                    fontWeight: FontWeight.w700,
                  ),
                );
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return const Text(
                  'No activity has occurred since this file was uploaded.',
                  style: TextStyle(
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w600,
                  ),
                );
              }

              IconData iconFor(String a) {
                switch (a) {
                  case 'upload':
                    return Icons.file_upload_outlined;
                  case 'view':
                    return Icons.visibility_outlined;
                  case 'download':
                    return Icons.download_outlined;
                  default:
                    return Icons.info_outline;
                }
              }

              String labelFor(String a) {
                switch (a) {
                  case 'upload':
                    return 'Uploaded';
                  case 'view':
                    return 'Viewed';
                  case 'download':
                    return 'Downloaded';
                  default:
                    return a;
                }
              }

              String actorFor(Map<String, dynamic> e) {
                final type = (e['actorType'] ?? '').toString().trim();
                final name = (e['actorName'] ?? '').toString().trim();
                final email = (e['actorEmail'] ?? '').toString().trim();
                final who = name.isNotEmpty
                    ? name
                    : (email.isNotEmpty ? email : '—');
                if (type.isEmpty) return who;
                // Enterprise label: "Client — John Doe" / "Associate — Jane"
                return '${type[0].toUpperCase()}${type.substring(1)} — $who';
              }

              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (c, i) {
                  final e = docs[i].data();
                  final action = (e['action'] ?? '').toString().trim();
                  final at = _tsToDate(e['occurredAt']);

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(iconFor(action), color: const Color(0xFF475467)),
                        const SizedBox(width: 12),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                labelFor(action),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                actorFor(e),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF667085),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                at == null ? '—' : _fmt(context, at),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF667085),
                                ),
                              ),
                            ],
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
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSelectedAdmin(List<_UploadDoc> selectedDocs) async {
    if (selectedDocs.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete selected files'),
        content: Text(
          'Delete ${selectedDocs.length} file(s)? This action cannot be undone.',
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
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('deleteDropoffUploadsBatch');

      final payload = selectedDocs.map((d) {
        return {'docPath': d.docPath, 'storagePath': d.storagePath};
      }).toList();

      await callable.call({'items': payload});

      if (!mounted) return;
      setState(() {
        _selected.clear();
        _visibleCount = _pageSize;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selected files deleted.')));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: ${e.code} ${e.message ?? ''}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleSort(_SortField field) {
    setState(() {
      if (_sortField == field) {
        _sortAsc = !_sortAsc;
      } else {
        _sortField = field;
        _sortAsc = field != _SortField.date;
      }
      _visibleCount = _pageSize;
    });
  }

  void _applySearch(String value) {
    setState(() {
      _q = value.trim().toLowerCase();
      _visibleCount = _pageSize;
      _selected.clear();
    });
  }

  String _typeLabel(_TypeFilter value) {
    switch (value) {
      case _TypeFilter.all:
        return 'All';
      case _TypeFilter.pdf:
        return 'PDF';
      case _TypeFilter.doc:
        return 'Word';
      case _TypeFilter.xls:
        return 'Excel';
      case _TypeFilter.img:
        return 'Images';
      case _TypeFilter.txt:
        return 'Text';
      case _TypeFilter.other:
        return 'Other';
    }
  }

  String _dateLabel(_DateFilter value) {
    switch (value) {
      case _DateFilter.all:
        return 'Any date';
      case _DateFilter.today:
        return 'Today';
      case _DateFilter.last7:
        return '7 days';
      case _DateFilter.last30:
        return '30 days';
    }
  }

  bool _dateMatches(DateTime? when, _DateFilter filter) {
    if (filter == _DateFilter.all) return true;
    if (when == null) return false;

    final now = DateTime.now();
    DateTime start;

    switch (filter) {
      case _DateFilter.today:
        start = DateTime(now.year, now.month, now.day);
        break;
      case _DateFilter.last7:
        start = now.subtract(const Duration(days: 7));
        break;
      case _DateFilter.last30:
        start = now.subtract(const Duration(days: 30));
        break;
      case _DateFilter.all:
        return true;
    }
    return when.isAfter(start);
  }

  Widget _filterChip({
    required ThemeData theme,
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return ChoiceChip(
      label: Text('$label $count'),
      selected: selected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelStyle: theme.textTheme.labelSmall?.copyWith(
        color: selected ? const Color(0xFF0B62D6) : const Color(0xFF344054),
        fontWeight: FontWeight.w900,
      ),
      selectedColor: const Color(0xFFEFF6FF),
      backgroundColor: const Color(0xFFF9FAFB),
      side: BorderSide(
        color: selected ? const Color(0xFFB2DDFF) : const Color(0xFFE4E7EC),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      onSelected: (_) => onSelected(),
    );
  }

  Widget _filterBar(ThemeData theme, List<_UploadDoc> rows) {
    int typeCount(_TypeFilter type) {
      if (type == _TypeFilter.all) return rows.length;
      return rows
          .where((r) => _inferTypeFilter(r.originalName, r.contentType) == type)
          .length;
    }

    int dateCount(_DateFilter date) =>
        rows.where((r) => _dateMatches(r.when, date)).length;

    Widget typeChip(_TypeFilter type) {
      return _filterChip(
        theme: theme,
        label: _typeLabel(type),
        count: typeCount(type),
        selected: _typeFilter == type,
        onSelected: () {
          setState(() {
            _typeFilter = type;
            _visibleCount = _pageSize;
            _selected.clear();
          });
        },
      );
    }

    Widget dateChip(_DateFilter date) {
      return _filterChip(
        theme: theme,
        label: _dateLabel(date),
        count: dateCount(date),
        selected: _dateFilter == date,
        onSelected: () {
          setState(() {
            _dateFilter = date;
            _visibleCount = _pageSize;
            _selected.clear();
          });
        },
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        typeChip(_TypeFilter.all),
        typeChip(_TypeFilter.pdf),
        typeChip(_TypeFilter.doc),
        typeChip(_TypeFilter.xls),
        typeChip(_TypeFilter.img),
        typeChip(_TypeFilter.txt),
        typeChip(_TypeFilter.other),
        const SizedBox(width: 6),
        dateChip(_DateFilter.all),
        dateChip(_DateFilter.today),
        dateChip(_DateFilter.last7),
        dateChip(_DateFilter.last30),
      ],
    );
  }

  String _formatSizeBytes(int bytes) {
    if (bytes <= 0) return '—';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  DateTime? _tsToDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return null;
  }

  Future<void> _showUploadDetailsDialog({required _UploadDoc doc}) async {
    await _logFileView(doc: doc, surface: 'details');
    final m = doc.data;

    final fileName = (m['originalName'] ?? doc.originalName).toString().trim();
    final contentType = (m['contentType'] ?? doc.contentType).toString().trim();
    final sizeBytes = (m['sizeBytes'] is num)
        ? (m['sizeBytes'] as num).toInt()
        : doc.sizeBytes;

    final uploadedAt = _tsToDate(m['createdAt']) ?? doc.when;

    final clientName = (m['requestClientName'] ?? doc.clientName)
        .toString()
        .trim();
    final clientEmail = (m['requestClientEmail'] ?? doc.clientEmail)
        .toString()
        .trim();
    final businessName = (m['requestBusinessName'] ?? doc.companyName)
        .toString()
        .trim();

    final requestedBy = (m['requestCreatedByName'] ?? doc.requestedBy)
        .toString()
        .trim();
    final requestedByEmail = (m['requestCreatedByEmail'] ?? '')
        .toString()
        .trim();

    final requestId = (m['requestId'] ?? '').toString().trim();
    final lastActivityAt = _tsToDate(m['lastActivityAt']);
    final lastActivityAction = (m['lastActivityAction'] ?? '')
        .toString()
        .trim();
    final lastActivityActor = (m['lastActivityActorName'] ?? '')
        .toString()
        .trim();

    String activityLabel(String action) {
      switch (action.toLowerCase().trim()) {
        case 'upload':
          return 'Uploaded';
        case 'view':
          return 'Viewed';
        case 'download':
          return 'Downloaded';
        case 'delete':
          return 'Deleted';
        default:
          return action.trim().isEmpty ? '—' : action.trim();
      }
    }

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Upload details'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow(label: 'File name', value: fileName),
                _DetailRow(
                  label: 'Type',
                  value: contentType.isEmpty ? '—' : contentType,
                ),
                _DetailRow(label: 'Size', value: _formatSizeBytes(sizeBytes)),
                _DetailRow(
                  label: 'Uploaded',
                  value: uploadedAt == null ? '—' : _fmt(context, uploadedAt),
                ),
                _DetailRow(
                  label: 'Request ID',
                  value: requestId.isEmpty ? '—' : requestId,
                ),
                _DetailRow(
                  label: 'Last activity',
                  value: activityLabel(lastActivityAction),
                ),
                if (lastActivityAt != null)
                  _DetailRow(
                    label: 'Activity time',
                    value: _fmt(context, lastActivityAt),
                  ),
                if (lastActivityActor.isNotEmpty)
                  _DetailRow(label: 'Activity by', value: lastActivityActor),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                _DetailRow(label: 'Client', value: clientName),
                _DetailRow(label: 'Client email', value: clientEmail),
                _DetailRow(label: 'Business', value: businessName),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                _DetailRow(label: 'Link creator', value: requestedBy),
                if (requestedByEmail.isNotEmpty)
                  _DetailRow(label: 'Creator email', value: requestedByEmail),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // ✅ Content-only loading state (AppShell provides chrome)
    if (_loadingRole) {
      return const Center(child: CircularProgressIndicator());
    }

    final isAdmin = _role == 'admin';
    final isMobile = MediaQuery.of(context).size.width < 700;

    return PageScaffold(
      title: 'File Box',
      subtitle: isAdmin
          ? 'All uploads across all document requests.'
          : 'Uploads from associate-created document requests.',
      hideHeader: false,
      wrapInCard: false,
      scrollable: false,
      maxContentWidth: 1400,

      // ✅ CRITICAL: give PageScaffold a flex child so it gets height
      child: Expanded(
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ===== Search =====
                TextField(
                  controller: _searchCtrl,
                  textInputAction: TextInputAction.search,
                  onChanged: _applySearch,
                  onSubmitted: _applySearch,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    hintText:
                        'Search files, clients, businesses, or request IDs',
                    suffixIcon: _q.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              _applySearch('');
                            },
                          ),
                  ),
                ),

                const SizedBox(height: 12),

                // ===== Table =====
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _uploadsStream,
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return const Center(
                          child: Text('Failed to load uploads'),
                        );
                      }
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final q = _q.trim().toLowerCase();
                      final docs = snap.data!.docs;

                      final all = docs.map((d) {
                        final m = d.data();
                        final name = _s(m['originalName']);
                        final contentType = _s(m['contentType']);
                        final storagePath = _s(m['storagePath']);

                        final uploadedBy = m['uploadedBy'];
                        final clientName = (uploadedBy is Map)
                            ? _s(uploadedBy['name'])
                            : '';
                        final fallbackClient = _s(m['clientName']).isNotEmpty
                            ? _s(m['clientName'])
                            : '';

                        final createdAt = _asDate(m['createdAt']);
                        final sizeBytes = (m['sizeBytes'] is num)
                            ? (m['sizeBytes'] as num).toInt()
                            : 0;

                        final requestedBy = _s(m['requestCreatedByName']);
                        final companyName = _s(m['requestBusinessName']);
                        final clientEmail = _s(m['requestClientEmail']);
                        final requestId = _s(m['requestId']);
                        final lastActivityAt = _asDate(m['lastActivityAt']);
                        final lastActivityAction = _s(m['lastActivityAction']);
                        final lastActivityActorName = _s(
                          m['lastActivityActorName'],
                        );

                        return _UploadDoc(
                          id: d.id,
                          docPath: d.reference.path,
                          originalName: name,
                          contentType: contentType,
                          storagePath: storagePath,
                          clientName: clientName.isNotEmpty
                              ? clientName
                              : (fallbackClient.isNotEmpty
                                    ? fallbackClient
                                    : '—'),
                          requestedBy: requestedBy.isNotEmpty
                              ? requestedBy
                              : '—',
                          companyName: companyName.isNotEmpty
                              ? companyName
                              : '—',
                          clientEmail: clientEmail.isNotEmpty
                              ? clientEmail
                              : '—',
                          when: createdAt,
                          lastActivityAt: lastActivityAt,
                          lastActivityAction: lastActivityAction,
                          lastActivityActorName: lastActivityActorName,
                          sizeBytes: sizeBytes,
                          requestId: requestId,
                          data: m,
                        );
                      }).toList();

                      final filtered = all.where((r) {
                        if (r.data['deleted'] == true) return false;

                        if (q.isNotEmpty) {
                          final hay =
                              ('${r.originalName} ${r.storagePath} ${r.clientName} '
                                      '${r.requestedBy} ${r.companyName} ${r.clientEmail} ${r.requestId}')
                                  .toLowerCase();
                          if (!hay.contains(q)) return false;
                        }

                        if (_typeFilter != _TypeFilter.all) {
                          final inferred = _inferTypeFilter(
                            r.originalName,
                            r.contentType,
                          );
                          if (inferred != _typeFilter) return false;
                        }

                        if (!_passesDateFilter(r.when)) return false;
                        return true;
                      }).toList();

                      filtered.sort((a, b) {
                        int res;
                        switch (_sortField) {
                          case _SortField.name:
                            res = a.originalName.toLowerCase().compareTo(
                              b.originalName.toLowerCase(),
                            );
                            break;
                          case _SortField.client:
                            res = a.clientName.toLowerCase().compareTo(
                              b.clientName.toLowerCase(),
                            );
                            break;
                          case _SortField.size:
                            res = a.sizeBytes.compareTo(b.sizeBytes);
                            break;
                          case _SortField.date:
                            res = (a.when ?? DateTime(0)).compareTo(
                              b.when ?? DateTime(0),
                            );
                            break;
                        }
                        return _sortAsc ? res : -res;
                      });

                      final visible = filtered.take(_visibleCount).toList();
                      final visibleIds = visible.map((e) => e.id).toSet();
                      final allVisibleSelected =
                          visible.isNotEmpty &&
                          _selected.containsAll(visibleIds);

                      _selectedDocsCache = visible
                          .where((e) => _selected.contains(e.id))
                          .toList();

                      return Column(
                        children: [
                          _filterBar(theme, all),
                          const SizedBox(height: 10),
                          if (isAdmin && _selected.isNotEmpty) ...[
                            Container(
                              height: 40,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF9FAFB),
                                border: Border.all(
                                  color: const Color(0xFFE4E7EC),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    '${_selected.length} selected',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: const Color(0xFF344054),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const Spacer(),
                                  SizedBox(
                                    height: 32,
                                    child: FilledButton.icon(
                                      onPressed:
                                          (_busy || _selectedDocsCache.isEmpty)
                                          ? null
                                          : () => _deleteSelectedAdmin(
                                              _selectedDocsCache,
                                            ),
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 16,
                                      ),
                                      label: const Text('Delete selected'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],

                          // ===== Table header =====
                          Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF9FAFB),
                              border: Border(
                                bottom: BorderSide(
                                  color: Colors.black.withValues(alpha: 0.06),
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: allVisibleSelected,
                                  onChanged: _busy
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
                                const SizedBox(width: 4),

                                // ✅ File column header (keep simple or make sortable)
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _toggleSort(_SortField.name),
                                    child: Row(
                                      children: [
                                        const Text(
                                          'File',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        _SortIndicator(
                                          active: _sortField == _SortField.name,
                                          asc: _sortAsc,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                if (!isMobile)
                                  SizedBox(
                                    width: 220,
                                    child: InkWell(
                                      onTap: () =>
                                          _toggleSort(_SortField.client),
                                      child: Row(
                                        children: [
                                          const Text(
                                            'Client',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          _SortIndicator(
                                            active:
                                                _sortField == _SortField.client,
                                            asc: _sortAsc,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                if (!isMobile)
                                  SizedBox(
                                    width: 160,
                                    child: InkWell(
                                      onTap: () => _toggleSort(_SortField.date),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          const Text(
                                            'Uploaded',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          _SortIndicator(
                                            active:
                                                _sortField == _SortField.date,
                                            asc: _sortAsc,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                if (!isMobile)
                                  SizedBox(
                                    width: 90,
                                    child: InkWell(
                                      onTap: () => _toggleSort(_SortField.size),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          const Text(
                                            'Size',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          _SortIndicator(
                                            active:
                                                _sortField == _SortField.size,
                                            asc: _sortAsc,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 78,
                                  child: Text(
                                    'Actions',
                                    textAlign: TextAlign.right,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF475467),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // ===== Rows =====
                          Expanded(
                            child: visible.isEmpty
                                ? Center(
                                    child: Text(
                                      q.isEmpty
                                          ? 'No uploads found.'
                                          : 'No files match your search.',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: const Color(0xFF667085),
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: visible.length,
                                    separatorBuilder: (_, __) =>
                                        const Divider(height: 1),
                                    itemBuilder: (c, i) {
                                      final row = visible[i];
                                      return _UploadRowEnhanced(
                                        id: row.id,
                                        docPath: row.docPath,
                                        data: row.data,
                                        selected: _selected.contains(row.id),
                                        isMobile: isMobile,
                                        isAdmin: isAdmin,
                                        clientName: row.clientName,
                                        requestedBy: row.requestedBy,
                                        companyName: row.companyName,
                                        clientEmail: row.clientEmail,
                                        lastActivityAt: row.lastActivityAt,
                                        lastActivityAction:
                                            row.lastActivityAction,
                                        lastActivityActorName:
                                            row.lastActivityActorName,
                                        onShowDetails: () =>
                                            _showUploadDetailsDialog(doc: row),
                                        onShowHistory: () =>
                                            _showActivityHistoryDialog(
                                              doc: row,
                                            ),
                                        formatWhen: (dt) => _fmt(context, dt),
                                        onSelect: (v) {
                                          setState(() {
                                            if (v) {
                                              _selected.add(row.id);
                                            } else {
                                              _selected.remove(row.id);
                                            }
                                          });
                                        },
                                        busy: _busy,
                                        onDownload: (path, name, type) =>
                                            _downloadFile(
                                              isAdmin: isAdmin,
                                              storagePath: path,
                                              filename: name,
                                              contentType: type,
                                              requestId:
                                                  (row.data['requestId'] ?? '')
                                                      .toString(),
                                              fileId: row.id,
                                            ),
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
          ),
        ),
      ),
    );
  }
}

/// Small, consistent label/value row for dialogs
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: const Color(0xFF667085),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF101828),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small sort chevron indicator (enterprise)
class _SortIndicator extends StatelessWidget {
  final bool active;
  final bool asc;

  const _SortIndicator({required this.active, required this.asc});

  @override
  Widget build(BuildContext context) {
    if (!active) {
      return const Icon(Icons.unfold_more, size: 16, color: Color(0xFF98A2B3));
    }
    return Icon(
      asc ? Icons.expand_less : Icons.expand_more,
      size: 16,
      color: const Color(0xFF475467),
    );
  }
}

class _UploadDoc {
  final String id;
  final String docPath;
  final String originalName;
  final String contentType;
  final String storagePath;
  final String clientName;

  final String requestedBy;
  final String companyName;
  final String clientEmail;

  final DateTime? when;
  final DateTime? lastActivityAt;
  final String lastActivityAction;
  final String lastActivityActorName;
  final int sizeBytes;
  final String requestId;
  final Map<String, dynamic> data;

  _UploadDoc({
    required this.id,
    required this.docPath,
    required this.originalName,
    required this.contentType,
    required this.storagePath,
    required this.clientName,
    required this.requestedBy,
    required this.companyName,
    required this.clientEmail,
    required this.when,
    required this.lastActivityAt,
    required this.lastActivityAction,
    required this.lastActivityActorName,
    required this.sizeBytes,
    required this.requestId,
    required this.data,
  });
}

/// ============================
/// ROW (ENHANCED + SELECT + CLIENT NAME)
/// ============================
class _UploadRowEnhanced extends StatelessWidget {
  final String id;
  final String docPath;
  final Map<String, dynamic> data;
  final bool selected;
  final bool isMobile;
  final bool busy;
  final bool isAdmin;
  final String clientName;
  final String Function(DateTime dt) formatWhen;
  final String requestedBy;
  final String companyName;
  final String clientEmail;
  final DateTime? lastActivityAt;
  final String lastActivityAction;
  final String lastActivityActorName;
  final ValueChanged<bool> onSelect;
  final void Function(String storagePath, String filename, String? contentType)
  onDownload;
  final VoidCallback onShowDetails;
  final VoidCallback onShowHistory;

  const _UploadRowEnhanced({
    required this.id,
    required this.docPath,
    required this.data,
    required this.selected,
    required this.isMobile,
    required this.busy,
    required this.clientName,
    required this.formatWhen,
    required this.onSelect,
    required this.requestedBy,
    required this.companyName,
    required this.clientEmail,
    required this.lastActivityAt,
    required this.lastActivityAction,
    required this.lastActivityActorName,
    required this.onDownload,
    required this.onShowDetails,
    required this.onShowHistory,
    required this.isAdmin,
  });

  static const bool _showImagePreview = false; // ✅ compact file box

  String _s(dynamic v) => (v ?? '').toString().trim();

  String _formatSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _activityLabel(String action) {
    switch (action.toLowerCase().trim()) {
      case 'upload':
        return 'Uploaded';
      case 'view':
        return 'Viewed';
      case 'download':
        return 'Downloaded';
      case 'delete':
        return 'Deleted';
      default:
        return action.trim().isEmpty ? 'No activity' : action.trim();
    }
  }

  String _fileTypeLabel(String fileName, String contentType) {
    final kind = detectFileKind(fileName: fileName, contentType: contentType);
    switch (kind) {
      case FileKind.pdf:
        return 'PDF document';
      case FileKind.word:
        return 'Word document';
      case FileKind.excel:
        return 'Excel spreadsheet';
      case FileKind.powerpoint:
        return 'Presentation';
      case FileKind.accounting:
        return 'Accounting file';
      case FileKind.image:
        return 'Image file';
      case FileKind.text:
        return 'Text file';
      case FileKind.archive:
        return 'Archive file';
      case FileKind.video:
        return 'Video file';
      case FileKind.audio:
        return 'Audio file';
      case FileKind.code:
        return 'Code file';
      case FileKind.data:
        return 'Data file';
      case FileKind.email:
        return 'Email file';
      case FileKind.cad:
        return 'CAD file';
      case FileKind.threeD:
        return '3D model';
      case FileKind.link:
        return 'Web link';
      case FileKind.executable:
        return 'Executable file';
      case FileKind.unknown:
        return 'File';
    }
  }

  String? _notableActivityText() {
    final action = lastActivityAction.toLowerCase().trim();
    if (action.isEmpty || action == 'upload') return null;

    final label = _activityLabel(action);
    final at = lastActivityAt;
    final when = at == null ? '' : formatWhen(at);
    return when.isEmpty ? label : '$label • $when';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final name = _s(data['originalName']).isEmpty
        ? 'Untitled'
        : _s(data['originalName']);
    final isDeleted = data['deleted'] == true;
    final contentType = _s(data['contentType']);
    final storagePath = _s(data['storagePath']);
    final sizeBytes = (data['sizeBytes'] is num)
        ? (data['sizeBytes'] as num).toInt()
        : 0;

    final createdAt = data['createdAt'];

    DateTime? when;
    if (createdAt is Timestamp) when = createdAt.toDate();

    final meta = resolveFileMeta(fileName: name, contentType: contentType);
    final fileTypeLabel = _fileTypeLabel(name, contentType);
    final notableActivity = _notableActivityText();

    return InkWell(
      onTap: busy ? null : () => onSelect(!selected),
      child: SizedBox(
        child: SizedBox(
          height: isMobile ? 58 : 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Checkbox(
                  value: selected,
                  onChanged: busy ? null : (v) => onSelect(v ?? false),
                ),
                Tooltip(
                  message: meta.tooltip,
                  child: Icon(meta.icon, color: meta.color, size: 18),
                ),
                const SizedBox(width: 6),
                if (!isMobile)
                  SizedBox(
                    width: 30,
                    child: meta.badge.isEmpty
                        ? const SizedBox()
                        : Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: meta.color.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              meta.badge,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: meta.color,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                  ),
                const SizedBox(width: 10),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        isDeleted ? '$name (Deleted)' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: isDeleted
                              ? const Color(0xFFB42318)
                              : const Color(0xFF101828),
                          decoration: isDeleted
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (isMobile)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              clientName.isNotEmpty ? clientName : '—',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: const Color(0xFF667085),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (notableActivity != null)
                              Text(
                                notableActivity,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: const Color(0xFF98A2B3),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 10.5,
                                ),
                              ),
                          ],
                        )
                      else
                        Text(
                          fileTypeLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: const Color(0xFF98A2B3),
                            fontWeight: FontWeight.w600,
                          ),
                        ),

                      if (_showImagePreview &&
                          !isMobile &&
                          meta.isImage &&
                          storagePath.isNotEmpty)
                        SizedBox(
                          height: 62, // ✅ height + top padding
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: FutureBuilder<String>(
                              future: FirebaseStorage.instance
                                  .ref(storagePath)
                                  .getDownloadURL(),
                              builder: (context, snap) {
                                if (!snap.hasData) {
                                  return const SizedBox(height: 56, width: 80);
                                }

                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.network(
                                    snap.data!,
                                    height: 56,
                                    width: 80,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const SizedBox(),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                if (!isMobile) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 220,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          clientName.isNotEmpty ? clientName : '—',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF344054),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          companyName.isNotEmpty ? companyName : clientEmail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: const Color(0xFF667085),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (!isMobile) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 160,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          when != null ? formatWhen(when) : '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF667085),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (notableActivity != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            notableActivity,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: const Color(0xFF98A2B3),
                              fontWeight: FontWeight.w600,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                if (!isMobile) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 90,
                    child: Text(
                      _formatSize(sizeBytes),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF667085),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],

                const SizedBox(width: 8),

                IconButton(
                  tooltip: 'Download',
                  icon: const Icon(Icons.download_outlined, size: 17),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 34,
                    height: 34,
                  ),
                  onPressed: (busy || isDeleted || storagePath.isEmpty)
                      ? null
                      : () => onDownload(storagePath, name, contentType),
                ),

                PopupMenuButton<String>(
                  tooltip: 'File actions',
                  itemBuilder: (c) => [
                    const PopupMenuItem(
                      value: 'download',
                      child: Text('Download'),
                    ),
                    const PopupMenuDivider(),

                    const PopupMenuItem(
                      value: 'copyName',
                      child: Text('Copy file name'),
                    ),
                    const PopupMenuItem(
                      value: 'copyClient',
                      child: Text('Copy client name'),
                    ),
                    const PopupMenuDivider(),

                    const PopupMenuItem(
                      value: 'details',
                      child: Text('View upload details'),
                    ),

                    if (isAdmin)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'Delete file',
                          style: TextStyle(color: Color(0xFFB42318)),
                        ),
                      ),

                    if (isAdmin)
                      const PopupMenuItem(
                        value: 'history',
                        child: Text('View activity history'),
                      ),
                  ],
                  onSelected: (v) async {
                    switch (v) {
                      case 'download':
                        if (busy) return;
                        if (storagePath.isEmpty) return;
                        onDownload(storagePath, name, contentType);
                        break;
                      case 'copyName':
                        await Clipboard.setData(ClipboardData(text: name));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('File name copied')),
                          );
                        }
                        break;

                      case 'copyClient':
                        await Clipboard.setData(
                          ClipboardData(text: clientName),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Client name copied')),
                          );
                        }
                        break;

                      case 'details':
                        onShowDetails();
                        break;

                      case 'delete':
                        if (busy) return;

                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete file'),
                            content: Text(
                              'Delete "$name"? The upload link will remain active, but this file will be marked as deleted.',
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

                        await FirebaseFunctions.instanceFor(
                          region: 'us-central1',
                        ).httpsCallable('softDeleteUploadFile').call({
                          'docPath': docPath,
                        });

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('File deleted')),
                          );
                        }
                        break;

                      case 'history':
                        onShowHistory();
                        break;
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
