import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_file_selector/flutter_web_file_selector.dart';
import 'dart:io';

import '../../theme/app_colors.dart';
import '../../services/auth_service.dart';

class DropoffClientScreen extends StatefulWidget {
  const DropoffClientScreen({super.key});

  @override
  State<DropoffClientScreen> createState() => _DropoffClientScreenState();
}

class _DropoffClientScreenState extends State<DropoffClientScreen> {
  final _auth = AuthService();
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

  // ✅ staged queue
  final List<PlatformFile> _queuedFiles = [];

  bool _loading = true;
  bool _uploading = false;

  String? _error;
  String? _success;
  Map<String, dynamic>? _info;

  final List<String> _recentUploads = [];

  String? _rid;
  String? _token;

  bool _isCompact(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return w < 600;
  }

  // -----------------------------
  // Utilities
  // -----------------------------

  Map<String, String> _extractDropoffParams() {
    // 1) Normal query params
    final qp = Uri.base.queryParameters;
    final rid1 = qp['rid'];
    final t1 = qp['t'];
    if (rid1 != null && t1 != null) {
      return {'rid': rid1, 't': t1};
    }

    // 2) Hash fragment query params
    final frag = Uri.base.fragment;
    final qIndex = frag.indexOf('?');
    if (qIndex == -1) return {};

    final query = frag.substring(qIndex + 1);
    if (query.trim().isEmpty) return {};
    return Uri.splitQueryString(query);
  }

  String _fileKey(PlatformFile f) =>
      '${f.name}|${f.size}|${f.path ?? ''}|${f.identifier ?? ''}';

