import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_colors.dart';

enum _SortField { name, client, size, date }

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

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _uploadsStream;

  // ✅ enterprise table state
  final Set<String> _selected = {};
  _SortField _sortField = _SortField.date;
  bool _sortAsc = false;

  // ✅ pagination (client-side, safe)
  static const int _pageSize = 50;
  int _visibleCount = _pageSize;

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
                  // ✅ Header
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

                      // ✅ Bulk actions
                      if (_selected.isNotEmpty) ...[
                        Text(
                          '${_selected.length} selected',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: isAdmin ? () {} : null,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Delete'),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 14),

                  // ✅ Search
                  TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() {
                      _q = v.toLowerCase();
                      _visibleCount = _pageSize;
                    }),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                      hintText:
                          'Search by file name, client name, or storage path…',
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ✅ Column headers
                  _HeaderRow(
                    sortField: _sortField,
                    asc: _sortAsc,
                    onSort: (f) => setState(() {
                      _sortAsc = _sortField == f ? !_sortAsc : true;
                      _sortField = f;
                    }),
                    onToggleAll: (v) =>
                        setState(() => _selected.clear()),
                  ),

                  const Divider(height: 1),

                  // ✅ Data
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _uploadsStream,
                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }

                        final q = _q.trim();
                        final docs = snap.data!.docs;

                        List<QueryDocumentSnapshot<Map<String, dynamic>>> rows =
                            q.isEmpty
                                ? docs
                                : docs.where((d) {
                                    final m = d.data();
                                    return _s(m['originalName'])
                                            .toLowerCase()
                                            .contains(q) ||
                                        _s(m['storagePath'])
                                            .toLowerCase()
                                            .contains(q) ||
                                        _s((m['uploadedBy'] as Map?)?['name'])
                                            .toLowerCase()
                                            .contains(q);
                                  }).toList();

                        // ✅ sort
                        rows.sort((a, b) {
                          final A = a.data(), B = b.data();
                          int r = 0;
                          switch (_sortField) {
                            case _SortField.name:
                              r = _s(A['originalName'])
                                  .compareTo(_s(B['originalName']));
                              break;
                            case _SortField.client:
                              r = _s((A['uploadedBy'] as Map?)?['name'])
                                  .compareTo(
                                      _s((B['uploadedBy'] as Map?)?['name']));
                              break;
                            case _SortField.size:
                              r = (A['sizeBytes'] ?? 0)
                                  .compareTo(B['sizeBytes'] ?? 0);
                              break;
                            case _SortField.date:
                              r = (A['createdAt'] as Timestamp?)
                                      ?.compareTo(B['createdAt']) ??
                                  0;
                              break;
                          }
                          return _sortAsc ? r : -r;
                        });

                        final visible =
                            rows.take(_visibleCount).toList();

                        return ListView.separated(
                          itemCount: visible.length + 1,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: Colors.black12),
                          itemBuilder: (c, i) {
                            if (i == visible.length) {
                              if (visible.length >= rows.length) {
                                return const SizedBox(height: 12);
                              }
                              return TextButton(
                                onPressed: () => setState(() =>
                                    _visibleCount += _pageSize),
                                child: const Text('Load more'),
                              );
                            }

                            final d = visible[i];
                            final id = d.reference.path;

                            return _UploadRowEnterprise(
                              selected: _selected.contains(id),
                              onSelect: (v) => setState(() {
                                v ? _selected.add(id) : _selected.remove(id);
                              }),
                              data: d.data(),
                              formatWhen: (dt) => _fmt(context, dt),
                              canDelete: isAdmin,
                            );
                          },
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

/// ============================
/// HEADER
/// ============================
class _HeaderRow extends StatelessWidget {
  final _SortField sortField;
  final bool asc;
  final ValueChanged<_SortField> onSort;
  final ValueChanged<bool?> onToggleAll;

  const _HeaderRow({
    required this.sortField,
    required this.asc,
    required this.onSort,
    required this.onToggleAll,
  });

  @override
  Widget build(BuildContext context) {
    TextStyle h() => Theme.of(context).textTheme.labelMedium!.copyWith(
          fontWeight: FontWeight.w800,
          color: const Color(0xFF667085),
        );

    Widget col(String t, _SortField f, {int flex = 1}) {
      return Expanded(
        flex: flex,
        child: InkWell(
          onTap: () => onSort(f),
          child: Row(
            children: [
              Text(t, style: h()),
              if (sortField == f)
                Icon(
                  asc ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 14,
                ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Checkbox(value: false, onChanged: onToggleAll),
          col('File name', _SortField.name, flex: 4),
          col('Client', _SortField.client, flex: 3),
          col('Size', _SortField.size),
          col('Uploaded', _SortField.date, flex: 2),
          const SizedBox(width: 88),
        ],
      ),
    );
  }
}

/// ============================
/// ROW
/// ============================
class _UploadRowEnterprise extends StatelessWidget {
  final bool selected;
  final ValueChanged<bool> onSelect;
  final Map<String, dynamic> data;
  final String Function(DateTime dt) formatWhen;
  final bool canDelete;

  const _UploadRowEnterprise({
    required this.selected,
    required this.onSelect,
    required this.data,
    required this.formatWhen,
    required this.canDelete,
  });

  String _s(dynamic v) => (v ?? '').toString().trim();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final name = _s(data['originalName']);
    final sizeBytes = data['sizeBytes'];
    final uploadedBy = (data['uploadedBy'] as Map?) ?? {};
    final client = _s(uploadedBy['name']);

    final createdAt = data['createdAt'];
    DateTime? when;
    if (createdAt is Timestamp) when = createdAt.toDate();

    String size = '';
    if (sizeBytes is num) {
      final b = sizeBytes.toInt();
      if (b < 1024) size = '$b B';
      else if (b < 1024 * 1024)
        size = '${(b / 1024).toStringAsFixed(1)} KB';
      else
        size = '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    return Container(
      height: 42,
      color: selected ? const Color(0xFFF2F4F7) : null,
      child: Row(
        children: [
          Checkbox(value: selected, onChanged: (v) => onSelect(v ?? false)),
          Expanded(
            flex: 4,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium!.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(flex: 3, child: Text(client)),
          Expanded(child: Text(size)),
          Expanded(
            flex: 2,
            child: Text(when != null ? formatWhen(when!) : ''),
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined, size: 18),
            tooltip: 'Download',
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: 'Delete',
            onPressed: canDelete ? () {} : null,
          ),
        ],
      ),
    );
  }
}