import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../widgets/page_scaffold.dart';
import '../utils/file_kind.dart';
import '../theme/app_colors.dart';

enum _SortField { name, size, date, expires, client, creator }

enum _TypeFilter { all, pdf, office, img, other }

enum _DateFilter { all, last30 }

enum _DuplicateUploadAction { replace, skip, cancel }

class FileBoxScreen extends StatefulWidget {
  const FileBoxScreen({super.key, this.autoOpenUpload = false});

  final bool autoOpenUpload;

  @override
  State<FileBoxScreen> createState() => _FileBoxScreenState();
}

class _FileBoxScreenState extends State<FileBoxScreen> {
  final _searchCtrl = TextEditingController();
  String _q = '';

  String? _role;
  bool _loadingRole = true;
  List<_UploadDoc> _selectedDocsCache = const [];

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _uploadsStream;

  final Set<String> _selected = {};
  _SortField _sortField = _SortField.date;
  bool _sortAsc = false;

  _TypeFilter _typeFilter = _TypeFilter.all;
  _DateFilter _dateFilter = _DateFilter.all;

  static const int _pageSize = 50;
  int _visibleCount = _pageSize;

  bool _busy = false;
  bool _autoUploadOpened = false;
  bool _draggingUploads = false;
  List<String> _uploadingNames = const [];
  final List<_FileBoxPendingUpload> _pendingUploads = [];

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
        .get();

    _role = (snap.data()?['role'] ?? '').toString().toLowerCase().trim();
    final isAdmin = _role == 'admin';

    _uploadsStream = isAdmin
        ? FirebaseFirestore.instance
              .collectionGroup('files')
              .where('deleted', isEqualTo: false) // Hide deleted at source
              .orderBy('createdAt', descending: true)
              .limit(500)
              .snapshots()
        : FirebaseFirestore.instance
              .collectionGroup('files')
              .where('requestCreatedByRole', isEqualTo: 'associate')
              .where('deleted', isEqualTo: false) // Hide deleted at source
              .orderBy('createdAt', descending: true)
              .limit(500)
              .snapshots();

    _loadingRole = false;
    if (mounted) setState(() {});

