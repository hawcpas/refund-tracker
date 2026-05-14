import 'package:cloud_functions/cloud_functions.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../utils/file_kind.dart';
import '../widgets/page_scaffold.dart';

class CreateSecureShareScreen extends StatefulWidget {
  const CreateSecureShareScreen({super.key, this.onCreated});

  final VoidCallback? onCreated;

  @override
  State<CreateSecureShareScreen> createState() =>
      _CreateSecureShareScreenState();
}

class _CreateSecureShareScreenState extends State<CreateSecureShareScreen> {
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');
  final _formKey = GlobalKey<FormState>();

  final _emailCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _emailFocusNode = FocusNode();

  String _source = '';
  int _expirationDays = 7;
  DateTime? _customExpiresAt;
  bool _sendEmail = false;
  bool _createLinkOnly = false;
  bool _includeMessage = false;
  bool _submitting = false;
  bool _loadingFiles = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _filesConfirmed = false;
  bool _showValidationHints = false;
  bool _passwordRequired = true;
  bool _draggingFiles = false;
  String? _selectedTemplateId;
  String _search = '';
  String? _expirationError;
  String? _createdUrl;

  final Set<int> _expandedSteps = {0};
  List<_ShareableFile> _availableFiles = const [];
  final Set<String> _selectedFileKeys = {};
  final List<_DeviceShareFile> _deviceFiles = [];

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

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _messageCtrl.dispose();
    _searchCtrl.dispose();
    _emailFocusNode.dispose();
    super.dispose();
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '-';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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

  bool _canPreviewDeviceFile(_DeviceShareFile file) {
    return file.contentType.toLowerCase().startsWith('image/');
  }

