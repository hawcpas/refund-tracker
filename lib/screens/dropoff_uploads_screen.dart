import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
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

  final Set<String> _selected = {};
  _SortField _sortField = _SortField.date;
  bool _sortAsc = false;

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
                      if (_selected.isNotEmpty) ...[
                        Text('${_selected.length} selected'),
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
                  const Divider(height: 1),

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

                        final rows = q.isEmpty
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

                        final visible =
                            rows.take(_visibleCount).toList();

                        return ListView.separated(
                          itemCount: visible.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: Colors.black12),
                          itemBuilder: (c, i) {
                            return _UploadRowEnhanced(
                              data: visible[i].data(),
                              formatWhen: (dt) => _fmt(context, dt),
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
  if (n.endsWith('.doc') || n.endsWith('.docx')) {
    return const _FileTypeMeta(
      icon: Icons.description_outlined,
      color: Color(0xFF1570EF),
      badge: 'DOC',
      tooltip: 'Word document',
      isImage: false,
    );
  }
  if (n.endsWith('.xls') || n.endsWith('.xlsx') || n.endsWith('.csv')) {
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
/// ROW (ENHANCED, SAFE)
/// ============================
class _UploadRowEnhanced extends StatelessWidget {
  final Map<String, dynamic> data;
  final String Function(DateTime dt) formatWhen;

  const _UploadRowEnhanced({
    required this.data,
    required this.formatWhen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final name = (data['originalName'] ?? 'Untitled').toString();
    final contentType = (data['contentType'] ?? '').toString();
    final storagePath = (data['storagePath'] ?? '').toString();

    final createdAt = data['createdAt'];
    DateTime? when;
    if (createdAt is Timestamp) when = createdAt.toDate();

    final meta = _fileMeta(name, contentType);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
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

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (meta.isImage && storagePath.isNotEmpty)
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
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          Text(
            when != null ? formatWhen(when!) : '',
            style: theme.textTheme.bodySmall,
          ),

          const SizedBox(width: 8),

          PopupMenuButton<String>(
            tooltip: 'Actions',
            itemBuilder: (c) => const [
              PopupMenuItem(value: 'open', child: Text('Open')),
              PopupMenuItem(value: 'download', child: Text('Download')),
            ],
            onSelected: (v) {
              // intentionally stubbed — wiring later
            },
          ),
        ],
      ),
    );
  }
}