  String _guessContentType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.txt')) return 'text/plain';
    return 'application/octet-stream';
  }

  void _addRecentUploads(Iterable<String> names) {
    _recentUploads.insertAll(0, names);
    if (_recentUploads.length > 10) {
      _recentUploads.removeRange(10, _recentUploads.length);
    }
  }

  // -----------------------------
  // Init + Validation (same behavior)
  // -----------------------------

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final params = _extractDropoffParams();
      _rid = params['rid'];
      _token = params['t'];

      if (_rid == null || _token == null) {
        throw Exception('Invalid link. Missing parameters.');
      }

      // anonymous auth
      User? user;
      if (kIsWeb) {
        user =
            FirebaseAuth.instance.currentUser ??
            (await FirebaseAuth.instance.signInAnonymously().timeout(
              const Duration(seconds: 15),
            )).user;
      } else {
        user = await _auth.signInAnonymouslyIfNeeded();
      }

      if (user == null) {
        throw Exception('Could not start secure upload session.');
      }

      final res = await _functions
          .httpsCallable('validateDropoffLink')
          .call({'rid': _rid, 'token': _token})
          .timeout(const Duration(seconds: 15));

      _info = Map<String, dynamic>.from(res.data as Map);

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _uploading = false;
        _error = e.toString();
        _success = null;
      });
    }
  }

  // -----------------------------
  // Queue helpers
  // -----------------------------

  void _removeQueuedAt(int index) {
    if (_uploading) return;
    setState(() => _queuedFiles.removeAt(index));
  }

  // Called by WebFileSelector (iOS Safari Web)
  Future<void> _queueFromXFiles(List<XFile> files) async {
    if (!mounted) return;

    if (files.isEmpty) {
      setState(() => _error = 'No file was selected.');
      return;
    }

    setState(() {
      _error = null;
      _success = null;
    });

    final existing = _queuedFiles.map(_fileKey).toSet();

    for (final xf in files) {
      final bytes = await xf.readAsBytes();
      final pf = PlatformFile(name: xf.name, size: bytes.length, bytes: bytes);

      final key = _fileKey(pf);
      if (!existing.contains(key)) {
        existing.add(key);
        _queuedFiles.add(pf);
      }
    }

    if (mounted) setState(() {});
  }

  // Non-iOS web + native platforms (staging only, no upload)
  Future<void> _pickFilesToQueue() async {
    if (_uploading) return;

    setState(() {
      _error = null;
      _success = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: kIsWeb, // web needs bytes
      );

      if (!mounted) return;

      if (result == null || result.files.isEmpty) {
        setState(() => _error = 'No file was selected.');
        return;
      }

      final existing = _queuedFiles.map(_fileKey).toSet();
      for (final f in result.files) {
        final key = _fileKey(f);
        if (!existing.contains(key)) {
          existing.add(key);
          _queuedFiles.add(f);
        }
      }

      setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'File selection failed.\n$e');
    }
  }

  // -----------------------------
  // Upload (bulk, explicit)
  // -----------------------------

  Future<void> _uploadQueuedFiles() async {
    if (_uploading) return;
    if (_queuedFiles.isEmpty) {
      setState(() => _error = 'Select at least one file to upload.');
      return;
    }

    setState(() {
      _uploading = true;
      _error = null;
      _success = null;
    });

    int uploaded = 0;
    final uploadedNames = <String>[];

    try {
      for (final f in List<PlatformFile>.from(_queuedFiles)) {
        final contentType = _guessContentType(f.name);
        final safeName = f.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final fileId = '${DateTime.now().microsecondsSinceEpoch}_$uploaded';
        final storagePath = 'dropoffs/${_rid!}/${fileId}_$safeName';

        final ref = FirebaseStorage.instance.ref(storagePath);

        if (kIsWeb) {
          final bytes = f.bytes;
          if (bytes == null) {
            throw Exception(
              'Missing file bytes for ${f.name}. Please reselect.',
            );
          }
          await ref.putData(bytes, SettableMetadata(contentType: contentType));
        } else {
          final path = f.path;
          if (path == null || path.isEmpty) {
            throw Exception(
              'Missing file path for ${f.name}. Please reselect.',
            );
          }
          await ref.putFile(
            File(path),
            SettableMetadata(contentType: contentType),
          );
        }

        await _functions.httpsCallable('finalizeDropoffUpload').call({
          'rid': _rid,
          'token': _token,
          'file': {
            'originalName': f.name,
            'storagePath': storagePath,
            'sizeBytes': f.size,
            'contentType': contentType,
          },
        });

        uploaded++;
        uploadedNames.add(f.name);
        _queuedFiles.removeWhere((x) => _fileKey(x) == _fileKey(f));
        if (mounted) setState(() {});
      }

      if (!mounted) return;
      // ✅ Send ONE summary email (server-side), after all uploads complete
      // ✅ Send ONE summary email (server-side), after all uploads complete
Map<String, dynamic>? notifyResult;
try {
  final res = await _functions
      .httpsCallable('notifyDropoffBatchUpload')
      .call({
        'rid': _rid,
        'token': _token,
        'files': uploadedNames,
      })
      .timeout(const Duration(seconds: 20));

  notifyResult = Map<String, dynamic>.from(res.data as Map);
  if (kDebugMode) {
    // ignore: avoid_print
    print('notifyDropoffBatchUpload result: $notifyResult');
  }
} catch (e) {
  if (kDebugMode) {
    // ignore: avoid_print
    print('Batch email notify failed: $e');
  }
  // ✅ show non-fatal warning to user (uploads still succeeded)
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Upload completed, but email notification failed: $e')),
    );
  }
}

