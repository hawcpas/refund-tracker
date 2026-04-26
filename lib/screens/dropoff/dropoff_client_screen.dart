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
import 'package:flutter_svg/flutter_svg.dart';
import '../../theme/brand_logo_svg.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'dart:collection';

enum _UploadItemState { queued, uploading, finalizing, success, failed }

// -----------------------------
// Brand colors (website palette)
// -----------------------------
const Color _kBrandBlue = Color(0xFF0032CC); // #0032cc
const Color _kGray = Color(0xFF808080); // #808080
const Color _kDarkGray = Color(0xFF424242); // #424242

class DropoffClientScreen extends StatefulWidget {
  const DropoffClientScreen({super.key});

  @override
  State<DropoffClientScreen> createState() => _DropoffClientScreenState();
}

class _Semaphore {
  _Semaphore(this._max);
  final int _max;
  int _current = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  Future<void> acquire() {
    if (_current < _max) {
      _current++;
      return Future.value();
    }
    final c = Completer<void>();
    _waiters.add(c);
    return c.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    } else {
      _current = (_current - 1).clamp(0, _max);
    }
  }
}

class _DropoffClientScreenState extends State<DropoffClientScreen> {
  final _auth = AuthService();
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

  // ✅ staged queue
  final List<PlatformFile> _queuedFiles = [];
  final Map<String, double> _uploadProgress = {};
  String? _currentlyUploadingKey;

  // 🚫 TEMP: disable native drag & drop until Windows build is shipped
  static const bool _enableDesktopDragDrop = false;

  bool _loading = true;
  bool _uploading = false;
  bool _showCompletionNote =
      false; // ✅ shows the inline "safe to close" message

  bool get _isClosed => ((_info?['status'] ?? 'closed').toString() != 'open');
  bool get _isVerifiedLink {
    final ok = (_info?['ok'] == true);
    return ok && _rid != null && _token != null;
  }

  bool get _allUploadsComplete {
    if (_queuedFiles.isEmpty) return false;

    for (final f in _queuedFiles) {
      final s = _fileState[_fileKey(f)];
      if (s != _UploadItemState.success) return false;
    }

    return !_uploading;
  }

