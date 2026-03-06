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

  bool _loading = true;
  bool _uploading = false;

  String? _error;
  Map<String, dynamic>? _info;

  String? _rid;
  String? _token;

  // ✅ Works for BOTH:
  //  - /dropoff?rid=...&t=...
  //  - /#/dropoff?rid=...&t=...
  Map<String, String> _extractDropoffParams() {
    // 1) Normal query params (path routing)
    final qp = Uri.base.queryParameters;
    final rid1 = qp['rid'];
    final t1 = qp['t'];
    if (rid1 != null && t1 != null) {
      return {'rid': rid1, 't': t1};
    }

    // 2) Hash fragment query params (hash routing)
    // Example fragment: "/dropoff?rid=...&t=..."
    final frag = Uri.base.fragment; // everything after '#'
    final qIndex = frag.indexOf('?');
    if (qIndex == -1) return {};

    final query = frag.substring(qIndex + 1);
    if (query.trim().isEmpty) return {};
    return Uri.splitQueryString(query);
  }

  // ✅ Content-type resolver (works on Web/Desktop/Mobile)
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

      // ✅ Debug: shows in browser DevTools console
      if (kDebugMode) {
        // ignore: avoid_print
        print('DROP-OFF PARAMS -> rid=$_rid, tPresent=${_token != null}');
      }

      if (_rid == null || _token == null) {
        throw Exception('Invalid link. Missing parameters.');
      }

      // ✅ Anonymous auth so Storage rules allow upload
      User? user;
      if (kIsWeb) {
        user =
            FirebaseAuth.instance.currentUser ??
            (await FirebaseAuth.instance.signInAnonymously()).user;
      } else {
        user = await _auth.signInAnonymouslyIfNeeded();
      }

      if (user == null) {
        throw Exception('Could not start secure upload session.');
      }

      // ✅ Validate link via Cloud Function
      final res = await _functions.httpsCallable('validateDropoffLink').call({
        'rid': _rid,
        'token': _token,
      });

      _info = Map<String, dynamic>.from(res.data as Map);

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _uploadPickedFiles(FilePickerResult result) async {
    setState(() {
      _uploading = true;
      _error = null;
    });

    try {
      int uploadedCount = 0;

      for (final f in result.files) {
        final bytes = f.bytes;
        if (bytes == null) {
          throw Exception(
            'Selected file data was unavailable. Please reselect the file and try again.',
          );
        }

        final contentType = _guessContentType(f.name);

        final fileId = '${DateTime.now().microsecondsSinceEpoch}_${uploadedCount}';
        final safeName = f.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final storagePath = 'dropoffs/${_rid!}/${fileId}_$safeName';

        final ref = FirebaseStorage.instance.ref(storagePath);
        await ref.putData(bytes, SettableMetadata(contentType: contentType));

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

        uploadedCount++;
      }

      if (!mounted) return;

      if (uploadedCount == 0) {
        setState(() => _error = 'No uploads were processed. Please try again.');
        return;
      }

      Navigator.pushReplacementNamed(context, '/dropoff/success');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Upload failed. Please try again.\n$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _handleIOSWebFiles(List<XFile> files) async {
    if (!mounted) return;

    if (files.isEmpty) {
      setState(() => _error = 'No file was selected.');
      return;
    }

    // Convert XFile -> FilePickerResult so you can reuse _uploadPickedFiles()
    final picked = <PlatformFile>[];
    for (final xf in files) {
      final bytes = await xf.readAsBytes();
      picked.add(PlatformFile(name: xf.name, size: bytes.length, bytes: bytes));
    }

    await _uploadPickedFiles(FilePickerResult(picked));
  }

  Future<void> _pickAndUpload() async {
    if (_uploading) return;

    setState(() {
      _uploading = true;
      _error = null;
    });

    try {
      // iOS Safari (web) can behave oddly; keep selection simple on web if needed.
      final result = await FilePicker.platform
          .pickFiles(
            allowMultiple: !kIsWeb
                ? true
                : true, // set to false if Safari still hangs
            withData: kIsWeb, // web: get bytes
            withReadStream: !kIsWeb, // mobile: stream/path
          )
          .timeout(
            const Duration(seconds: 60),
            onTimeout: () {
              throw Exception(
                'File selection did not complete. If you are on iPhone Safari, try selecting a single file or use a different browser.',
              );
            },
          );

      if (result == null || result.files.isEmpty) {
        // User cancelled OR iOS returned null; give a visible message
        if (!mounted) return;
        setState(() {
          _uploading = false;
          _error = 'No file was selected.';
        });
        return;
      }

      int uploadedCount = 0;

      for (final f in result.files) {
        final fileId = '${DateTime.now().microsecondsSinceEpoch}_${uploadedCount}';
        final safeName = f.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final storagePath = 'dropoffs/${_rid!}/${fileId}_$safeName';
        final ref = FirebaseStorage.instance.ref(storagePath);

        final contentType = _guessContentType(f.name);
        final meta = SettableMetadata(contentType: contentType);

        // ---- Upload (Web vs Native) ----
        // ---- Upload (Web vs Native) ----
        if (kIsWeb) {
          final bytes = f.bytes;
          if (bytes == null) {
            throw Exception(
              'Selected file data was unavailable. Please retry.',
            );
          }
          await ref.putData(bytes, meta);
        } else {
          final path = f.path;
          if (path == null || path.isEmpty) {
            throw Exception('File path unavailable. Please reselect the file.');
          }
          await ref.putFile(File(path), meta); // add: import 'dart:io';
        }

        // ---- Finalize (server writes metadata + counters) ----
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
        uploadedCount++;
      }

      if (!mounted) return;

      if (uploadedCount == 0) {
        setState(() {
          _error = 'No uploads were processed. Please try again.';
        });
        return;
      }

      Navigator.pushReplacementNamed(context, '/dropoff/success');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Upload failed. Please try again.\n$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = (_info?['status'] ?? 'open').toString();
    final canUpload = status == 'open';

    return Scaffold(
      backgroundColor: AppColors.pageBackgroundLight,
      appBar: AppBar(title: const Text('Secure Drop-Off')),
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
                      'Use this secure page to upload files to the firm.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF475467),
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 14),

                    if (_loading) ...[
                      const Center(child: CircularProgressIndicator()),
                      const SizedBox(height: 6),
                      Text(
                        'Validating link…',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF667085),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ] else ...[
                      // ✅ SHOW ERROR WITHOUT HIDING UI
                      if (_error != null) ...[
                        _ErrorBanner(message: _error!),
                        const SizedBox(height: 12),
                      ],

                      if ((_info?['message'] ?? '')
                          .toString()
                          .trim()
                          .isNotEmpty)
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

                      if (!canUpload)
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

                      // ✅ UPLOAD BUTTON ALWAYS STAYS
                      SizedBox(
                        height: 46,
                        width: double.infinity,
                        child: WebFileSelector.isIOSWeb
                            ? WebFileSelector(
                                multiple: true,
                                accept:
                                    '.pdf,.png,.jpg,.jpeg,.doc,.docx,.xls,.xlsx,.csv,.txt',
                                onData: _handleIOSWebFiles,
                                child: FilledButton.icon(
                                  onPressed: (!canUpload || _uploading)
                                      ? null
                                      : () {},
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
                                    _uploading
                                        ? 'Uploading…'
                                        : 'Choose files to upload',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.brandBlue,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              )
                            : FilledButton.icon(
                                onPressed: (!canUpload || _uploading)
                                    ? null
                                    : _pickAndUpload,
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
                                  _uploading
                                      ? 'Uploading…'
                                      : 'Choose files to upload',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.brandBlue,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                      ),

                      const SizedBox(height: 10),
                      Text(
                        'Files upload securely. You may close this page after upload completes.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF667085),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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