// Optional: if server says it didn't email anyone, show that clearly
if (notifyResult != null && notifyResult['emailed'] != true && mounted) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Upload completed. Email notification was not sent (no recipient found).')),
  );
}
      setState(() {
        _success =
            'Upload complete — $uploaded file(s) uploaded. You can upload more.';
        _addRecentUploads(uploadedNames);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error =
            'Upload failed. $uploaded file(s) uploaded before the error.\n$e';
      });
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // -----------------------------
  // UI
  // -----------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = (_info?['status'] ?? 'open').toString();
    final canUploadNow = !_loading && status == 'open';
    final isCompact = _isCompact(context);

    // ✅ "Add files" button: wrapped for iOS Safari web using WebFileSelector
    // This matches the package’s documented usage (wrap a button, use onData). [1](https://pub.dev/documentation/flutter_web_file_selector/latest/)[2](https://github.com/koichia/flutter_web_file_selector)[4](https://pub.dev/packages/flutter_web_file_selector/example)
    Widget addFilesBtn = OutlinedButton.icon(
      onPressed: canUploadNow && !_uploading
          ? () {
              // non-iOS-web path
              if (!WebFileSelector.isIOSWeb) {
                _pickFilesToQueue();
              }
            }
          : null,
      icon: const Icon(Icons.add),
      label: const Text(
        'Add files',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
    );

    if (WebFileSelector.isIOSWeb) {
      addFilesBtn = WebFileSelector(
        multiple: true,
        // accept: '.pdf,.png,.jpg,.jpeg,.doc,.docx,.xls,.xlsx,.csv,.txt',
        onData: (files) async {
          await _queueFromXFiles(files);
        },
        child: addFilesBtn,
      );
    }

    final uploadBtn = FilledButton.icon(
      onPressed: canUploadNow && !_uploading && _queuedFiles.isNotEmpty
          ? _uploadQueuedFiles
          : null,
      icon: _uploading
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.upload_file),
      label: Text(
        _uploading ? 'Uploading…' : 'Upload selected (${_queuedFiles.length})',
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: (!canUploadNow || _queuedFiles.isEmpty || _uploading)
            ? Colors.grey.shade400
            : AppColors.brandBlue,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: AppColors.pageBackgroundLight,
        appBar: AppBar(
          title: const Text('Secure Drop-Off'),
          automaticallyImplyLeading: false,
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              children: [
                _WhiteSection(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Upload Documents',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF101828),
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Select files first, review the list, remove any items, then upload.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF475467),
                          height: 1.25,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 14),

                      if (_loading) ...[
                        Row(
                          children: [
                            const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Validating link…',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF667085),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],

                      if (_error != null) ...[
                        _ErrorBanner(message: _error!),
                        const SizedBox(height: 12),
                      ],

                      if (_success != null) ...[
                        _SuccessBanner(message: _success!),
                        const SizedBox(height: 12),
                      ],

                      if (_recentUploads.isNotEmpty) ...[
                        _RecentUploadsCard(
                          fileNames: _recentUploads,
                          onClear: () {
                            setState(() {
                              _recentUploads.clear();
                              _success = null;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                      ],

                      if ((_info?['message'] ?? '')
                          .toString()
                          .trim()
                          .isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.brandBlue.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.brandBlue.withOpacity(0.18),
                            ),
                          ),
                          child: Text(
                            (_info?['message'] ?? '').toString(),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF475467),
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      if (!_loading && !canUploadNow) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            'This drop-off request is no longer accepting uploads.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],

                      if (_queuedFiles.isNotEmpty) ...[
                        _QueuedFilesCard(
                          files: _queuedFiles,
                          onRemove: _removeQueuedAt,
                          disabled: _uploading,
                        ),
                        const SizedBox(height: 12),
                      ],

                      Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: isCompact ? double.infinity : 520,
                          ),
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              SizedBox(height: 46, child: addFilesBtn),
                              SizedBox(height: 46, child: uploadBtn),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),
                      Text(
                        'Files are uploaded securely. You can add more files, remove items, then upload when ready.',
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
          ),
        ),
      ),
    );
  }
}

// -----------------------------
// Supporting Widgets
// -----------------------------

class _QueuedFilesCard extends StatelessWidget {
  final List<PlatformFile> files;
  final void Function(int index) onRemove;
  final bool disabled;

  const _QueuedFilesCard({
    required this.files,
    required this.onRemove,
    required this.disabled,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ready to upload',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: const Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 8),
          ...files.asMap().entries.map((e) {
            final i = e.key;
            final f = e.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.insert_drive_file_outlined,
                    size: 16,
                    color: Color(0xFF475467),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      f.name,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF475467),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.red.shade700),
                    tooltip: disabled ? 'Uploading…' : 'Remove',
                    onPressed: disabled ? null : () => onRemove(i),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _WhiteSection extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const _WhiteSection({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      padding: padding,
      child: child,
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFB42318), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFFB42318),
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessBanner extends StatelessWidget {
  final String message;
  const _SuccessBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_outline,
            color: Color(0xFF067647),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF067647),
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentUploadsCard extends StatelessWidget {
  final List<String> fileNames;
  final VoidCallback onClear;

  const _RecentUploadsCard({required this.fileNames, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
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
                child: Text(
                  'Recent uploads',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF101828),
                  ),
                ),
              ),
              TextButton(
                onPressed: onClear,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Clear',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF475467),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...fileNames.map(
            (n) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.insert_drive_file_outlined,
                    size: 16,
                    color: Color(0xFF475467),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      n,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF475467),
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