  bool get _isDesktop {
    if (kIsWeb) return !WebFileSelector.isIOSWeb; // web desktop OK, iOS web NO
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return true;
      default:
        return false;
    }
  }

  bool _isDragging = false;

  Future<Map<String, dynamic>?> _uploadOne(PlatformFile f, int index) async {
    final fileKey = _fileKey(f);

    try {
      if (mounted) {
        setState(() {
          _currentFileName = f.name; // optional: last touched
          _fileState[fileKey] = _UploadItemState.uploading;
          _fileError.remove(fileKey);
          _uploadProgress[fileKey] = 0.0;
        });
      }

      final contentType = _guessContentType(f.name);
      final safeName = f.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

      // IMPORTANT: avoid collisions in parallel
      final fileId =
          '${DateTime.now().microsecondsSinceEpoch}_${f.name.hashCode}_${f.size}_$index';
      final storagePath = 'dropoffs/${_rid!}/${fileId}_$safeName';

      final ref = FirebaseStorage.instance.ref(storagePath);

      UploadTask task;

      if (kIsWeb) {
        final bytes = f.bytes;
        if (bytes == null) {
          throw Exception('Missing file bytes for ${f.name}. Please reselect.');
        }
        task = ref.putData(bytes, SettableMetadata(contentType: contentType));
      } else {
        final path = f.path;
        if (path == null || path.isEmpty) {
          throw Exception('Missing file path for ${f.name}. Please reselect.');
        }
        task = ref.putFile(
          File(path),
          SettableMetadata(contentType: contentType),
        );
      }

      late final StreamSubscription<TaskSnapshot> sub;
      try {
        sub = task.snapshotEvents.listen((snapshot) {
          final total = snapshot.totalBytes;
          if (total > 0 && mounted) {
            setState(() {
              _uploadProgress[fileKey] = snapshot.bytesTransferred / total;
            });
          }
        });

        await task;

        if (mounted) {
          setState(() {
            _uploadProgress[fileKey] = 1.0;
            _fileState[fileKey] = _UploadItemState.finalizing;
          });
        }

        await Future<void>.delayed(const Duration(milliseconds: 120));
      } finally {
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

      if (mounted) {
        setState(() {
          _fileState[fileKey] = _UploadItemState.success;
          _fileError.remove(fileKey);
          _uploadProgress[fileKey] = 1.0;
        });
      }

      // return metadata for notifyDropoffBatchUpload
      return {'name': f.name, 'sizeBytes': f.size};
    } catch (e) {
      if (mounted) {
        setState(() {
          _fileState[fileKey] = _UploadItemState.failed;
          _fileError[fileKey] = _friendlyFunctionsError(e);
          _uploadProgress.remove(fileKey);
        });
      }
      return null; // keep batch going
    }
  }

  Widget _desktopDropZone({required bool enabled}) {
    if (!_enableDesktopDragDrop || !_isDesktop) {
      return const SizedBox.shrink();
    }

    return DropTarget(
      onDragEntered: (_) {
        setState(() => _isDragging = true);
      },
      onDragExited: (_) {
        setState(() => _isDragging = false);
      },
      onDragDone: (details) async {
        setState(() => _isDragging = false);

        if (!enabled || details.files.isEmpty) return;

        setState(() {
          _dismissCompletionNote();
          _error = null;
          _success = null;
        });

        // Convert XFile → PlatformFile using your existing logic
        await _queueFromXFiles(details.files);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
        decoration: BoxDecoration(
          color: _isDragging
              ? AppColors.brandBlue.withOpacity(0.06)
              : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            width: 2,
            color: _isDragging
                ? AppColors.brandBlue
                : Colors.black.withOpacity(0.14),
            style: BorderStyle.solid,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_upload_outlined,
                size: 32,
                color: _isDragging
                    ? AppColors.brandBlue
                    : const Color(0xFF667085),
              ),
              const SizedBox(height: 10),
              Text(
                _isDragging ? 'Drop files to add' : 'Drag & drop files here',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF344054),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Files are added to the list and uploaded only when you click “Upload selected”.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF667085),
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _allFilesSucceeded {
    if (_queuedFiles.isEmpty) return false;
    for (final f in _queuedFiles) {
      final s = _fileState[_fileKey(f)];
      if (s != _UploadItemState.success) return false;
    }
    return true;
  }

  bool _notifyingRequester = false;
  bool _requesterNotified = false;

  String? _error;
  String? _success;
  Map<String, dynamic>? _info;

  final List<String> _recentUploads = [];

  // ✅ Per-file status (enterprise: keep rows + show success state)
  final Map<String, _UploadItemState> _fileState = {};
  final Map<String, String> _fileError =
      {}; // optional, for failed state messages

  int get _pendingCount {
    int c = 0;
    for (final f in _queuedFiles) {
      final k = _fileKey(f);
      final s = _fileState[k] ?? _UploadItemState.queued;
      if (s != _UploadItemState.success) c++;
    }
    return c;
  }

  String? _rid;
  String? _token;

  int _totalToUpload = 0;
  int _uploadedSoFar = 0;
  String? _currentFileName;

  double get _overallProgress {
    if (_totalToUpload <= 0) return 0.0;

    double sum = 0.0;
    int counted = 0;

    for (final f in _queuedFiles) {
      final k = _fileKey(f);
      final s = _fileState[k] ?? _UploadItemState.queued;

      // count only files that are part of this run (not already success before run)
      if (s == _UploadItemState.success) {
        sum += 1.0;
        counted++;
        continue;
      }

      final p = _uploadProgress[k];
      if (p != null) {
        sum += p.clamp(0.0, 1.0);
        counted++;
      }
    }

    if (counted == 0) return 0.0;
    return (sum / _totalToUpload).clamp(0.0, 1.0);
  }

  static const String _closedMsg =
      'This upload request is no longer accepting files. '
      'If you need to submit documents, please request for a new link or for the link to be re-enabled.';

  bool _isCompact(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return w < 600;
  }

  String _friendlyFunctionsError(Object e) {
    if (e is FirebaseFunctionsException) {
      switch (e.code) {
        case 'failed-precondition':
          return _closedMsg;
        case 'permission-denied':
          return 'You do not have permission to upload to this link.';
        case 'unauthenticated':
          return 'Your upload session has expired. Please refresh the page.';
        case 'not-found':
          return 'This upload link has been removed and is no longer available. If you need to submit documents, please request a new link.';
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

  void _dismissCompletionNote() {
    if (!mounted || !_showCompletionNote) return;
    setState(() => _showCompletionNote = false);
  }

  void _markCompletionNoteVisible() {
    if (!mounted || _showCompletionNote) return;
    setState(() => _showCompletionNote = true);
  }

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
        throw Exception(
          'Unable to start your upload session. Please refresh the page and try again.',
        );
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

    final f = _queuedFiles[index];
    final k = _fileKey(f);

    setState(() {
      _queuedFiles.removeAt(index);
      _uploadProgress.remove(k);
      _fileState.remove(k);
      _fileError.remove(k);
      if (_currentlyUploadingKey == k) _currentlyUploadingKey = null;
    });
  }

  Future<void> _queueFromXFiles(List<XFile> files) async {
    if (!mounted) return;

    // ✅ If user cancels, do nothing (no error UI)
    if (files.isEmpty) return;

    setState(() {
      _dismissCompletionNote();
      //_resetCompletedSessionIfNeeded(); // ✅ clears prior completed session UI
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
        _fileState[key] = _UploadItemState.queued;
        _fileError.remove(key);
      }
    }

    if (mounted) setState(() {});
  }

  void _resetCompletedSessionIfNeeded() {
    if (_uploading) return; // never clear mid-upload
    if (_queuedFiles.isEmpty) return; // nothing to clear
    if (_pendingCount != 0) return; // still has queued/failed items

    // ✅ All files are success => new session should start clean
    _queuedFiles.clear();
    _uploadProgress.clear();
    _fileState.clear();
    _fileError.clear();

    _currentlyUploadingKey = null;
    _currentFileName = null;

    _totalToUpload = 0;
    _uploadedSoFar = 0;
  }

  // Non-iOS web + native platforms (staging only, no upload)
  Future<void> _pickFilesToQueue() async {
    if (_uploading) return;

    setState(() {
      _dismissCompletionNote();
      //_resetCompletedSessionIfNeeded(); // ✅ clears prior completed session UI
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

          _fileState[key] = _UploadItemState.queued;
          _fileError.remove(key);
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

    final pending = _queuedFiles
        .where(
          (f) =>
              (_fileState[_fileKey(f)] ?? _UploadItemState.queued) !=
              _UploadItemState.success,
        )
        .toList();

    if (pending.isEmpty) {
      setState(() {
        _error = null;
        _success = 'All selected files have already been uploaded.';
      });
      return;
    }

    setState(() {
      _uploading = true;
      _error = null;
      _success = null;

      _showCompletionNote = false;
      _notifyingRequester = false;
      _requesterNotified = false;

      _totalToUpload = pending.length;
      _uploadedSoFar = 0;
      _currentFileName = null;
    });

    int uploaded = 0;
    final uploadedNames = <String>[];
    final uploadedMeta = <Map<String, dynamic>>[];

    try {
      // ✅ Concurrency cap (safe defaults)
      final int concurrency = kIsWeb ? 3 : 4;
      final sem = _Semaphore(concurrency);

      // With parallel uploads, there is no single “currently uploading” file
      _currentlyUploadingKey = null;

      // Launch throttled tasks
      final futures = <Future<void>>[];

      for (int i = 0; i < pending.length; i++) {
        final f = pending[i];

        futures.add(() async {
          await sem.acquire();
          try {
            // _uploadOne already updates per-file state/progress and marks failed/success
            final meta = await _uploadOne(f, i);

            // Only count successes
            if (meta != null && mounted) {
              setState(() {
                uploadedMeta.add(meta);
                uploadedNames.add((meta['name'] ?? '').toString());
                uploaded = uploadedMeta.length;
                _uploadedSoFar = uploaded;
              });
            }
          } finally {
            sem.release();
          }
        }());
      }

      // Wait for all uploads + finalizations to finish
      await Future.wait(futures);

      if (!mounted) return;

      // ✅ STEP 3 — SHOW COMPLETION BANNER IMMEDIATELY
      if (uploadedNames.isNotEmpty) {
        setState(() {
          _showCompletionNote = true; // ✅ THIS was missing
          _notifyingRequester = true; // ✅ start "Notifying…" state
          _requesterNotified = false;
          _success = null;
        });
      }
      // ✅ Send ONE summary email (server-side), after all uploads complete
      try {
        if (uploadedNames.isNotEmpty) {
          await _functions
              .httpsCallable('notifyDropoffBatchUpload')
              .call({
                'rid': _rid,
                'token': _token,
                'files': uploadedMeta, // ✅ ONLY successfully uploaded files
              })
              .timeout(const Duration(seconds: 20));

          if (mounted) {
            setState(() {
              _notifyingRequester = false;
              _requesterNotified = true;
            });
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('Batch email notify failed: $e');
        }

        // Non-fatal: uploads still succeeded
        if (mounted) {
          setState(() {
            _notifyingRequester = false;
            _requesterNotified = false;
          });

          // Optional: remove SnackBar if you don't want clients to ever see email errors
          // (recommended for client-facing UX)
          // ScaffoldMessenger.of(context).showSnackBar(
          //   SnackBar(content: Text('Upload completed. Notification will be sent shortly.')),
          // );
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
        _addRecentUploads(uploadedNames);

        // ✅ DO NOT show completion note here anymore
        // It is now shown immediately after uploads succeed (Step 3)

        _success = null;
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

    // ✅ Closed-state notice:
    // Prefer a specific backend error (e.g. deleted / not found),
    // otherwise fall back to the generic closed message.
    final String closedNotice = (_error != null && _error!.trim().isNotEmpty)
        ? _error!
        : _closedMsg;

    final bool isDeletedLink =
        _error != null && _error!.toLowerCase().contains('removed');

    final statusLower = status.toLowerCase().trim();
    final bool isExpiredLink = statusLower == 'expired';
    final bool isDisabledLink =
        !canUploadNow && !isDeletedLink; // includes closed/disabled/expired
    // ✅ Skeleton width calculation (responsive + professional)
    final w = MediaQuery.of(context).size.width;
    final maxLine = (w < 520) ? w - 80 : 520.0;

    // ✅ Show the completion/status banner as soon as uploads are done,
    // even while we are still sending the email notification.
    final showSessionBanner =
        _showCompletionNote && (_notifyingRequester || _requesterNotified);

    final brand = AppColors.brandBlue;

    final isIOSWeb = kIsWeb && WebFileSelector.isIOSWeb;

    final bool headerReady = !_loading;
    final bool showHeaderTitle = headerReady && canUploadNow;

    Widget addFilesBtn;

    // ✅ iOS Web: NEVER await before the picker opens.
    // The file dialog must be triggered directly by the user gesture. [2](https://www.telerik.com/blazor-ui/documentation/knowledge-base/upload-openselectfilesdialog-safari)[1](https://github.com/miguelpruivo/flutter_file_picker/issues/1736)
    if (isIOSWeb) {
      final baseBtn = OutlinedButton.icon(
        onPressed: (canUploadNow && !_uploading)
            ? () {
                setState(() {
                  _dismissCompletionNote();
                  _error = null;
                  _success = null;
                });
              }
            : null,
        icon: const Icon(Icons.add),
        label: const Text(
          'Add files',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        style:
            OutlinedButton.styleFrom(
              foregroundColor: brand,
              iconColor: brand,
              side: BorderSide(color: brand.withOpacity(0.85), width: 1.5),
              backgroundColor: brand.withOpacity(0.06),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size.fromHeight(48),
            ).copyWith(
              overlayColor: MaterialStateProperty.resolveWith<Color?>((states) {
                if (states.contains(MaterialState.hovered)) {
                  return brand.withOpacity(0.08); // ✅ smooth hover
                }
                if (states.contains(MaterialState.pressed)) {
                  return brand.withOpacity(0.12); // ✅ pressed feedback
                }
                return null;
              }),
            ),
      );

      // WebFileSelector is designed to fix iOS/iPadOS web picker behavior. [3](https://github.com/koichia/flutter_web_file_selector)
      addFilesBtn = WebFileSelector(
        multiple: true,
        onData: (files) async {
          // ✅ Validate AFTER selection (safe on iOS Safari)
          final ok = await _refreshAndCheckCanUpload(showMessage: true);
          if (!ok) {
            if (!mounted) return;
            setState(() {
              _queuedFiles.clear();
              _uploadProgress.clear();
              _currentlyUploadingKey = null;
            });
            return;
          }

          await _queueFromXFiles(files);
        },
        child: baseBtn,
      );
    } else {
      // ✅ Non‑iOS web/native: staged selection is fine
      addFilesBtn = OutlinedButton.icon(
        onPressed: (canUploadNow && !_uploading)
            ? () async {
                setState(() {
                  _dismissCompletionNote();
                  _error = null;
                  _success = null;
                });

                // ✅ Re-check server status right before letting user pick
                final ok = await _refreshAndCheckCanUpload(showMessage: true);
                if (!ok) {
                  if (!mounted) return;
                  setState(() {
                    _queuedFiles.clear();
                    _uploadProgress.clear();
                    _currentlyUploadingKey = null;
                  });
                  return;
                }

                _pickFilesToQueue();
              }
            : null,
        icon: const Icon(Icons.add),
        label: const Text(
          'Add files',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        style:
            OutlinedButton.styleFrom(
              foregroundColor: brand,
              iconColor: brand,
              side: BorderSide(color: brand.withOpacity(0.85), width: 1.5),
              backgroundColor: brand.withOpacity(0.06),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size.fromHeight(48),
            ).copyWith(
              overlayColor: MaterialStateProperty.resolveWith<Color?>((states) {
                if (states.contains(MaterialState.hovered)) {
                  return brand.withOpacity(0.08); // ✅ smooth hover
                }
                if (states.contains(MaterialState.pressed)) {
                  return brand.withOpacity(0.12); // ✅ pressed feedback
                }
                return null;
              }),
            ),
      );
    }

    String possessive(String name) {
      final n = name.trim();
      if (n.isEmpty) return 'their';
      return n.toLowerCase().endsWith('s') ? "$n’" : "$n’s";
    }

    // Only compute sender once data is actually ready (prevents “fallback flash”)
    final String rawSender = headerReady
        ? (_info?['requestedByName'] ?? '').toString().trim()
        : '';

    final bool hasSenderName = rawSender.isNotEmpty;

    final String titleText = hasSenderName
        ? '$rawSender has sent you this request'
        : (!canUploadNow
              ? 'This upload link is no longer available.'
              : 'A secure upload request has been sent to you.');

    final String recipientPossessive = hasSenderName
        ? possessive(rawSender)
        : 'our';

    final uploadBtn = FilledButton.icon(
      onPressed: canUploadNow && !_uploading && _pendingCount > 0
          ? _uploadQueuedFiles
          : null,
      icon: (_uploading || _notifyingRequester)
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
            ? 'Uploading files…'
            : _notifyingRequester
            ? 'Sending email…'
            : 'Upload selected ($_pendingCount)',
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        backgroundColor: (!canUploadNow || _pendingCount == 0 || _uploading)
            ? Colors.grey.shade400
            : AppColors.brandBlue,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    return PopScope(
      canPop:
          false, // ✅ blocks back navigation (Android predictive back compliant)
      child: Scaffold(
        // ✅ True page background (prevents white canvas)
        backgroundColor: const Color(0xFFDCDCDC),

        body: Container(
          // ✅ Entire screen painted light gray
          decoration: const BoxDecoration(
            color: Color(0xFFDCDCDC), // #dcdcdc
          ),

          child: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 720,
                    ), // ✅ OTP-like width
                    child: ListView(
                      padding: const EdgeInsets.all(18),
                      children: [
                        // ✅ Main secure card
                        Container(
                          padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.black.withOpacity(0.06),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.10),
                                blurRadius: 18,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // =========================================================
                              // ✅ BRAND HEADER (NOW INSIDE THE CARD)
                              // =========================================================
                              const _DropoffBrandHeader(dense: true),

                              // ✅ Tighter spacing when header/title is hidden
                              SizedBox(height: showHeaderTitle ? 14 : 8),

                              // ✅ Only show divider when a title is actually visible
                              if (showHeaderTitle) ...[
                                const Divider(
                                  height: 1,
                                  color: Color(0xFFE4E7EC),
                                ),
                                const SizedBox(height: 14),
                              ],

                              // =========================================================
                              // ✅ HEADER — ALWAYS VISIBLE
                              // =========================================================
                              // --- Header helpers (local to build) ---
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Title only (no subtitle)
                                        if (!headerReady)
                                          _SkeletonLine(
                                            height: 22,
                                            width: maxLine * 0.8,
                                            radius: 10,
                                          )
                                        else if (canUploadNow)
                                          Text(
                                            titleText,
                                            style: theme.textTheme.titleLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                  color: _kDarkGray,
                                                ),
                                          )
                                        else
                                          const SizedBox.shrink(),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(width: 10),

                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      _VerifiedLinkPill(
                                        loading: _loading,
                                        canUploadNow: canUploadNow,
                                        isDeleted: isDeletedLink,
                                        isExpired: isExpiredLink,
                                        verified: _isVerifiedLink,
                                      ),
                                    ],
                                  ),
                                ],
                              ),

                              // =========================================================
                              // ✅ ANIMATED BODY — REVEALED AFTER VERIFICATION
                              // =========================================================
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 380),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, animation) {
                                  final curved = CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic,
                                    reverseCurve: Curves.easeInCubic,
                                  );

                                  return ClipRect(
                                    child: FadeTransition(
                                      opacity: curved,
                                      child: SizeTransition(
                                        sizeFactor: curved,
                                        axis: Axis.vertical,
                                        axisAlignment:
                                            -1.0, // expand downward from top
                                        child: child,
                                      ),
                                    ),
                                  );
                                },

                                child: _loading
                                    ? const SizedBox(key: ValueKey('empty'))
                                    // =========================================================
                                    // ✅ CLOSED / INVALID LINK — CONTEXT + NOTICE ONLY
                                    // =========================================================
                                    : !canUploadNow
                                    ? Column(
                                        key: const ValueKey('closed'),
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 12),

                                          // ✅ CONTEXT (For / Requested by)
                                          AnimatedSize(
                                            duration: const Duration(
                                              milliseconds: 220,
                                            ),
                                            curve: Curves.easeOutCubic,
                                            alignment: Alignment.topCenter,
                                            child: canUploadNow
                                                ? Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 12,
                                                        ),
                                                    child: _BriefContextPanel(
                                                      info: _info,
                                                    ),
                                                  )
                                                : const SizedBox.shrink(),
                                          ),

                                          const SizedBox(height: 16),

                                          // ✅ SINGLE SOURCE OF TRUTH — CLOSED NOTICE
                                          _NoticeBanner.closed(closedNotice),

                                          const SizedBox(height: 18),
                                        ],
                                      )
                                    // =========================================================
                                    // ✅ OPEN LINK — FULL UPLOAD EXPERIENCE
                                    // =========================================================
                                    : Column(
                                        key: const ValueKey('open'),
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 12),

                                          // ✅ CONTEXT PANEL
                                          AnimatedSize(
                                            duration: const Duration(
                                              milliseconds: 220,
                                            ),
                                            curve: Curves.easeOutCubic,
                                            alignment: Alignment.topCenter,
                                            child: canUploadNow
                                                ? Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 12,
                                                        ),
                                                    child: _BriefContextPanel(
                                                      info: _info,
                                                    ),
                                                  )
                                                : const SizedBox.shrink(),
                                          ),

                                          const SizedBox(height: 16),

                                          // ✅ NON‑CLOSED ERRORS ONLY
                                          _Reveal(
                                            show: _error != null && !_isClosed,
                                            child: Column(
                                              children: [
                                                _ErrorBanner(
                                                  message: _error ?? '',
                                                ),
                                                const SizedBox(height: 12),
                                              ],
                                            ),
                                          ),

                                          // ✅ QUEUED FILES
                                          _Reveal(
                                            show: _queuedFiles.isNotEmpty,
                                            child: _QueuedFilesCard(
                                              files: _queuedFiles,
                                              onRemove: _removeQueuedAt,
                                              disabled: _uploading,
                                              progress: _uploadProgress,
                                              activeKey: _currentlyUploadingKey,
                                              state: _fileState,
                                              errors: _fileError,
                                              notifyingRequester:
                                                  _notifyingRequester,
                                              requesterNotified:
                                                  _requesterNotified,
                                            ),
                                          ),

                                          const SizedBox(height: 12),

                                          // ✅ SESSION COMPLETION
                                          _Reveal(
                                            show: showSessionBanner,
                                            child: Column(
                                              children: [
                                                _SessionCompletionBanner(
                                                  notifyingRequester:
                                                      _notifyingRequester,
                                                  requesterNotified:
                                                      _requesterNotified,
                                                ),
                                              ],
                                            ),
                                          ),

                                          const SizedBox(height: 12),

                                          // ✅ ACTION BUTTONS
                                          SizedBox(
                                            height: 48,
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                Expanded(
                                                  child: SizedBox.expand(
                                                    child: addFilesBtn,
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: SizedBox.expand(
                                                    child: uploadBtn,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                          const SizedBox(height: 12),

                                          // ✅ FOOTNOTE (ONLY WHEN OPEN)
                                          // ✅ FOOTNOTE (ONLY WHEN OPEN) — moved from header
                                          if (!headerReady) ...[
                                            _SkeletonLine(
                                              height: 14,
                                              width: maxLine,
                                              radius: 10,
                                            ),
                                          ] else
                                            RichText(
                                              textScaleFactor: 1.0,
                                              text: TextSpan(
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                      fontSize: 9.5,
                                                      height: 1.4,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: const Color(
                                                        0xFF667085,
                                                      ),
                                                    ),
                                                children: [
                                                  TextSpan(
                                                    text:
                                                        'Your files will be uploaded securely to $recipientPossessive account. Learn more about file requests and our ',
                                                  ),

                                                  WidgetSpan(
                                                    alignment:
                                                        PlaceholderAlignment
                                                            .baseline,
                                                    baseline:
                                                        TextBaseline.alphabetic,
                                                    child: _InlineHoverLink(
                                                      label: 'Privacy Policy',
                                                      onTap: () =>
                                                          Navigator.pushNamed(
                                                            context,
                                                            '/privacy',
                                                          ),
                                                      enableHover: _isDesktop,
                                                      style: const TextStyle(
                                                        fontSize: 9.5,
                                                        height: 1.4,
                                                        color: Color(
                                                          0xFF475467,
                                                        ),
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        decoration:
                                                            TextDecoration
                                                                .underline,
                                                        decorationThickness:
                                                            1.0,
                                                      ),
                                                      hoverStyle:
                                                          const TextStyle(
                                                            fontSize: 9.5,
                                                            height: 1.4,
                                                            color: Color(
                                                              0xFF344054,
                                                            ),
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            decoration:
                                                                TextDecoration
                                                                    .underline,
                                                            decorationThickness:
                                                                1.5,
                                                          ),
                                                    ),
                                                  ),

                                                  const TextSpan(text: '.'),
                                                ],
                                              ),
                                            ),

                                          const SizedBox(height: 18),
                                        ],
                                      ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),
                        const _DropoffFooter(),
                        const SizedBox(height: 24),
                      ],
                    ),
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

class _Shimmer extends StatefulWidget {
  final Widget child;
  const _Shimmer({required this.child});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Neutral enterprise shimmer
    const base = Color(0xFFE4E7EC);
    const highlight = Color(0xFFF2F4F7);

    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value; // 0..1
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) {
            final dx = rect.width * (t * 2 - 1); // slide -1..+1 widths
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [base, highlight, base],
              stops: const [0.2, 0.5, 0.8],
              transform: _SlidingGradientTransform(dx),
            ).createShader(rect);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double dx;
  const _SlidingGradientTransform(this.dx);

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(dx, 0, 0);
  }
}

class _SkeletonLine extends StatelessWidget {
  final double height;
  final double width;
  final double radius;

  const _SkeletonLine({this.height = 14, required this.width, this.radius = 8});

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          height: height,
          width: width,
          color: const Color(0xFFE4E7EC),
        ),
      ),
    );
  }
}

