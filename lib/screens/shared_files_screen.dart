import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';

class SharedFilesScreen extends StatelessWidget {
  const SharedFilesScreen({super.key});

  Future<void> _openFile(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open file')));
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.pageBackgroundLight,
      appBar: AppBar(title: const Text('Shared Files')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black.withOpacity(0.05)),
                ),
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Shared Files',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF101828),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Files available to everyone in the app.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF475467),
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 14),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('shared_files')
                          .where('visible', isEqualTo: true)
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
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        final docs = snap.data!.docs;
                        if (docs.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('No shared files yet.'),
                          );
                        }

                        return Column(
                          children: [
                            for (int i = 0; i < docs.length; i++) ...[
                              _SharedFileRow(
                                data: docs[i].data() as Map<String, dynamic>,
                                onTap: (url) => _openFile(context, url),
                              ),
                              if (i != docs.length - 1)
                                Divider(color: Colors.black.withOpacity(0.06)),
                            ],
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

class _SharedFileRow extends StatefulWidget {
  final Map<String, dynamic> data;
  final void Function(String url) onTap;

  const _SharedFileRow({required this.data, required this.onTap});

  @override
  State<_SharedFileRow> createState() => _SharedFileRowState();
}

class _SharedFileRowState extends State<_SharedFileRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final description = (widget.data['description'] ?? '').toString();
    final url = (widget.data['fileUrl'] ?? '').toString().trim();

    // ✅ Prefer Firestore 'name', otherwise derive it from URL/path
    final name = _bestDisplayName(widget.data, url);

    // ✅ Firestore can return int/long/double depending on platform
    final sizeRaw = widget.data['sizeBytes'];
    final size = (sizeRaw is num) ? sizeRaw.toInt() : 0;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: url.isEmpty ? null : () => widget.onTap(url),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandBlue,
                        decoration: _hovered ? TextDecoration.underline : null,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF667085),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                size == 0 ? '' : _formatFileSize(size),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: const Color(0xFF667085),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.open_in_new,
                size: 16,
                color: AppColors.brandBlue.withOpacity(_hovered ? 0.75 : 0.55),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _bestDisplayName(Map<String, dynamic> data, String url) {
    // 1) explicit name set in Firestore
    final rawName = (data['name'] ?? '').toString().trim();
    if (rawName.isNotEmpty) return rawName;

    // 2) if you store a storage path in Firestore, prefer that
    final rawPath = (data['storagePath'] ?? data['path'] ?? '')
        .toString()
        .trim();
    if (rawPath.isNotEmpty) {
      final last = rawPath
          .split('/')
          .where((p) => p.isNotEmpty)
          .toList()
          .lastOrNull;
      if (last != null && last.isNotEmpty) return last;
    }

    // 3) derive from URL
    final fromUrl = _filenameFromUrl(url);
    if (fromUrl.isNotEmpty) return fromUrl;

    return 'Untitled';
  }

  String _filenameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';

    // Firebase Storage download URLs often look like:
    // https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<ENCODED_PATH>?alt=media&token=...
    final segments = uri.pathSegments;

    final oIndex = segments.indexOf('o');
    if (oIndex != -1 && oIndex + 1 < segments.length) {
      final encodedFullPath = segments[oIndex + 1];
      final decodedFullPath = Uri.decodeComponent(encodedFullPath);
      final last = decodedFullPath
          .split('/')
          .where((p) => p.isNotEmpty)
          .toList()
          .lastOrNull;
      if (last != null && last.isNotEmpty) return last;
    }

    // fallback: last path segment
    if (segments.isNotEmpty) {
      return Uri.decodeComponent(segments.last);
    }

    return '';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

extension _LastOrNull<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
