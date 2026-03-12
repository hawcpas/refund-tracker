import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_colors.dart';

class DropoffUploadsScreen extends StatefulWidget {
  const DropoffUploadsScreen({super.key});

  @override
  State<DropoffUploadsScreen> createState() => _DropoffUploadsScreenState();
}

class _DropoffUploadsScreenState extends State<DropoffUploadsScreen> {
  String _q = '';
  final _searchCtrl = TextEditingController();

  String? _role;
  bool _loadingRole = true;

  late Stream<QuerySnapshot<Map<String, dynamic>>> _uploadsStream;

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

  String _safeString(dynamic v) => (v ?? '').toString().trim();

  String _formatDateTime(BuildContext context, DateTime dt) {
    final loc = MaterialLocalizations.of(context);
    final date = loc.formatShortDate(dt);
    final time = loc.formatTimeOfDay(
      TimeOfDay.fromDateTime(dt),
      alwaysUse24HourFormat: false,
    );
    return '$date • $time';
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
      appBar: AppBar(title: const Text("Client Upload Activity")),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black.withOpacity(0.05)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Client Uploaded Files",
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF101828),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isAdmin
                          ? "All files uploaded through client upload links (admin + associate requests)."
                          : "Files uploaded through client upload links created by associates.",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF475467),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ✅ SEARCH — NOW STABLE
                    TextField(
                      controller: _searchCtrl,
                      onChanged: (v) {
                        setState(() {
                          _q = v.toLowerCase();
                        });
                      },
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText:
                            'Search by client name, file name, or request ID…',
                      ),
                    ),
                    const SizedBox(height: 14),

                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _uploadsStream,
                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        final q = _q.trim();
                        final docs = snap.data!.docs;

                        final filtered = q.isEmpty
                            ? docs
                            : docs.where((d) {
                                final data = d.data();
                                return _safeString(
                                      data['originalName'],
                                    ).toLowerCase().contains(q) ||
                                    _safeString(
                                      data['storagePath'],
                                    ).toLowerCase().contains(q) ||
                                    _safeString(
                                      (data['uploadedBy'] as Map?)?['name'],
                                    ).toLowerCase().contains(q);
                              }).toList();

                        if (filtered.isEmpty) {
                          return const Text(
                            'No uploads found.',
                            style: TextStyle(color: Color(0xFF667085)),
                          );
                        }

                        return Column(
                          children: [
                            for (final d in filtered)
                              _UploadRow(
                                data: d.data(),
                                fullPath: d.reference.path,
                                formatWhen: (dt) =>
                                    _formatDateTime(context, dt),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UploadRow extends StatelessWidget {
  final Map<String, dynamic> data;
  final String fullPath;
  final String Function(DateTime dt) formatWhen;

  const _UploadRow({
    required this.data,
    required this.fullPath,
    required this.formatWhen,
  });

  String _safeString(dynamic v) => (v ?? '').toString().trim();

  String _extractRequestIdFromPath(String path) {
    final parts = path.split('/');
    final i = parts.indexOf('dropoff_requests');
    if (i != -1 && i + 1 < parts.length) return parts[i + 1];
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final originalName = _safeString(data['originalName']);
    final storagePath = _safeString(data['storagePath']);
    final sizeBytes = data['sizeBytes'];
    final contentType = _safeString(data['contentType']);

    final uploadedBy = (data['uploadedBy'] is Map)
        ? Map<String, dynamic>.from(data['uploadedBy'])
        : <String, dynamic>{};
    final uploadedByName = _safeString(uploadedBy['name']);

    final createdAt = data['createdAt'];
    DateTime? when;
    if (createdAt is Timestamp) when = createdAt.toDate();

    final requestId = _extractRequestIdFromPath(fullPath);

    String sizeLabel = '';
    if (sizeBytes is num) {
      final b = sizeBytes.toInt();
      if (b < 1024) {
        sizeLabel = '$b B';
      } else if (b < 1024 * 1024) {
        sizeLabel = '${(b / 1024).toStringAsFixed(1)} KB';
      } else {
        sizeLabel = '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.insert_drive_file_outlined,
            size: 20,
            color: AppColors.brandBlue.withOpacity(0.85),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  originalName.isNotEmpty ? originalName : 'Untitled',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF101828),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (uploadedByName.isNotEmpty) uploadedByName,
                    if (sizeLabel.isNotEmpty) sizeLabel,
                    if (contentType.isNotEmpty) contentType,
                  ].join(' • '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF667085),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (when != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule,
                        size: 14,
                        color: Color(0xFF667085),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        formatWhen(when!),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: const Color(0xFF667085),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
                if (requestId.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Request ID: ${requestId.substring(0, requestId.length > 8 ? 8 : requestId.length)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF667085),
                      fontWeight: FontWeight.w700,
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