class _InlineHoverLink extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool enableHover; // ✅ desktop-only
  final TextStyle style;
  final TextStyle hoverStyle;

  const _InlineHoverLink({
    required this.label,
    required this.onTap,
    required this.enableHover,
    required this.style,
    required this.hoverStyle,
  });

  @override
  State<_InlineHoverLink> createState() => _InlineHoverLinkState();
}

class _InlineHoverLinkState extends State<_InlineHoverLink> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = (widget.enableHover && _hovering)
        ? widget.hoverStyle
        : widget.style;

    final child = AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      style: effectiveStyle,
      child: Text(widget.label),
    );

    // Desktop hover only
    if (widget.enableHover) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.translucent,
          child: child,
        ),
      );
    }

    // Mobile / touch: no hover, but still clickable
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.translucent,
      child: child,
    );
  }
}

class _Reveal extends StatelessWidget {
  final bool show;
  final Widget child;

  const _Reveal({required this.show, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.02),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: show ? child : const SizedBox.shrink(),
    );
  }
}

class _VerifiedLinkPill extends StatelessWidget {
  final bool loading;
  final bool verified;

  // ✅ new inputs
  final bool canUploadNow;
  final bool isDeleted;
  final bool isExpired;

  const _VerifiedLinkPill({
    required this.loading,
    required this.verified,
    required this.canUploadNow,
    required this.isDeleted,
    required this.isExpired,
  });

