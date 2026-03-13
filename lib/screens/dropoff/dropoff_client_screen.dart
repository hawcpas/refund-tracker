import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_file_selector/flutter_web_file_selector.dart';
import 'dart:io';
import 'dart:async';

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
  final Map<String, double> _uploadProgress = {};
  String? _currentlyUploadingKey;

  bool _loading = true;
  bool _uploading = false;

  bool get _isClosed => ((_info?['status'] ?? 'closed').toString() != 'open');

  String? _error;
  String? _success;
  Map<String, dynamic>? _info;

  final List<String> _recentUploads = [];

  String? _rid;
  String? _token;

  int _totalToUpload = 0;
  int _uploadedSoFar = 0;
  String? _currentFileName;

  double get _overallProgress {
    if (_totalToUpload <= 0) return 0.0;

    // You upload sequentially, so there is typically one active progress entry.
    final activeKey = _currentlyUploadingKey;
    final activeP = activeKey == null
        ? 0.0
        : (_uploadProgress[activeKey] ?? 0.0);

    final overall = (_uploadedSoFar + activeP) / _totalToUpload;
    return overall.clamp(0.0, 1.0);
  }

  static const String _closedMsg =
      'This secure upload request has been closed. If you need to submit files, please request a new link.';

  bool _isCompact(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return w < 600;
  }

  String _friendlyFunctionsError(Object e) {
    if (e is FirebaseFunctionsException) {
      switch (e.code) {
        case 'failed-precondition':
          return 'This secure upload request has been closed. If you need to submit files, please request a new link.';
        case 'permission-denied':
          return 'You do not have permission to upload to this link.';
        case 'unauthenticated':
          return 'Your upload session has expired. Please refresh the page.';
        case 'not-found':
          return 'This upload link could not be found.';
        case 'deadline-exceeded':
          return 'The request took too long. Please try again.';
        default:
          return 'We couldn’t complete your request. Please try again.';
      }
    }

    // Fallback for non-Firebase errors
    return 'An unexpected error occurred. Please try again.';
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

  Future<bool> _refreshAndCheckCanUpload({bool showMessage = true}) async {
    if (_rid == null || _token == null) return false;

    try {
      final res = await _functions
          .httpsCallable('validateDropoffLink')
          .call({'rid': _rid, 'token': _token})
          .timeout(const Duration(seconds: 15));

      final data = Map<String, dynamic>.from(res.data as Map);
      _info = data;

      final status = (_info?['status'] ?? 'closed').toString();
      final canUploadNow = !_loading && status == 'open';

      if (!canUploadNow && showMessage && mounted) {
        setState(() {
          _error = _closedMsg;
          _success = null;
        });
      }

      if (mounted) setState(() {}); // refresh UI status + buttons
      return canUploadNow;
    } catch (e) {
      // If validation fails, treat as not allowed and show friendly error
      if (mounted && showMessage) {
        setState(() {
          _error = _friendlyFunctionsError(e);
          _success = null;
        });
      }
      return false;
    }
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
        _error = _friendlyFunctionsError(e);
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

  Future<void> _queueFromXFiles(List<XFile> files) async {
    if (!mounted) return;

    // ✅ If user cancels, do nothing (no error UI)
    if (files.isEmpty) return;

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

      // ✅ If user cancels, do nothing (no error UI)
      if (result == null || result.files.isEmpty) return;

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
    // ✅ Recompute upload eligibility locally (do NOT rely on build())
    final status = (_info?['status'] ?? 'open').toString();
    final canUploadNow = !_loading && status == 'open';

    if (!canUploadNow) {
      setState(() {
        _error = _closedMsg;
      });
      return;
    }

    if (_uploading) return;
    if (_queuedFiles.isEmpty) {
      setState(() => _error = 'Select at least one file to upload.');
      return;
    }

    setState(() {
      _uploading = true;
      _error = null;
      _success = null;

      _totalToUpload = _queuedFiles.length;
      _uploadedSoFar = 0;
      _currentFileName = null;
    });

    int uploaded = 0;
    final uploadedNames = <String>[];

    try {
      for (final f in List<PlatformFile>.from(_queuedFiles)) {
        if (mounted) {
          setState(() {
            _currentFileName = f.name;
          });
        }

        final contentType = _guessContentType(f.name);
        final safeName = f.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final fileId = '${DateTime.now().microsecondsSinceEpoch}_$uploaded';
        final storagePath = 'dropoffs/${_rid!}/${fileId}_$safeName';

        final ref = FirebaseStorage.instance.ref(storagePath);

        // ✅ START: UploadTask + progress (goes right here, replacing putData/putFile)
        UploadTask task;

        if (kIsWeb) {
          final bytes = f.bytes;
          if (bytes == null) {
            throw Exception(
              'Missing file bytes for ${f.name}. Please reselect.',
            );
          }

          task = ref.putData(bytes, SettableMetadata(contentType: contentType));
        } else {
          final path = f.path;
          if (path == null || path.isEmpty) {
            throw Exception(
              'Missing file path for ${f.name}. Please reselect.',
            );
          }

          task = ref.putFile(
            File(path),
            SettableMetadata(contentType: contentType),
          );
        }

        final fileKey = _fileKey(f);

        _uploadProgress[fileKey] = 0.0;
        _currentlyUploadingKey = fileKey;

        late final StreamSubscription<TaskSnapshot> sub;

        try {
          sub = task.snapshotEvents.listen((snapshot) {
            final total = snapshot.totalBytes;
            if (total > 0) {
              final progressValue = snapshot.bytesTransferred / total;
              if (mounted) {
                setState(() {
                  _uploadProgress[fileKey] = progressValue;
                });
              }
            }
          });

          // ✅ wait for upload to finish
          await task;
        } finally {
          // ✅ stop listening even if upload throws
          await sub.cancel();
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

        _uploadedSoFar = uploaded;
        if (mounted) setState(() {});

        _queuedFiles.removeWhere((x) => _fileKey(x) == _fileKey(f));

        // ✅ cleanup progress state
        _uploadProgress.remove(fileKey);
        if (_currentlyUploadingKey == fileKey) _currentlyUploadingKey = null;

        if (mounted) setState(() {});
      }
      if (!mounted) return;

      // ✅ Send ONE summary email (server-side), after all uploads complete
      try {
        final res = await _functions
            .httpsCallable('notifyDropoffBatchUpload')
            .call({'rid': _rid, 'token': _token, 'files': uploadedNames})
            .timeout(const Duration(seconds: 20));

        if (kDebugMode) {
          // ignore: avoid_print
          print('notifyDropoffBatchUpload result: ${res.data}');
        }
      } catch (e) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('Batch email notify failed: $e');
        }
        // ✅ Non-fatal: uploads still succeeded
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Upload completed, but email notification failed: $e',
              ),
            ),
          );
        }
      }
      // ✅ Send ONE summary email (server-side), after all uploads complete
      /*
      Map<String, dynamic>? notifyResult;
      try {
        final res = await _functions
            .httpsCallable('notifyDropoffBatchUpload')
            .call({'rid': _rid, 'token': _token, 'files': uploadedNames})
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
            SnackBar(
              content: Text(
                'Upload completed, but email notification failed: $e',
              ),
            ),
          );
        }
      }

      // Optional: if server says it didn't email anyone, show that clearly
      if (notifyResult != null &&
          notifyResult.containsKey('emailed') &&
          notifyResult['emailed'] == false &&
          mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Upload completed. Email notification was not sent (no recipient found).',
            ),
          ),
        );
      }
      */
      setState(() {
        _success =
            'Upload complete — $uploaded file(s) uploaded. You can upload more.';
        _addRecentUploads(uploadedNames);
      });
    } catch (e) {
      if (!mounted) return;

      final message = _friendlyFunctionsError(e);

      if (e is FirebaseFunctionsException && e.code == 'failed-precondition') {
        _info = {...?_info, 'status': 'closed'};
      }

      setState(() {
        _error = message;
      });
    } finally {
      if (!mounted) return;

      // Let the UI paint the "100%" / last file state at least once.
      await Future<void>.delayed(const Duration(milliseconds: 250));

      if (!mounted) return;
      setState(() {
        _uploading = false;
        _currentFileName = null;
        _currentlyUploadingKey = null;
        _uploadProgress.clear();
        _totalToUpload = 0;
        _uploadedSoFar = 0;
      });
    }
  }

  // -----------------------------
  // UI
  // -----------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = (_info?['status'] ?? 'closed').toString();
    final canUploadNow = !_loading && status == 'open';
    final isCompact = _isCompact(context);

    final brand = AppColors.brandBlue;

    Widget addFilesBtn = OutlinedButton.icon(
      onPressed: (canUploadNow && !_uploading)
          ? () async {
              setState(() {
                _error = null;
                _success = null;
              });

              // ✅ Re-check server status right before letting user pick
              final ok = await _refreshAndCheckCanUpload(showMessage: true);
              if (!ok) {
                setState(() {
                  _queuedFiles.clear();
                  _uploadProgress.clear();
                  _currentlyUploadingKey = null;
                });
                return;
              }

              // Non‑iOS web/native: open normal picker
              if (!WebFileSelector.isIOSWeb) {
                _pickFilesToQueue();
              }
              // iOS web: WebFileSelector wrapper handles the file prompt
            }
          : null,
      icon: const Icon(Icons.add),
      label: const Text(
        'Add files',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor:
            brand, // bright text color [2](https://github.com/koichia/flutter_web_file_selector)
        iconColor: brand, // force icon to match (no theme surprise)
        side: BorderSide(
          color: brand,
          width: 1.6,
        ), // stronger stroke = more “pop”
        backgroundColor: brand.withOpacity(
          0.08,
        ), // subtle tint to make it punchy
        overlayColor: brand.withOpacity(0.12), // press ripple tint
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        disabledForegroundColor: brand.withOpacity(
          0.55,
        ), // disabled, but still branded [1](https://stackoverflow.com/questions/77714785/flutter-web-file-picker-not-working-on-safari)
        disabledBackgroundColor: Colors.transparent,
      ),
    );

    if (WebFileSelector.isIOSWeb && canUploadNow && !_uploading) {
      addFilesBtn = WebFileSelector(
        multiple: true,
        onData: (files) async {
          final ok = await _refreshAndCheckCanUpload(showMessage: true);
          if (!ok) {
            setState(() {
              _queuedFiles.clear();
              _uploadProgress.clear();
              _currentlyUploadingKey = null;
            });

            return;
          }

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
        body: Stack(
          children: [
            Center(
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
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
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

                          if (_uploading) ...[
                            _UploadingBanner(
                              total: _totalToUpload,
                              done: _uploadedSoFar,
                              currentFileName: _currentFileName,
                              progress: _overallProgress,
                            ),
                            const SizedBox(height: 12),
                          ],

                          if (_error != null && !_isClosed) ...[
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
                                _closedMsg,
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
                              progress: _uploadProgress,
                              activeKey: _currentlyUploadingKey,
                            ),
                            const SizedBox(height: 12),
                          ],

                          Row(
                            children: [
                              Flexible(
                                fit: FlexFit.loose,
                                child: IgnorePointer(
                                  ignoring: !canUploadNow,
                                  child: Opacity(
                                    opacity: canUploadNow ? 1.0 : 0.55,
                                    child: SizedBox(
                                      height: 48,
                                      child: addFilesBtn,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                fit: FlexFit.loose,
                                child: SizedBox(height: 48, child: uploadBtn),
                              ),
                            ],
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

            // ✅ enterprise top progress indicator while uploading
            if (_uploading)
              const Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: AppColors.brandBlue,
                  backgroundColor: Colors.transparent,
                ),
              ),
          ],
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

  final Map<String, double> progress;
  final String? activeKey;

  const _QueuedFilesCard({
    required this.files,
    required this.onRemove,
    required this.disabled,
    required this.progress,
    required this.activeKey,
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

            final key =
                '${f.name}|${f.size}|${f.path ?? ''}|${f.identifier ?? ''}';
            final p = progress[key];

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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

                  if (p != null) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value:
                            p, // 0.0 → 1.0 determinate progress [1](https://api.flutter.dev/flutter/material/LinearProgressIndicator-class.html)
                        minHeight: 6,
                        backgroundColor: Colors.black.withOpacity(0.06),
                        color: AppColors.brandBlue,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${(p * 100).clamp(0, 100).toStringAsFixed(0)}%',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF667085),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
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

class _UploadingBanner extends StatelessWidget {
  final int total;
  final int done;
  final double progress;
  final String? currentFileName;

  const _UploadingBanner({
    required this.total,
    required this.done,
    required this.progress,
    required this.currentFileName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = (progress * 100).clamp(0, 100).toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.brandBlue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.brandBlue.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.cloud_upload_outlined,
                color: AppColors.brandBlue,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Uploading files — please do not close this browser window.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF101828),
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ),
              Text(
                '$done/$total',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF475467),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),

          if (currentFileName != null &&
              currentFileName!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Current file: $currentFileName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: const Color(0xFF475467),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],

          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.black.withOpacity(0.06),
              color: AppColors.brandBlue,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$pct% complete',
            style: theme.textTheme.labelSmall?.copyWith(
              color: const Color(0xFF667085),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
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
