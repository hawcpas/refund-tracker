import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import '../utils/file_kind.dart';

class SecureShareScreen extends StatefulWidget {
  const SecureShareScreen({super.key});

  @override
  State<SecureShareScreen> createState() => _SecureShareScreenState();
}

class _SecureShareScreenState extends State<SecureShareScreen> {
  final _passwordCtrl = TextEditingController();
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

  bool _loading = false;
  String? _error;
  String? _shareId;
  DateTime? _expiresAt;
  List<_SecureSharedFile> _files = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shareId ??= Uri.base.queryParameters['sid']?.trim();
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '-';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime dt) {
    final loc = MaterialLocalizations.of(context);
    return '${loc.formatShortDate(dt)} at ${loc.formatTimeOfDay(TimeOfDay.fromDateTime(dt))}';
  }

  Future<void> _unlock() async {
    final shareId = (_shareId ?? '').trim();
    final password = _passwordCtrl.text.trim();
    if (shareId.isEmpty) {
      setState(() => _error = 'This secure link is missing its share ID.');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Enter the password provided by our office.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _functions.httpsCallable('openSecureFileShare').call({
        'shareId': shareId,
        'password': password,
      });

      final data = Map<String, dynamic>.from(res.data as Map);
      final rawFiles = (data['files'] is List) ? data['files'] as List : [];
      final expiresAtMillis = data['expiresAtMillis'];

      setState(() {
        _expiresAt = expiresAtMillis is num
            ? DateTime.fromMillisecondsSinceEpoch(expiresAtMillis.toInt())
            : null;
        _files = rawFiles
            .map((f) => _SecureSharedFile.fromMap(Map<String, dynamic>.from(f)))
            .toList();
      });
    } on FirebaseFunctionsException catch (e) {
      setState(() {
        _error = e.message?.trim().isNotEmpty == true
            ? e.message
            : 'Unable to open this secure share.';
      });
    } catch (e) {
      setState(() => _error = 'Unable to open this secure share.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download(_SecureSharedFile file) async {
    final shareId = (_shareId ?? '').trim();
    final password = _passwordCtrl.text.trim();
    if (shareId.isEmpty || password.isEmpty) return;

    setState(() => _loading = true);
    try {
      final res = await _functions
          .httpsCallable('getSecureShareDownloadUrl')
          .call({
            'shareId': shareId,
            'password': password,
            'fileId': file.fileId,
          });

      final data = Map<String, dynamic>.from(res.data as Map);
      final url = (data['url'] ?? '').toString();
      if (url.isEmpty) throw Exception('Missing download URL.');

      final uri = Uri.parse(url);
      if (kIsWeb) {
        await launchUrl(uri, webOnlyWindowName: '_self');
      } else {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message ?? 'Download failed.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Download failed.')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unlocked = _files.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE4E7EC)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.brandBlue.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.lock_outline,
                            color: AppColors.brandBlue,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Secure file share',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: const Color(0xFF101828),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                unlocked
                                    ? 'Download the files shared with you.'
                                    : 'Enter the password provided by our office.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF667085),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    if (!unlocked) ...[
                      TextField(
                        controller: _passwordCtrl,
                        obscureText: true,
                        enabled: !_loading,
                        onSubmitted: (_) => _unlock(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.key_outlined),
                          errorText: _error,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 42,
                        child: FilledButton.icon(
                          onPressed: _loading ? null : _unlock,
                          icon: _loading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.lock_open_outlined, size: 18),
                          label: const Text('Open secure files'),
                        ),
                      ),
                    ] else ...[
                      if (_expiresAt != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Available until ${_formatDate(_expiresAt!)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF667085),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFE4E7EC)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _files.length,
                          separatorBuilder: (_, __) => const Divider(
                            height: 1,
                            color: Color(0xFFE4E7EC),
                          ),
                          itemBuilder: (context, index) {
                            final file = _files[index];
                            final meta = resolveFileMeta(
                              fileName: file.originalName,
                              contentType: file.contentType,
                            );
                            return ListTile(
                              leading: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: meta.color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  meta.icon,
                                  color: meta.color,
                                  size: 18,
                                ),
                              ),
                              title: Text(
                                file.originalName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(_formatSize(file.sizeBytes)),
                              trailing: IconButton(
                                tooltip: 'Download',
                                icon: const Icon(Icons.download_outlined),
                                onPressed: _loading
                                    ? null
                                    : () => _download(file),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecureSharedFile {
  const _SecureSharedFile({
    required this.fileId,
    required this.originalName,
    required this.contentType,
    required this.sizeBytes,
  });

  final String fileId;
  final String originalName;
  final String contentType;
  final int sizeBytes;

  factory _SecureSharedFile.fromMap(Map<String, dynamic> map) {
    return _SecureSharedFile(
      fileId: (map['fileId'] ?? '').toString(),
      originalName: (map['originalName'] ?? 'File').toString(),
      contentType: (map['contentType'] ?? '').toString(),
      sizeBytes: map['sizeBytes'] is num
          ? (map['sizeBytes'] as num).toInt()
          : 0,
    );
  }
}
