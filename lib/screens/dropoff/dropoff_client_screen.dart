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
  bool _isCompact(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return w < 600; // phones & small tablets
  }

  String? _error;
  Map<String, dynamic>? _info;

  String? _success;
  final List<String> _recentUploads = [];

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

  void _addRecentUploads(Iterable<String> names) {
    _recentUploads.insertAll(0, names);
    // Keep it tidy: last 10 filenames
    if (_recentUploads.length > 10) {
      _recentUploads.removeRange(10, _recentUploads.length);
    }
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

  Future<void> _uploadPickedFiles(FilePickerResult result) async {
    setState(() {
      _uploading = true;
      _error = null;
      _success = null; // clear previous success when starting new upload
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

        final fileId =
            '${DateTime.now().microsecondsSinceEpoch}_${uploadedCount}';
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

      setState(() {
        _success =
            'Upload complete — $uploadedCount file(s) uploaded. You can upload more.';
        _addRecentUploads(result.files.map((f) => f.name));
      });
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
      _success = null; // ✅ clear prior success
    });

    try {
      // iOS Safari (web) can behave oddly; keep selection simple on web if needed.
      final result = await FilePicker.platform
          .pickFiles(
            allowMultiple: !kIsWeb ? true : true, // keep your current behavior
            withData: kIsWeb, // web: get bytes
            withReadStream: !kIsWeb, // mobile/desktop: stream/path
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
      final uploadedNames = <String>[];

      for (final f in result.files) {
        final fileId =
            '${DateTime.now().microsecondsSinceEpoch}_$uploadedCount';
        final safeName = f.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final storagePath = 'dropoffs/${_rid!}/${fileId}_$safeName';
        final ref = FirebaseStorage.instance.ref(storagePath);

        final contentType = _guessContentType(f.name);
        final meta = SettableMetadata(contentType: contentType);

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
          await ref.putFile(File(path), meta);
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
        uploadedNames.add(f.name);
      }

      if (!mounted) return;

      if (uploadedCount == 0) {
        setState(() {
          _error = 'No uploads were processed. Please try again.';
        });
        return;
      }

      // ✅ Enterprise-feel: stay on the page and show confirmation.
      setState(() {
        _success =
            'Upload complete — $uploadedCount file(s) uploaded. You can upload more.';
        _addRecentUploads(uploadedNames);
      });

      // ❌ Remove this, because it forces them away (and causes the “refresh to upload again” feeling)
      // Navigator.pushReplacementNamed(context, '/dropoff/success');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Upload failed. Please try again.\n$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Widget _buildUploadButton(bool canUploadNow) {
    final disabled = !canUploadNow || _uploading;

    return FilledButton.icon(
      onPressed: disabled
          ? null
          : () async {
              // ✅ Safari requires the picker to be launched directly from the tap handler.
              // (Not via a wrapper widget’s onData, and not deferred to later.) [1](https://stackoverflow.com/questions/77714785/flutter-web-file-picker-not-working-on-safari)

              try {
                // Set UI state immediately (still inside user gesture)
                if (!mounted) return;
                setState(() {
                  _uploading = true;
                  _error = null;
                  _success = null;
                });

                final result = await FilePicker.platform.pickFiles(
                  allowMultiple: true,
                  withData: true, // ensures bytes are present on web
                );

                if (!mounted) return;

                if (result == null || result.files.isEmpty) {
                  setState(() {
                    _uploading = false;
                    _error = 'No file was selected.';
                  });
                  return;
                }

                // Reuse your existing upload pipeline
                await _uploadPickedFiles(result);
              } catch (e) {
                if (!mounted) return;
                setState(() {
                  _error = 'Upload failed. Please try again.\n$e';
                  _uploading = false;
                });
              } finally {
                if (mounted) setState(() => _uploading = false);
              }
            },
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
        _uploading ? 'Uploading…' : 'Choose files to upload',
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: disabled ? Colors.grey.shade400 : AppColors.brandBlue,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = (_info?['status'] ?? 'open').toString();
    // ✅ SINGLE SOURCE OF TRUTH
    final canUploadNow = !_loading && status == 'open';
    final canUpload = status == 'open';
    final isCompact = _isCompact(context);
    final useWebSelector = kIsWeb;

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

                    // ✅ Always show validation status (but do NOT hide the button)
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

                    // ✅ SHOW ERROR WITHOUT HIDING UI
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

                    // Only allow uploads after validation is done AND status is open
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

                    Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: isCompact
                              ? double.infinity
                              : 360, // ✅ enterprise width
                        ),
                        child: SizedBox(
                          height: 46,
                          width: double.infinity,
                          child: _buildUploadButton(canUploadNow),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),
                    Text(
                      'Files are uploaded securely. You may upload additional files or close this page when finished.',
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
          // Header row: "Recent uploads" + Clear link
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