  Future<void> _previewDeviceFile(_DeviceShareFile file) async {
    if (!_canPreviewDeviceFile(file)) return;
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF101828),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE4E7EC)),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: InteractiveViewer(
                    child: Image.memory(file.bytes, fit: BoxFit.contain),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

  Future<void> _addDeviceFiles(List<_DeviceShareFile> files) async {
    if (files.isEmpty) return;
    setState(() {
      _filesConfirmed = false;
      final existingKeys = _deviceFiles.map((f) => f.key).toSet();
      for (final file in files) {
        if (existingKeys.add(file.key)) {
          _deviceFiles.add(file);
        }
      }
    });
  }

  Future<void> _handleDroppedFiles(DropDoneDetails details) async {
    final dropped = <_DeviceShareFile>[];
    for (final file in details.files) {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) continue;
      dropped.add(
        _DeviceShareFile(
          name: file.name,
          sizeBytes: bytes.length,
          bytes: bytes,
          contentType: _guessContentType(file.name),
        ),
      );
    }
    await _addDeviceFiles(dropped);
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

  Future<void> _chooseFileBox() async {
    setState(() {
      _source = 'fileBox';
      _loadingFiles = true;
      _filesConfirmed = false;
      _expandedSteps.add(0);
    });
    try {
      final files = await _loadShareableFiles();
      if (!mounted) return;
      setState(() {
        _availableFiles = files;
        _loadingFiles = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingFiles = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to load File Box files.')),
      );
    }
  }

  Future<void> _chooseDevice() async {
    final files = await _pickDeviceFiles();
    await _addDeviceFiles(files);
  }

  void _changeSource() {
    setState(() {
      _source = '';
      _search = '';
      _searchCtrl.clear();
    });
  }

  Future<void> _finish() async {
    setState(() => _showValidationHints = true);

    if (_selectedFileCount == 0) {
      _openStep(0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one file.')),
      );
      return;
    }

    if (!_clientComplete) {
      _openStep(1);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_clientValidationMessage)));
      return;
    }

    if (!_securityComplete) {
      _openStep(2);
      _formKey.currentState?.validate();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complete the security section.')),
      );
      return;
    }

    if (!_deliveryComplete) {
      _openStep(3);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_deliveryValidationMessage)));
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);
    try {
      final selectedFiles = _availableFiles
          .where((f) => _selectedFileKeys.contains(f.key))
          .toList();
      final uploadedFiles = _deviceFiles.isEmpty
          ? const <Map<String, dynamic>>[]
          : await _uploadDeviceFiles(_deviceFiles);

      final res = await _functions.httpsCallable('createSecureFileShare').call({
        'files': selectedFiles
            .map((f) => {'requestId': f.requestId, 'fileId': f.fileId})
            .toList(),
        'uploadedFiles': uploadedFiles,
        'recipientEmail': _emailCtrl.text.trim().toLowerCase(),
        'recipientName': _nameCtrl.text.trim(),
        'passwordRequired': _passwordRequired,
        'password': _passwordCtrl.text.trim(),
        'message': _includeMessage ? _messageCtrl.text.trim() : '',
        'expirationDays': _expirationDays,
        if (_customExpiresAt != null)
          'expiresAtMillis': _customExpiresAt!.millisecondsSinceEpoch,
        'sendEmail': _sendEmail,
      });

      final data = Map<String, dynamic>.from(res.data as Map);
      final url = (data['url'] ?? '').toString();
      if (!mounted) return;
      setState(() => _createdUrl = url);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Secure share created.')));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Secure share failed: ${e.code} ${e.message ?? ''}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Secure share failed: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _backToSentFiles() {
    if (widget.onCreated != null) {
      widget.onCreated!();
      return;
    }
    Navigator.pushReplacementNamed(context, '/send-files');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNarrow = MediaQuery.of(context).size.width < 760;

    return PageScaffold(
      title: _createdUrl == null ? 'Create secure link' : 'Secure link ready',
      subtitle: _createdUrl == null
          ? 'Choose files, protect access, and prepare the client-facing message.'
          : 'Copy the secure link or return to sent files.',
      wrapInCard: false,
      maxContentWidth: 1280,
      commandBar: FluentCommandBar(
        actions: [
          FluentCommandAction(
            icon: Icons.arrow_back,
            label: 'Sent files',
            onPressed: _submitting ? null : _backToSentFiles,
            accent: false,
          ),
          if (_createdUrl == null)
            FluentCommandAction(
              icon: Icons.lock_outline,
              label: 'Create secure link',
              onPressed: _submitting ? null : _finish,
              accent: true,
            ),
        ],
        overflowActions: const [],
      ),
      child: _createdUrl == null
          ? Form(
              key: _formKey,
              child: isNarrow
                  ? Column(
                      children: [
                        _buildMainWorkflow(theme),
                        const SizedBox(height: 14),
                        _buildSummary(theme),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildMainWorkflow(theme)),
                        const SizedBox(width: 16),
                        SizedBox(width: 380, child: _buildSummary(theme)),
                      ],
                    ),
            )
          : _SuccessPanel(
              url: _createdUrl!,
              sendEmail: _sendEmail,
              onCopy: () async {
                await Clipboard.setData(ClipboardData(text: _createdUrl!));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Secure link copied.')),
                );
              },
              onDone: _backToSentFiles,
              onCreateAnother: () {
                setState(() {
                  _createdUrl = null;
                  _source = '';
                  _selectedFileKeys.clear();
                  _deviceFiles.clear();
                  _availableFiles = const [];
                  _emailCtrl.clear();
                  _nameCtrl.clear();
                  _messageCtrl.clear();
                  _passwordCtrl.clear();
                  _confirmPasswordCtrl.clear();
                  _selectedTemplateId = null;
                  _sendEmail = false;
                  _createLinkOnly = false;
                  _includeMessage = false;
                  _expirationDays = 7;
                  _customExpiresAt = null;
                  _expirationError = null;
                  _filesConfirmed = false;
                  _showValidationHints = false;
                  _passwordRequired = true;
                  _expandedSteps
                    ..clear()
                    ..add(0);
                });
              },
            ),
    );
  }

  Widget _buildMainWorkflow(ThemeData theme) {
    return Column(
      children: [
        _SetupProgressStrip(
          steps: [
            _ProgressStepState(
              label: 'Files',
              complete: _filesComplete,
              attention: _showValidationHints && !_filesComplete,
              onTap: () => _openStep(0),
            ),
            _ProgressStepState(
              label: 'Client',
              complete: _clientComplete,
              attention: _showValidationHints && !_clientComplete,
              onTap: () => _openStep(1),
            ),
            _ProgressStepState(
              label: 'Security',
              complete: _securityComplete,
              attention: _showValidationHints && !_securityComplete,
              onTap: () => _openStep(2),
            ),
            _ProgressStepState(
              label: 'Delivery',
              complete: _deliveryComplete,
              attention: _showValidationHints && !_deliveryComplete,
              optional: !_deliveryChoiceMade,
              onTap: () => _openStep(3),
            ),
            _ProgressStepState(
              label: 'Review',
              complete: _readyToCreate,
              attention: _showValidationHints && !_readyToCreate,
              onTap: () => _openAllSteps(),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SectionShell(
          title: 'Files',
          icon: Icons.folder_outlined,
          step: 1,
          expanded: _expandedSteps.contains(0),
          completed: _filesComplete,
          attention: _showValidationHints && !_filesComplete,
          trailing: _filesComplete ? _fileCountLabel : 'Required',
          onTap: () => _toggleStep(0),
          child: _buildFilesSection(theme),
        ),
        const SizedBox(height: 14),
        _SectionShell(
          title: 'Client',
          icon: Icons.badge_outlined,
          step: 2,
          expanded: _expandedSteps.contains(1),
          completed: _clientComplete,
          attention: _showValidationHints && !_clientComplete,
          trailing: _clientSectionStatus,
          onTap: () => _toggleStep(1),
          child: _buildClientSection(),
        ),
        const SizedBox(height: 14),
        _SectionShell(
          title: 'Security',
          icon: Icons.shield_outlined,
          step: 3,
          expanded: _expandedSteps.contains(2),
          completed: _securityComplete,
          attention: _showValidationHints && !_securityComplete,
          trailing: _securitySectionStatus,
          onTap: () => _toggleStep(2),
          child: _buildSecuritySection(),
        ),
        const SizedBox(height: 14),
        _SectionShell(
          title: 'Delivery',
          icon: Icons.send_outlined,
          step: 4,
          expanded: _expandedSteps.contains(3),
          completed: _deliveryComplete,
          attention: _showValidationHints && !_deliveryComplete,
          trailing: _deliverySectionStatus,
          onTap: () => _toggleStep(3),
          child: _buildDeliverySection(),
        ),
      ],
    );
  }

  int get _selectedFileCount => _selectedFileKeys.length + _deviceFiles.length;

  bool get _filesComplete => _filesConfirmed && _selectedFileCount > 0;

  bool get _clientHasIdentity =>
      _nameCtrl.text.trim().isNotEmpty || _emailCtrl.text.trim().isNotEmpty;

  bool get _clientEmailValid {
    final email = _emailCtrl.text.trim();
    return email.isNotEmpty && email.contains('@') && email.contains('.');
  }

  bool get _clientComplete =>
      _clientHasIdentity && (!_sendEmail || _clientEmailValid);

  bool get _securityComplete {
    if (_expirationError != null) return false;
    if (!_passwordRequired) return true;
    final password = _passwordCtrl.text.trim();
    final confirm = _confirmPasswordCtrl.text.trim();
    return password.length >= 6 && confirm == password;
  }

  bool get _deliveryChoiceMade => _sendEmail || _createLinkOnly;

  bool get _deliveryComplete =>
      (_createLinkOnly && !_sendEmail) || (_sendEmail && _clientEmailValid);

  bool get _readyToCreate =>
      _filesComplete &&
      _clientComplete &&
      _securityComplete &&
      _deliveryComplete;

  String get _fileCountLabel {
    return '$_selectedFileCount selected';
  }

  String get _clientSectionStatus {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    if (name.isNotEmpty) return name;
    if (email.isNotEmpty) return email;
    return 'Not set';
  }

  String get _securitySectionStatus {
    final access = _passwordRequired ? 'Password' : 'No password';
    return '$access - $_expirationLabel';
  }

  String get _deliverySectionStatus {
    if (!_deliveryChoiceMade) return 'Choose delivery';
    if (_sendEmail && !_clientEmailValid) return 'Needs email';
    return _sendEmail ? 'Email enabled' : 'Link only';
  }

  String get _clientValidationMessage {
    if (!_clientHasIdentity) return 'Enter a client name or email.';
    if (_sendEmail && !_clientEmailValid) {
      return 'Enter a valid client email before sending by email.';
    }
    return 'Complete the client section.';
  }

  String get _deliveryValidationMessage {
    if (_sendEmail && !_clientEmailValid) {
      return 'Email delivery requires a valid client email.';
    }
    return 'Choose email delivery or link-only delivery.';
  }

  List<_ReviewIssue> get _reviewIssues {
    final items = <_ReviewIssue>[];
    if (!_filesComplete) {
      items.add(
        _ReviewIssue(
          message: 'Confirm at least one file.',
          actionLabel: 'Go to Files',
          onTap: () => _openStep(0),
        ),
      );
    }
    if (!_clientHasIdentity) {
      items.add(
        _ReviewIssue(
          message: 'Enter a client name or email.',
          actionLabel: 'Go to Client',
          onTap: () => _openStep(1),
        ),
      );
    }
    if (_sendEmail && !_clientEmailValid) {
      items.add(
        _ReviewIssue(
          message: 'Add a valid client email for email delivery.',
          actionLabel: 'Add email',
          onTap: _focusClientEmail,
        ),
      );
    }
    if (!_deliveryChoiceMade) {
      items.add(
        _ReviewIssue(
          message: 'Choose how the files will be delivered.',
          actionLabel: 'Go to Delivery',
          onTap: () => _openStep(3),
        ),
      );
    }
    if (!_securityComplete) {
      items.add(
        _ReviewIssue(
          message: _expirationError ?? 'Complete the password settings.',
          actionLabel: 'Go to Security',
          onTap: () => _openStep(2),
        ),
      );
    }
    return items;
  }

  String get _expirationLabel {
    final custom = _customExpiresAt;
    if (custom != null) {
      final loc = MaterialLocalizations.of(context);
      return '${loc.formatShortDate(custom)} ${loc.formatTimeOfDay(TimeOfDay.fromDateTime(custom))}';
    }
    return '$_expirationDays day${_expirationDays == 1 ? '' : 's'}';
  }

  List<_SelectedShareFile> get _readyFiles {
    final fromFileBox = _availableFiles
        .where((f) => _selectedFileKeys.contains(f.key))
        .map(
          (f) => _SelectedShareFile(
            key: f.key,
            name: f.originalName,
            contentType: f.contentType,
            sizeBytes: f.sizeBytes,
            sourceLabel: 'File Box',
            onPreview: null,
            onRemove: () => setState(() {
              _selectedFileKeys.remove(f.key);
              _filesConfirmed = false;
            }),
          ),
        );
    final fromDevice = _deviceFiles.map(
      (f) => _SelectedShareFile(
        key: f.key,
        name: f.name,
        contentType: f.contentType,
        sizeBytes: f.sizeBytes,
        sourceLabel: 'Device upload',
        onPreview: _canPreviewDeviceFile(f)
            ? () => _previewDeviceFile(f)
            : null,
        onRemove: () => setState(() {
          _deviceFiles.remove(f);
          _filesConfirmed = false;
        }),
      ),
    );
    return [...fromFileBox, ...fromDevice];
  }

  List<_ClientSuggestion> get _clientSuggestions {
    final seen = <String>{};
    final out = <_ClientSuggestion>[];
    for (final file in _availableFiles) {
      final name = file.clientName.trim();
      final email = file.clientEmail.trim();
      if (name.isEmpty && email.isEmpty) continue;
      final key = '${name.toLowerCase()}|${email.toLowerCase()}';
      if (!seen.add(key)) continue;
      out.add(_ClientSuggestion(name: name, email: email));
    }
    return out.take(8).toList();
  }

  void _toggleStep(int step) {
    setState(() {
      if (_expandedSteps.contains(step)) {
        _expandedSteps.remove(step);
      } else {
        _expandedSteps.add(step);
      }
    });
  }

  void _openStep(int step) {
    setState(() => _expandedSteps.add(step));
  }

  void _openAllSteps() {
    setState(() => _expandedSteps.addAll({0, 1, 2, 3}));
  }

  void _focusClientEmail() {
    _openStep(1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _emailFocusNode.requestFocus();
    });
  }

  Future<void> _pickCustomExpiration() async {
    final now = DateTime.now();
    final initial =
        _customExpiresAt ?? now.add(Duration(days: _expirationDays));
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;

    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!selected.isAfter(DateTime.now())) {
      setState(() {
        _expirationError = 'Expiration must be set to a future date and time.';
        _expandedSteps.add(2);
      });
      return;
    }
    setState(() {
      _customExpiresAt = selected;
      _expirationError = null;
    });
  }

  void _confirmFiles() {
    if (_selectedFileCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one file.')),
      );
      return;
    }
    setState(() {
      _filesConfirmed = true;
      _expandedSteps.add(1);
    });
  }

  Widget _buildFilesSection(ThemeData theme) {
    final filteredFiles = _availableFiles.where((f) {
      final q = _search.trim().toLowerCase();
      if (q.isEmpty) return true;
      return ('${f.originalName} ${f.clientName} ${f.clientEmail} ${f.businessName}')
          .toLowerCase()
          .contains(q);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReadyFilesPanel(
          files: _readyFiles,
          formatSize: _formatSize,
          onConfirm: _selectedFileCount == 0 || _submitting
              ? null
              : _confirmFiles,
          onClearAll: _selectedFileCount == 0 || _submitting
              ? null
              : () => setState(() {
                  _selectedFileKeys.clear();
                  _deviceFiles.clear();
                  _filesConfirmed = false;
                }),
          confirmed: _filesComplete,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: _submitting ? null : _chooseFileBox,
              icon: const Icon(Icons.inventory_2_outlined, size: 16),
              label: Text(
                _source == 'fileBox'
                    ? 'Refresh File Box'
                    : 'Choose from File Box',
              ),
            ),
            OutlinedButton.icon(
              onPressed: _submitting ? null : _chooseDevice,
              icon: const Icon(Icons.upload_file_outlined, size: 16),
              label: const Text('Upload from device'),
            ),
            if (_source == 'fileBox')
              TextButton.icon(
                onPressed: _submitting ? null : _changeSource,
                icon: const Icon(Icons.keyboard_arrow_up_outlined, size: 17),
                label: const Text('Hide File Box'),
              ),
          ],
        ),
        if (_source != 'fileBox') ...[
          const SizedBox(height: 12),
          _FileDropZone(
            dragging: _draggingFiles,
            enabled: !_submitting,
            onChooseFiles: _chooseDevice,
            onDragEntered: () => setState(() => _draggingFiles = true),
            onDragExited: () => setState(() => _draggingFiles = false),
            onDropped: (details) async {
              setState(() => _draggingFiles = false);
              await _handleDroppedFiles(details);
            },
          ),
        ],
        if (_source == 'fileBox') ...[
          const SizedBox(height: 12),
          _FileBoxPickerPanel(
            searchController: _searchCtrl,
            search: _search,
            loading: _loadingFiles,
            files: filteredFiles,
            selectedKeys: _selectedFileKeys,
            submitting: _submitting,
            formatSize: _formatSize,
            onBack: _submitting ? null : _changeSource,
            onSearchChanged: (v) => setState(() => _search = v),
            onToggle: (file, selected) {
              setState(() {
                _filesConfirmed = false;
                if (selected) {
                  _selectedFileKeys.add(file.key);
                } else {
                  _selectedFileKeys.remove(file.key);
                }
              });
            },
          ),
        ],
      ],
    );
  }

  Widget _buildClientSection() {
    final suggestions = _clientSuggestions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (suggestions.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: suggestions.map((client) {
              final label = client.name.isNotEmpty ? client.name : client.email;
              return ActionChip(
                avatar: const Icon(Icons.person_outline, size: 16),
                label: Text(label),
                onPressed: _submitting
                    ? null
                    : () => setState(() {
                        _nameCtrl.text = client.name;
                        _emailCtrl.text = client.email;
                      }),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
        ],
        TextFormField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Client or company name',
            prefixIcon: Icon(Icons.business_outlined),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _emailCtrl,
          focusNode: _emailFocusNode,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'Client email',
            helperText: _sendEmail
                ? 'Required for email delivery.'
                : 'Optional unless emailing the secure files.',
            errorText: _showValidationHints && _sendEmail && !_clientEmailValid
                ? 'Enter a valid email address to send directly.'
                : null,
            prefixIcon: const Icon(Icons.mail_outline),
          ),
          validator: (v) {
            final value = (v ?? '').trim();
            if (_sendEmail && !value.contains('@')) {
              return 'Enter a valid email or turn off email sending.';
            }
            return null;
          },
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildSecuritySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          value: _passwordRequired,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'Require password to open link',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: const Text('Recommended for client files.'),
          onChanged: _submitting
              ? null
              : (v) => setState(() {
                  _passwordRequired = v == true;
                  if (!_passwordRequired) {
                    _passwordCtrl.clear();
                    _confirmPasswordCtrl.clear();
                  }
                }),
        ),
        if (_passwordRequired) ...[
          const SizedBox(height: 8),
          TextFormField(
            controller: _passwordCtrl,
            obscureText: _obscurePassword,
            onChanged: (_) {
              setState(() {});
              if (_confirmPasswordCtrl.text.isNotEmpty) {
                _formKey.currentState?.validate();
              }
            },
            decoration: InputDecoration(
              labelText: 'Password',
              helperText: 'Share this password with the client separately.',
              prefixIcon: const Icon(Icons.key_outlined),
              suffixIcon: IconButton(
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: (v) {
              if (!_passwordRequired) return null;
              if ((v ?? '').trim().length < 6) {
                return 'Use at least 6 characters.';
              }
              return null;
            },
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _confirmPasswordCtrl,
            obscureText: _obscureConfirmPassword,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Confirm password',
              prefixIcon: const Icon(Icons.verified_user_outlined),
              suffixIcon: IconButton(
                tooltip: _obscureConfirmPassword
                    ? 'Show confirmation'
                    : 'Hide confirmation',
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(
                  () => _obscureConfirmPassword = !_obscureConfirmPassword,
                ),
              ),
            ),
            validator: (v) {
              if (!_passwordRequired) return null;
              final password = _passwordCtrl.text.trim();
              final confirm = (v ?? '').trim();
              if (confirm.isEmpty) return 'Re-enter the password.';
              if (confirm != password) return 'Passwords do not match.';
              return null;
            },
          ),
        ],
        const SizedBox(height: 14),
        const Text(
          'Expiration',
          style: TextStyle(
            color: Color(0xFF344054),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [1, 7, 14, 30].map(_dayChip).toList(),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _submitting ? null : _pickCustomExpiration,
          icon: const Icon(Icons.calendar_month_outlined, size: 16),
          label: Text(
            _customExpiresAt == null
                ? 'Custom date and time'
                : 'Custom: $_expirationLabel',
          ),
        ),
        if (_expirationError != null) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.error_outline,
                size: 16,
                color: Color(0xFFB42318),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _expirationError!,
                  style: const TextStyle(
                    color: Color(0xFFB42318),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildDeliverySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DeliveryChoiceTile(
          selected: _sendEmail,
          icon: Icons.outgoing_mail,
          title: 'Email secure files to client',
          subtitle:
              'Send the secure link to the client. The password is never included.',
          onTap: _submitting
              ? null
              : () => setState(() {
                  _sendEmail = true;
                  _createLinkOnly = false;
                }),
        ),
        const SizedBox(height: 8),
        _DeliveryChoiceTile(
          selected: _createLinkOnly,
          icon: Icons.link_outlined,
          title: 'Create secure link only',
          subtitle: 'Create the link now and copy it after creation.',
          onTap: _submitting
              ? null
              : () => setState(() {
                  _createLinkOnly = true;
                  _sendEmail = false;
                }),
        ),
        const SizedBox(height: 8),
        _DeliveryNote(passwordRequired: _passwordRequired),
        const SizedBox(height: 14),
        CheckboxListTile(
          value: _includeMessage,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'Include message template',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: const Text(
            'Optional. Choose a template or write a custom note.',
          ),
          onChanged: _submitting
              ? null
              : (v) => setState(() => _includeMessage = v == true),
        ),
        if (_includeMessage) ...[
          const SizedBox(height: 8),
          _buildMessageSection(),
        ] else ...[
          const SizedBox(height: 4),
          const Text(
            'No client message included.',
            style: TextStyle(
              color: Color(0xFF667085),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMessageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Message template',
          style: TextStyle(
            color: Color(0xFF344054),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _shareMessageTemplates.map((template) {
            final selected = _selectedTemplateId == template.id;
            return ChoiceChip(
              label: Text(template.title),
              selected: selected,
              showCheckmark: false,
              selectedColor: const Color(0xFFEAF2FF),
              backgroundColor: const Color(0xFFF9FAFB),
              side: BorderSide(
                color: selected ? AppColors.brandBlue : const Color(0xFFE4E7EC),
              ),
              labelStyle: TextStyle(
                color: selected ? AppColors.brandBlue : const Color(0xFF667085),
                fontWeight: FontWeight.w800,
              ),
              onSelected: _submitting
                  ? null
                  : (_) => setState(() {
                      _selectedTemplateId = template.id;
                      _messageCtrl.text = _applyShareTemplateTokens(
                        template.body,
                        _nameCtrl.text,
                      );
                    }),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _messageCtrl,
          minLines: 4,
          maxLines: 7,
          decoration: InputDecoration(
            labelText: 'Message',
            prefixIcon: const Icon(Icons.notes_outlined),
            suffixIcon: _messageCtrl.text.trim().isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear message',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() {
                      _selectedTemplateId = null;
                      _messageCtrl.clear();
                    }),
                  ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 6),
        Text(
          _messageCtrl.text.trim().isEmpty
              ? 'Message optional - no client message included.'
              : 'Message will be included with the secure link.',
          style: const TextStyle(
            color: Color(0xFF667085),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _dayChip(int days) {
    final selected = _expirationDays == days;
    return ChoiceChip(
      label: Text(days == 1 ? '1 day' : '$days days'),
      selected: selected,
      showCheckmark: false,
      selectedColor: const Color(0xFFEAF2FF),
      backgroundColor: const Color(0xFFF9FAFB),
      side: BorderSide(
        color: selected ? AppColors.brandBlue : const Color(0xFFE4E7EC),
      ),
      labelStyle: TextStyle(
        color: selected ? AppColors.brandBlue : const Color(0xFF667085),
        fontWeight: FontWeight.w800,
      ),
      onSelected: _submitting
          ? null
          : (_) => setState(() {
              _expirationDays = days;
              _customExpiresAt = null;
              _expirationError = null;
            }),
    );
  }

  Widget _buildSummary(ThemeData theme) {
    final files = _readyFiles;
    final client = _nameCtrl.text.trim().isNotEmpty
        ? _nameCtrl.text.trim()
        : (_emailCtrl.text.trim().isNotEmpty ? _emailCtrl.text.trim() : '-');
    final issues = _reviewIssues;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE4E7EC)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.fact_check_outlined,
                size: 18,
                color: AppColors.brandBlue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Review before sending',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF101828),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_showValidationHints && issues.isNotEmpty)
            _ReviewWarnings(items: issues)
          else if (issues.isNotEmpty)
            const _ReviewPendingNotice()
          else
            const _ReviewReadyNotice(),
          const SizedBox(height: 12),
          _SecuritySummaryLine(
            passwordRequired: _passwordRequired,
            expirationLabel: _expirationLabel,
          ),
          const SizedBox(height: 10),
          _ClientFacingPreview(
            client: client,
            fileCount: files.length,
            expirationLabel: _expirationLabel,
            deliveryLabel: _sendEmail
                ? 'Email will be sent'
                : 'Copy link after creation',
          ),
          const SizedBox(height: 12),
          _SummaryRow(label: 'Files', value: '${files.length} selected'),
          _SummaryRow(label: 'Client', value: client),
          if (_emailCtrl.text.trim().isNotEmpty)
            _SummaryRow(label: 'Email', value: _emailCtrl.text.trim()),
          _SummaryRow(
            label: 'Access',
            value: _passwordRequired ? 'Password' : 'No password',
          ),
          _SummaryRow(label: 'Expires', value: _expirationLabel),
          _SummaryRow(label: 'Delivery', value: _deliverySectionStatus),
          if (files.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFE4E7EC)),
            const SizedBox(height: 12),
            Text(
              'Prepared files',
              style: theme.textTheme.labelMedium?.copyWith(
                color: const Color(0xFF344054),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: files.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: Color(0xFFE4E7EC)),
                itemBuilder: (context, index) {
                  final file = files[index];
                  return _SummaryFileRow(file: file, formatSize: _formatSize);
                },
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _finish,
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _readyToCreate ? Icons.lock_outline : Icons.error_outline,
                      size: 16,
                    ),
              label: Text(
                _readyToCreate ? 'Create secure link' : 'Review required items',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SetupProgressStrip extends StatelessWidget {
  const _SetupProgressStrip({required this.steps});

  final List<_ProgressStepState> steps;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE4E7EC)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: steps.map((step) => _ProgressStepChip(step: step)).toList(),
      ),
    );
  }
}

class _ProgressStepChip extends StatelessWidget {
  const _ProgressStepChip({required this.step});

  final _ProgressStepState step;

  @override
  Widget build(BuildContext context) {
    final color = step.attention
        ? const Color(0xFFB42318)
        : step.complete
        ? const Color(0xFF067647)
        : step.optional
        ? const Color(0xFF667085)
        : AppColors.brandBlue;
    final bg = step.attention
        ? const Color(0xFFFFF6F5)
        : step.complete
        ? const Color(0xFFF6FEF9)
        : step.optional
        ? const Color(0xFFF9FAFB)
        : const Color(0xFFEAF2FF);
    final border = step.attention
        ? const Color(0xFFFDA29B)
        : step.complete
        ? const Color(0xFFABEFC6)
        : const Color(0xFFE4E7EC);
    final icon = step.attention
        ? Icons.error_outline
        : step.complete
        ? Icons.check_circle_outline
        : step.optional
        ? Icons.radio_button_unchecked
        : Icons.circle_outlined;

    return InkWell(
      onTap: step.onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(
              step.optional ? '${step.label} optional' : step.label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressStepState {
  const _ProgressStepState({
    required this.label,
    required this.complete,
    required this.attention,
    required this.onTap,
    this.optional = false,
  });

  final String label;
  final bool complete;
  final bool attention;
  final bool optional;
  final VoidCallback onTap;
}

class _SectionShell extends StatelessWidget {
  const _SectionShell({
    required this.title,
    required this.icon,
    required this.child,
    required this.step,
    required this.expanded,
    required this.completed,
    required this.attention,
    required this.onTap,
    this.trailing,
    this.subtitle,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final int step;
  final bool expanded;
  final bool completed;
  final bool attention;
  final VoidCallback onTap;
  final String? trailing;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = attention
        ? const Color(0xFFFDA29B)
        : completed
        ? const Color(0xFFABEFC6)
        : expanded
        ? AppColors.brandBlue.withValues(alpha: 0.45)
        : const Color(0xFFE4E7EC);
    final headerColor = attention
        ? const Color(0xFFFFF6F5)
        : completed
        ? const Color(0xFFF6FEF9)
        : expanded
        ? const Color(0xFFF6F9FF)
        : Colors.white;
    final accentColor = attention
        ? const Color(0xFFD92D20)
        : completed
        ? const Color(0xFF067647)
        : expanded
        ? AppColors.brandBlue
        : const Color(0xFF98A2B3);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: headerColor,
            child: InkWell(
              onTap: onTap,
              child: Row(
                children: [
                  Container(width: 3, height: 52, color: accentColor),
                  const SizedBox(width: 11),
                  _StepBadge(
                    step: step,
                    active: expanded,
                    completed: completed,
                    attention: attention,
                  ),
                  const SizedBox(width: 10),
                  Icon(icon, size: 18, color: accentColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: const Color(0xFF253858),
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (subtitle != null &&
                            subtitle!.trim().isNotEmpty) ...[
                          const SizedBox(height: 1),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF667085),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 14, left: 10),
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 190),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: completed
                              ? const Color(0xFFECFDF3)
                              : attention
                              ? const Color(0xFFFFEDEA)
                              : Colors.white,
                          border: Border.all(
                            color: completed
                                ? const Color(0xFFABEFC6)
                                : attention
                                ? const Color(0xFFFDA29B)
                                : const Color(0xFFE4E7EC),
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          trailing!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: completed
                                ? const Color(0xFF067647)
                                : attention
                                ? const Color(0xFFB42318)
                                : const Color(0xFF475467),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: const Color(0xFF667085),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 160),
            firstCurve: Curves.easeOutCubic,
            secondCurve: Curves.easeOutCubic,
            sizeCurve: Curves.easeOutCubic,
            crossFadeState: expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Divider(height: 1, color: Color(0xFFE4E7EC)),
                Padding(padding: const EdgeInsets.all(14), child: child),
              ],
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _StepBadge extends StatelessWidget {
  const _StepBadge({
    required this.step,
    required this.active,
    required this.completed,
    required this.attention,
  });

  final int step;
  final bool active;
  final bool completed;
  final bool attention;

  @override
  Widget build(BuildContext context) {
    final bg = attention
        ? const Color(0xFFFFEDEA)
        : completed
        ? const Color(0xFF067647)
        : active
        ? const Color(0xFFEAF2FF)
        : const Color(0xFFF2F4F7);
    final border = attention
        ? const Color(0xFFD92D20)
        : completed
        ? const Color(0xFF067647)
        : active
        ? AppColors.brandBlue
        : const Color(0xFFD0D5DD);
    final fg = attention
        ? const Color(0xFFD92D20)
        : completed || active
        ? AppColors.brandBlue
        : const Color(0xFF475467);

    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      alignment: Alignment.center,
      child: attention
          ? const Icon(Icons.error_outline, color: Color(0xFFD92D20), size: 14)
          : completed
          ? const Icon(Icons.check, color: Colors.white, size: 14)
          : Text(
              '$step',
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
    );
  }
}

class _ReadyFilesPanel extends StatelessWidget {
  const _ReadyFilesPanel({
    required this.files,
    required this.formatSize,
    required this.onConfirm,
    required this.onClearAll,
    required this.confirmed,
  });

  final List<_SelectedShareFile> files;
  final String Function(int bytes) formatSize;
  final VoidCallback? onConfirm;
  final VoidCallback? onClearAll;
  final bool confirmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFiles = files.isNotEmpty;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: confirmed ? const Color(0xFFF6FEF9) : const Color(0xFFF9FAFB),
        border: Border.all(
          color: confirmed ? const Color(0xFFABEFC6) : const Color(0xFFE4E7EC),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Icon(
                  confirmed
                      ? Icons.check_circle_outline
                      : Icons.outbox_outlined,
                  size: 18,
                  color: confirmed
                      ? const Color(0xFF067647)
                      : AppColors.brandBlue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasFiles ? 'Ready to send' : 'No files selected',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: const Color(0xFF253858),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (hasFiles)
                  Text(
                    '${files.length} file${files.length == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF667085),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          ),
          if (hasFiles) ...[
            const Divider(height: 1, color: Color(0xFFE4E7EC)),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: files.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: Color(0xFFE4E7EC)),
                itemBuilder: (context, index) {
                  final file = files[index];
                  final meta = resolveFileMeta(
                    fileName: file.name,
                    contentType: file.contentType,
                  );
                  return ListTile(
                    dense: true,
                    leading: Icon(meta.icon, color: meta.color, size: 20),
                    title: Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(formatSize(file.sizeBytes)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _SourcePill(label: file.sourceLabel),
                        const SizedBox(width: 4),
                        if (file.onPreview != null)
                          IconButton(
                            tooltip: 'Preview',
                            icon: const Icon(
                              Icons.visibility_outlined,
                              size: 18,
                            ),
                            onPressed: file.onPreview,
                          ),
                        IconButton(
                          tooltip: 'Remove file',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: file.onRemove,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE4E7EC)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  TextButton(onPressed: onClearAll, child: const Text('Clear')),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: onConfirm,
                    icon: const Icon(Icons.check_outlined, size: 16),
                    label: Text(confirmed ? 'Files confirmed' : 'Use files'),
                  ),
                ],
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Choose from File Box, upload from device, or use both.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF667085),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SourcePill extends StatelessWidget {
  const _SourcePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final isUpload = label.toLowerCase().contains('upload');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isUpload ? const Color(0xFFFFFAEB) : const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isUpload ? const Color(0xFFFEDF89) : const Color(0xFFD6E8FF),
        ),
      ),
      child: Text(
        isUpload ? 'Uploaded from device' : 'File Box',
        style: TextStyle(
          color: isUpload ? const Color(0xFFB54708) : AppColors.brandBlue,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _FileDropZone extends StatelessWidget {
  const _FileDropZone({
    required this.dragging,
    required this.enabled,
    required this.onChooseFiles,
    required this.onDragEntered,
    required this.onDragExited,
    required this.onDropped,
  });

  final bool dragging;
  final bool enabled;
  final VoidCallback onChooseFiles;
  final VoidCallback onDragEntered;
  final VoidCallback onDragExited;
  final Future<void> Function(DropDoneDetails details) onDropped;

  @override
  Widget build(BuildContext context) {
    final color = dragging ? AppColors.brandBlue : const Color(0xFFD0D5DD);
    return DropTarget(
      onDragEntered: (_) {
        if (enabled) onDragEntered();
      },
      onDragExited: (_) {
        if (enabled) onDragExited();
      },
      onDragDone: enabled ? (details) => onDropped(details) : null,
      child: InkWell(
        onTap: enabled ? onChooseFiles : null,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
          decoration: BoxDecoration(
            color: dragging ? const Color(0xFFEAF2FF) : const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color, width: dragging ? 1.4 : 1),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE4E7EC)),
                ),
                child: Icon(
                  Icons.cloud_upload_outlined,
                  color: dragging
                      ? AppColors.brandBlue
                      : const Color(0xFF475467),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Drop files here',
                      style: TextStyle(
                        color: Color(0xFF253858),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Or click to upload from your device.',
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
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
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
}

class _FileBoxPickerPanel extends StatelessWidget {
  const _FileBoxPickerPanel({
    required this.searchController,
    required this.search,
    required this.loading,
    required this.files,
    required this.selectedKeys,
    required this.submitting,
    required this.formatSize,
    required this.onBack,
    required this.onSearchChanged,
    required this.onToggle,
  });

  final TextEditingController searchController;
  final String search;
  final bool loading;
  final List<_ShareableFile> files;
  final Set<String> selectedKeys;
  final bool submitting;
  final String Function(int bytes) formatSize;
  final VoidCallback? onBack;
  final ValueChanged<String> onSearchChanged;
  final void Function(_ShareableFile file, bool selected) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE4E7EC)),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            color: const Color(0xFFF9FAFB),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('Change source'),
                ),
                const Spacer(),
                Text(
                  selectedKeys.isEmpty
                      ? 'Select files below'
                      : '${selectedKeys.length} in queue',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF475467),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE4E7EC)),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: searchController,
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: search.trim().isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          searchController.clear();
                          onSearchChanged('');
                        },
                      ),
                hintText: 'Search files, clients, or businesses',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE4E7EC)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE4E7EC)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.brandBlue),
                ),
              ),
            ),
          ),
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            color: const Color(0xFFF9FAFB),
            child: Row(
              children: const [
                SizedBox(width: 34),
                Expanded(child: _PickerHeaderText('Name')),
                SizedBox(width: 112, child: _PickerHeaderText('Client')),
                SizedBox(width: 72, child: _PickerHeaderText('Size')),
                SizedBox(width: 44),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE4E7EC)),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: loading
                ? const _FileBoxPickerLoading()
                : files.isEmpty
                ? _FileBoxPickerEmpty(search: search)
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: files.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: Color(0xFFE4E7EC)),
                    itemBuilder: (context, index) {
                      final file = files[index];
                      final selected = selectedKeys.contains(file.key);
                      return _FileBoxPickerRow(
                        file: file,
                        selected: selected,
                        submitting: submitting,
                        formatSize: formatSize,
                        onToggle: (value) => onToggle(file, value),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _FileBoxPickerRow extends StatelessWidget {
  const _FileBoxPickerRow({
    required this.file,
    required this.selected,
    required this.submitting,
    required this.formatSize,
    required this.onToggle,
  });

  final _ShareableFile file;
  final bool selected;
  final bool submitting;
  final String Function(int bytes) formatSize;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final businessOrEmail = file.businessName.isNotEmpty
        ? file.businessName
        : file.clientEmail;
    return Material(
      color: selected ? const Color(0xFFF6F9FF) : Colors.white,
      child: InkWell(
        onTap: submitting ? null : () => onToggle(!selected),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              _FileKindTile(
                fileName: file.originalName,
                contentType: file.contentType,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.originalName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF101828),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      businessOrEmail.isEmpty ? 'File Box' : businessOrEmail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF667085),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 112,
                child: Text(
                  file.clientName.isEmpty ? '-' : file.clientName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF475467),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                width: 72,
                child: Text(
                  formatSize(file.sizeBytes),
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF667085),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                width: 44,
                child: Checkbox(
                  value: selected,
                  onChanged: submitting
                      ? null
                      : (value) => onToggle(value == true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileKindTile extends StatelessWidget {
  const _FileKindTile({required this.fileName, required this.contentType});

  final String fileName;
  final String contentType;

  @override
  Widget build(BuildContext context) {
    final meta = resolveFileMeta(fileName: fileName, contentType: contentType);
    return Tooltip(
      message: meta.tooltip,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: meta.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        ),
        alignment: Alignment.center,
        child: Icon(meta.icon, size: 16, color: meta.color),
      ),
    );
  }
}

class _PickerHeaderText extends StatelessWidget {
  const _PickerHeaderText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: const Color(0xFF667085),
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _FileBoxPickerLoading extends StatelessWidget {
  const _FileBoxPickerLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text(
            'Loading File Box files...',
            style: TextStyle(
              color: Color(0xFF667085),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FileBoxPickerEmpty extends StatelessWidget {
  const _FileBoxPickerEmpty({required this.search});

  final String search;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.search_off_outlined, color: Color(0xFF98A2B3)),
          const SizedBox(height: 8),
          Text(
            search.trim().isEmpty
                ? 'No files available.'
                : 'No matching files.',
            style: const TextStyle(
              color: Color(0xFF475467),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            'Try a different search or upload from your device.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF667085),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryNote extends StatelessWidget {
  const _DeliveryNote({required this.passwordRequired});

  final bool passwordRequired;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        border: Border.all(color: const Color(0xFFE4E7EC)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 17, color: Color(0xFF667085)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              passwordRequired
                  ? 'For security, send the password through a separate channel such as phone or a separate email.'
                  : 'This link can be opened without a password until it expires or is revoked.',
              style: const TextStyle(
                color: Color(0xFF667085),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryChoiceTile extends StatelessWidget {
  const _DeliveryChoiceTile({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF6FEF9) : const Color(0xFFF9FAFB),
          border: Border.all(
            color: selected ? const Color(0xFFABEFC6) : const Color(0xFFE4E7EC),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.check_circle_outline : icon,
              size: 20,
              color: selected ? const Color(0xFF067647) : AppColors.brandBlue,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF253858),
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
      ),
    );
  }
}

class _ReviewWarnings extends StatelessWidget {
  const _ReviewWarnings({required this.items});

  final List<_ReviewIssue> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6F5),
        border: Border.all(color: const Color(0xFFFDA29B)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.error_outline, size: 17, color: Color(0xFFB42318)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Required before sending',
                  style: TextStyle(
                    color: Color(0xFFB42318),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  const SizedBox(width: 25),
                  Expanded(
                    child: Text(
                      item.message,
                      style: const TextStyle(
                        color: Color(0xFF912018),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: item.onTap,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFB42318),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    child: Text(item.actionLabel),
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

class _SecuritySummaryLine extends StatelessWidget {
  const _SecuritySummaryLine({
    required this.passwordRequired,
    required this.expirationLabel,
  });

  final bool passwordRequired;
  final String expirationLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        border: Border.all(color: const Color(0xFFE4E7EC)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.shield_outlined,
            size: 16,
            color: AppColors.brandBlue,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${passwordRequired ? 'Password required' : 'No password'} - Expires $expirationLabel',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF344054),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientFacingPreview extends StatelessWidget {
  const _ClientFacingPreview({
    required this.client,
    required this.fileCount,
    required this.expirationLabel,
    required this.deliveryLabel,
  });

  final String client;
  final int fileCount;
  final String expirationLabel;
  final String deliveryLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F9FF),
        border: Border.all(color: const Color(0xFFD6E8FF)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Client-facing preview',
            style: TextStyle(
              color: Color(0xFF253858),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          _PreviewLine(
            label: 'Recipient',
            value: client == '-' ? 'Not set' : client,
          ),
          _PreviewLine(
            label: 'Files',
            value: '$fileCount file${fileCount == 1 ? '' : 's'}',
          ),
          _PreviewLine(label: 'Expires', value: expirationLabel),
          _PreviewLine(label: 'Delivery', value: deliveryLabel),
        ],
      ),
    );
  }
}

class _PreviewLine extends StatelessWidget {
  const _PreviewLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF667085),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF253858),
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewReadyNotice extends StatelessWidget {
  const _ReviewReadyNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6FEF9),
        border: Border.all(color: const Color(0xFFABEFC6)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle_outline, size: 17, color: Color(0xFF067647)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Ready to create secure link',
              style: TextStyle(
                color: Color(0xFF067647),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewPendingNotice extends StatelessWidget {
  const _ReviewPendingNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        border: Border.all(color: const Color(0xFFE4E7EC)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, size: 17, color: Color(0xFF667085)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Complete the setup sections, then review before creating the link.',
              style: TextStyle(
                color: Color(0xFF667085),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryFileRow extends StatelessWidget {
  const _SummaryFileRow({required this.file, required this.formatSize});

  final _SelectedShareFile file;
  final String Function(int bytes) formatSize;

  @override
  Widget build(BuildContext context) {
    final meta = resolveFileMeta(
      fileName: file.name,
      contentType: file.contentType,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(meta.icon, color: meta.color, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF253858),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _SourcePill(label: file.sourceLabel),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        formatSize(file.sizeBytes),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF667085),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 78,
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
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF101828),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessPanel extends StatelessWidget {
  const _SuccessPanel({
    required this.url,
    required this.sendEmail,
    required this.onCopy,
    required this.onDone,
    required this.onCreateAnother,
  });

  final String url;
  final bool sendEmail;
  final VoidCallback onCopy;
  final VoidCallback onDone;
  final VoidCallback onCreateAnother;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE4E7EC)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_user_outlined, color: AppColors.brandBlue),
          const SizedBox(height: 12),
          Text(
            sendEmail
                ? 'The secure link was emailed to the client.'
                : 'Copy this secure link and provide the password separately.',
            style: const TextStyle(
              color: Color(0xFF475467),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          SelectableText(url),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy link'),
              ),
              OutlinedButton.icon(
                onPressed: onCreateAnother,
                icon: const Icon(Icons.add_link_outlined, size: 16),
                label: const Text('Create another'),
              ),
              TextButton(onPressed: onDone, child: const Text('Sent files')),
            ],
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

class _ClientSuggestion {
  const _ClientSuggestion({required this.name, required this.email});

  final String name;
  final String email;
}

class _ReviewIssue {
  const _ReviewIssue({
    required this.message,
    required this.actionLabel,
    required this.onTap,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onTap;
}

class _SelectedShareFile {
  const _SelectedShareFile({
    required this.key,
    required this.name,
    required this.contentType,
    required this.sizeBytes,
    required this.sourceLabel,
    required this.onPreview,
    required this.onRemove,
  });

  final String key;
  final String name;
  final String contentType;
  final int sizeBytes;
  final String sourceLabel;
  final VoidCallback? onPreview;
  final VoidCallback onRemove;
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
