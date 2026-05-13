import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import '../theme/brand_logo_svg.dart';
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
  bool _checkingStatus = true;
  String? _error;
  String? _blockedStatus;
  String? _shareId;
  DateTime? _expiresAt;
  List<_SecureSharedFile> _files = const [];
  final Set<String> _selectedFileIds = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_shareId == null) {
      _shareId = Uri.base.queryParameters['sid']?.trim();
      _checkShareStatus();
    }
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

  Future<void> _checkShareStatus() async {
    final shareId = (_shareId ?? '').trim();
    if (shareId.isEmpty) {
      setState(() {
        _checkingStatus = false;
        _blockedStatus = 'unavailable';
      });
      return;
    }

    try {
      final res = await _functions.httpsCallable('getSecureShareStatus').call({
        'shareId': shareId,
      });
      final data = Map<String, dynamic>.from(res.data as Map);
      final status = (data['status'] ?? '').toString().toLowerCase().trim();
      final expiresAtMillis = data['expiresAtMillis'];

      if (!mounted) return;
      setState(() {
        _checkingStatus = false;
        _expiresAt = expiresAtMillis is num
            ? DateTime.fromMillisecondsSinceEpoch(expiresAtMillis.toInt())
            : null;
        _blockedStatus = status == 'active' ? null : status;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checkingStatus = false;
        _blockedStatus = 'unavailable';
      });
    }
  }

  String get _blockedTitle {
    switch (_blockedStatus) {
      case 'expired':
        return 'This secure link has expired';
      case 'revoked':
        return 'This secure link is no longer available';
      default:
        return 'This secure link is unavailable';
    }
  }

  String get _blockedMessage {
    switch (_blockedStatus) {
      case 'expired':
        final date = _expiresAt == null
            ? ''
            : ' It expired on ${_formatDate(_expiresAt!)}.';
        return 'For your protection, access to this file share is no longer available.$date Please contact our office if you need a new secure link.';
      case 'revoked':
        return 'Access to this file share has been disabled. Please contact our office if you need assistance.';
      default:
        return 'We could not verify this secure link. Please contact our office if you believe this is unexpected.';
    }
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
        _selectedFileIds
          ..clear()
          ..addAll(_files.map((f) => f.fileId));
      });
    } on FirebaseFunctionsException catch (e) {
      setState(() {
        if (e.code == 'deadline-exceeded') {
          _blockedStatus = 'expired';
          _error = null;
        } else if (e.code == 'failed-precondition') {
          _blockedStatus = 'revoked';
          _error = null;
        } else {
          _error = e.message?.trim().isNotEmpty == true
              ? e.message
              : 'Unable to open this secure share.';
        }
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

  Future<void> _downloadSelected() async {
    final shareId = (_shareId ?? '').trim();
    final password = _passwordCtrl.text.trim();
    if (shareId.isEmpty || password.isEmpty || _selectedFileIds.isEmpty) {
      return;
    }

    setState(() => _loading = true);
    try {
      final res = await _functions
          .httpsCallable('getSecureShareZipDownloadUrl')
          .call({
            'shareId': shareId,
            'password': password,
            'fileIds': _selectedFileIds.toList(),
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
      backgroundColor: const Color(0xFFDCDCDC),
      body: Container(
        decoration: const BoxDecoration(color: Color(0xFFDCDCDC)),
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 32, 18, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.06),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.10),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _SecureShareBrandHeader(dense: true),
                            const SizedBox(height: 8),
                            const Divider(height: 1, color: Color(0xFFE4E7EC)),
                            const SizedBox(height: 14),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: AppColors.brandBlue.withValues(
                                      alpha: 0.10,
                                    ),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Secure file share',
                                        style: theme.textTheme.titleLarge
                                            ?.copyWith(
                                              color: const Color(0xFF101828),
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      if (_blockedStatus == null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          _checkingStatus
                                              ? 'Verifying this secure link.'
                                              : unlocked
                                              ? 'Download the files shared with you.'
                                              : 'Enter the password provided by our office.',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
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
                            const SizedBox(height: 22),
                            if (_checkingStatus) ...[
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 18),
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                            ] else if (_blockedStatus != null) ...[
                              _SecureShareNotice(
                                icon: _blockedStatus == 'expired'
                                    ? Icons.schedule_outlined
                                    : Icons.block_outlined,
                                title: _blockedTitle,
                                message: _blockedMessage,
                              ),
                            ] else if (!unlocked) ...[
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
                                height: 48,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.brandBlue,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: _loading ? null : _unlock,
                                  icon: _loading
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.lock_open_outlined,
                                          size: 18,
                                        ),
                                  label: const Text('Open secure files'),
                                ),
                              ),
                            ] else ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF9FAFB),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFFE4E7EC),
                                  ),
                                ),
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final compact = constraints.maxWidth < 560;
                                    final statusText = _expiresAt == null
                                        ? 'Secure files are ready.'
                                        : 'Available until ${_formatDate(_expiresAt!)}';
                                    final status = Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Icon(
                                          Icons.verified_user_outlined,
                                          color: AppColors.brandBlue,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            statusText,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: const Color(
                                                    0xFF475467,
                                                  ),
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ),
                                      ],
                                    );
                                    final actions = Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      alignment: compact
                                          ? WrapAlignment.start
                                          : WrapAlignment.end,
                                      children: [
                                        TextButton.icon(
                                          onPressed:
                                              _selectedFileIds.length ==
                                                  _files.length
                                              ? () => setState(
                                                  _selectedFileIds.clear,
                                                )
                                              : () => setState(() {
                                                  _selectedFileIds
                                                    ..clear()
                                                    ..addAll(
                                                      _files.map(
                                                        (f) => f.fileId,
                                                      ),
                                                    );
                                                }),
                                          icon: const Icon(
                                            Icons.checklist,
                                            size: 16,
                                          ),
                                          label: Text(
                                            _selectedFileIds.length ==
                                                    _files.length
                                                ? 'Clear'
                                                : 'Select all',
                                          ),
                                        ),
                                        FilledButton.icon(
                                          style: FilledButton.styleFrom(
                                            backgroundColor:
                                                AppColors.brandBlue,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                          ),
                                          onPressed:
                                              (_loading ||
                                                  _selectedFileIds.isEmpty)
                                              ? null
                                              : _downloadSelected,
                                          icon: const Icon(
                                            Icons.download_outlined,
                                            size: 16,
                                          ),
                                          label: Text(
                                            _selectedFileIds.length <= 1
                                                ? 'Download'
                                                : 'Download ZIP',
                                          ),
                                        ),
                                      ],
                                    );

                                    if (compact) {
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          status,
                                          const SizedBox(height: 10),
                                          actions,
                                        ],
                                      );
                                    }

                                    return Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: status),
                                        const SizedBox(width: 10),
                                        actions,
                                      ],
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 12),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: const Color(0xFFE4E7EC),
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  children: [
                                    Container(
                                      height: 40,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                      ),
                                      color: const Color(0xFFF9FAFB),
                                      child: Row(
                                        children: const [
                                          SizedBox(width: 44),
                                          Expanded(
                                            child: _ShareHeaderText('Name'),
                                          ),
                                          SizedBox(
                                            width: 110,
                                            child: _ShareHeaderText('Size'),
                                          ),
                                          SizedBox(
                                            width: 88,
                                            child: _ShareHeaderText(
                                              'Actions',
                                              alignEnd: true,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Divider(
                                      height: 1,
                                      color: Color(0xFFE4E7EC),
                                    ),
                                    ..._files.map((file) {
                                      final selected = _selectedFileIds
                                          .contains(file.fileId);
                                      return Column(
                                        children: [
                                          InkWell(
                                            onTap: () => setState(() {
                                              if (selected) {
                                                _selectedFileIds.remove(
                                                  file.fileId,
                                                );
                                              } else {
                                                _selectedFileIds.add(
                                                  file.fileId,
                                                );
                                              }
                                            }),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 8,
                                                  ),
                                              child: Row(
                                                children: [
                                                  Checkbox(
                                                    value: selected,
                                                    onChanged: (v) => setState(
                                                      () {
                                                        if (v == true) {
                                                          _selectedFileIds.add(
                                                            file.fileId,
                                                          );
                                                        } else {
                                                          _selectedFileIds
                                                              .remove(
                                                                file.fileId,
                                                              );
                                                        }
                                                      },
                                                    ),
                                                  ),
                                                  _ClientShareFileTypeIcon(
                                                    fileName: file.originalName,
                                                    contentType:
                                                        file.contentType,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text(
                                                      file.originalName,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color: Color(
                                                          0xFF101828,
                                                        ),
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                    ),
                                                  ),
                                                  SizedBox(
                                                    width: 110,
                                                    child: Text(
                                                      _formatSize(
                                                        file.sizeBytes,
                                                      ),
                                                      style: const TextStyle(
                                                        color: Color(
                                                          0xFF667085,
                                                        ),
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ),
                                                  SizedBox(
                                                    width: 88,
                                                    child: Align(
                                                      alignment:
                                                          Alignment.centerRight,
                                                      child: IconButton(
                                                        tooltip:
                                                            'Download file',
                                                        icon: const Icon(
                                                          Icons
                                                              .download_outlined,
                                                          size: 18,
                                                        ),
                                                        onPressed: _loading
                                                            ? null
                                                            : () => _download(
                                                                file,
                                                              ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          if (file != _files.last)
                                            const Divider(
                                              height: 1,
                                              color: Color(0xFFE4E7EC),
                                            ),
                                        ],
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _SecureShareFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClientShareFileTypeIcon extends StatelessWidget {
  const _ClientShareFileTypeIcon({
    required this.fileName,
    required this.contentType,
  });

  final String fileName;
  final String contentType;

  @override
  Widget build(BuildContext context) {
    final meta = resolveFileMeta(fileName: fileName, contentType: contentType);

    return Tooltip(
      message: meta.tooltip,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: meta.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Icon(meta.icon, size: 16, color: meta.color),
      ),
    );
  }
}

class _SecureShareBrandHeader extends StatelessWidget {
  const _SecureShareBrandHeader({this.dense = false});

  final bool dense;

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

class _SecureShareNotice extends StatelessWidget {
  const _SecureShareNotice({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFF667085).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: const Color(0xFF475467), size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF101828),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF475467),
                    height: 1.45,
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

class _SecureShareFooter extends StatelessWidget {
  const _SecureShareFooter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          'Copyright ${DateTime.now().year} Axume & Associates CPAs, AAC',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFF667085),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Secure Client Portal.\nAll rights reserved.',
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

class _ShareHeaderText extends StatelessWidget {
  const _ShareHeaderText(this.text, {this.alignEnd = false});

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