  @override
  Widget build(BuildContext context) {
    // While validateDropoffLink is in progress
    if (loading) {
      return const _Pill(
        icon: SizedBox(
          height: 14,
          width: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        text: 'Verifying…',
        bg: Color(0xFFF2F4F7),
        fg: Color(0xFF475467),
        border: Color(0xFFE4E7EC),
      );
    }

    // ✅ Removed (deleted link)
    if (isDeleted) {
      return const _Pill(
        icon: Icon(Icons.delete_outline, size: 16),
        text: 'Removed',
        bg: Color(0xFFF2F4F7),
        fg: Color(0xFF475467),
        border: Color(0xFFD0D5DD),
      );
    }

    // ✅ Expired (time-based)
    if (isExpired) {
      return const _Pill(
        icon: Icon(Icons.schedule, size: 16),
        text: 'Expired',
        bg: Color(0xFFFFFAEB),
        fg: Color(0xFFB54708),
        border: Color(0xFFFEC84B),
      );
    }

    // ✅ Disabled / closed (no longer accepting uploads)
    if (!canUploadNow) {
      return const _Pill(
        icon: Icon(Icons.lock_outline, size: 16),
        text: 'Disabled',
        bg: Color(0xFFFFFAEB),
        fg: Color(0xFFB54708),
        border: Color(0xFFFEC84B),
      );
    }

    // ✅ Verified (only show when link is OPEN and validated)
    if (!verified) return const SizedBox.shrink();

    return const _Pill(
      icon: Icon(Icons.verified_user, size: 16),
      text: 'Link verified',
      bg: Color(0xFFECFDF3),
      fg: Color(0xFF067647),
      border: Color(0xFFABEFC6),
    );
  }
}

class _LinkStatusPill extends StatelessWidget {
  final String status;
  const _LinkStatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase().trim();

