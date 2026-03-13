import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';

enum _SortField { name, client, size, date }

enum _TypeFilter { all, pdf, doc, xls, img, txt, other }

enum _DateFilter { all, today, last7, last30 }

class DropoffUploadsScreen extends StatefulWidget {
  const DropoffUploadsScreen({super.key});

  @override
  State<DropoffUploadsScreen> createState() => _DropoffUploadsScreenState();
}

class _DropoffUploadsScreenState extends State<DropoffUploadsScreen> {
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
        .get(const GetOptions(source: Source.server));

    _role = (snap.data()?['role'] ?? '').toString().toLowerCase().trim();
    final isAdmin = _role == 'admin';

    _uploadsStream = isAdmin
        ? FirebaseFirestore.instance
              .collectionGroup('files')
              .orderBy('createdAt', descending: true)
              .limit(500)
              .snapshots()
        : FirebaseFirestore.instance
              .collectionGroup('files')
              .where('requestCreatedByRole', isEqualTo: 'associate')
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
    final n = name.toLowerCase();
    final t = contentType.toLowerCase();
    if (n.endsWith('.pdf') || t.contains('pdf')) return _TypeFilter.pdf;
    if (n.endsWith('.doc') || n.endsWith('.docx') || t.contains('word')) {
      return _TypeFilter.doc;
    }
    if (n.endsWith('.xls') ||
        n.endsWith('.xlsx') ||
        n.endsWith('.csv') ||
        t.contains('excel') ||
        t.contains('spreadsheet'))
      return _TypeFilter.xls;
    if (t.startsWith('image/') ||
        n.endsWith('.png') ||
        n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.gif') ||
        n.endsWith('.webp'))
      return _TypeFilter.img;
    if (n.endsWith('.txt') || n.endsWith('.log')) return _TypeFilter.txt;
    return _TypeFilter.other;
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
        _sortAsc = true;
      }
      _visibleCount = _pageSize;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loadingRole) {
      return const Scaffold(
        backgroundColor: AppColors.pageBackgroundLight,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isAdmin = _role == 'admin';
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Scaffold(
      backgroundColor: AppColors.pageBackgroundLight,
      appBar: AppBar(title: const Text('Client Upload Activity')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black.withOpacity(0.05)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ===== Header =====
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Client Uploaded Files',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isAdmin
                                  ? 'All uploads across all client upload links.'
                                  : 'Uploads from associate-created client upload links.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFF475467),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // ===== Search =====
                  TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() {
                      _q = v.toLowerCase();
                      _visibleCount = _pageSize;
                      _selected.clear();
                    }),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search by file name, client name, or path…',
                    ),
                  ),

                  const SizedBox(height: 10),

                  // ===== Filters (enterprise) =====
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: isMobile ? 220 : 260,
                        child: DropdownButtonFormField<_TypeFilter>(
                          value: _typeFilter,
                          isDense: true,
                          decoration: const InputDecoration(
                            labelText: 'File type',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: _TypeFilter.all,
                              child: Text('All types'),
                            ),
                            DropdownMenuItem(
                              value: _TypeFilter.pdf,
                              child: Text('PDF'),
                            ),
                            DropdownMenuItem(
                              value: _TypeFilter.doc,
                              child: Text('Word'),
                            ),
                            DropdownMenuItem(
                              value: _TypeFilter.xls,
                              child: Text('Excel / CSV'),
                            ),
                            DropdownMenuItem(
                              value: _TypeFilter.img,
                              child: Text('Images'),
                            ),
                            DropdownMenuItem(
                              value: _TypeFilter.txt,
                              child: Text('Text / Log'),
                            ),
                            DropdownMenuItem(
                              value: _TypeFilter.other,
                              child: Text('Other'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _typeFilter = v;
                              _visibleCount = _pageSize;
                              _selected.clear();
                            });
                          },
                        ),
                      ),
                      SizedBox(
                        width: isMobile ? 220 : 240,
                        child: DropdownButtonFormField<_DateFilter>(
                          value: _dateFilter,
                          isDense: true,
                          decoration: const InputDecoration(
                            labelText: 'Date range',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: _DateFilter.all,
                              child: Text('All time'),
                            ),
                            DropdownMenuItem(
                              value: _DateFilter.today,
                              child: Text('Today'),
                            ),
                            DropdownMenuItem(
                              value: _DateFilter.last7,
                              child: Text('Last 7 days'),
                            ),
                            DropdownMenuItem(
                              value: _DateFilter.last30,
                              child: Text('Last 30 days'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _dateFilter = v;
                              _visibleCount = _pageSize;
                              _selected.clear();
                            });
                          },
                        ),
                      ),

                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () {
                                setState(() {
                                  _q = '';
                                  _searchCtrl.clear();
                                  _typeFilter = _TypeFilter.all;
                                  _dateFilter = _DateFilter.all;
                                  _sortField = _SortField.date;
                                  _sortAsc = false;
                                  _visibleCount = _pageSize;
                                  _selected.clear();
                                });
                              },
                        icon: const Icon(Icons.filter_alt_off, size: 18),
                        label: const Text('Clear'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),
                  const Divider(height: 1),

                  // ===== Table header + list =====
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _uploadsStream,
                      builder: (context, snap) {
                        if (snap.hasError) {
                          final msg = snap.error.toString();
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                msg.contains('permission-denied')
                                    ? 'You do not have permission to view these uploads.'
                                    : 'Failed to load uploads: $msg',
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          );
                        }

                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        if (!snap.hasData) {
                          return const Center(child: Text('No data.'));
                        }

                        final q = _q.trim().toLowerCase();
                        final docs = snap.data!.docs;

                        // Build normalized doc models
                        final all = docs.map((d) {
                          final m = d.data();
                          final name = _s(m['originalName']);
                          final contentType = _s(m['contentType']);
                          final storagePath = _s(m['storagePath']);

                          // Client name (requested)
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
                            when: createdAt,
                            sizeBytes: sizeBytes,
                            data: m,
                          );
                        }).toList();

                        // Filter
                        List<_UploadDoc> filtered = all.where((r) {
                          // text search
                          if (q.isNotEmpty) {
                            final hay =
                                ('${r.originalName} ${r.storagePath} ${r.clientName}')
                                    .toLowerCase();
                            if (!hay.contains(q)) return false;
                          }

                          // type filter
                          if (_typeFilter != _TypeFilter.all) {
                            final inferred = _inferTypeFilter(
                              r.originalName,
                              r.contentType,
                            );
                            if (inferred != _typeFilter) return false;
                          }

                          // date filter
                          if (!_passesDateFilter(r.when)) return false;

                          return true;
                        }).toList();

                        // Sort
                        int cmpString(String a, String b) =>
                            a.toLowerCase().compareTo(b.toLowerCase());
                        int cmpInt(int a, int b) => a.compareTo(b);
                        int cmpDate(DateTime? a, DateTime? b) {
                          if (a == null && b == null) return 0;
                          if (a == null) return -1;
                          if (b == null) return 1;
                          return a.compareTo(b);
                        }

                        filtered.sort((a, b) {
                          int res;
                          switch (_sortField) {
                            case _SortField.name:
                              res = cmpString(a.originalName, b.originalName);
                              break;
                            case _SortField.client:
                              res = cmpString(a.clientName, b.clientName);
                              break;
                            case _SortField.size:
                              res = cmpInt(a.sizeBytes, b.sizeBytes);
                              break;
                            case _SortField.date:
                              res = cmpDate(a.when, b.when);
                              break;
                          }
                          return _sortAsc ? res : -res;
                        });

                        // Pagination
                        final visible = filtered.take(_visibleCount).toList();

                        // Selection helpers
                        final visibleIds = visible.map((e) => e.id).toSet();
                        final allVisibleSelected =
                            visible.isNotEmpty &&
                            _selected.containsAll(visibleIds);

                        final selectedDocs = visible
                            .where((e) => _selected.contains(e.id))
                            .toList();

                        _selectedDocsCache = selectedDocs;

                        return Column(
                          children: [
                            // Header row (select all + sortable columns)
                            Container(
                              height: 44,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
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

                                  // File column
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
                                            active:
                                                _sortField == _SortField.name,
                                            asc: _sortAsc,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  // Client column (hide on very small screens)
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
                                                  _sortField ==
                                                  _SortField.client,
                                              asc: _sortAsc,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                  // Size
                                  if (!isMobile)
                                    SizedBox(
                                      width: 100,
                                      child: InkWell(
                                        onTap: () =>
                                            _toggleSort(_SortField.size),
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

                                  // Uploaded
                                  SizedBox(
                                    width: isMobile ? 140 : 180,
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

                                  const SizedBox(width: 6),

                                  // Bulk delete button sits in header when selected
                                  if (_selected.isNotEmpty) ...[
                                    Text('${_selected.length} selected'),
                                    const SizedBox(width: 12),
                                    FilledButton.icon(
                                      onPressed:
                                          (!isAdmin ||
                                              _busy ||
                                              _selectedDocsCache.isEmpty)
                                          ? null
                                          : () => _deleteSelectedAdmin(
                                              _selectedDocsCache,
                                            ),
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 18,
                                      ),
                                      label: Text(
                                        'Delete (${_selected.length})',
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            // List
                            Expanded(
                              child: ListView.separated(
                                itemCount: visible.length + 1,
                                separatorBuilder: (_, __) => const Divider(
                                  height: 1,
                                  color: Colors.black12,
                                ),
                                itemBuilder: (c, i) {
                                  if (i == visible.length) {
                                    // Footer: load more
                                    if (_visibleCount >= filtered.length) {
                                      return const SizedBox(height: 8);
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      child: Center(
                                        child: OutlinedButton(
                                          onPressed: _busy
                                              ? null
                                              : () => setState(() {
                                                  _visibleCount =
                                                      (_visibleCount +
                                                              _pageSize)
                                                          .clamp(0, 500);
                                                }),
                                          child: Text(
                                            'Load more (${filtered.length - visible.length} remaining)',
                                          ),
                                        ),
                                      ),
                                    );
                                  }

                                  final row = visible[i];
                                  final selected = _selected.contains(row.id);

                                  return _UploadRowEnhanced(
                                    id: row.id,
                                    docPath: row.docPath,
                                    data: row.data,
                                    selected: selected,
                                    isMobile: isMobile,
                                    clientName: row.clientName,
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
  final DateTime? when;
  final int sizeBytes;
  final Map<String, dynamic> data;

  _UploadDoc({
    required this.id,
    required this.docPath,
    required this.originalName,
    required this.contentType,
    required this.storagePath,
    required this.clientName,
    required this.when,
    required this.sizeBytes,
    required this.data,
  });
}

/// ============================
/// FILE TYPE META
/// ============================
class _FileTypeMeta {
  final IconData icon;
  final Color color;
  final String badge;
  final String tooltip;
  final bool isImage;

  const _FileTypeMeta({
    required this.icon,
    required this.color,
    required this.badge,
    required this.tooltip,
    required this.isImage,
  });
}

_FileTypeMeta _fileMeta(String name, String type) {
  final n = name.toLowerCase();
  final t = type.toLowerCase();

  if (n.endsWith('.pdf') || t.contains('pdf')) {
    return const _FileTypeMeta(
      icon: Icons.picture_as_pdf_outlined,
      color: Color(0xFFD92D20),
      badge: 'PDF',
      tooltip: 'PDF document',
      isImage: false,
    );
  }
  if (n.endsWith('.doc') || n.endsWith('.docx') || t.contains('word')) {
    return const _FileTypeMeta(
      icon: Icons.description_outlined,
      color: Color(0xFF1570EF),
      badge: 'DOC',
      tooltip: 'Word document',
      isImage: false,
    );
  }
  if (n.endsWith('.xls') ||
      n.endsWith('.xlsx') ||
      n.endsWith('.csv') ||
      t.contains('excel')) {
    return const _FileTypeMeta(
      icon: Icons.table_chart_outlined,
      color: Color(0xFF027A48),
      badge: 'XLS',
      tooltip: 'Spreadsheet',
      isImage: false,
    );
  }
  if (t.startsWith('image/')) {
    return const _FileTypeMeta(
      icon: Icons.image_outlined,
      color: Color(0xFF2E90FA),
      badge: 'IMG',
      tooltip: 'Image file',
      isImage: true,
    );
  }
  if (n.endsWith('.txt') || n.endsWith('.log')) {
    return const _FileTypeMeta(
      icon: Icons.article_outlined,
      color: Color(0xFF0E7090),
      badge: 'TXT',
      tooltip: 'Text file',
      isImage: false,
    );
  }
  if (n.endsWith('.ps1')) {
    return const _FileTypeMeta(
      icon: Icons.terminal_outlined,
      color: Color(0xFF6941C6),
      badge: 'PS',
      tooltip: 'PowerShell script',
      isImage: false,
    );
  }

  return const _FileTypeMeta(
    icon: Icons.insert_drive_file_outlined,
    color: Color(0xFF667085),
    badge: 'FILE',
    tooltip: 'File',
    isImage: false,
  );
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
  final String clientName;
  final String Function(DateTime dt) formatWhen;
  final ValueChanged<bool> onSelect;

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
  });

  String _s(dynamic v) => (v ?? '').toString().trim();

  String _formatSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final name = _s(data['originalName']).isEmpty
        ? 'Untitled'
        : _s(data['originalName']);
    final contentType = _s(data['contentType']);
    final storagePath = _s(data['storagePath']);
    final sizeBytes = (data['sizeBytes'] is num)
        ? (data['sizeBytes'] as num).toInt()
        : 0;

    final createdAt = data['createdAt'];
    DateTime? when;
    if (createdAt is Timestamp) when = createdAt.toDate();

    final meta = _fileMeta(name, contentType);

    return InkWell(
      onTap: busy ? null : () => onSelect(!selected),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Checkbox(
              value: selected,
              onChanged: busy ? null : (v) => onSelect(v ?? false),
            ),

            Tooltip(
              message: meta.tooltip,
              child: Icon(meta.icon, color: meta.color, size: 20),
            ),
            const SizedBox(width: 6),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: meta.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                meta.badge,
                style: TextStyle(
                  color: meta.color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Main cell: filename + client name (always shown)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF101828),
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Mobile: keep client under filename (since Client column is hidden)
                  if (isMobile) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Client: $clientName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF667085),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],

                  // Optional image preview (kept)
                  if (!isMobile && meta.isImage && storagePath.isNotEmpty)
                    FutureBuilder<String>(
                      future: FirebaseStorage.instance
                          .ref(storagePath)
                          .getDownloadURL(),
                      builder: (context, snap) {
                        if (!snap.hasData) return const SizedBox();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              snap.data!,
                              height: 56,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox(),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),

            // Client column (desktop/table)
            if (!isMobile) ...[
              const SizedBox(width: 10),
              SizedBox(
                width: 220, // match your header width
                child: Text(
                  clientName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF475467),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],

            if (!isMobile) ...[
              const SizedBox(width: 10),
              SizedBox(
                width: 100,
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

            const SizedBox(width: 10),

            SizedBox(
              width: isMobile ? 140 : 180,
              child: Text(
                when != null ? formatWhen(when!) : '',
                textAlign: TextAlign.right,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF667085),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Row actions (copy download url, copy storage path)
            PopupMenuButton<String>(
              tooltip: 'Actions',
              itemBuilder: (c) => const [
                PopupMenuItem(value: 'copyName', child: Text('Copy file name')),
                PopupMenuItem(
                  value: 'copyClient',
                  child: Text('Copy client name'),
                ),
                PopupMenuItem(
                  value: 'copyPath',
                  child: Text('Copy storage path'),
                ),
                PopupMenuItem(
                  value: 'open',
                  child: Text('Open (download URL)'),
                ),
              ],
              onSelected: (v) async {
                if (v == 'copyName') {
                  await Clipboard.setData(ClipboardData(text: name));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('File name copied')),
                    );
                  }
                }
                if (v == 'copyClient') {
                  await Clipboard.setData(ClipboardData(text: clientName));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Client name copied')),
                    );
                  }
                }
                if (v == 'copyPath') {
                  await Clipboard.setData(ClipboardData(text: storagePath));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Storage path copied')),
                    );
                  }
                }
                if (v == 'open') {
                  if (storagePath.isEmpty) return;
                  final url = await FirebaseStorage.instance
                      .ref(storagePath)
                      .getDownloadURL();
                  final uri = Uri.parse(url);
                  await launchUrl(uri, webOnlyWindowName: '_blank');
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