    if (mounted && widget.autoOpenUpload && !_autoUploadOpened) {
      _autoUploadOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _chooseAndUploadToFileBox();
      });
    }
  }

  String _s(dynamic v) => (v ?? '').toString().trim();

  String _fmt(BuildContext c, DateTime d) {
    final loc = MaterialLocalizations.of(c);
    return '${loc.formatShortDate(d)} at ${loc.formatTimeOfDay(TimeOfDay.fromDateTime(d))}';
  }

  DateTime? _asDate(dynamic createdAt) {
    if (createdAt is Timestamp) return createdAt.toDate();
    return null;
  }

  String _guessContentType(String fileName) {
    final name = fileName.toLowerCase().trim();
    if (name.endsWith('.pdf')) return 'application/pdf';
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    if (name.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (name.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (name.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (name.endsWith('.doc')) return 'application/msword';
    if (name.endsWith('.txt')) return 'text/plain';
    if (name.endsWith('.zip')) return 'application/zip';
    return 'application/octet-stream';
  }

  Future<Uint8List?> _readPlatformFileBytes(PlatformFile file) async {
    final bytes = file.bytes;
    if (bytes != null && bytes.isNotEmpty) return bytes;

    final stream = file.readStream;
    if (stream == null) return null;

    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      builder.add(chunk);
    }

    final collected = builder.takeBytes();
    return collected.isEmpty ? null : collected;
  }

  Future<List<_FileBoxPendingUpload>> _pickFileBoxUploads() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      withReadStream: !kIsWeb,
    );
    if (result == null) return const [];

    final files = <_FileBoxPendingUpload>[];
    var unreadableCount = 0;

    for (final f in result.files) {
      final bytes = await _readPlatformFileBytes(f);
      if (bytes == null || bytes.isEmpty) {
        unreadableCount++;
        continue;
      }

      files.add(
        _FileBoxPendingUpload(
          name: f.name,
          sizeBytes: f.size > 0 ? f.size : bytes.length,
          bytes: bytes,
          contentType: _guessContentType(f.name),
        ),
      );
    }

    if (files.isEmpty && unreadableCount > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The selected file could not be read. Try saving it to Files first, then upload again.',
          ),
        ),
      );
    }

    return files;
  }

  Future<void> _chooseAndUploadToFileBox() async {
    final files = await _pickFileBoxUploads();
    _stageFileBoxUploads(files);
  }

  Future<void> _handleDroppedUploads(DropDoneDetails details) async {
    final files = <_FileBoxPendingUpload>[];
    for (final file in details.files) {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) continue;
      files.add(
        _FileBoxPendingUpload(
          name: file.name,
          sizeBytes: bytes.length,
          bytes: bytes,
          contentType: _guessContentType(file.name),
        ),
      );
    }
    _stageFileBoxUploads(files);
  }

  void _stageFileBoxUploads(List<_FileBoxPendingUpload> files) {
    if (files.isEmpty) return;
    setState(() {
      final existingKeys = _pendingUploads.map((f) => f.key).toSet();
      for (final file in files) {
        if (existingKeys.add(file.key)) {
          _pendingUploads.add(file);
        }
      }
      _draggingUploads = false;
    });
  }

  Future<void> _uploadToFileBox(List<_FileBoxPendingUpload> files) async {
    if (files.isEmpty) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in is required to upload files.')),
      );
      return;
    }

    setState(() {
      _busy = true;
      _uploadingNames = files.map((f) => f.name).toList();
    });

    final uploaded = <Map<String, dynamic>>[];
    final uploadedPaths = <String>[];

    try {
      for (var i = 0; i < files.length; i++) {
        final file = files[i];
        final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final objectId =
            '${DateTime.now().microsecondsSinceEpoch}_${i}_${safeName.hashCode}';
        final storagePath =
            'secure_share_uploads/$uid/filebox-$objectId-$safeName';
        final ref = FirebaseStorage.instance.ref(storagePath);

        await ref.putData(
          file.bytes,
          SettableMetadata(contentType: file.contentType),
        );

        uploadedPaths.add(storagePath);
        uploaded.add({
          'storagePath': storagePath,
          'originalName': file.name,
          'contentType': file.contentType,
          'sizeBytes': file.sizeBytes,
        });
      }

      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('createFileBoxUploads');
      var res = await callable.call({
        'uploadedFiles': uploaded,
        'duplicateMode': 'check',
      });

      var data = Map<String, dynamic>.from(res.data as Map);
      if (data['duplicateActionRequired'] == true) {
        if (!mounted) return;
        final action = await _showDuplicateUploadDialog(data);
        if (action == null || action == _DuplicateUploadAction.cancel) {
          for (final path in uploadedPaths) {
            try {
              await FirebaseStorage.instance.ref(path).delete();
            } catch (_) {
              // Best-effort cleanup for staged uploads.
            }
          }
          if (!mounted) return;
          setState(() => _pendingUploads.clear());
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Upload cancelled. File Box was unchanged.'),
            ),
          );
          return;
        }

        res = await callable.call({
          'uploadedFiles': uploaded,
          'duplicateMode': action == _DuplicateUploadAction.replace
              ? 'replace'
              : 'skip',
        });
        data = Map<String, dynamic>.from(res.data as Map);
      }

      final reusedCount = data['reusedCount'] is num
          ? (data['reusedCount'] as num).toInt()
          : 0;
      final replacedCount = data['replacedCount'] is num
          ? (data['replacedCount'] as num).toInt()
          : 0;
      final skippedCount = data['skippedCount'] is num
          ? (data['skippedCount'] as num).toInt()
          : 0;

      if (!mounted) return;
      final message = replacedCount > 0
          ? '$replacedCount existing file(s) replaced in File Box.'
          : skippedCount > 0
          ? '${files.length - skippedCount} file(s) uploaded. $skippedCount conflict(s) skipped.'
          : reusedCount > 0
          ? 'Duplicate file already exists. Using the existing File Box item.'
          : files.length == 1
          ? 'File uploaded to File Box.'
          : '${files.length} files uploaded to File Box.';
      setState(() => _pendingUploads.clear());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      for (final path in uploadedPaths) {
        try {
          await FirebaseStorage.instance.ref(path).delete();
        } catch (_) {
          // Best-effort cleanup for staged uploads.
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _draggingUploads = false;
          _uploadingNames = const [];
        });
      }
    }
  }

  Future<_DuplicateUploadAction?> _showDuplicateUploadDialog(
    Map<String, dynamic> data,
  ) {
    final rawConflicts = data['nameConflicts'] is List
        ? data['nameConflicts'] as List
        : const [];
    final rawExact = data['exactDuplicates'] is List
        ? data['exactDuplicates'] as List
        : const [];

    final conflicts = rawConflicts
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final exact = rawExact
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return showDialog<_DuplicateUploadAction>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 36,
                        width: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFAEB),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFEDF89)),
                        ),
                        child: const Icon(
                          Icons.file_copy_outlined,
                          size: 19,
                          color: Color(0xFFB54708),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'File name already exists',
                              style: TextStyle(
                                color: Color(0xFF101828),
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                height: 1.15,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Some uploads have the same name as files already in File Box. Review how you want to handle them.',
                              style: TextStyle(
                                color: Color(0xFF667085),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (exact.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _DuplicateNotice(
                      icon: Icons.check_circle_outline,
                      title: '${exact.length} exact duplicate(s)',
                      subtitle:
                          'Already in File Box. These will use the existing file and will not create another copy.',
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    '${conflicts.length} file name conflict${conflicts.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: Color(0xFF344054),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCFCFD),
                      border: Border.all(color: const Color(0xFFE4E7EC)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: conflicts.take(5).map((item) {
                        return ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.insert_drive_file_outlined,
                            color: AppColors.brandBlue,
                          ),
                          title: Text(
                            (item['uploadedName'] ?? 'File').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF101828),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          subtitle: const Text(
                            'A file with this name is already in File Box.',
                            style: TextStyle(
                              color: Color(0xFF667085),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  if (conflicts.length > 5)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '+${conflicts.length - 5} more file(s)',
                        style: const TextStyle(
                          color: Color(0xFF667085),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      border: Border.all(color: const Color(0xFFE4E7EC)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Keep existing files will upload only the new files and leave conflicting files unchanged. Replace existing files will update the File Box version for matching names.',
                      style: TextStyle(
                        color: Color(0xFF475467),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () =>
                            Navigator.pop(ctx, _DuplicateUploadAction.cancel),
                        child: const Text('Cancel upload'),
                      ),
                      const Spacer(),
                      OutlinedButton(
                        onPressed: () =>
                            Navigator.pop(ctx, _DuplicateUploadAction.skip),
                        child: const Text('Keep existing files'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: () =>
                            Navigator.pop(ctx, _DuplicateUploadAction.replace),
                        child: const Text('Replace existing files'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  _TypeFilter _inferTypeFilter(String name, String contentType) {
    final kind = detectFileKind(fileName: name, contentType: contentType);

    switch (kind) {
      case FileKind.pdf:
        return _TypeFilter.pdf;
      case FileKind.word:
      case FileKind.excel:
      case FileKind.powerpoint:
        return _TypeFilter.office;
      case FileKind.image:
        return _TypeFilter.img;
      default:
        return _TypeFilter.other;
    }
  }

  bool _passesDateFilter(DateTime? when) {
    if (_dateFilter == _DateFilter.all) return true;
    if (when == null) return false;

    final now = DateTime.now();
    DateTime start;

    switch (_dateFilter) {
      case _DateFilter.last30:
        start = now.subtract(const Duration(days: 30));
        break;
      case _DateFilter.all:
        return true;
    }
    return when.isAfter(start);
  }

  Future<void> _downloadFile({
    required bool isAdmin,
    required String storagePath,
    required String filename,
    String? contentType,
    String? requestId,
    String? fileId,
    bool showReadyDialog = true,
  }) async {
    if (storagePath.trim().isEmpty) return;

    setState(() => _busy = true);
    try {
      final fn = isAdmin ? 'getAdminDownloadUrl' : 'getDropoffDownloadUrl';

      final res = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable(fn)
          .call({
            'storagePath': storagePath,
            'filename': filename,
            'contentType': (contentType ?? '').toString(),
            'requestId': (requestId ?? '').toString(),
            'fileId': (fileId ?? '').toString(),
          });

      final data = Map<String, dynamic>.from(res.data as Map);
      final url = (data['url'] ?? '').toString();

      if (url.isEmpty) {
        throw Exception('Could not generate download link.');
      }

      final uri = Uri.parse(url);

      if (!mounted) return;

      if (!showReadyDialog) {
        if (kIsWeb) {
          await launchUrl(uri, webOnlyWindowName: '_self');
        } else {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }

        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Downloading $filename...')));
        return;
      }

      // iOS/Safari-friendly: user taps a button, then navigation is allowed.
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Download ready'),
          content: Text(filename),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                // Web (including iPhone Safari Flutter web): use same-tab navigation
                if (kIsWeb) {
                  await launchUrl(uri, webOnlyWindowName: '_self');
                } else {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Download'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Downloading $filename...')));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final msg = 'Download failed: ${e.code} ${e.message ?? ''}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadSelectedZip(List<_UploadDoc> selectedDocs) async {
    final eligible = selectedDocs
        .where(
          (d) =>
              d.requestId.trim().isNotEmpty &&
              d.storagePath.trim().isNotEmpty &&
              d.data['deleted'] != true,
        )
        .toList();

    if (eligible.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least two files to zip.')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final res = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('getDropoffZipDownloadUrl')
          .call({
            'files': eligible
                .map((d) => {'requestId': d.requestId, 'fileId': d.id})
                .toList(),
          });

      final data = Map<String, dynamic>.from(res.data as Map);
      final url = (data['url'] ?? '').toString();
      final fileCount = (data['fileCount'] is num)
          ? (data['fileCount'] as num).toInt()
          : eligible.length;

      if (url.isEmpty) {
        throw Exception('Could not generate ZIP download link.');
      }

      final uri = Uri.parse(url);
      if (!mounted) return;

      if (kIsWeb) {
        await launchUrl(uri, webOnlyWindowName: '_self');
      } else {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloading $fileCount files as ZIP...')),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ZIP download failed: ${e.code} ${e.message ?? ''}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ZIP download failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showSecureShareDialog(List<_UploadDoc> selectedDocs) async {
    final eligible = selectedDocs
        .where(
          (d) =>
              d.requestId.trim().isNotEmpty &&
              d.storagePath.trim().isNotEmpty &&
              d.data['deleted'] != true,
        )
        .toList();

    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one file to share.')),
      );
      return;
    }

    final emails = eligible
        .map((d) => d.clientEmail.trim())
        .where((e) => e.isNotEmpty && e != '-' && e.contains('@'))
        .toSet();
    final names = eligible
        .map((d) => d.clientName.trim())
        .where((n) => n.isNotEmpty && n != '-')
        .toSet();

    final emailCtrl = TextEditingController(
      text: emails.length == 1 ? emails.first : '',
    );
    final nameCtrl = TextEditingController(
      text: names.length == 1 ? names.first : '',
    );
    final passwordCtrl = TextEditingController();
    final messageCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    bool sendEmail = emailCtrl.text.trim().isNotEmpty;
    int expirationDays = 7;
    bool submitting = false;

    Future<void> showCreatedDialog({
      required String url,
      required int fileCount,
      required bool emailed,
    }) async {
      final linkCtrl = TextEditingController(text: url);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Secure share created'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  emailed
                      ? 'The secure link was emailed and is ready to copy.'
                      : 'Copy this secure link and provide the password separately.',
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF475467),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: linkCtrl,
                  readOnly: true,
                  maxLines: 1,
                  decoration: const InputDecoration(
                    labelText: 'Secure link',
                    prefixIcon: Icon(Icons.link_outlined),
                  ),
                  onTap: () {
                    linkCtrl.selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: linkCtrl.text.length,
                    );
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  '$fileCount ${fileCount == 1 ? "file" : "files"} shared. Link expires in $expirationDays ${expirationDays == 1 ? "day" : "days"}.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF667085),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: url));
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Secure link copied.')),
                  );
                }
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy link'),
            ),
          ],
        ),
      );
      linkCtrl.dispose();
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: !submitting,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            Future<void> submit() async {
              if (!(formKey.currentState?.validate() ?? false)) return;

              setLocalState(() => submitting = true);
              setState(() => _busy = true);
              try {
                final res =
                    await FirebaseFunctions.instanceFor(
                      region: 'us-central1',
                    ).httpsCallable('createSecureFileShare').call({
                      'files': eligible
                          .map(
                            (d) => {'requestId': d.requestId, 'fileId': d.id},
                          )
                          .toList(),
                      'recipientEmail': emailCtrl.text.trim().toLowerCase(),
                      'recipientName': nameCtrl.text.trim(),
                      'password': passwordCtrl.text.trim(),
                      'message': messageCtrl.text.trim(),
                      'expirationDays': expirationDays,
                      'sendEmail': sendEmail,
                    });

                final data = Map<String, dynamic>.from(res.data as Map);
                final url = (data['url'] ?? '').toString();
                final fileCount = data['fileCount'] is num
                    ? (data['fileCount'] as num).toInt()
                    : eligible.length;
                final emailed = data['emailed'] == true;

                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                await showCreatedDialog(
                  url: url,
                  fileCount: fileCount,
                  emailed: emailed,
                );
              } on FirebaseFunctionsException catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Secure share failed: ${e.code} ${e.message ?? ''}',
                    ),
                  ),
                );
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('Secure share failed: $e')),
                );
              } finally {
                if (mounted) setState(() => _busy = false);
                if (ctx.mounted) setLocalState(() => submitting = false);
              }
            }

            Widget dayChip(int days) {
              final selected = expirationDays == days;
              return ChoiceChip(
                label: Text(days == 1 ? '1 day' : '$days days'),
                selected: selected,
                showCheckmark: false,
                selectedColor: const Color(0xFFEAF2FF),
                backgroundColor: const Color(0xFFF9FAFB),
                side: BorderSide(
                  color: selected
                      ? AppColors.brandBlue
                      : const Color(0xFFE4E7EC),
                ),
                labelStyle: TextStyle(
                  color: selected
                      ? AppColors.brandBlue
                      : const Color(0xFF667085),
                  fontWeight: FontWeight.w800,
                ),
                onSelected: submitting
                    ? null
                    : (_) => setLocalState(() => expirationDays = days),
              );
            }

            return AlertDialog(
              title: const Text('Create secure share'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${eligible.length} ${eligible.length == 1 ? "file" : "files"} selected',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF667085),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          enabled: !submitting,
                          decoration: const InputDecoration(
                            labelText: 'Client email',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                          validator: (v) {
                            final value = (v ?? '').trim();
                            if (sendEmail && !value.contains('@')) {
                              return 'Enter a valid email or turn off email sending.';
                            }
                            return null;
                          },
                          onChanged: (_) => setLocalState(() {}),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: nameCtrl,
                          enabled: !submitting,
                          decoration: const InputDecoration(
                            labelText: 'Client name',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: passwordCtrl,
                          obscureText: true,
                          enabled: !submitting,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            helperText:
                                'Share this password with the client separately.',
                            prefixIcon: Icon(Icons.key_outlined),
                          ),
                          validator: (v) {
                            if ((v ?? '').trim().length < 6) {
                              return 'Use at least 6 characters.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: messageCtrl,
                          enabled: !submitting,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Message',
                            prefixIcon: Icon(Icons.notes_outlined),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Expiration',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: const Color(0xFF344054),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [1, 7, 14, 30].map(dayChip).toList(),
                        ),
                        const SizedBox(height: 12),
                        CheckboxListTile(
                          value: sendEmail,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('Email secure link to client'),
                          subtitle: const Text(
                            'The password is not included in the email.',
                          ),
                          onChanged: submitting
                              ? null
                              : (v) =>
                                    setLocalState(() => sendEmail = v == true),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: submitting ? null : submit,
                  icon: submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_outline, size: 16),
                  label: const Text('Create secure share'),
                ),
              ],
            );
          },
        );
      },
    );

    emailCtrl.dispose();
    nameCtrl.dispose();
    passwordCtrl.dispose();
    messageCtrl.dispose();
  }

  Future<void> _logFileView({
    required _UploadDoc doc,
    required String surface, // 'details' or 'history'
  }) async {
    try {
      final requestId = (doc.data['requestId'] ?? '').toString().trim();
      if (requestId.isEmpty) return;

      await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('logFileActivity').call({
        'requestId': requestId,
        'fileId': doc.id,
        'action': 'view',
        'surface': surface,
      });
    } catch (_) {
      // Best-effort only: never block UI for logging
    }
  }

  Future<void> _showActivityHistoryDialog({required _UploadDoc doc}) async {
    if (_role != 'admin') return;
    await _logFileView(doc: doc, surface: 'history');
    final m = doc.data;
    final requestId = (m['requestId'] ?? '').toString().trim();

    // Query: events for this file (requires an index: fileId + occurredAt)
    final q = FirebaseFirestore.instance
        .collection('file_activity')
        .where('fileId', isEqualTo: doc.id)
        .where('requestId', isEqualTo: requestId)
        .orderBy('occurredAt', descending: true)
        .limit(50);

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Activity history'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 420),
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: q.snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Text(
                  snap.error.toString(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFB42318),
                    fontWeight: FontWeight.w700,
                  ),
                );
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return const Text(
                  'No activity has occurred since this file was uploaded.',
                  style: TextStyle(
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w600,
                  ),
                );
              }

              IconData iconFor(String a) {
                switch (a) {
                  case 'upload':
                    return Icons.file_upload_outlined;
                  case 'view':
                    return Icons.visibility_outlined;
                  case 'download':
                    return Icons.download_outlined;
                  default:
                    return Icons.info_outline;
                }
              }

              String labelFor(String a) {
                switch (a) {
                  case 'upload':
                    return 'Uploaded';
                  case 'view':
                    return 'Viewed';
                  case 'download':
                    return 'Downloaded';
                  default:
                    return a;
                }
              }

              String actorFor(Map<String, dynamic> e) {
                final type = (e['actorType'] ?? '').toString().trim();
                final name = (e['actorName'] ?? '').toString().trim();
                final email = (e['actorEmail'] ?? '').toString().trim();
                final who = name.isNotEmpty
                    ? name
                    : (email.isNotEmpty ? email : '-');
                if (type.isEmpty) return who;
                return '${type[0].toUpperCase()}${type.substring(1)} - $who';
              }

              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (c, i) {
                  final e = docs[i].data();
                  final action = (e['action'] ?? '').toString().trim();
                  final at = _tsToDate(e['occurredAt']);

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(iconFor(action), color: const Color(0xFF475467)),
                        const SizedBox(width: 12),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                labelFor(action),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                actorFor(e),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF667085),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                at == null ? '-' : _fmt(context, at),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF667085),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSelectedAdmin(List<_UploadDoc> selectedDocs) async {
    if (selectedDocs.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete selected files'),
        content: Text(
          'Delete ${selectedDocs.length} file(s)? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('deleteDropoffUploadsBatch');

      final payload = selectedDocs.map((d) {
        return {'docPath': d.docPath, 'storagePath': d.storagePath};
      }).toList();

      await callable.call({'items': payload});

      if (!mounted) return;
      setState(() {
        _selected.clear();
        _visibleCount = _pageSize;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selected files deleted.')));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: ${e.code} ${e.message ?? ''}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleSort(_SortField field) {
    setState(() {
      if (_sortField == field) {
        _sortAsc = !_sortAsc;
      } else {
        _sortField = field;
        _sortAsc = field != _SortField.date;
      }
      _visibleCount = _pageSize;
    });
  }

  void _applySearch(String value) {
    setState(() {
      _q = value.trim().toLowerCase();
      _visibleCount = _pageSize;
      _selected.clear();
    });
  }

  String _typeLabel(_TypeFilter value) {
    switch (value) {
      case _TypeFilter.all:
        return 'All';
      case _TypeFilter.pdf:
        return 'PDF';
      case _TypeFilter.office:
        return 'Office';
      case _TypeFilter.img:
        return 'Images';
      case _TypeFilter.other:
        return 'Other';
    }
  }

  String _dateLabel(_DateFilter value) {
    switch (value) {
      case _DateFilter.all:
        return 'Any date';
      case _DateFilter.last30:
        return 'Recent';
    }
  }

  bool _dateMatches(DateTime? when, _DateFilter filter) {
    if (filter == _DateFilter.all) return true;
    if (when == null) return false;

    final now = DateTime.now();
    DateTime start;

    switch (filter) {
      case _DateFilter.last30:
        start = now.subtract(const Duration(days: 30));
        break;
      case _DateFilter.all:
        return true;
    }
    return when.isAfter(start);
  }

  Widget _filterChip({
    required ThemeData theme,
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return ChoiceChip(
      label: Text('$label $count'),
      selected: selected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelStyle: theme.textTheme.labelSmall?.copyWith(
        color: selected ? AppColors.brandBlue : const Color(0xFF667085),
        fontWeight: FontWeight.w800,
      ),
      selectedColor: const Color(0xFFEAF2FF),
      backgroundColor: const Color(0xFFF9FAFB),
      side: BorderSide(
        color: selected ? AppColors.brandBlue : const Color(0xFFE4E7EC),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      onSelected: (_) => onSelected(),
    );
  }

  Widget _filterBar(ThemeData theme, List<_UploadDoc> rows) {
    int typeCount(_TypeFilter type) {
      if (type == _TypeFilter.all) return rows.length;
      return rows
          .where((r) => _inferTypeFilter(r.originalName, r.contentType) == type)
          .length;
    }

    int dateCount(_DateFilter date) =>
        rows.where((r) => _dateMatches(r.when, date)).length;

    Widget typeChip(_TypeFilter type) {
      return _filterChip(
        theme: theme,
        label: _typeLabel(type),
        count: typeCount(type),
        selected: _typeFilter == type,
        onSelected: () {
          setState(() {
            _typeFilter = type;
            _visibleCount = _pageSize;
            _selected.clear();
          });
        },
      );
    }

    Widget dateChip(_DateFilter date) {
      final selected = _dateFilter == date;
      return _filterChip(
        theme: theme,
        label: _dateLabel(date),
        count: dateCount(date),
        selected: selected,
        onSelected: () {
          setState(() {
            _dateFilter = selected ? _DateFilter.all : date;
            _visibleCount = _pageSize;
            _selected.clear();
          });
        },
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        typeChip(_TypeFilter.all),
        typeChip(_TypeFilter.pdf),
        typeChip(_TypeFilter.office),
        typeChip(_TypeFilter.img),
        typeChip(_TypeFilter.other),
        const SizedBox(width: 6),
        dateChip(_DateFilter.last30),
      ],
    );
  }

  String _formatSizeBytes(int bytes) {
    if (bytes <= 0) return '-';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  DateTime? _tsToDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return null;
  }

  Future<void> _showUploadDetailsDialog({required _UploadDoc doc}) async {
    await _logFileView(doc: doc, surface: 'details');
    final m = doc.data;

    final fileName = (m['originalName'] ?? doc.originalName).toString().trim();
    final contentType = (m['contentType'] ?? doc.contentType).toString().trim();
    final sizeBytes = (m['sizeBytes'] is num)
        ? (m['sizeBytes'] as num).toInt()
        : doc.sizeBytes;

    final uploadedAt = _tsToDate(m['createdAt']) ?? doc.when;

    final requestedBy = (m['requestCreatedByName'] ?? doc.requestedBy)
        .toString()
        .trim();
    final requestedByEmail = (m['requestCreatedByEmail'] ?? '')
        .toString()
        .trim();

    final requestId = (m['requestId'] ?? '').toString().trim();

    String activityLabel(String action) {
      switch (action.toLowerCase().trim()) {
        case 'upload':
          return 'Uploaded';
        case 'view':
          return 'Viewed';
        case 'download':
          return 'Downloaded';
        case 'delete':
          return 'Deleted';
        default:
          return action.trim().isEmpty ? '-' : action.trim();
      }
    }

    if (!mounted) return;

    final meta = resolveFileMeta(fileName: fileName, contentType: contentType);
    final storagePath = (m['storagePath'] ?? doc.storagePath).toString().trim();
    final fileType = meta.tooltip.replaceAll(
      RegExp(r'\s+file$', caseSensitive: false),
      '',
    );

    Query<Map<String, dynamic>> auditQuery = FirebaseFirestore.instance
        .collection('file_activity')
        .where('fileId', isEqualTo: doc.id)
        .orderBy('occurredAt', descending: true)
        .limit(8);

    if (requestId.isNotEmpty) {
      auditQuery = FirebaseFirestore.instance
          .collection('file_activity')
          .where('fileId', isEqualTo: doc.id)
          .where('requestId', isEqualTo: requestId)
          .orderBy('occurredAt', descending: true)
          .limit(8);
    }

    String actorFor(Map<String, dynamic> e) {
      final type = (e['actorType'] ?? '').toString().trim();
      final name = (e['actorName'] ?? '').toString().trim();
      final email = (e['actorEmail'] ?? '').toString().trim();
      final who = name.isNotEmpty ? name : (email.isNotEmpty ? email : '-');
      if (type.isEmpty) return who;
      return '${type[0].toUpperCase()}${type.substring(1)} - $who';
    }

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        title: Row(
          children: [
            _FileDetailsIconTile(
              icon: meta.icon,
              color: meta.color,
              iconColor: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$fileType - ${_formatSizeBytes(sizeBytes)}',
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 620),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FileDetailsCard(
                  title: 'Overview',
                  icon: Icons.info_outline,
                  children: [
                    _FileDetailRow(
                      label: 'Created',
                      value: uploadedAt == null
                          ? '-'
                          : _fmt(context, uploadedAt),
                    ),
                    _FileDetailRow(
                      label: 'Creator',
                      value: requestedBy.isNotEmpty ? requestedBy : '-',
                      secondary: requestedByEmail,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _FileDetailsCard(
                  title: 'Audit activity',
                  icon: Icons.manage_search_outlined,
                  children: [
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: auditQuery.snapshots(),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return const _FileDetailsEmptyState(
                            text: 'Activity is not available yet.',
                          );
                        }
                        if (!snap.hasData) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: LinearProgressIndicator(minHeight: 2),
                          );
                        }

                        final events = snap.data!.docs;
                        if (events.isEmpty) {
                          return const _FileDetailsEmptyState(
                            text: 'No tracked activity for this file yet.',
                          );
                        }

                        return Column(
                          children: events.map((event) {
                            final e = event.data();
                            final action = activityLabel(
                              (e['action'] ?? '').toString(),
                            );
                            final at = _tsToDate(e['occurredAt']);
                            final surface = (e['surface'] ?? '').toString();
                            return _FileAuditEventRow(
                              action: action,
                              actor: actorFor(e),
                              when: at == null ? '-' : _fmt(context, at),
                              surface: surface,
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: storagePath.isEmpty
                ? null
                : () {
                    Navigator.pop(context);
                    _downloadFile(
                      isAdmin: _role == 'admin',
                      storagePath: storagePath,
                      filename: fileName,
                      contentType: contentType,
                      requestId: requestId,
                      fileId: doc.id,
                      showReadyDialog: false,
                    );
                  },
            icon: const Icon(Icons.download_outlined, size: 16),
            label: const Text('Download'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Content-only loading state (AppShell provides chrome).
    if (_loadingRole) {
      return const Center(child: CircularProgressIndicator());
    }

    final isAdmin = _role == 'admin';
    final isMobile = MediaQuery.of(context).size.width < 700;

    return PageScaffold(
      title: 'File Box',
      subtitle: isAdmin
          ? 'All uploads across all document requests.'
          : 'Uploads from associate-created document requests.',
      hideHeader: false,
      wrapInCard: false,
      scrollable: false,
      maxContentWidth: 1400,
      commandBar: FluentCommandBar(
        actions: [
          FluentCommandAction(
            icon: Icons.upload_file_outlined,
            label: 'Upload files',
            onPressed: _busy ? null : _chooseAndUploadToFileBox,
            accent: true,
          ),
        ],
        overflowActions: const [],
      ),

      // Give PageScaffold a flex child so it gets height.
      child: Expanded(
        child: DropTarget(
          onDragEntered: (_) => setState(() => _draggingUploads = true),
          onDragExited: (_) => setState(() => _draggingUploads = false),
          onDragDone: _busy ? null : _handleDroppedUploads,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.05),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isMobile ? 10 : 16,
                    isMobile ? 10 : 14,
                    isMobile ? 10 : 16,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_uploadingNames.isNotEmpty) ...[
                        _FileBoxUploadStatus(names: _uploadingNames),
                        const SizedBox(height: 12),
                      ] else if (_pendingUploads.isNotEmpty) ...[
                        _FileBoxUploadQueue(
                          files: _pendingUploads,
                          formatSize: _formatSizeBytes,
                          onUpload: _busy
                              ? null
                              : () => _uploadToFileBox(
                                  List<_FileBoxPendingUpload>.from(
                                    _pendingUploads,
                                  ),
                                ),
                          onClear: _busy
                              ? null
                              : () => setState(() => _pendingUploads.clear()),
                          onRemove: _busy
                              ? null
                              : (file) => setState(
                                  () => _pendingUploads.removeWhere(
                                    (item) => item.key == file.key,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Container(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9FAFB),
                          border: Border.all(color: const Color(0xFFE4E7EC)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: TextField(
                          controller: _searchCtrl,
                          textInputAction: TextInputAction.search,
                          onChanged: _applySearch,
                          onSubmitted: _applySearch,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF344054),
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: Colors.white,
                            prefixIcon: const Icon(Icons.search, size: 18),
                            hintText:
                                'Search files, clients, businesses, or request IDs',
                            hintStyle: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF667085),
                              fontWeight: FontWeight.w600,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color(0xFFE4E7EC),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color(0xFFE4E7EC),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color(0xFFD0D5DD),
                              ),
                            ),
                            suffixIcon: _q.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear search',
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      _applySearch('');
                                    },
                                  ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // ===== Table =====
                      Expanded(
                        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: _uploadsStream,
                          builder: (context, snap) {
                            if (snap.hasError) {
                              return const Center(
                                child: Text('Failed to load uploads'),
                              );
                            }
                            if (!snap.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            final q = _q.trim().toLowerCase();
                            final docs = snap.data!.docs;

                            final all = docs.map((d) {
                              final m = d.data();
                              final name = _s(m['originalName']);
                              final contentType = _s(m['contentType']);
                              final storagePath = _s(m['storagePath']);

                              final uploadedBy = m['uploadedBy'];
                              final clientName = (uploadedBy is Map)
                                  ? _s(uploadedBy['name'])
                                  : '';
                              final fallbackClient =
                                  _s(m['clientName']).isNotEmpty
                                  ? _s(m['clientName'])
                                  : '';

                              final createdAt = _asDate(m['createdAt']);
                              final sizeBytes = (m['sizeBytes'] is num)
                                  ? (m['sizeBytes'] as num).toInt()
                                  : 0;

                              final requestedBy = _s(m['requestCreatedByName']);
                              final companyName = _s(m['requestBusinessName']);
                              final clientEmail = _s(m['requestClientEmail']);
                              final requestId = _s(m['requestId']);
                              final expirationKnown =
                                  m.containsKey('requestExpiresAt') ||
                                  m.containsKey('expiresAt');
                              final expiresAt = _asDate(
                                m['requestExpiresAt'] ?? m['expiresAt'],
                              );
                              final lastActivityAt = _asDate(
                                m['lastActivityAt'],
                              );
                              final lastActivityAction = _s(
                                m['lastActivityAction'],
                              );
                              final lastActivityActorName = _s(
                                m['lastActivityActorName'],
                              );

                              return _UploadDoc(
                                id: d.id,
                                docPath: d.reference.path,
                                originalName: name,
                                contentType: contentType,
                                storagePath: storagePath,
                                clientName: clientName.isNotEmpty
                                    ? clientName
                                    : (fallbackClient.isNotEmpty
                                          ? fallbackClient
                                          : '-'),
                                requestedBy: requestedBy.isNotEmpty
                                    ? requestedBy
                                    : '-',
                                companyName: companyName.isNotEmpty
                                    ? companyName
                                    : '-',
                                clientEmail: clientEmail.isNotEmpty
                                    ? clientEmail
                                    : '-',
                                when: createdAt,
                                expirationKnown: expirationKnown,
                                expiresAt: expiresAt,
                                lastActivityAt: lastActivityAt,
                                lastActivityAction: lastActivityAction,
                                lastActivityActorName: lastActivityActorName,
                                sizeBytes: sizeBytes,
                                requestId: requestId,
                                data: m,
                              );
                            }).toList();

                            final searchTokens = q
                                .split(RegExp(r'\s+'))
                                .where((part) => part.trim().isNotEmpty)
                                .toList();

                            final filtered = all.where((r) {
                              if (r.data['deleted'] == true) return false;

                              if (searchTokens.isNotEmpty) {
                                final meta = resolveFileMeta(
                                  fileName: r.originalName,
                                  contentType: r.contentType,
                                );
                                final hay =
                                    ('${r.originalName} ${r.storagePath} ${r.clientName} '
                                            '${r.requestedBy} ${r.companyName} ${r.clientEmail} '
                                            '${r.requestId} ${r.contentType} ${meta.badge} ${meta.tooltip}')
                                        .toLowerCase();
                                if (!searchTokens.every(hay.contains))
                                  return false;
                              }

                              if (_typeFilter != _TypeFilter.all) {
                                final inferred = _inferTypeFilter(
                                  r.originalName,
                                  r.contentType,
                                );
                                if (inferred != _typeFilter) return false;
                              }

                              if (!_passesDateFilter(r.when)) return false;
                              return true;
                            }).toList();

                            filtered.sort((a, b) {
                              int res;
                              switch (_sortField) {
                                case _SortField.name:
                                  res = a.originalName.toLowerCase().compareTo(
                                    b.originalName.toLowerCase(),
                                  );
                                  break;
                                case _SortField.client:
                                  res = a.clientName.toLowerCase().compareTo(
                                    b.clientName.toLowerCase(),
                                  );
                                  break;
                                case _SortField.size:
                                  res = a.sizeBytes.compareTo(b.sizeBytes);
                                  break;
                                case _SortField.date:
                                  res =
                                      (a.lastActivityAt ??
                                              a.when ??
                                              DateTime(0))
                                          .compareTo(
                                            b.lastActivityAt ??
                                                b.when ??
                                                DateTime(0),
                                          );
                                  break;
                                case _SortField.expires:
                                  res = (a.expiresAt ?? DateTime(9999))
                                      .compareTo(b.expiresAt ?? DateTime(9999));
                                  break;
                                case _SortField.creator:
                                  res = a.requestedBy.toLowerCase().compareTo(
                                    b.requestedBy.toLowerCase(),
                                  );
                                  break;
                              }
                              return _sortAsc ? res : -res;
                            });

                            final visible = filtered
                                .take(_visibleCount)
                                .toList();
                            final visibleIds = visible.map((e) => e.id).toSet();
                            final allVisibleSelected =
                                visible.isNotEmpty &&
                                _selected.containsAll(visibleIds);

                            _selectedDocsCache = visible
                                .where((e) => _selected.contains(e.id))
                                .toList();

                            final selectedActionIsSingleDownload =
                                _selectedDocsCache.length == 1;
                            final selectedActionIcon =
                                selectedActionIsSingleDownload
                                ? Icons.download_outlined
                                : Icons.archive_outlined;
                            final selectedActionLabel =
                                selectedActionIsSingleDownload
                                ? 'Download'
                                : 'Download ZIP';

                            return Column(
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Color(0xFFE4E7EC),
                                      ),
                                    ),
                                  ),
                                  child: _filterBar(theme, all),
                                ),
                                // ===== Table header =====
                                if (!isMobile || _selected.isNotEmpty)
                                  Container(
                                    height: isMobile && _selected.isNotEmpty
                                        ? 92
                                        : 42,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isMobile ? 6 : 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF9FAFB),
                                      border: Border(
                                        bottom: BorderSide(
                                          color: Colors.black.withValues(
                                            alpha: 0.06,
                                          ),
                                        ),
                                      ),
                                    ),
                                    child: _selected.isNotEmpty
                                        ? _FileBoxSelectionToolbar(
                                            selectedCount: _selected.length,
                                            isAdmin: isAdmin,
                                            busy: _busy,
                                            canAct:
                                                _selectedDocsCache.isNotEmpty,
                                            downloadIcon: selectedActionIcon,
                                            downloadLabel: selectedActionLabel,
                                            onClear: () => setState(
                                              () => _selected.clear(),
                                            ),
                                            onSecureShare: () =>
                                                _showSecureShareDialog(
                                                  _selectedDocsCache,
                                                ),
                                            onDownload: () {
                                              if (selectedActionIsSingleDownload) {
                                                final doc =
                                                    _selectedDocsCache.single;
                                                _downloadFile(
                                                  isAdmin: isAdmin,
                                                  storagePath: doc.storagePath,
                                                  filename: doc.originalName,
                                                  contentType: doc.contentType,
                                                  requestId: doc.requestId,
                                                  fileId: doc.id,
                                                  showReadyDialog: false,
                                                );
                                                return;
                                              }

                                              _downloadSelectedZip(
                                                _selectedDocsCache,
                                              );
                                            },
                                            onDelete: () =>
                                                _deleteSelectedAdmin(
                                                  _selectedDocsCache,
                                                ),
                                            allVisibleSelected:
                                                allVisibleSelected,
                                            onToggleAll: (v) {
                                              setState(() {
                                                if (allVisibleSelected) {
                                                  _selected.removeAll(
                                                    visibleIds,
                                                  );
                                                } else {
                                                  _selected.addAll(visibleIds);
                                                }
                                              });
                                            },
                                          )
                                        : Row(
                                            children: [
                                              Checkbox(
                                                value: allVisibleSelected,
                                                onChanged: _busy
                                                    ? null
                                                    : (v) {
                                                        setState(() {
                                                          if (v == true) {
                                                            _selected.addAll(
                                                              visibleIds,
                                                            );
                                                          } else {
                                                            _selected.removeAll(
                                                              visibleIds,
                                                            );
                                                          }
                                                        });
                                                      },
                                              ),
                                              const SizedBox(width: 4),

                                              // File column header.
                                              Expanded(
                                                child: InkWell(
                                                  onTap: () => _toggleSort(
                                                    _SortField.name,
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      const Text(
                                                        'Name',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: Color(
                                                            0xFF475467,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      _SortIndicator(
                                                        active:
                                                            _sortField ==
                                                            _SortField.name,
                                                        asc: _sortAsc,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),

                                              if (!isMobile)
                                                SizedBox(
                                                  width: 90,
                                                  child: InkWell(
                                                    onTap: () => _toggleSort(
                                                      _SortField.size,
                                                    ),
                                                    child: Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment.end,
                                                      children: [
                                                        const Text(
                                                          'Size',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color: Color(
                                                              0xFF475467,
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 6,
                                                        ),
                                                        _SortIndicator(
                                                          active:
                                                              _sortField ==
                                                              _SortField.size,
                                                          asc: _sortAsc,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),

                                              if (!isMobile)
                                                SizedBox(
                                                  width: 160,
                                                  child: InkWell(
                                                    onTap: () => _toggleSort(
                                                      _SortField.date,
                                                    ),
                                                    child: Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment.end,
                                                      children: [
                                                        const Text(
                                                          'Date uploaded',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color: Color(
                                                              0xFF475467,
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 6,
                                                        ),
                                                        _SortIndicator(
                                                          active:
                                                              _sortField ==
                                                              _SortField.date,
                                                          asc: _sortAsc,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),

                                              if (!isMobile)
                                                SizedBox(
                                                  width: 130,
                                                  child: InkWell(
                                                    onTap: () => _toggleSort(
                                                      _SortField.expires,
                                                    ),
                                                    child: Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment.end,
                                                      children: [
                                                        const Text(
                                                          'Expires',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color: Color(
                                                              0xFF475467,
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 6,
                                                        ),
                                                        _SortIndicator(
                                                          active:
                                                              _sortField ==
                                                              _SortField
                                                                  .expires,
                                                          asc: _sortAsc,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),

                                              if (!isMobile)
                                                SizedBox(
                                                  width: 170,
                                                  child: InkWell(
                                                    onTap: () => _toggleSort(
                                                      _SortField.creator,
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        const Text(
                                                          'Creator',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color: Color(
                                                              0xFF475467,
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 6,
                                                        ),
                                                        _SortIndicator(
                                                          active:
                                                              _sortField ==
                                                              _SortField
                                                                  .creator,
                                                          asc: _sortAsc,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),

                                              const SizedBox(width: 8),
                                              SizedBox(
                                                width: 78,
                                                child: Text(
                                                  'Actions',
                                                  textAlign: TextAlign.right,
                                                  style: theme
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: const Color(
                                                          0xFF475467,
                                                        ),
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),

                                // ===== Rows =====
                                Expanded(
                                  child: visible.isEmpty
                                      ? Center(
                                          child: Text(
                                            q.isEmpty
                                                ? 'No uploads found.'
                                                : 'No files match your search.',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: const Color(
                                                    0xFF667085,
                                                  ),
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        )
                                      : ListView.separated(
                                          itemCount: visible.length,
                                          separatorBuilder: (_, __) => Divider(
                                            height: 1,
                                            color: Colors.black.withValues(
                                              alpha: 0.08,
                                            ),
                                          ),
                                          itemBuilder: (c, i) {
                                            final row = visible[i];
                                            return _UploadRowEnhanced(
                                              id: row.id,
                                              docPath: row.docPath,
                                              data: row.data,
                                              selected: _selected.contains(
                                                row.id,
                                              ),
                                              isMobile: isMobile,
                                              isAdmin: isAdmin,
                                              clientName: row.clientName,
                                              requestedBy: row.requestedBy,
                                              companyName: row.companyName,
                                              clientEmail: row.clientEmail,
                                              expirationKnown:
                                                  row.expirationKnown,
                                              expiresAt: row.expiresAt,
                                              lastActivityAt:
                                                  row.lastActivityAt,
                                              lastActivityAction:
                                                  row.lastActivityAction,
                                              lastActivityActorName:
                                                  row.lastActivityActorName,
                                              onShowDetails: () =>
                                                  _showUploadDetailsDialog(
                                                    doc: row,
                                                  ),
                                              onShowHistory: () =>
                                                  _showActivityHistoryDialog(
                                                    doc: row,
                                                  ),
                                              formatWhen: (dt) =>
                                                  _fmt(context, dt),
                                              onSelect: (v) {
                                                setState(() {
                                                  if (v) {
                                                    _selected.add(row.id);
                                                  } else {
                                                    _selected.remove(row.id);
                                                  }
                                                });
                                              },
                                              busy: _busy,
                                              onDownload: (path, name, type) =>
                                                  _downloadFile(
                                                    isAdmin: isAdmin,
                                                    storagePath: path,
                                                    filename: name,
                                                    contentType: type,
                                                    requestId:
                                                        (row.data['requestId'] ??
                                                                '')
                                                            .toString(),
                                                    fileId: row.id,
                                                  ),
                                            );
                                          },
                                        ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_draggingUploads)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.brandBlue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.brandBlue,
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 18,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFD0D5DD)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x1A000000),
                                blurRadius: 18,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.cloud_upload_outlined,
                                color: AppColors.brandBlue,
                                size: 34,
                              ),
                              SizedBox(height: 10),
                              Text(
                                'Drop files to prepare upload',
                                style: TextStyle(
                                  color: Color(0xFF101828),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Review the queue before adding files to File Box.',
                                style: TextStyle(
                                  color: Color(0xFF667085),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small, consistent label/value row for dialogs
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: const Color(0xFF667085),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF101828),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileBoxUploadStatus extends StatelessWidget {
  const _FileBoxUploadStatus({required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final label = names.length == 1
        ? 'Uploading ${names.first}'
        : 'Uploading ${names.length} files';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF253858),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'File Box',
            style: TextStyle(
              color: AppColors.brandBlue,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _FileBoxUploadQueue extends StatelessWidget {
  const _FileBoxUploadQueue({
    required this.files,
    required this.formatSize,
    required this.onUpload,
    required this.onClear,
    required this.onRemove,
  });

  final List<_FileBoxPendingUpload> files;
  final String Function(int bytes) formatSize;
  final VoidCallback? onUpload;
  final VoidCallback? onClear;
  final ValueChanged<_FileBoxPendingUpload>? onRemove;

  @override
  Widget build(BuildContext context) {
    final preview = files.take(4).toList();
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFD0D5DD)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.upload_file_outlined,
                  size: 18,
                  color: AppColors.brandBlue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${files.length} ready to upload to File Box',
                    style: const TextStyle(
                      color: Color(0xFF253858),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                TextButton(onPressed: onClear, child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onUpload,
                  icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                  label: Text(
                    files.length == 1
                        ? 'Upload file'
                        : 'Upload ${files.length} files',
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE4E7EC)),
          ...preview.map((file) {
            final meta = resolveFileMeta(
              fileName: file.name,
              contentType: file.contentType,
            );
            return Column(
              children: [
                ListTile(
                  dense: true,
                  leading: _FileKindIcon(meta: meta),
                  title: Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${formatSize(file.sizeBytes)} • Ready to upload',
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: 'Remove from upload queue',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: onRemove == null ? null : () => onRemove!(file),
                  ),
                ),
                if (file != preview.last)
                  const Divider(height: 1, color: Color(0xFFE4E7EC)),
              ],
            );
          }),
          if (files.length > preview.length)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '+${files.length - preview.length} more file(s) queued',
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FileKindIcon extends StatelessWidget {
  const _FileKindIcon({required this.meta});

  final FileKindMeta meta;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      width: 30,
      decoration: BoxDecoration(
        color: meta.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: meta.color.withValues(alpha: 0.22)),
      ),
      alignment: Alignment.center,
      child: Icon(meta.icon, size: 17, color: meta.color),
    );
  }
}

class _DuplicateNotice extends StatelessWidget {
  const _DuplicateNotice({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAEB),
        border: Border.all(color: const Color(0xFFFEDF89)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFFB54708)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF7A2E0E),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

class _FileDetailsIconTile extends StatelessWidget {
  const _FileDetailsIconTile({
    required this.icon,
    required this.color,
    required this.iconColor,
  });

  final IconData icon;
  final Color color;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      width: 32,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 18, color: iconColor),
    );
  }
}

class _FileDetailsCard extends StatelessWidget {
  const _FileDetailsCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFD),
        border: Border.all(color: const Color(0xFFE4E7EC)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF6F9FF),
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
              border: Border(
                bottom: BorderSide(color: Color(0xFFE4E7EC), width: 1),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 17, color: AppColors.brandBlue),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF253858),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _FileDetailRow extends StatelessWidget {
  const _FileDetailRow({
    required this.label,
    required this.value,
    this.secondary = '',
  });

  final String label;
  final String value;
  final String secondary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF667085),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value.isEmpty ? '-' : value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (secondary.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    secondary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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

class _FileAuditEventRow extends StatelessWidget {
  const _FileAuditEventRow({
    required this.action,
    required this.actor,
    required this.when,
    required this.surface,
  });

  final String action;
  final String actor;
  final String when;
  final String surface;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: const Color(0xFFD6E8FF)),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.timeline_outlined,
              color: AppColors.brandBlue,
              size: 15,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (actor.isNotEmpty) actor,
                    if (surface.isNotEmpty) surface,
                  ].join(' - '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            when,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FileDetailsEmptyState extends StatelessWidget {
  const _FileDetailsEmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF667085),
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FileBoxSelectionToolbar extends StatelessWidget {
  const _FileBoxSelectionToolbar({
    required this.selectedCount,
    required this.isAdmin,
    required this.busy,
    required this.canAct,
    required this.downloadIcon,
    required this.downloadLabel,
    required this.allVisibleSelected,
    required this.onToggleAll,
    required this.onClear,
    required this.onSecureShare,
    required this.onDownload,
    required this.onDelete,
  });

  final int selectedCount;
  final bool isAdmin;
  final bool busy;
  final bool canAct;
  final IconData downloadIcon;
  final String downloadLabel;
  final bool allVisibleSelected;
  final ValueChanged<bool?> onToggleAll;
  final VoidCallback onClear;
  final VoidCallback onSecureShare;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final disabled = busy || !canAct;
    final deleteLabel = selectedCount > 1 ? 'Delete all' : 'Delete';

    Widget toolbarRow({required bool compact}) {
      return Row(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Checkbox(
            value: allVisibleSelected ? true : null,
            tristate: true,
            onChanged: busy ? null : onToggleAll,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 6),
          Text(
            '$selectedCount selected',
            style: const TextStyle(
              color: Color(0xFF344054),
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: busy ? null : onClear,
            child: const Text('Clear'),
          ),
          if (!compact) const Spacer() else const SizedBox(width: 8),
          SizedBox(
            height: 32,
            child: FilledButton.icon(
              onPressed: disabled ? null : onSecureShare,
              icon: const Icon(Icons.lock_outline, size: 16),
              label: const Text('Send files'),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 32,
            child: OutlinedButton.icon(
              onPressed: disabled ? null : onDownload,
              icon: Icon(downloadIcon, size: 16),
              label: Text(downloadLabel),
            ),
          ),
          if (isAdmin) ...[
            const SizedBox(width: 8),
            SizedBox(
              height: 32,
              child: TextButton.icon(
                onPressed: disabled ? null : onDelete,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: Text(deleteLabel),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFB42318),
                ),
              ),
            ),
          ],
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Checkbox(
                    value: allVisibleSelected ? true : null,
                    tristate: true,
                    onChanged: busy ? null : onToggleAll,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$selectedCount selected',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF344054),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: busy ? null : onClear,
                    child: const Text('Clear'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 34,
                      child: FilledButton.icon(
                        onPressed: disabled ? null : onSecureShare,
                        icon: const Icon(Icons.lock_outline, size: 15),
                        label: const FittedBox(child: Text('Send')),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 34,
                      child: OutlinedButton.icon(
                        onPressed: disabled ? null : onDownload,
                        icon: Icon(downloadIcon, size: 15),
                        label: FittedBox(child: Text(downloadLabel)),
                      ),
                    ),
                  ),
                  if (isAdmin) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 34,
                        child: TextButton.icon(
                          onPressed: disabled ? null : onDelete,
                          icon: const Icon(Icons.delete_outline, size: 15),
                          label: FittedBox(child: Text(deleteLabel)),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFB42318),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          );
        }

        return toolbarRow(compact: false);
      },
    );
  }
}

/// Small sort chevron indicator (enterprise)
class _SortIndicator extends StatelessWidget {
  final bool active;
  final bool asc;

  const _SortIndicator({required this.active, required this.asc});

  @override
  Widget build(BuildContext context) {
    if (!active) {
      return const Icon(Icons.unfold_more, size: 16, color: Color(0xFF98A2B3));
    }
    return Icon(
      asc ? Icons.expand_less : Icons.expand_more,
      size: 16,
      color: const Color(0xFF475467),
    );
  }
}

class _UploadDoc {
  final String id;
  final String docPath;
  final String originalName;
  final String contentType;
  final String storagePath;
  final String clientName;

  final String requestedBy;
  final String companyName;
  final String clientEmail;

  final DateTime? when;
  final bool expirationKnown;
  final DateTime? expiresAt;
  final DateTime? lastActivityAt;
  final String lastActivityAction;
  final String lastActivityActorName;
  final int sizeBytes;
  final String requestId;
  final Map<String, dynamic> data;

  _UploadDoc({
    required this.id,
    required this.docPath,
    required this.originalName,
    required this.contentType,
    required this.storagePath,
    required this.clientName,
    required this.requestedBy,
    required this.companyName,
    required this.clientEmail,
    required this.when,
    required this.expirationKnown,
    required this.expiresAt,
    required this.lastActivityAt,
    required this.lastActivityAction,
    required this.lastActivityActorName,
    required this.sizeBytes,
    required this.requestId,
    required this.data,
  });
}

class _FileKindIconTile extends StatelessWidget {
  const _FileKindIconTile({required this.meta});

  final FileKindMeta meta;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      width: 28,
      decoration: BoxDecoration(
        color: meta.color,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      alignment: Alignment.center,
      child: Icon(meta.icon, size: 16, color: Colors.white),
    );
  }
}

/// ============================
/// ROW (ENHANCED + SELECT + CLIENT NAME)
/// ============================
class _UploadRowEnhanced extends StatelessWidget {
  final String id;
  final String docPath;
  final Map<String, dynamic> data;
  final bool selected;
  final bool isMobile;
  final bool busy;
  final bool isAdmin;
  final String clientName;
  final String Function(DateTime dt) formatWhen;
  final String requestedBy;
  final String companyName;
  final String clientEmail;
  final bool expirationKnown;
  final DateTime? expiresAt;
  final DateTime? lastActivityAt;
  final String lastActivityAction;
  final String lastActivityActorName;
  final ValueChanged<bool> onSelect;
  final void Function(String storagePath, String filename, String? contentType)
  onDownload;
  final VoidCallback onShowDetails;
  final VoidCallback onShowHistory;

  const _UploadRowEnhanced({
    required this.id,
    required this.docPath,
    required this.data,
    required this.selected,
    required this.isMobile,
    required this.busy,
    required this.clientName,
    required this.formatWhen,
    required this.onSelect,
    required this.requestedBy,
    required this.companyName,
    required this.clientEmail,
    required this.expirationKnown,
    required this.expiresAt,
    required this.lastActivityAt,
    required this.lastActivityAction,
    required this.lastActivityActorName,
    required this.onDownload,
    required this.onShowDetails,
    required this.onShowHistory,
    required this.isAdmin,
  });

  static const bool _showImagePreview = false; // Compact file box.

  String _s(dynamic v) => (v ?? '').toString().trim();

  String _formatSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _activityLabel(String action) {
    switch (action.toLowerCase().trim()) {
      case 'upload':
        return 'Uploaded';
      case 'view':
        return 'Viewed';
      case 'download':
        return 'Downloaded';
      case 'delete':
        return 'Deleted';
      default:
        return action.trim().isEmpty ? 'No activity' : action.trim();
    }
  }

  String _fileTypeLabel(String fileName, String contentType) {
    final kind = detectFileKind(fileName: fileName, contentType: contentType);
    switch (kind) {
      case FileKind.pdf:
        return 'PDF';
      case FileKind.word:
        return 'Word';
      case FileKind.excel:
        return 'Excel';
      case FileKind.powerpoint:
        return 'PowerPoint';
      case FileKind.accounting:
        return 'Accounting';
      case FileKind.image:
        return 'Image';
      case FileKind.text:
        return 'Text';
      case FileKind.archive:
        return 'Archive';
      case FileKind.video:
        return 'Video';
      case FileKind.audio:
        return 'Audio';
      case FileKind.code:
        return 'Code';
      case FileKind.data:
        return 'Data';
      case FileKind.email:
        return 'Email';
      case FileKind.cad:
        return 'CAD';
      case FileKind.threeD:
        return '3D';
      case FileKind.link:
        return 'Link';
      case FileKind.executable:
        return 'Executable';
      case FileKind.unknown:
        return 'File';
    }
  }

  String? _notableActivityText() {
    final action = lastActivityAction.toLowerCase().trim();
    if (action.isEmpty || action == 'upload') return null;

    final label = _activityLabel(action);
    final at = lastActivityAt;
    final when = at == null ? '' : formatWhen(at);
    return when.isEmpty ? label : '$label - $when';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final name = _s(data['originalName']).isEmpty
        ? 'Untitled'
        : _s(data['originalName']);
    final isDeleted = data['deleted'] == true;
    final contentType = _s(data['contentType']);
    final storagePath = _s(data['storagePath']);
    final sizeBytes = (data['sizeBytes'] is num)
        ? (data['sizeBytes'] as num).toInt()
        : 0;

    final createdAt = data['createdAt'];

    DateTime? when;
    if (createdAt is Timestamp) when = createdAt.toDate();

    final meta = resolveFileMeta(fileName: name, contentType: contentType);
    final fileTypeLabel = _fileTypeLabel(name, contentType);
    final notableActivity = _notableActivityText();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        overlayColor: MaterialStateProperty.resolveWith<Color?>((states) {
          if (states.contains(MaterialState.pressed)) {
            return const Color(0xFFE2E8F0);
          }
          if (states.contains(MaterialState.hovered)) {
            return const Color(0xFFF1F5F9);
          }
          return null;
        }),
        onTap: busy ? null : onShowDetails,
        child: SizedBox(
          height: isMobile ? 68 : 58,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              isMobile ? 10 : 16,
              isMobile ? 6 : 12,
              isMobile ? 10 : 16,
              isMobile ? 6 : 12,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: isMobile ? 34 : 36,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Checkbox(
                      value: selected,
                      onChanged: busy ? null : (v) => onSelect(v ?? false),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                Tooltip(
                  message: meta.tooltip,
                  child: _FileKindIconTile(meta: meta),
                ),
                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isMobile)
                        Text(
                          isDeleted ? '$name (Deleted)' : name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.12,
                            color: isDeleted
                                ? const Color(0xFFB42318)
                                : const Color(0xFF101828),
                            decoration: isDeleted
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        )
                      else
                        SelectableText(
                          isDeleted ? '$name (Deleted)' : name,
                          maxLines: 1,
                          onTap: busy ? null : onShowDetails,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: isDeleted
                                ? const Color(0xFFB42318)
                                : const Color(0xFF101828),
                            decoration: isDeleted
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      if (!isMobile) const SizedBox(height: 2),
                      if (isMobile)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$fileTypeLabel - ${_formatSize(sizeBytes)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: const Color(0xFF667085),
                                fontWeight: FontWeight.w500,
                                height: 1.15,
                              ),
                            ),
                            if (notableActivity != null)
                              Text(
                                notableActivity,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: const Color(0xFF98A2B3),
                                  fontWeight: FontWeight.w500,
                                  fontSize: 10.5,
                                  height: 1.15,
                                ),
                              ),
                          ],
                        )
                      else
                        SelectableText(
                          fileTypeLabel,
                          maxLines: 1,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: const Color(0xFF98A2B3),
                            fontWeight: FontWeight.w500,
                          ),
                        ),

                      if (_showImagePreview &&
                          !isMobile &&
                          meta.isImage &&
                          storagePath.isNotEmpty)
                        SizedBox(
                          height: 62, // Height + top padding.
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: FutureBuilder<String>(
                              future: FirebaseStorage.instance
                                  .ref(storagePath)
                                  .getDownloadURL(),
                              builder: (context, snap) {
                                if (!snap.hasData) {
                                  return const SizedBox(height: 56, width: 80);
                                }

                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.network(
                                    snap.data!,
                                    height: 56,
                                    width: 80,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const SizedBox(),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                if (!isMobile) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 90,
                    child: SelectableText(
                      _formatSize(sizeBytes),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF667085),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],

                if (!isMobile) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 160,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SelectableText(
                          when != null ? formatWhen(when) : '',
                          maxLines: 1,
                          textAlign: TextAlign.right,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF667085),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (notableActivity != null) ...[
                          const SizedBox(height: 2),
                          SelectableText(
                            notableActivity,
                            maxLines: 1,
                            textAlign: TextAlign.right,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: const Color(0xFF98A2B3),
                              fontWeight: FontWeight.w500,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                if (!isMobile) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 130,
                    child: SelectableText(
                      expiresAt == null
                          ? (expirationKnown ? 'No expiration' : '-')
                          : formatWhen(expiresAt!),
                      maxLines: 1,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF667085),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],

                if (!isMobile) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 170,
                    child: SelectableText(
                      requestedBy.isNotEmpty ? requestedBy : '-',
                      maxLines: 1,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF667085),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],

                const SizedBox(width: 10),

                IconButton(
                  tooltip: 'Download',
                  icon: const Icon(
                    Icons.download_outlined,
                    size: 16,
                    color: Color(0xFF475467),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 34,
                    height: 34,
                  ),
                  onPressed: (busy || isDeleted || storagePath.isEmpty)
                      ? null
                      : () => onDownload(storagePath, name, contentType),
                ),

                SizedBox(
                  width: 34,
                  height: 34,
                  child: Center(
                    child: PopupMenuButton<String>(
                      tooltip: 'File actions',
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.more_horiz, size: 18),
                      itemBuilder: (c) => [
                        const PopupMenuItem(
                          value: 'download',
                          child: Text('Download'),
                        ),
                        const PopupMenuDivider(),

                        const PopupMenuItem(
                          value: 'copyName',
                          child: Text('Copy file name'),
                        ),
                        const PopupMenuDivider(),

                        const PopupMenuItem(
                          value: 'details',
                          child: Text('File details'),
                        ),

                        if (isAdmin)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text(
                              'Delete file',
                              style: TextStyle(color: Color(0xFFB42318)),
                            ),
                          ),

                        if (isAdmin)
                          const PopupMenuItem(
                            value: 'history',
                            child: Text('View activity history'),
                          ),
                      ],
                      onSelected: (v) async {
                        switch (v) {
                          case 'download':
                            if (busy) return;
                            if (storagePath.isEmpty) return;
                            onDownload(storagePath, name, contentType);
                            break;
                          case 'copyName':
                            await Clipboard.setData(ClipboardData(text: name));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('File name copied'),
                                ),
                              );
                            }
                            break;

                          case 'details':
                            onShowDetails();
                            break;

                          case 'delete':
                            if (busy) return;

                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete file'),
                                content: Text(
                                  'Delete "$name"? The upload link will remain active, but this file will be marked as deleted.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );

                            if (confirm != true) return;

                            await FirebaseFunctions.instanceFor(
                              region: 'us-central1',
                            ).httpsCallable('softDeleteUploadFile').call({
                              'docPath': docPath,
                            });

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('File deleted')),
                              );
                            }
                            break;

                          case 'history':
                            onShowHistory();
                            break;
                        }
                      },
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

class _FileBoxPendingUpload {
  const _FileBoxPendingUpload({
    required this.name,
    required this.sizeBytes,
    required this.bytes,
    required this.contentType,
  });

  final String name;
  final int sizeBytes;
  final Uint8List bytes;
  final String contentType;

  String get key => '$name|$sizeBytes|${bytes.length}|$contentType';
}
