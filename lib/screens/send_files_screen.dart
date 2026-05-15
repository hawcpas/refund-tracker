import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../utils/file_kind.dart';
import '../widgets/page_scaffold.dart';

class SendFilesScreen extends StatefulWidget {
  const SendFilesScreen({super.key, this.onCreateSecureShare});

  final VoidCallback? onCreateSecureShare;

  @override
  State<SendFilesScreen> createState() => _SendFilesScreenState();
}

class _SendFilesScreenState extends State<SendFilesScreen> {
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');
  late Future<List<_SecureShareRow>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _loadShares();
  }

  Future<List<_SecureShareRow>> _loadShares() async {
    final res = await _functions.httpsCallable('listSecureFileShares').call();
    final data = Map<String, dynamic>.from(res.data as Map);
    final raw = (data['shares'] is List) ? data['shares'] as List : [];
    return raw
        .map((s) => _SecureShareRow.fromMap(Map<String, dynamic>.from(s)))
        .toList();
  }

  void _refresh() {
    setState(() => _future = _loadShares());
  }

  void _openCreateSecureShare() {
    if (widget.onCreateSecureShare != null) {
      widget.onCreateSecureShare!();
      return;
    }
    Navigator.pushNamed(context, '/send-files/new');
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return '-';
    final loc = MaterialLocalizations.of(context);
    return '${loc.formatShortDate(dt)} ${loc.formatTimeOfDay(TimeOfDay.fromDateTime(dt))}';
  }

  String _shortDate(DateTime? dt) {
    if (dt == null) return '-';
    final loc = MaterialLocalizations.of(context);
    return loc.formatShortDate(dt);
  }

  String _relativeLabel(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return _shortDate(dt);
  }

  String _activitySummary(_SecureShareRow row) {
    if (row.lastViewedAt != null) {
      return 'Viewed ${_relativeLabel(row.lastViewedAt)}';
    }
    if (row.lastDownloadedAt != null) {
      return 'Downloaded ${_relativeLabel(row.lastDownloadedAt)}';
    }
    if (row.createdAt != null) {
      return 'Sent ${_relativeLabel(row.createdAt)}';
    }
    return 'Not viewed';
  }

  String _expiresSummary(_SecureShareRow row) {
    final dt = row.expiresAt;
    if (dt == null) return '-';
    final now = DateTime.now();
    final diff = dt.difference(now);
    if (row.status == 'expired' || diff.isNegative) {
      return 'Expired ${_shortDate(dt)}';
    }
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Tomorrow';
    if (diff.inDays < 14) return 'In ${diff.inDays} days';
    return _shortDate(dt);
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return const Color(0xFF067647);
      case 'expired':
        return const Color(0xFFB54708);
      case 'revoked':
        return const Color(0xFFB42318);
      default:
        return const Color(0xFF667085);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return 'Active';
      case 'expired':
        return 'Expired';
      case 'revoked':
        return 'Revoked';
      default:
        return status.isEmpty ? '-' : status;
    }
  }

  Future<void> _copyLink(_SecureShareRow share) async {
    await Clipboard.setData(ClipboardData(text: share.url));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Secure link copied.')));
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '-';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _applyShareTemplateTokens(String text, String clientName) {
    final name = clientName.trim();
    final firstName = name.isEmpty
        ? 'Client'
        : name.split(RegExp(r'\s+')).first;
    return text
        .replaceAll('{{clientName}}', name.isEmpty ? 'Client' : name)
        .replaceAll('{{clientFirstName}}', firstName);
  }

  List<_ShareMessageTemplate> get _shareMessageTemplates => const [
    _ShareMessageTemplate(
      id: 'secure_delivery',
      title: 'Secure file delivery',
      body:
          'Dear {{clientFirstName}},\n\n'
          'Please use the secure link provided to access the files we have shared with you. For your protection, the password will be provided separately.\n\n'
          'Best regards,\n'
          'Axume & Associates CPAs',
    ),
    _ShareMessageTemplate(
      id: 'tax_documents',
      title: 'Tax documents',
      body:
          'Dear {{clientFirstName}},\n\n'
          'We have securely shared documents related to your tax file. Please use the secure link to view or download the files at your convenience.\n\n'
          'Best regards,\n'
          'Axume & Associates CPAs',
    ),
    _ShareMessageTemplate(
      id: 'review_and_download',
      title: 'Review and download',
      body:
          'Dear {{clientFirstName}},\n\n'
          'The requested files are ready for your review. Please access them through the secure link and download a copy for your records.\n\n'
          'Best regards,\n'
          'Axume & Associates CPAs',
    ),
  ];

  Future<List<_ShareableFile>> _loadShareableFiles() async {
    final res = await _functions.httpsCallable('listShareableFiles').call();
    final data = Map<String, dynamic>.from(res.data as Map);
    final raw = (data['files'] is List) ? data['files'] as List : [];
    return raw
        .map((f) => _ShareableFile.fromMap(Map<String, dynamic>.from(f)))
        .toList();
  }

  Future<List<_DeviceShareFile>> _pickDeviceFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return const [];

    return result.files
        .where((f) => f.bytes != null && f.bytes!.isNotEmpty)
        .map(
          (f) => _DeviceShareFile(
            name: f.name,
            sizeBytes: f.size,
            bytes: f.bytes!,
            contentType: _guessContentType(f.name),
          ),
        )
        .toList();
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

  Future<List<Map<String, dynamic>>> _uploadDeviceFiles(
    List<_DeviceShareFile> files,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw Exception('Sign-in required.');
    }

    final uploaded = <Map<String, dynamic>>[];
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final objectId =
          '${DateTime.now().microsecondsSinceEpoch}_${i}_${safeName.hashCode}';
      final storagePath = 'secure_share_uploads/$uid/$objectId-$safeName';
      final ref = FirebaseStorage.instance.ref(storagePath);

      await ref.putData(
        file.bytes,
        SettableMetadata(contentType: file.contentType),
      );

      uploaded.add({
        'storagePath': storagePath,
        'originalName': file.name,
        'contentType': file.contentType,
        'sizeBytes': file.sizeBytes,
      });
    }
    return uploaded;
  }

  Future<void> _revoke(_SecureShareRow share) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke secure share'),
        content: Text(
          'Revoke access for ${share.clientLabel}? The secure link will stop working immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      await _functions.httpsCallable('revokeSecureFileShare').call({
        'shareId': share.shareId,
      });
      _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Secure share revoked.')));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message ?? 'Revoke failed.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeFromList(_SecureShareRow share) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from Send Files'),
        content: Text(
          'Remove ${share.clientLabel} from this list? This keeps the audit record and does not revoke the client link.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      await _functions.httpsCallable('hideSecureFileShare').call({
        'shareId': share.shareId,
      });
      _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Secure share removed from list.')),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message ?? 'Remove failed.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showDetails(_SecureShareRow share) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: const Text('Secure share details'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620, maxHeight: 520),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailRow(label: 'Client', value: share.clientLabel),
                  _DetailRow(label: 'Sent by', value: share.senderLabel),
                  _DetailRow(label: 'Sent', value: _fmt(share.createdAt)),
                  _DetailRow(label: 'Expires', value: _fmt(share.expiresAt)),
                  _DetailRow(
                    label: 'Last viewed',
                    value: _fmt(share.lastViewedAt),
                  ),
                  _DetailRow(
                    label: 'Last downloaded',
                    value: _fmt(share.lastDownloadedAt),
                  ),
                  _DetailRow(
                    label: 'Status',
                    value: _statusLabel(share.status),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Files',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: const Color(0xFF344054),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE4E7EC)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: share.files.map((file) {
                        final meta = resolveFileMeta(
                          fileName: file.originalName,
                          contentType: file.contentType,
                        );
                        return ListTile(
                          dense: true,
                          leading: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: meta.color,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              meta.icon,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                          title: Text(
                            file.originalName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () => _copyLink(share),
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy link'),
            ),
          ],
        );
      },
    );
  }

  int _defaultExpirationDaysFor(DateTime? expiresAt) {
    if (expiresAt == null) return 7;
    final diff = expiresAt.difference(DateTime.now());
    if (diff.inDays <= 1) return 1;
    if (diff.inDays <= 7) return 7;
    if (diff.inDays <= 14) return 14;
    return 30;
  }

  Future<void> _showEditSecureShareDialog(_SecureShareRow share) async {
    var currentShare = share;
    final emailCtrl = TextEditingController(text: share.recipientEmail);
    final nameCtrl = TextEditingController(text: share.recipientName);
    final messageCtrl = TextEditingController(text: share.message);
    final passwordCtrl = TextEditingController();
    final confirmPasswordCtrl = TextEditingController();
    final searchCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    var expirationDays = _defaultExpirationDaysFor(currentShare.expiresAt);
    var submitting = false;
    var loadingFiles = false;
    var showFileBoxPicker = false;
    List<_ShareableFile> availableFiles = const [];
    final selectedFileKeys = <String>{};
    final removedFileKeys = <String>{};
    final deviceFiles = <_DeviceShareFile>[];
    var search = '';

    Future<void> loadFileBox(StateSetter setLocalState) async {
      setLocalState(() {
        showFileBoxPicker = true;
        loadingFiles = true;
      });
      try {
        final files = await _loadShareableFiles();
        final existingKeys = currentShare.files
            .map((f) => f.sourceKey)
            .where((key) => key.isNotEmpty)
            .toSet();
        setLocalState(() {
          availableFiles = files
              .where((file) => !existingKeys.contains(file.key))
              .toList();
          loadingFiles = false;
        });
      } catch (_) {
        setLocalState(() => loadingFiles = false);
      }
    }

    Future<void> addDeviceFiles(StateSetter setLocalState) async {
      final files = await _pickDeviceFiles();
      if (files.isEmpty) return;
      setLocalState(() {
        final existingKeys = deviceFiles.map((f) => f.key).toSet();
        for (final file in files) {
          if (existingKeys.add(file.key)) {
            deviceFiles.add(file);
          }
        }
      });
    }

    Future<void> finish(
      BuildContext dialogContext,
      StateSetter setLocalState,
    ) async {
      if (!(formKey.currentState?.validate() ?? false)) return;
      final remainingExistingCount = currentShare.files
          .where((file) => !removedFileKeys.contains(file.removalKey))
          .length;
      if (remainingExistingCount +
              selectedFileKeys.length +
              deviceFiles.length ==
          0) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          const SnackBar(
            content: Text('A secure share must include at least one file.'),
          ),
        );
        return;
      }

      setLocalState(() => submitting = true);
      setState(() => _busy = true);

      try {
        final selectedFiles = availableFiles
            .where((f) => selectedFileKeys.contains(f.key))
            .toList();
        final uploadedFiles = deviceFiles.isEmpty
            ? const <Map<String, dynamic>>[]
            : await _uploadDeviceFiles(deviceFiles);

        final payload = <String, dynamic>{
          'shareId': currentShare.shareId,
          'files': selectedFiles
              .map((f) => {'requestId': f.requestId, 'fileId': f.fileId})
              .toList(),
          'removeFiles': currentShare.files
              .where((file) => removedFileKeys.contains(file.removalKey))
              .map(
                (file) => {'requestId': file.requestId, 'fileId': file.fileId},
              )
              .toList(),
          'uploadedFiles': uploadedFiles,
          'recipientEmail': emailCtrl.text.trim().toLowerCase(),
          'recipientName': nameCtrl.text.trim(),
          'message': messageCtrl.text.trim(),
          'expirationDays': expirationDays,
        };
        final password = passwordCtrl.text.trim();
        if (password.isNotEmpty) payload['password'] = password;

        final res = await _functions
            .httpsCallable('updateSecureFileShare')
            .call(payload);
        final data = Map<String, dynamic>.from(res.data as Map);
        final addedFileCount = data['addedFileCount'] is num
            ? (data['addedFileCount'] as num).toInt()
            : selectedFiles.length + uploadedFiles.length;
        final removedFileCount = data['removedFileCount'] is num
            ? (data['removedFileCount'] as num).toInt()
            : removedFileKeys.length;

        final refreshedShares = await _loadShares();
        _SecureShareRow? updatedShare;
        for (final item in refreshedShares) {
          if (item.shareId == currentShare.shareId) {
            updatedShare = item;
            break;
          }
        }

        if (!dialogContext.mounted) return;
        setState(() => _future = Future.value(refreshedShares));
        setLocalState(() {
          if (updatedShare != null) {
            currentShare = updatedShare;
            emailCtrl.text = updatedShare.recipientEmail;
            nameCtrl.text = updatedShare.recipientName;
            messageCtrl.text = updatedShare.message;
            expirationDays = _defaultExpirationDaysFor(updatedShare.expiresAt);
          }
          passwordCtrl.clear();
          confirmPasswordCtrl.clear();
          selectedFileKeys.clear();
          removedFileKeys.clear();
          deviceFiles.clear();
          availableFiles = const [];
          showFileBoxPicker = false;
          search = '';
          searchCtrl.clear();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              addedFileCount > 0 || removedFileCount > 0
                  ? 'Secure share updated. Added $addedFileCount and removed $removedFileCount file(s).'
                  : 'Secure share updated.',
            ),
          ),
        );
      } on FirebaseFunctionsException catch (e) {
        if (!dialogContext.mounted) return;
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: Text('Update failed: ${e.code} ${e.message ?? ''}'),
          ),
        );
      } catch (e) {
        if (!dialogContext.mounted) return;
        ScaffoldMessenger.of(
          dialogContext,
        ).showSnackBar(SnackBar(content: Text('Update failed: $e')));
      } finally {
        if (mounted) setState(() => _busy = false);
        if (dialogContext.mounted) {
          setLocalState(() => submitting = false);
        }
      }
    }

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Manage secure share',
      barrierColor: Colors.black.withValues(alpha: 0.025),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        final theme = Theme.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            final filteredFiles = availableFiles.where((f) {
              final q = search.trim().toLowerCase();
              if (q.isEmpty) return true;
              return ('${f.originalName} ${f.clientName} ${f.clientEmail} ${f.businessName}')
                  .toLowerCase()
                  .contains(q);
            }).toList();
            final pendingAddCount =
                selectedFileKeys.length + deviceFiles.length;
            final saveLabel = pendingAddCount > 0
                ? 'Add $pendingAddCount ${pendingAddCount == 1 ? 'file' : 'files'}'
                : 'Save changes';

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

            Widget linkPanel() => Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                border: Border.all(color: const Color(0xFFE4E7EC)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.link_outlined,
                    color: AppColors.brandBlue,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      currentShare.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF475467),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _copyLink(currentShare),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy'),
                  ),
                ],
              ),
            );

            Widget sectionTitle(String text, {String? trailing}) => Row(
              children: [
                Text(
                  text,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: const Color(0xFF344054),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (trailing != null) ...[
                  const Spacer(),
                  Text(
                    trailing,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF667085),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            );

            Widget currentFilesList() => DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE4E7EC)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: currentShare.files.map((file) {
                  final meta = resolveFileMeta(
                    fileName: file.originalName,
                    contentType: file.contentType,
                  );
                  final removed = removedFileKeys.contains(file.removalKey);
                  return ListTile(
                    dense: true,
                    tileColor: removed ? const Color(0xFFFFF1F3) : Colors.white,
                    leading: Icon(
                      meta.icon,
                      color: removed ? const Color(0xFFB42318) : meta.color,
                    ),
                    title: Text(
                      file.originalName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: removed
                            ? const Color(0xFFB42318)
                            : const Color(0xFF101828),
                        decoration: removed ? TextDecoration.lineThrough : null,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(_formatSize(file.sizeBytes)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          removed ? 'Will remove' : 'Included',
                          style: TextStyle(
                            color: removed
                                ? const Color(0xFFB42318)
                                : const Color(0xFF667085),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: removed ? 'Keep file' : 'Remove from share',
                          icon: Icon(
                            removed ? Icons.undo_outlined : Icons.close,
                            size: 18,
                            color: removed
                                ? AppColors.brandBlue
                                : const Color(0xFFB42318),
                          ),
                          onPressed: submitting
                              ? null
                              : () => setLocalState(() {
                                  if (removed) {
                                    removedFileKeys.remove(file.removalKey);
                                  } else {
                                    removedFileKeys.add(file.removalKey);
                                  }
                                }),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            );

            Widget sectionShell({
              required String title,
              required IconData icon,
              required Widget child,
              String? trailing,
            }) {
              return Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFE4E7EC)),
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF6F9FF),
                        border: Border(
                          bottom: BorderSide(color: Color(0xFFE4E7EC)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 3,
                            height: 44,
                            color: AppColors.brandBlue,
                          ),
                          const SizedBox(width: 11),
                          Icon(icon, size: 18, color: AppColors.brandBlue),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              title,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: const Color(0xFF253858),
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (trailing != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 14),
                              child: Text(
                                trailing,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF667085),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(padding: const EdgeInsets.all(14), child: child),
                  ],
                ),
              );
            }

            Widget fileControls() => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                currentFilesList(),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: (submitting || loadingFiles)
                          ? null
                          : () => loadFileBox(setLocalState),
                      icon: const Icon(Icons.inventory_2_outlined, size: 16),
                      label: Text(
                        showFileBoxPicker
                            ? 'Refresh File Box'
                            : 'Add from File Box',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: submitting
                          ? null
                          : () => addDeviceFiles(setLocalState),
                      icon: const Icon(Icons.upload_file_outlined, size: 16),
                      label: Text(
                        deviceFiles.isEmpty
                            ? 'Upload from device'
                            : 'Add more uploads',
                      ),
                    ),
                  ],
                ),
                if (showFileBoxPicker) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: searchCtrl,
                    onChanged: (v) => setLocalState(() => search = v),
                    decoration: const InputDecoration(
                      labelText: 'Search File Box',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 220),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE4E7EC)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: loadingFiles
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        : filteredFiles.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('No additional files found.'),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: filteredFiles.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final file = filteredFiles[index];
                              final selected = selectedFileKeys.contains(
                                file.key,
                              );
                              final meta = resolveFileMeta(
                                fileName: file.originalName,
                                contentType: file.contentType,
                              );
                              return CheckboxListTile(
                                value: selected,
                                onChanged: submitting
                                    ? null
                                    : (v) => setLocalState(() {
                                        if (v == true) {
                                          selectedFileKeys.add(file.key);
                                        } else {
                                          selectedFileKeys.remove(file.key);
                                        }
                                      }),
                                secondary: Icon(meta.icon, color: meta.color),
                                title: Text(
                                  file.originalName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  [
                                    if (file.clientName.isNotEmpty)
                                      file.clientName,
                                    if (file.businessName.isNotEmpty)
                                      file.businessName,
                                    _formatSize(file.sizeBytes),
                                  ].join(' - '),
                                ),
                              );
                            },
                          ),
                  ),
                ],
                if (deviceFiles.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  sectionTitle('Device uploads'),
                  const SizedBox(height: 8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE4E7EC)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: deviceFiles.map((file) {
                        final meta = resolveFileMeta(
                          fileName: file.name,
                          contentType: file.contentType,
                        );
                        return ListTile(
                          dense: true,
                          leading: Icon(meta.icon, color: meta.color),
                          title: Text(file.name),
                          subtitle: Text(_formatSize(file.sizeBytes)),
                          trailing: IconButton(
                            tooltip: 'Remove file',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: submitting
                                ? null
                                : () => setLocalState(
                                    () => deviceFiles.remove(file),
                                  ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
            );

            Widget accessControls() => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                sectionTitle('Expiration from today'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [1, 7, 14, 30].map(dayChip).toList(),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'New password',
                    helperText: 'Leave blank to keep the current password.',
                    prefixIcon: Icon(Icons.key_outlined),
                  ),
                  validator: (v) {
                    final value = (v ?? '').trim();
                    if (value.isNotEmpty && value.length < 6) {
                      return 'Use at least 6 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: confirmPasswordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm new password',
                    prefixIcon: Icon(Icons.verified_user_outlined),
                  ),
                  validator: (v) {
                    final password = passwordCtrl.text.trim();
                    final confirm = (v ?? '').trim();
                    if (password.isEmpty && confirm.isEmpty) return null;
                    if (confirm.isEmpty) {
                      return 'Re-enter the new password.';
                    }
                    if (confirm != password) {
                      return 'Passwords do not match.';
                    }
                    return null;
                  },
                ),
              ],
            );

            Widget messageControls() => Column(
              children: [
                TextFormField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Client email',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                  validator: (v) {
                    final value = (v ?? '').trim();
                    if (value.isNotEmpty && !value.contains('@')) {
                      return 'Enter a valid email.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Client name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: messageCtrl,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
              ],
            );

            final media = MediaQuery.of(ctx);
            final isCompactPanel = media.size.width < 720;
            const desktopPanelBodyWidth = 640.0;
            const desktopPanelOuterWidth = desktopPanelBodyWidth + 48.0;
            final sidePanelLeftInset = isCompactPanel
                ? 0.0
                : (media.size.width - desktopPanelOuterWidth - 12).clamp(
                    72.0,
                    media.size.width,
                  );
            final panelContentHeight = isCompactPanel
                ? media.size.height - 172
                : media.size.height - 202;

            return AlertDialog(
              alignment: isCompactPanel
                  ? Alignment.center
                  : Alignment.centerRight,
              insetPadding: EdgeInsets.only(
                left: sidePanelLeftInset,
                right: isCompactPanel ? 0 : 12,
                top: isCompactPanel ? 0 : 12,
                bottom: isCompactPanel ? 0 : 12,
              ),
              elevation: isCompactPanel ? 0 : 24,
              shadowColor: Colors.black.withValues(alpha: 0.24),
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(isCompactPanel ? 0 : 14),
                side: BorderSide(
                  color: isCompactPanel
                      ? Colors.transparent
                      : const Color(0xFFD0D5DD),
                ),
              ),
              titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
              contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              title: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.tune_outlined,
                      color: AppColors.brandBlue,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Manage secure share'),
                        SizedBox(height: 2),
                        Text(
                          'Update files, access, and client-facing details.',
                          style: TextStyle(
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
              content: SizedBox(
                width: isCompactPanel
                    ? media.size.width
                    : desktopPanelBodyWidth,
                height: panelContentHeight < 360 ? 360 : panelContentHeight,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        linkPanel(),
                        const SizedBox(height: 14),
                        sectionShell(
                          title: 'Files',
                          icon: Icons.folder_outlined,
                          trailing:
                              '${currentShare.files.where((file) => !removedFileKeys.contains(file.removalKey)).length + selectedFileKeys.length + deviceFiles.length} total',
                          child: fileControls(),
                        ),
                        const SizedBox(height: 12),
                        sectionShell(
                          title: 'Access',
                          icon: Icons.shield_outlined,
                          child: accessControls(),
                        ),
                        const SizedBox(height: 12),
                        sectionShell(
                          title: 'Client message',
                          icon: Icons.badge_outlined,
                          child: messageControls(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.pop(ctx),
                  child: const Text('Back'),
                ),
                FilledButton.icon(
                  onPressed: submitting
                      ? null
                      : () => finish(ctx, setLocalState),
                  icon: submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          pendingAddCount > 0
                              ? Icons.add_outlined
                              : Icons.save_outlined,
                          size: 16,
                        ),
                  label: Text(saveLabel),
                ),
              ],
            );
          },
        );
      },
      transitionBuilder: (ctx, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return FadeTransition(
          opacity: Tween<double>(begin: 0.94, end: 1).animate(curved),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );

    emailCtrl.dispose();
    nameCtrl.dispose();
    messageCtrl.dispose();
    passwordCtrl.dispose();
    confirmPasswordCtrl.dispose();
    searchCtrl.dispose();
  }

  Future<void> _showCreateSecureShareDialog() async {
    final emailCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final confirmPasswordCtrl = TextEditingController();
    final messageCtrl = TextEditingController();
    final searchCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    String source = '';
    int expirationDays = 7;
    bool sendEmail = false;
    bool submitting = false;
    bool obscurePassword = true;
    bool obscureConfirmPassword = true;
    String? selectedTemplateId;
    List<_ShareableFile> availableFiles = const [];
    final selectedFileKeys = <String>{};
    final deviceFiles = <_DeviceShareFile>[];
    String search = '';

    Future<void> finish(
      BuildContext dialogContext,
      StateSetter setLocalState,
    ) async {
      if (!(formKey.currentState?.validate() ?? false)) return;
      if (source == 'fileBox' && selectedFileKeys.isEmpty) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          const SnackBar(content: Text('Select at least one file.')),
        );
        return;
      }
      if (source == 'device' && deviceFiles.isEmpty) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          const SnackBar(content: Text('Choose at least one file.')),
        );
        return;
      }

      setLocalState(() => submitting = true);
      setState(() => _busy = true);

      try {
        final selectedFiles = availableFiles
            .where((f) => selectedFileKeys.contains(f.key))
            .toList();
        final uploadedFiles = source == 'device'
            ? await _uploadDeviceFiles(deviceFiles)
            : const <Map<String, dynamic>>[];

        final res = await _functions
            .httpsCallable('createSecureFileShare')
            .call({
              'files': selectedFiles
                  .map((f) => {'requestId': f.requestId, 'fileId': f.fileId})
                  .toList(),
              'uploadedFiles': uploadedFiles,
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
            : selectedFiles.length + uploadedFiles.length;
        final emailed = data['emailed'] == true;

        if (!dialogContext.mounted) return;
        Navigator.pop(dialogContext);
        _refresh();

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
                        ? 'The secure link was emailed to the client.'
                        : 'Copy this secure link and provide the password separately.',
                    style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF475467),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(url),
                  const SizedBox(height: 10),
                  Text(
                    '$fileCount ${fileCount == 1 ? "file" : "files"} shared.',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF667085),
                      fontWeight: FontWeight.w700,
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
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Secure link copied.')),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy link'),
              ),
            ],
          ),
        );
      } on FirebaseFunctionsException catch (e) {
        if (!dialogContext.mounted) return;
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: Text('Secure share failed: ${e.code} ${e.message ?? ''}'),
          ),
        );
      } catch (e) {
        if (!dialogContext.mounted) return;
        ScaffoldMessenger.of(
          dialogContext,
        ).showSnackBar(SnackBar(content: Text('Secure share failed: $e')));
      } finally {
        if (mounted) setState(() => _busy = false);
        if (dialogContext.mounted) {
          setLocalState(() => submitting = false);
        }
      }
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            final filteredFiles = availableFiles.where((f) {
              final q = search.trim().toLowerCase();
              if (q.isEmpty) return true;
              return ('${f.originalName} ${f.clientName} ${f.clientEmail} ${f.businessName}')
                  .toLowerCase()
                  .contains(q);
            }).toList();

            Future<void> chooseFileBox() async {
              setLocalState(() {
                source = 'fileBox';
                submitting = true;
              });
              try {
                final files = await _loadShareableFiles();
                setLocalState(() {
                  availableFiles = files;
                  submitting = false;
                });
              } catch (_) {
                setLocalState(() => submitting = false);
              }
            }

            Future<void> chooseDevice() async {
              final files = await _pickDeviceFiles();
              if (files.isEmpty) return;
              setLocalState(() {
                source = 'device';
                final existingKeys = deviceFiles.map((f) => f.key).toSet();
                for (final file in files) {
                  if (existingKeys.add(file.key)) {
                    deviceFiles.add(file);
                  }
                }
              });
            }

            Widget sourceTile({
              required IconData icon,
              required String title,
              required String subtitle,
              required VoidCallback onTap,
            }) {
              return InkWell(
                onTap: submitting ? null : onTap,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE4E7EC)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, color: AppColors.brandBlue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Color(0xFF101828),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              style: const TextStyle(
                                color: Color(0xFF667085),
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Color(0xFF98A2B3)),
                    ],
                  ),
                ),
              );
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
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
              contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              title: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.lock_outline,
                      color: AppColors.brandBlue,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Create secure share'),
                        SizedBox(height: 2),
                        Text(
                          'Choose files and protect access with a client password.',
                          style: TextStyle(
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
              content: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 720,
                  maxHeight: 680,
                ),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (source.isEmpty) ...[
                          sourceTile(
                            icon: Icons.inventory_2_outlined,
                            title: 'Choose from File Box',
                            subtitle:
                                'Send files already stored in the portal.',
                            onTap: chooseFileBox,
                          ),
                          const SizedBox(height: 10),
                          sourceTile(
                            icon: Icons.upload_file_outlined,
                            title: 'Upload from device',
                            subtitle: 'Upload new files for this secure share.',
                            onTap: chooseDevice,
                          ),
                        ] else ...[
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: submitting
                                    ? null
                                    : () => setLocalState(() {
                                        source = '';
                                        availableFiles = const [];
                                        selectedFileKeys.clear();
                                        deviceFiles.clear();
                                      }),
                                icon: const Icon(Icons.arrow_back, size: 16),
                                label: const Text('Change source'),
                              ),
                              const Spacer(),
                              Text(
                                source == 'fileBox'
                                    ? '${selectedFileKeys.length} selected'
                                    : '${deviceFiles.length} selected',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF667085),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (source == 'fileBox') ...[
                            TextField(
                              controller: searchCtrl,
                              onChanged: (v) => setLocalState(() => search = v),
                              decoration: const InputDecoration(
                                labelText: 'Search File Box',
                                prefixIcon: Icon(Icons.search),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              constraints: const BoxConstraints(maxHeight: 230),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: const Color(0xFFE4E7EC),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: submitting
                                  ? const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(24),
                                        child: CircularProgressIndicator(),
                                      ),
                                    )
                                  : ListView.separated(
                                      shrinkWrap: true,
                                      itemCount: filteredFiles.length,
                                      separatorBuilder: (_, __) =>
                                          const Divider(height: 1),
                                      itemBuilder: (context, index) {
                                        final file = filteredFiles[index];
                                        final selected = selectedFileKeys
                                            .contains(file.key);
                                        final meta = resolveFileMeta(
                                          fileName: file.originalName,
                                          contentType: file.contentType,
                                        );
                                        return CheckboxListTile(
                                          value: selected,
                                          onChanged: submitting
                                              ? null
                                              : (v) => setLocalState(() {
                                                  if (v == true) {
                                                    selectedFileKeys.add(
                                                      file.key,
                                                    );
                                                  } else {
                                                    selectedFileKeys.remove(
                                                      file.key,
                                                    );
                                                  }
                                                }),
                                          secondary: Icon(
                                            meta.icon,
                                            color: meta.color,
                                          ),
                                          title: Text(
                                            file.originalName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          subtitle: Text(
                                            [
                                              if (file.clientName.isNotEmpty)
                                                file.clientName,
                                              if (file.businessName.isNotEmpty)
                                                file.businessName,
                                              _formatSize(file.sizeBytes),
                                            ].join(' - '),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ] else ...[
                            OutlinedButton.icon(
                              onPressed: submitting ? null : chooseDevice,
                              icon: const Icon(Icons.upload_file_outlined),
                              label: Text(
                                deviceFiles.isEmpty
                                    ? 'Choose files'
                                    : 'Add more files',
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: const Color(0xFFE4E7EC),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                children: deviceFiles.map((file) {
                                  final meta = resolveFileMeta(
                                    fileName: file.name,
                                    contentType: file.contentType,
                                  );
                                  return ListTile(
                                    dense: true,
                                    leading: Icon(meta.icon, color: meta.color),
                                    title: Text(file.name),
                                    subtitle: Text(_formatSize(file.sizeBytes)),
                                    trailing: IconButton(
                                      tooltip: 'Remove file',
                                      icon: const Icon(Icons.close, size: 18),
                                      onPressed: submitting
                                          ? null
                                          : () => setLocalState(
                                              () => deviceFiles.remove(file),
                                            ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: emailCtrl,
                            keyboardType: TextInputType.emailAddress,
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
                            decoration: const InputDecoration(
                              labelText: 'Client name',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: passwordCtrl,
                            obscureText: obscurePassword,
                            onChanged: (_) {
                              setLocalState(() {});
                              if (confirmPasswordCtrl.text.isNotEmpty) {
                                formKey.currentState?.validate();
                              }
                            },
                            decoration: InputDecoration(
                              labelText: 'Password',
                              helperText:
                                  'Share this password with the client separately.',
                              prefixIcon: const Icon(Icons.key_outlined),
                              suffixIcon: IconButton(
                                tooltip: obscurePassword
                                    ? 'Show password'
                                    : 'Hide password',
                                icon: Icon(
                                  obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                                onPressed: () => setLocalState(
                                  () => obscurePassword = !obscurePassword,
                                ),
                              ),
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
                            controller: confirmPasswordCtrl,
                            obscureText: obscureConfirmPassword,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            onChanged: (_) => setLocalState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Confirm password',
                              prefixIcon: const Icon(
                                Icons.verified_user_outlined,
                              ),
                              suffixIcon: IconButton(
                                tooltip: obscureConfirmPassword
                                    ? 'Show confirmation'
                                    : 'Hide confirmation',
                                icon: Icon(
                                  obscureConfirmPassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                                onPressed: () => setLocalState(
                                  () => obscureConfirmPassword =
                                      !obscureConfirmPassword,
                                ),
                              ),
                            ),
                            validator: (v) {
                              final password = passwordCtrl.text.trim();
                              final confirm = (v ?? '').trim();
                              if (confirm.isEmpty) {
                                return 'Re-enter the password.';
                              }
                              if (confirm != password) {
                                return 'Passwords do not match.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: selectedTemplateId,
                            decoration: const InputDecoration(
                              labelText: 'Message template',
                              prefixIcon: Icon(Icons.article_outlined),
                            ),
                            items: _shareMessageTemplates
                                .map(
                                  (template) => DropdownMenuItem<String>(
                                    value: template.id,
                                    child: Text(template.title),
                                  ),
                                )
                                .toList(),
                            onChanged: submitting
                                ? null
                                : (id) => setLocalState(() {
                                    selectedTemplateId = id;
                                    _ShareMessageTemplate? template;
                                    for (final item in _shareMessageTemplates) {
                                      if (item.id == id) {
                                        template = item;
                                        break;
                                      }
                                    }
                                    if (template != null) {
                                      messageCtrl.text =
                                          _applyShareTemplateTokens(
                                            template.body,
                                            nameCtrl.text,
                                          );
                                    }
                                  }),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: messageCtrl,
                            minLines: 2,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              labelText: 'Message',
                              prefixIcon: Icon(Icons.notes_outlined),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [1, 7, 14, 30].map(dayChip).toList(),
                          ),
                          const SizedBox(height: 10),
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
                                : (v) => setLocalState(
                                    () => sendEmail = v == true,
                                  ),
                          ),
                        ],
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
                if (source.isNotEmpty)
                  FilledButton.icon(
                    onPressed: submitting
                        ? null
                        : () => finish(ctx, setLocalState),
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
    confirmPasswordCtrl.dispose();
    messageCtrl.dispose();
    searchCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PageScaffold(
      title: 'Send Files',
      subtitle:
          'Create and monitor password-protected file shares sent to clients.',
      wrapInCard: false,
      maxContentWidth: 1400,
      commandBar: FluentCommandBar(
        actions: [
          FluentCommandAction(
            icon: Icons.add_link_outlined,
            label: 'Create secure share',
            onPressed: _busy ? null : _openCreateSecureShare,
            accent: true,
          ),
          FluentCommandAction(
            icon: Icons.refresh,
            label: 'Refresh',
            onPressed: _busy ? null : _refresh,
            accent: false,
          ),
        ],
        overflowActions: const [],
      ),
      child: FutureBuilder<List<_SecureShareRow>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            );
          }

          if (snap.hasError) {
            return _EmptyState(
              icon: Icons.warning_amber_outlined,
              title: 'Unable to load sent files',
              subtitle: 'Please refresh or try again shortly.',
              actionLabel: 'Refresh',
              onAction: _refresh,
            );
          }

          final rows = snap.data ?? const <_SecureShareRow>[];
          if (rows.isEmpty) {
            return _EmptyState(
              icon: Icons.lock_outline,
              title: 'No secure shares yet',
              subtitle:
                  'Create a secure share from File Box files or files uploaded from your device.',
              actionLabel: 'Create secure share',
              onAction: _openCreateSecureShare,
            );
          }

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 1120,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE4E7EC)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Container(
                      height: 42,
                      color: const Color(0xFFF9FAFB),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: const [
                          Expanded(flex: 3, child: _HeaderText('Client')),
                          SizedBox(width: 80, child: _HeaderText('Files')),
                          SizedBox(width: 116, child: _HeaderText('Status')),
                          SizedBox(width: 180, child: _HeaderText('Activity')),
                          SizedBox(width: 150, child: _HeaderText('Expires')),
                          SizedBox(
                            width: 204,
                            child: _HeaderText('Actions', alignEnd: true),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE4E7EC)),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: Color(0xFFE4E7EC)),
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        final color = _statusColor(row.status);
                        return InkWell(
                          onTap: () => _showDetails(row),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        row.clientLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: const Color(0xFF101828),
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      if (row.recipientEmail.isNotEmpty)
                                        Text(
                                          row.recipientEmail,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: const Color(0xFF667085),
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 80,
                                  child: Text(
                                    '${row.fileCount}',
                                    style: _cellStyle(theme),
                                  ),
                                ),
                                SizedBox(
                                  width: 116,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.10),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: color.withValues(alpha: 0.22),
                                        ),
                                      ),
                                      child: Text(
                                        _statusLabel(row.status),
                                        style: TextStyle(
                                          color: color,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 180,
                                  child: Text(
                                    _activitySummary(row),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: _cellStyle(theme),
                                  ),
                                ),
                                SizedBox(
                                  width: 150,
                                  child: Text(
                                    _expiresSummary(row),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: _cellStyle(theme),
                                  ),
                                ),
                                SizedBox(
                                  width: 204,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      IconButton(
                                        tooltip: 'Copy link',
                                        icon: const Icon(Icons.copy, size: 17),
                                        onPressed: () => _copyLink(row),
                                      ),
                                      IconButton(
                                        tooltip: 'Manage share',
                                        icon: const Icon(
                                          Icons.tune_outlined,
                                          size: 17,
                                        ),
                                        onPressed:
                                            (_busy || row.status == 'revoked')
                                            ? null
                                            : () => _showEditSecureShareDialog(
                                                row,
                                              ),
                                      ),
                                      IconButton(
                                        tooltip: 'Revoke',
                                        icon: const Icon(
                                          Icons.block_outlined,
                                          size: 17,
                                        ),
                                        onPressed:
                                            (_busy || row.status != 'active')
                                            ? null
                                            : () => _revoke(row),
                                      ),
                                      IconButton(
                                        tooltip: 'Remove from list',
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          size: 17,
                                        ),
                                        onPressed: _busy
                                            ? null
                                            : () => _removeFromList(row),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  TextStyle? _cellStyle(ThemeData theme) {
    return theme.textTheme.bodySmall?.copyWith(
      color: const Color(0xFF475467),
      fontWeight: FontWeight.w700,
    );
  }
}

class _HeaderText extends StatelessWidget {
  const _HeaderText(this.text, {this.alignEnd = false});

  final String text;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: alignEnd ? TextAlign.right : TextAlign.left,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: const Color(0xFF475467),
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.brandBlue, size: 34),
          const SizedBox(height: 12),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: const Color(0xFF101828),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF667085),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.folder_open_outlined, size: 16),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF667085),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF101828),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareMessageTemplate {
  const _ShareMessageTemplate({
    required this.id,
    required this.title,
    required this.body,
  });

  final String id;
  final String title;
  final String body;
}

class _SecureShareRow {
  const _SecureShareRow({
    required this.shareId,
    required this.url,
    required this.recipientName,
    required this.recipientEmail,
    required this.message,
    required this.createdByName,
    required this.createdByEmail,
    required this.createdAt,
    required this.expiresAt,
    required this.lastViewedAt,
    required this.lastDownloadedAt,
    required this.status,
    required this.fileCount,
    required this.files,
  });

  final String shareId;
  final String url;
  final String recipientName;
  final String recipientEmail;
  final String message;
  final String createdByName;
  final String createdByEmail;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final DateTime? lastViewedAt;
  final DateTime? lastDownloadedAt;
  final String status;
  final int fileCount;
  final List<_SecureShareFile> files;

  String get clientLabel {
    if (recipientName.trim().isNotEmpty) return recipientName.trim();
    if (recipientEmail.trim().isNotEmpty) return recipientEmail.trim();
    return 'Client';
  }

  String get senderLabel {
    if (createdByName.trim().isNotEmpty) return createdByName.trim();
    if (createdByEmail.trim().isNotEmpty) return createdByEmail.trim();
    return '-';
  }

  factory _SecureShareRow.fromMap(Map<String, dynamic> map) {
    DateTime? date(dynamic v) {
      if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
      return null;
    }

    final rawFiles = (map['files'] is List) ? map['files'] as List : [];
    return _SecureShareRow(
      shareId: (map['shareId'] ?? '').toString(),
      url: (map['url'] ?? '').toString(),
      recipientName: (map['recipientName'] ?? '').toString(),
      recipientEmail: (map['recipientEmail'] ?? '').toString(),
      message: (map['message'] ?? '').toString(),
      createdByName: (map['createdByName'] ?? '').toString(),
      createdByEmail: (map['createdByEmail'] ?? '').toString(),
      createdAt: date(map['createdAtMillis']),
      expiresAt: date(map['expiresAtMillis']),
      lastViewedAt: date(map['lastViewedAtMillis']),
      lastDownloadedAt: date(map['lastDownloadedAtMillis']),
      status: (map['status'] ?? '').toString(),
      fileCount: map['fileCount'] is num
          ? (map['fileCount'] as num).toInt()
          : 0,
      files: rawFiles
          .map((f) => _SecureShareFile.fromMap(Map<String, dynamic>.from(f)))
          .toList(),
    );
  }
}

class _SecureShareFile {
  const _SecureShareFile({
    required this.requestId,
    required this.fileId,
    required this.originalName,
    required this.contentType,
    required this.sizeBytes,
  });

  final String requestId;
  final String fileId;
  final String originalName;
  final String contentType;
  final int sizeBytes;

  String get sourceKey => requestId.isEmpty ? '' : '$requestId/$fileId';
  String get removalKey => '$requestId/$fileId';

  factory _SecureShareFile.fromMap(Map<String, dynamic> map) {
    return _SecureShareFile(
      requestId: (map['requestId'] ?? '').toString(),
      fileId: (map['fileId'] ?? '').toString(),
      originalName: (map['originalName'] ?? 'File').toString(),
      contentType: (map['contentType'] ?? '').toString(),
      sizeBytes: map['sizeBytes'] is num
          ? (map['sizeBytes'] as num).toInt()
          : 0,
    );
  }
}

class _ShareableFile {
  const _ShareableFile({
    required this.requestId,
    required this.fileId,
    required this.originalName,
    required this.contentType,
    required this.sizeBytes,
    required this.clientName,
    required this.clientEmail,
    required this.businessName,
  });

  final String requestId;
  final String fileId;
  final String originalName;
  final String contentType;
  final int sizeBytes;
  final String clientName;
  final String clientEmail;
  final String businessName;

  String get key => '$requestId/$fileId';

  factory _ShareableFile.fromMap(Map<String, dynamic> map) {
    return _ShareableFile(
      requestId: (map['requestId'] ?? '').toString(),
      fileId: (map['fileId'] ?? '').toString(),
      originalName: (map['originalName'] ?? 'File').toString(),
      contentType: (map['contentType'] ?? '').toString(),
      sizeBytes: map['sizeBytes'] is num
          ? (map['sizeBytes'] as num).toInt()
          : 0,
      clientName: (map['clientName'] ?? '').toString(),
      clientEmail: (map['clientEmail'] ?? '').toString(),
      businessName: (map['businessName'] ?? '').toString(),
    );
  }
}

class _DeviceShareFile {
  const _DeviceShareFile({
    required this.name,
    required this.sizeBytes,
    required this.bytes,
    required this.contentType,
  });

  final String name;
  final int sizeBytes;
  final Uint8List bytes;
  final String contentType;

  String get key => '$name/$sizeBytes/${bytes.length}';
}