    if (s == 'open') {
      return const _Pill(
        icon: Icon(Icons.check_circle, size: 16),
        text: 'Open',
        bg: Color(0xFFECFDF3),
        fg: Color(0xFF067647),
        border: Color(0xFFABEFC6),
      );
    }

    if (s == 'closed') {
      return const _Pill(
        icon: Icon(Icons.lock, size: 16),
        text: 'Closed',
        bg: Color(0xFFFEF3F2),
        fg: Color(0xFFB42318),
        border: Color(0xFFFDA29B),
      );
    }

    // Default/unknown
    return _Pill(
      icon: const Icon(Icons.info_outline, size: 16),
      text: status.isEmpty ? '—' : status,
      bg: const Color(0xFFF2F4F7),
      fg: const Color(0xFF475467),
      border: const Color(0xFFE4E7EC),
    );
  }
}

class _Pill extends StatelessWidget {
  final Widget icon;
  final String text;
  final Color bg;
  final Color fg;
  final Color border;

  const _Pill({
    required this.icon,
    required this.text,
    required this.bg,
    required this.fg,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconTheme(
            data: IconThemeData(color: fg),
            child: icon,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _QueuedFilesCard extends StatelessWidget {
  final List<PlatformFile> files;
  final void Function(int index) onRemove;
  final bool disabled;

  final Map<String, double> progress;
  final Map<String, _UploadItemState> state;
  final Map<String, String> errors;
  final String? activeKey;

  // ✅ ADD THESE
  final bool notifyingRequester;
  final bool requesterNotified;

  const _QueuedFilesCard({
    required this.files,
    required this.onRemove,
    required this.disabled,
    required this.progress,
    required this.activeKey,
    required this.state,
    required this.errors,

    // ✅ ADD THESE
    required this.notifyingRequester,
    required this.requesterNotified,
  });

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Widget _buildMetaRow(ThemeData theme, PlatformFile f, _UploadItemState s) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatFileSize(f.size),
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: const Color(0xFF98A2B3),
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
        const SizedBox(width: 6),

        if (s != _UploadItemState.queued) ...[
          const Text('•', style: TextStyle(color: Color(0xFF98A2B3))),
          const SizedBox(width: 6),
        ],

        Text(
          s == _UploadItemState.queued
              ? 'Queued'
              : s == _UploadItemState.finalizing
              ? 'Finalizing…'
              : s == _UploadItemState.success
              ? 'Uploaded'
              : s == _UploadItemState.failed
              ? 'Failed'
              : '',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            fontWeight: s == _UploadItemState.success
                ? FontWeight.w700
                : FontWeight.w600,
            color: s == _UploadItemState.success
                ? const Color(0xFF067647)
                : s == _UploadItemState.failed
                ? const Color(0xFFB42318)
                : const Color(0xFF667085),
            height: 1.2,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // Slightly closer to white = quieter panel
        color: const Color(0xFFFCFCFD),
        borderRadius: BorderRadius.circular(12),

        // Use a neutral border token instead of black opacity
        border: Border.all(color: const Color(0xFFE4E7EC)),
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
          const SizedBox(height: 4),
          ...files.asMap().entries.map((e) {
            final i = e.key;
            final f = e.value;

            final key =
                '${f.name}|${f.size}|${f.path ?? ''}|${f.identifier ?? ''}';
            final p = progress[key];
            final s = state[key] ?? _UploadItemState.queued;
            final err = errors[key];

            // ✅ Stable layout constants (declared OUTSIDE widget list)
            const double statusBarHeight = 6;
            const double statusGap = 6;
            const double statusTextHeight = 16;
            const double statusAreaHeight =
                statusBarHeight + statusGap + statusTextHeight;
            const double _fileNameLineHeight = 18;
            const double _metaLineHeight = 16;
            const double _textBlockHeight =
                _fileNameLineHeight + 4 + _metaLineHeight; // 4 = spacing

            final isCompact = MediaQuery.of(context).size.width < 600;

            // Normalize progress (always defined)
            final double pv = (s == _UploadItemState.uploading)
                ? (p ?? 0.0)
                : (s == _UploadItemState.queued)
                ? 0.0
                : 1.0;

            // Status text (single line, stable)
            final String statusText = (s == _UploadItemState.queued)
                ? 'Queued'
                : (s == _UploadItemState.uploading)
                ? 'Uploading… ${(pv * 100).clamp(0, 100).toStringAsFixed(0)}%'
                : (s == _UploadItemState.finalizing)
                ? 'Finalizing…'
                : (s == _UploadItemState.success)
                ? 'Uploaded'
                : (err ?? 'Upload failed');

            return Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: isCompact ? 10 : 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.insert_drive_file_outlined,
                        size: 16,
                        color: _kGray,
                      ),
                      const SizedBox(width: 8),

                      Expanded(
                        child: SizedBox(
                          height: _textBlockHeight,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                height: _fileNameLineHeight,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    f.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: _kGray,
                                      fontWeight: FontWeight.w600,
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                height: _metaLineHeight,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: _buildMetaRow(theme, f, s),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      SizedBox(
                        width: isCompact ? 72 : 210,
                        child: isCompact
                            ? _buildCompactStatusRow(
                                state: s,
                                progress: p ?? 0.0,
                              )
                            : _buildInlineStatusRow(
                                state: s,
                                progress: p ?? 0.0,
                              ),
                      ),

                      const SizedBox(width: 6),
                      SizedBox(
                        width: 34,
                        height: 34,
                        child: (s == _UploadItemState.queued && !disabled)
                            ? IconButton(
                                padding: EdgeInsets.zero,
                                icon: Icon(
                                  Icons.close,
                                  color: Colors.red.shade700,
                                  size: 18,
                                ),
                                onPressed: () => onRemove(i),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),

                // ✅ divider OUTSIDE the row
                if (i != files.length - 1)
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFE4E7EC),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCompactStatusRow({
    required _UploadItemState state,
    required double progress,
  }) {
    const double iconSize = 16;
    const double percentWidth = 34; // reserve space even when hidden

    Widget spinner() => const SizedBox(
      width: iconSize,
      height: iconSize,
      child: CircularProgressIndicator(strokeWidth: 2),
    );

    Widget percentText(String text, {bool visible = true}) => SizedBox(
      width: percentWidth,
      child: Opacity(
        opacity: visible ? 1 : 0, // ✅ keeps width without showing
        child: Text(
          text,
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF667085),
          ),
        ),
      ),
    );

    // ✅ Uploading
    if (state == _UploadItemState.uploading) {
      final pct = (progress.clamp(0.0, 1.0) * 100).round();

      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [percentText('$pct%'), const SizedBox(width: 6), spinner()],
      );
    }

    // ✅ Finalizing — SAME LAYOUT, percent hidden
    if (state == _UploadItemState.finalizing) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          percentText('100%', visible: false), // ✅ holds space
          const SizedBox(width: 6),
          spinner(),
        ],
      );
    }

    // ✅ Success
    if (state == _UploadItemState.success) {
      return const Align(
        alignment: Alignment.centerRight,
        child: Icon(Icons.check_circle, size: 18, color: Color(0xFF067647)),
      );
    }

    // ✅ Failed
    if (state == _UploadItemState.failed) {
      return const Align(
        alignment: Alignment.centerRight,
        child: Icon(Icons.error_outline, size: 18, color: Color(0xFFB42318)),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildInlineStatusRow({
    required _UploadItemState state,
    required double progress,
  }) {
    const double barHeight = 6;
    const double rowHeight = 18;
    const Color track = Color(0x14000000); // slightly stronger than 0.08

    Widget bar(double value, {Color color = const Color(0xFF067647)}) {
      return Align(
        alignment: Alignment.center,
        child: SizedBox(
          height: barHeight, // ✅ hard cap thickness
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              backgroundColor: track,
              color: color,
            ),
          ),
        ),
      );
    }

    // No bar for queued (status is next to name)
    if (state == _UploadItemState.queued) {
      return const SizedBox.shrink();
    }

    // ✅ Uploading: determinate bar + SMOOTH percent display
    if (state == _UploadItemState.uploading) {
      final target = progress.clamp(0.0, 1.0);

      return SizedBox(
        height: rowHeight,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: target), // ✅ animates from previous value
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) {
            final pct = (v * 100).round().clamp(0, 100);

            return Row(
              children: [
                Expanded(child: bar(v)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 38, // ✅ matches 100% width
                  child: Text(
                    '$pct%',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF667085),
                    ),
                  ),
                ),

                // keep a small reserved space so layout doesn't shift when check appears
                const SizedBox(width: 8),
                const SizedBox(width: 18, height: 18),
              ],
            );
          },
        ),
      );
    }

    // ✅ Finalizing: full bar, keep it same thickness (optional subtle “working” cue)
    if (state == _UploadItemState.finalizing) {
      return SizedBox(
        height: rowHeight,
        child: Row(
          children: [
            Expanded(child: bar(1.0)),
            const SizedBox(width: 8),
            const SizedBox(
              width: 38,
              child: Text(
                '100%',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF667085),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      );
    }

    // ✅ Success: keep full bar AND show checkmark on the right
    if (state == _UploadItemState.success) {
      return SizedBox(
        height: rowHeight,
        child: Row(
          children: [
            Expanded(child: bar(1.0, color: const Color(0xFF05603A))),
            const SizedBox(width: 8),
            const SizedBox(
              width: 38,
              child: Text(
                '100%',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF067647),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.check_circle, size: 18, color: Color(0xFF067647)),
          ],
        ),
      );
    }

    // Failed
    return SizedBox(
      height: rowHeight,
      child: const Align(
        alignment: Alignment.centerRight,
        child: Icon(Icons.error_outline, size: 18, color: Color(0xFFB42318)),
      ),
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color bg;
  final Color fg;
  final Color border;

  const _NoticeBanner({
    required this.message,
    required this.icon,
    required this.bg,
    required this.fg,
    required this.border,
  });

  factory _NoticeBanner.closed(String message) => _NoticeBanner(
    message: message,
    icon: Icons.lock_outline,
    bg: const Color(0xFFFFFAEB), // warm neutral (not loud red)
    fg: const Color(0xFFB54708), // amber/brown text
    border: const Color(0xFFFEC84B), // subtle amber border
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
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

class _BriefContextPanel extends StatelessWidget {
  final Map<String, dynamic>? info;
  const _BriefContextPanel({required this.info});

  String _s(dynamic v) => (v ?? '').toString().trim();

  String _maskEmail(String email) {
    final at = email.indexOf('@');
    if (at <= 1) return email; // too short or invalid, show as-is

    final name = email.substring(0, at);
    final domain = email.substring(at);

    if (name.length <= 2) {
      return '${name[0]}***$domain';
    }

    return '${name[0]}***$domain';
  }

  Widget _row(BuildContext context, String label, String value) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2), // ✅ tight spacing
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92, // ✅ consistent label column
            child: Text(
              '$label:',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF667085),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF344054),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context); // ✅ ADD THIS
    final requestMessage = _s(info?['message']);
    final clientName = _s(info?['clientName']);
    final requestedByName = _s(info?['requestedByName']);
    final email = _s(info?['email']);
    final company = _s(info?['businessName']);
    final clientEmail = _s(
      info?['clientEmail'] ?? info?['client_email'] ?? info?['recipientEmail'],
    );

    // Safety: never show requester email here
    if (clientEmail == _s(info?['requestedByEmail'])) {
      // ignore
    }

    if (kDebugMode) {
      debugPrint('Dropoff info keys: ${info?.keys}');
    }

    final hasAny = [clientName, company, clientEmail].any((v) => v.isNotEmpty);

    if (!hasAny) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10), // ✅ compact
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, // ✅ LEFT aligned
        children: [
          if (clientName.isNotEmpty) _row(context, 'For', clientName),

          if (company.isNotEmpty) _row(context, 'Company', company),

          if (clientEmail.isNotEmpty)
            _row(context, 'Email', _maskEmail(clientEmail)),

          // ✅ Merge the “Dear …” request message into the SAME rectangle
          if (requestMessage.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: Color(0xFFE4E7EC)),
            const SizedBox(height: 10),
            Text(
              requestMessage,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF475467),
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniKVRow extends StatelessWidget {
  final String label;
  final String value;

  const _MiniKVRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '$label:',
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFF667085),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            softWrap: true,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF344054),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _DropoffBrandHeader extends StatelessWidget {
  final bool dense;
  const _DropoffBrandHeader({this.dense = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SvgPicture.string(
        kBrandLogoSvg2,
        height: dense ? 104 : 120,
        fit: BoxFit.contain,
      ),
    );
  }
}

class _DropoffFooter extends StatelessWidget {
  const _DropoffFooter();

  Widget _link(BuildContext context, String label, VoidCallback onTap) {
    return _InlineHoverLink(
      label: label,
      onTap: onTap,
      enableHover: true,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: AppColors.brandBlue,
      ),
      hoverStyle: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: AppColors.brandBlue,
        decoration: TextDecoration.underline,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Text(
          '© ${DateTime.now().year} Axume & Associates CPAs, AAC',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFF667085),
            fontWeight: FontWeight.w600,
          ),
        ),

        const SizedBox(height: 4),

        Text(
          'Secure Document Upload Portal.\nAll rights reserved.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFF667085),
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _SessionCompletionBanner extends StatelessWidget {
  final bool notifyingRequester;
  final bool requesterNotified;

  const _SessionCompletionBanner({
    required this.notifyingRequester,
    required this.requesterNotified,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Enterprise messaging: status-first, calm, no cheerleading.
    final String line1 = 'All files have been successfully uploaded.';
    final String line2 = notifyingRequester
        ? 'Preparing and sending the email notification. Please keep this page open.'
        : requesterNotified
        ? 'The recipient has been notified by email. You may upload additional files, or safely close this page.'
        : '';

    // Color: green only when final state is reached
    final Color accent = requesterNotified
        ? const Color(0xFF067647)
        : const Color(0xFF667085);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: requesterNotified
            ? Colors.green.withOpacity(0.06)
            : const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: requesterNotified
              ? Colors.green.withOpacity(0.25)
              : Colors.black.withOpacity(0.10),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          notifyingRequester
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF667085), // enterprise neutral
                  ),
                )
              : Icon(
                  requesterNotified ? Icons.check_circle : Icons.info_outline,
                  color: accent,
                  size: 18,
                ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line1,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: requesterNotified
                        ? const Color(0xFF067647)
                        : const Color(0xFF101828),
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  line2,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: requesterNotified
                        ? const Color(0xFF067647)
                        : const Color(0xFF475467),
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
