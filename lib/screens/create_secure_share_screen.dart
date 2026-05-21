import 'dart:typed_data';

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
  final _accessNoteCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _clientSearchCtrl = TextEditingController();
  final _customDateCtrl = TextEditingController();
  final _customTimeCtrl = TextEditingController();
  final _emailFocusNode = FocusNode();

  String _source = '';
  int _expirationDays = 7;
  DateTime? _customExpiresAt;
  bool _sendEmail = true;
  bool _createLinkOnly = false;
  bool _includeMessage = true;
  bool _submitting = false;
  bool _loadingFiles = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _filesConfirmed = false;
  bool _showValidationHints = false;
  bool _passwordRequired = true;
  bool _detailsProtected = true;
  bool _notifyOnFirstDownload = false;
  bool _draggingFiles = false;
  bool _showCustomExpiration = false;
  String _customPeriod = 'PM';
  String? _selectedTemplateId = 'secure_delivery';
  String _search = '';
  String _clientSearch = '';
  String? _expirationError;
  String? _createdUrl;
  int _currentStep = 0;

  static const String _defaultAccessNote =
      'Use the password provided separately by our office.';

  final Set<int> _expandedSteps = {0};
  final Set<int> _attentionSteps = {};
  List<_ShareableFile> _availableFiles = const [];
  final Set<String> _selectedFileKeys = {};
  final List<_DeviceShareFile> _deviceFiles = [];

  List<_ShareMessageTemplate> get _shareMessageTemplates => const [
    _ShareMessageTemplate(
      id: 'secure_delivery',
      title: 'Files sent to you',
      body:
          'Dear {{clientFirstName}},\n\n'
          'Your files are available below. Please review and download a copy for your records.\n\n'
          'Best regards,\n'
          'Axume & Associates CPAs',
    ),
    _ShareMessageTemplate(
      id: 'tax_documents',
      title: 'Tax documents',
      body:
          'Dear {{clientFirstName}},\n\n'
          'Documents related to your tax file are available below. Please review and download a copy for your records.\n\n'
          'Best regards,\n'
          'Axume & Associates CPAs',
    ),
    _ShareMessageTemplate(
      id: 'review_and_download',
      title: 'Review and download',
      body:
          'Dear {{clientFirstName}},\n\n'
          'The requested files are ready for your review. Please download a copy for your records.\n\n'
          'Best regards,\n'
          'Axume & Associates CPAs',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _restoreCreateDefaults(clearClient: false, clearFiles: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _chooseFileBox();
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _accessNoteCtrl.dispose();
    _messageCtrl.dispose();
    _searchCtrl.dispose();
    _clientSearchCtrl.dispose();
    _customDateCtrl.dispose();
    _customTimeCtrl.dispose();
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

  void _syncMessageTemplateForClient() {
    if (!_includeMessage || _selectedTemplateId == null) return;
    final template = _shareMessageTemplates.where(
      (template) => template.id == _selectedTemplateId,
    );
    if (template.isEmpty) return;
    _messageCtrl.text = _applyShareTemplateTokens(
      template.first.body,
      _nameCtrl.text,
    );
  }

  void _restoreCreateDefaults({
    required bool clearClient,
    required bool clearFiles,
  }) {
    _source = '';
    if (clearFiles) {
      _selectedFileKeys.clear();
      _deviceFiles.clear();
      _availableFiles = const [];
      _filesConfirmed = false;
    }
    if (clearClient) {
      _emailCtrl.clear();
      _nameCtrl.clear();
      _clientSearchCtrl.clear();
      _clientSearch = '';
    }
    _messageCtrl.clear();
    _passwordCtrl.clear();
    _confirmPasswordCtrl.clear();
    _accessNoteCtrl.text = _defaultAccessNote;
    _selectedTemplateId = 'secure_delivery';
    _sendEmail = true;
    _createLinkOnly = false;
    _includeMessage = true;
    _expirationDays = 7;
    _customExpiresAt = null;
    _expirationError = null;
    _customDateCtrl.clear();
    _customTimeCtrl.clear();
    _customPeriod = 'PM';
    _showCustomExpiration = false;
    _showValidationHints = false;
    _passwordRequired = true;
    _detailsProtected = true;
    _currentStep = 0;
    _attentionSteps.clear();
    _expandedSteps
      ..clear()
      ..add(0);
    _syncMessageTemplateForClient();
  }

  Future<List<_ShareableFile>> _loadShareableFiles() async {
    final res = await _functions.httpsCallable('listShareableFiles').call();
    final data = Map<String, dynamic>.from(res.data as Map);
    final raw = (data['files'] is List) ? data['files'] as List : [];
    return raw
        .map((f) => _ShareableFile.fromMap(Map<String, dynamic>.from(f)))
        .toList();
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

  Future<List<_DeviceShareFile>> _pickDeviceFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      withReadStream: true,
    );
    if (result == null) return const [];

    final files = <_DeviceShareFile>[];
    var unreadableCount = 0;

    for (final f in result.files) {
      final bytes = await _readPlatformFileBytes(f);
      if (bytes == null || bytes.isEmpty) {
        unreadableCount++;
        continue;
      }

      files.add(
        _DeviceShareFile(
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
    setState(() {
      _showValidationHints = true;
      _attentionSteps
        ..clear()
        ..addAll({
          if (!_filesComplete) 0,
          if (!_clientComplete) 1,
          if (!_securityComplete) 2,
          if (!_deliveryComplete) 3,
        });
    });

    if (_selectedFileCount == 0) {
      _markStepAttention(0);
      _openStep(0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one file.')),
      );
      return;
    }

    if (!_clientComplete) {
      _markStepAttention(1);
      _openStep(1);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_clientValidationMessage)));
      return;
    }

    if (!_securityComplete) {
      _markStepAttention(2);
      _openStep(2);
      _formKey.currentState?.validate();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complete the security section.')),
      );
      return;
    }

    if (!_deliveryComplete) {
      _markStepAttention(3);
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
        'detailsProtected': _detailsProtected,
        'password': _passwordCtrl.text.trim(),
        'accessNote': _accessNoteCtrl.text.trim(),
        'message': _includeMessage ? _messageCtrl.text.trim() : '',
        'expirationDays': _expirationDays,
        if (_customExpiresAt != null)
          'expiresAtMillis': _customExpiresAt!.millisecondsSinceEpoch,
        'sendEmail': _sendEmail,
        'notifyOnFirstDownload': _notifyOnFirstDownload,
      });

      final data = Map<String, dynamic>.from(res.data as Map);
      final url = (data['url'] ?? '').toString();
      if (!mounted) return;
      setState(() => _createdUrl = url);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('File link created.')));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('File link failed: ${e.code} ${e.message ?? ''}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('File link failed: $e')));
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
      title: _createdUrl == null ? 'Send files' : 'File link ready',
      subtitle: _createdUrl == null
          ? 'Choose files, protect access, and prepare the client-facing message.'
          : 'Copy the file link or return to sent files.',
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
              icon: Icons.fact_check_outlined,
              label: 'Review',
              onPressed: _submitting ? null : () => _openStep(4),
              accent: true,
            ),
        ],
        overflowActions: const [],
      ),
      child: _createdUrl == null
          ? Form(
              key: _formKey,
              child: isNarrow
                  ? _buildMainWorkflow(theme)
                  : _buildMainWorkflow(theme),
            )
          : _SuccessPanel(
              url: _createdUrl!,
              sendEmail: _sendEmail,
              onCopy: () async {
                await Clipboard.setData(ClipboardData(text: _createdUrl!));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('File link copied.')),
                );
              },
              onDone: _backToSentFiles,
              onCreateAnother: () {
                setState(() {
                  _createdUrl = null;
                  _restoreCreateDefaults(clearClient: true, clearFiles: true);
                });
                _chooseFileBox();
              },
            ),
    );
  }

  Widget _buildMainWorkflow(ThemeData theme) {
    final activeStep = _activeStepShell(theme);
    return Column(
      children: [
        _SetupProgressStrip(
          steps: [
            _ProgressStepState(
              label: 'Files',
              active: _currentStep == 0,
              complete: _filesComplete,
              attention: _stepHasAttention(0),
              onTap: () => _openStep(0),
            ),
            _ProgressStepState(
              label: 'Client',
              active: _currentStep == 1,
              complete: _clientComplete,
              attention: _stepHasAttention(1),
              onTap: () => _openStep(1),
            ),
            _ProgressStepState(
              label: 'Security',
              active: _currentStep == 2,
              complete: _securityComplete,
              attention: _stepHasAttention(2),
              onTap: () => _openStep(2),
            ),
            _ProgressStepState(
              label: 'Delivery',
              active: _currentStep == 3,
              complete: _deliveryComplete,
              attention: _stepHasAttention(3),
              onTap: () => _openStep(3),
            ),
            _ProgressStepState(
              label: 'Review',
              active: _currentStep == 4,
              complete: _readyToCreate,
              attention: _stepHasAttention(4),
              onTap: () => _openStep(4),
            ),
          ],
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: KeyedSubtree(
            key: ValueKey<int>(_currentStep),
            child: activeStep,
          ),
        ),
        if (_currentStep != 4) ...[
          const SizedBox(height: 14),
          _WizardNavigationBar(
            backEnabled: _currentStep > 0 && !_submitting,
            primaryLabel: _wizardPrimaryLabel,
            primaryIcon: _wizardPrimaryIcon,
            submitting: _submitting,
            onBack: _currentStep > 0 ? _goBackOneStep : null,
            onPrimary: _continueFromCurrentStep,
          ),
        ],
      ],
    );
  }

  Widget _activeStepShell(ThemeData theme) {
    switch (_currentStep) {
      case 0:
        return _SectionShell(
          title: 'Files',
          subtitle: 'Select the files that will be available to the client.',
          icon: Icons.folder_outlined,
          step: 1,
          expanded: true,
          completed: _filesComplete,
          attention: _stepHasAttention(0),
          trailing: _filesComplete
              ? 'Files confirmed'
              : (_selectedFileCount > 0 ? _fileCountLabel : 'Required'),
          onTap: () {},
          showToggle: false,
          child: _buildFilesSection(theme),
        );
      case 1:
        return _SectionShell(
          title: 'Client',
          subtitle: 'Identify who this file link is for.',
          icon: Icons.badge_outlined,
          step: 2,
          expanded: true,
          completed: _clientComplete,
          attention: _stepHasAttention(1),
          trailing: _clientSectionStatus,
          onTap: () {},
          showToggle: false,
          child: _buildClientSection(),
        );
      case 2:
        return _SectionShell(
          title: 'Security',
          subtitle: 'Set password and expiration protection.',
          icon: Icons.shield_outlined,
          step: 3,
          expanded: true,
          completed: _securityComplete,
          attention: _stepHasAttention(2),
          trailing: _securitySectionStatus,
          onTap: () {},
          showToggle: false,
          child: _buildSecuritySection(),
        );
      case 3:
        return _SectionShell(
          title: 'Delivery',
          subtitle: 'Choose whether to email the link or create it only.',
          icon: Icons.send_outlined,
          step: 4,
          expanded: true,
          completed: _deliveryComplete,
          attention: _stepHasAttention(3),
          trailing: _deliverySectionStatus,
          onTap: () {},
          showToggle: false,
          child: _buildDeliverySection(),
        );
      default:
        return _buildSummary(theme);
    }
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

  bool _stepHasAttention(int step) {
    if (_attentionSteps.contains(step)) return true;
    if (!_showValidationHints) return false;
    switch (step) {
      case 0:
        return !_filesComplete;
      case 1:
        return !_clientComplete;
      case 2:
        return !_securityComplete;
      case 3:
        return !_deliveryComplete;
      case 4:
        return !_readyToCreate;
      default:
        return false;
    }
  }

  void _markStepAttention(int step) {
    setState(() => _attentionSteps.add(step));
  }

  void _clearStepAttention(int step) {
    if (!_attentionSteps.contains(step)) return;
    setState(() => _attentionSteps.remove(step));
  }

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

  String get _wizardPrimaryLabel {
    switch (_currentStep) {
      case 0:
        return 'Continue to client';
      case 1:
        return 'Continue to security';
      case 2:
        return 'Continue to delivery';
      case 3:
        return 'Review';
      default:
        return _sendEmail ? 'Send files' : 'Create link';
    }
  }

  IconData get _wizardPrimaryIcon {
    return _currentStep == 3 ? Icons.fact_check_outlined : Icons.arrow_forward;
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
      return '${loc.formatMediumDate(custom)} at ${loc.formatTimeOfDay(TimeOfDay.fromDateTime(custom))}';
    }
    return '$_expirationDays day${_expirationDays == 1 ? '' : 's'}';
  }

  String? get _customExpirationPreview {
    final custom = _customExpiresAt;
    if (custom == null) return null;
    final loc = MaterialLocalizations.of(context);
    final weekday = loc.formatFullDate(custom).split(',').first;
    return 'Expires $weekday, ${loc.formatMediumDate(custom)} at ${loc.formatTimeOfDay(TimeOfDay.fromDateTime(custom))}';
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
    final query = _clientSearch.trim().toLowerCase();
    for (final file in _availableFiles) {
      final name = file.clientName.trim();
      final email = file.clientEmail.trim();
      final businessName = file.businessName.trim();
      if (name.isEmpty && email.isEmpty) continue;
      final haystack = '$name $email $businessName'.toLowerCase();
      if (query.isNotEmpty && !haystack.contains(query)) continue;
      final key = '${name.toLowerCase()}|${email.toLowerCase()}';
      if (!seen.add(key)) continue;
      out.add(
        _ClientSuggestion(name: name, email: email, businessName: businessName),
      );
    }
    return out.take(8).toList();
  }

  void _selectClientSuggestion(_ClientSuggestion client) {
    setState(() {
      _nameCtrl.text = client.name.isNotEmpty
          ? client.name
          : client.businessName;
      _emailCtrl.text = client.email;
      _clientSearchCtrl.text = client.displayName;
      _clientSearch = client.displayName;
      _attentionSteps.remove(1);
      _syncMessageTemplateForClient();
    });
  }

  void _toggleStep(int step) {
    setState(() {
      _currentStep = step.clamp(0, 4).toInt();
      _expandedSteps
        ..clear()
        ..add(_currentStep.clamp(0, 3).toInt());
    });
  }

  void _openStep(int step) {
    setState(() {
      _currentStep = step.clamp(0, 4).toInt();
      _expandedSteps
        ..clear()
        ..add(_currentStep.clamp(0, 3).toInt());
    });
  }

  void _openAllSteps() {
    _openStep(4);
  }

  void _focusClientEmail() {
    _openStep(1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _emailFocusNode.requestFocus();
    });
  }

  void _goBackOneStep() {
    if (_currentStep <= 0) return;
    _openStep(_currentStep - 1);
  }

  void _continueFromCurrentStep() {
    switch (_currentStep) {
      case 0:
        if (_selectedFileCount == 0) {
          _markStepAttention(0);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Select at least one file.')),
          );
          return;
        }
        setState(() {
          _filesConfirmed = true;
          _attentionSteps.remove(0);
        });
        _openStep(1);
        return;
      case 1:
        if (!_clientHasIdentity) {
          _markStepAttention(1);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enter a client name or email.')),
          );
          return;
        }
        if (_sendEmail && !_clientEmailValid) {
          _markStepAttention(1);
          _focusClientEmail();
          return;
        }
        _clearStepAttention(1);
        _openStep(2);
        return;
      case 2:
        if (!(_formKey.currentState?.validate() ?? false) ||
            !_securityComplete) {
          _markStepAttention(2);
          return;
        }
        _clearStepAttention(2);
        _openStep(3);
        return;
      case 3:
        if (!_deliveryComplete) {
          _markStepAttention(3);
          if (_sendEmail && !_clientEmailValid) {
            _markStepAttention(1);
            _focusClientEmail();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Choose email delivery or link-only delivery.'),
              ),
            );
          }
          return;
        }
        _clearStepAttention(3);
        _openStep(4);
        return;
      default:
        _finish();
    }
  }

  void _syncCustomExpirationFromFields() {
    if (!_showCustomExpiration) {
      setState(() => _showCustomExpiration = true);
    }

    final dateText = _customDateCtrl.text.trim();
    final timeText = _customTimeCtrl.text.trim();

    if (dateText.isEmpty && timeText.isEmpty) {
      setState(() {
        _customExpiresAt = null;
        _expirationError = null;
      });
      return;
    }

    final parsed = _parseCustomExpiration(dateText, timeText, _customPeriod);
    if (parsed == null) {
      setState(() {
        _customExpiresAt = null;
        _expirationError = 'Enter a valid date and time.';
      });
      return;
    }

    if (!parsed.isAfter(DateTime.now())) {
      setState(() {
        _customExpiresAt = null;
        _expirationError = 'Expiration must be set to a future date and time.';
      });
      return;
    }

    setState(() {
      _customExpiresAt = parsed;
      _expirationError = null;
    });
  }

  DateTime? _parseCustomExpiration(String date, String time, String period) {
    final dateMatch = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(date);
    final timeMatch = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(time);
    if (dateMatch == null || timeMatch == null) return null;

    final month = int.tryParse(dateMatch.group(1)!);
    final day = int.tryParse(dateMatch.group(2)!);
    final year = int.tryParse(dateMatch.group(3)!);
    var hour = int.tryParse(timeMatch.group(1)!);
    final minute = int.tryParse(timeMatch.group(2)!);
    if (month == null ||
        day == null ||
        year == null ||
        hour == null ||
        minute == null) {
      return null;
    }
    if (hour < 1 || hour > 12 || minute < 0 || minute > 59) return null;

    if (period == 'PM' && hour != 12) hour += 12;
    if (period == 'AM' && hour == 12) hour = 0;

    final value = DateTime(year, month, day, hour, minute);
    if (value.year != year || value.month != month || value.day != day) {
      return null;
    }
    return value;
  }

  void _showCustomExpirationFields() {
    final base =
        _customExpiresAt ?? DateTime.now().add(Duration(days: _expirationDays));
    final hour12 = base.hour % 12 == 0 ? 12 : base.hour % 12;
    final period = base.hour >= 12 ? 'PM' : 'AM';

    setState(() {
      _showCustomExpiration = true;
      _customDateCtrl.text =
          '${base.month.toString().padLeft(2, '0')}/${base.day.toString().padLeft(2, '0')}/${base.year}';
      _customTimeCtrl.text =
          '$hour12:${base.minute.toString().padLeft(2, '0')}';
      _customPeriod = period;
      _expirationError = null;
    });
    _syncCustomExpirationFromFields();
  }

  void _setCustomExpirationTime(int hour, int minute, String period) {
    if (!_showCustomExpiration) {
      _showCustomExpirationFields();
    }

    setState(() {
      _customTimeCtrl.text = '$hour:${minute.toString().padLeft(2, '0')}';
      _customPeriod = period;
    });
    _syncCustomExpirationFromFields();
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
      _expandedSteps
        ..clear()
        ..add(0);
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

    final selectedPane = _ReadyFilesPanel(
      files: _readyFiles,
      formatSize: _formatSize,
      maxListHeight: 420,
      onConfirm: _selectedFileCount == 0 || _submitting ? null : _confirmFiles,
      onClearAll: _selectedFileCount == 0 || _submitting
          ? null
          : () => setState(() {
              _selectedFileKeys.clear();
              _deviceFiles.clear();
              _filesConfirmed = false;
            }),
      confirmed: _filesComplete,
    );

    final addFilesPane = _AddFilesPane(
      source: _source,
      loadingFiles: _loadingFiles,
      filteredFiles: filteredFiles,
      selectedFileKeys: _selectedFileKeys,
      submitting: _submitting,
      searchController: _searchCtrl,
      search: _search,
      formatSize: _formatSize,
      dragging: _draggingFiles,
      onChooseDevice: _chooseDevice,
      onChooseFileBox: _chooseFileBox,
      onHideFileBox: _changeSource,
      onDragEntered: () => setState(() => _draggingFiles = true),
      onDragExited: () => setState(() => _draggingFiles = false),
      onDropped: (details) async {
        setState(() => _draggingFiles = false);
        await _handleDroppedFiles(details);
      },
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
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoPane = constraints.maxWidth >= 900;
        if (!twoPane) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [addFilesPane, const SizedBox(height: 12), selectedPane],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 7, child: addFilesPane),
            const SizedBox(width: 14),
            Expanded(flex: 5, child: selectedPane),
          ],
        );
      },
    );
  }

  Widget _buildClientSection() {
    final suggestions = _clientSuggestions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _clientSearchCtrl,
          decoration: const InputDecoration(
            labelText: 'Search recent clients',
            helperText: 'Select a client to autofill name and email.',
            prefixIcon: Icon(Icons.manage_search_outlined),
          ),
          onChanged: (value) => setState(() => _clientSearch = value),
        ),
        if (_clientSearch.trim().isNotEmpty || suggestions.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ClientSuggestionPicker(
            suggestions: suggestions,
            enabled: !_submitting,
            onSelected: _selectClientSuggestion,
          ),
          const SizedBox(height: 14),
        ],
        TextFormField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Client or company name',
            prefixIcon: Icon(Icons.business_outlined),
          ),
          onChanged: (_) => setState(_syncMessageTemplateForClient),
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
                : 'Optional unless emailing the file link.',
            errorText: _stepHasAttention(1) && _sendEmail && !_clientEmailValid
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
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F9FF),
            border: Border.all(color: const Color(0xFFD6E8FF)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            children: [
              Icon(Icons.lock_outline, size: 17, color: AppColors.brandBlue),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Password required before files can be opened.',
                  style: TextStyle(
                    color: Color(0xFF253858),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
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
            final password = _passwordCtrl.text.trim();
            final confirm = (v ?? '').trim();
            if (confirm.isEmpty) return 'Re-enter the password.';
            if (confirm != password) return 'Passwords do not match.';
            return null;
          },
        ),
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
        if (!_showCustomExpiration)
          OutlinedButton.icon(
            onPressed: _submitting ? null : _showCustomExpirationFields,
            icon: const Icon(Icons.edit_calendar_outlined, size: 16),
            label: const Text('Custom expiration'),
          )
        else
          _CustomExpirationFields(
            dateController: _customDateCtrl,
            timeController: _customTimeCtrl,
            period: _customPeriod,
            enabled: !_submitting,
            errorText: _expirationError,
            previewText: _customExpirationPreview,
            onChanged: _syncCustomExpirationFromFields,
            onPeriodChanged: (value) {
              setState(() => _customPeriod = value);
              _syncCustomExpirationFromFields();
            },
            onQuickTime: _setCustomExpirationTime,
            onClear: _submitting
                ? null
                : () => setState(() {
                    _showCustomExpiration = false;
                    _customExpiresAt = null;
                    _expirationError = null;
                    _customDateCtrl.clear();
                    _customTimeCtrl.clear();
                  }),
          ),
      ],
    );
  }

  Widget _buildDeliverySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAccessNoteSection(),
        const SizedBox(height: 14),
        _DeliveryChoiceTile(
          selected: _sendEmail,
          icon: Icons.outgoing_mail,
          title: 'Email file link to client',
          subtitle: 'Password is never included in email.',
          onTap: _submitting
              ? null
              : () {
                  setState(() {
                    _sendEmail = true;
                    _createLinkOnly = false;
                    _attentionSteps.remove(3);
                  });
                },
        ),
        const SizedBox(height: 8),
        _DeliveryChoiceTile(
          selected: _createLinkOnly,
          icon: Icons.link_outlined,
          title: 'Copy link manually',
          subtitle: 'Copy the link after it is created.',
          onTap: _submitting
              ? null
              : () {
                  setState(() {
                    _createLinkOnly = true;
                    _sendEmail = false;
                    _attentionSteps.remove(3);
                  });
                },
        ),
        const SizedBox(height: 8),
        _DeliveryNote(passwordRequired: _passwordRequired),
        const SizedBox(height: 14),
        CheckboxListTile(
          value: _detailsProtected,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'Protect file details until password is entered',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: const Text(
            'Recommended. The email and file page will not reveal names, notes, or the file list until the client opens it with the password.',
          ),
          onChanged: _submitting
              ? null
              : (v) => setState(() => _detailsProtected = v != false),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: _notifyOnFirstDownload,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'Email me on first download',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: const Text(
            'Send one notification to the sender when the client downloads from this link for the first time.',
          ),
          onChanged: _submitting
              ? null
              : (v) => setState(() => _notifyOnFirstDownload = v == true),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: _includeMessage,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'Show a File Page Message',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: const Text(
            'Optional message shown with the files after access is verified.',
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
            'No file page message will be shown.',
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

  Widget _buildAccessNoteSection() {
    const noteOptions = [
      _defaultAccessNote,
      'Use the password sent by text message.',
      'Use the password discussed by phone.',
      'Contact our office if you do not have the password.',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFD),
        border: Border.all(color: const Color(0xFFE4E7EC)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.lock_person_outlined,
                size: 17,
                color: AppColors.brandBlue,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Password Page Message',
                  style: TextStyle(
                    color: Color(0xFF344054),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Optional message shown above the password field. Keep it generic and avoid file or client details.',
            style: TextStyle(
              color: Color(0xFF667085),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: noteOptions.map((text) {
              final selected = _accessNoteCtrl.text.trim() == text;
              return ChoiceChip(
                label: Text(text),
                selected: selected,
                showCheckmark: false,
                selectedColor: const Color(0xFFEAF2FF),
                backgroundColor: Colors.white,
                side: BorderSide(
                  color: selected
                      ? AppColors.brandBlue
                      : const Color(0xFFE4E7EC),
                ),
                labelStyle: TextStyle(
                  color: selected
                      ? AppColors.brandBlue
                      : const Color(0xFF344054),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
                onSelected: _submitting
                    ? null
                    : (_) => setState(() => _accessNoteCtrl.text = text),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _accessNoteCtrl,
            minLines: 2,
            maxLines: 3,
            maxLength: 220,
            decoration: const InputDecoration(
              labelText: 'Message shown above the password field',
              prefixIcon: Icon(Icons.info_outline),
              counterText: '',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'File Page Message',
          style: TextStyle(
            color: Color(0xFF344054),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 620;
            final cards = _shareMessageTemplates.map((template) {
              return _MessageTemplateOption(
                title: template.title,
                selected: _selectedTemplateId == template.id,
                onTap: _submitting
                    ? null
                    : () => setState(() {
                        _selectedTemplateId = template.id;
                        _messageCtrl.text = _applyShareTemplateTokens(
                          template.body,
                          _nameCtrl.text,
                        );
                      }),
              );
            }).toList();
            if (narrow) {
              return Column(
                children: [
                  for (int i = 0; i < cards.length; i++) ...[
                    cards[i],
                    if (i != cards.length - 1) const SizedBox(height: 8),
                  ],
                ],
              );
            }
            return Row(
              children: [
                for (int i = 0; i < cards.length; i++) ...[
                  Expanded(child: cards[i]),
                  if (i != cards.length - 1) const SizedBox(width: 8),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            border: Border.all(color: const Color(0xFFE4E7EC)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextFormField(
            controller: _messageCtrl,
            minLines: 5,
            maxLines: 8,
            decoration: InputDecoration(
              labelText: 'Message shown on the file page',
              alignLabelWithHint: true,
              prefixIcon: const Padding(
                padding: EdgeInsets.only(bottom: 72),
                child: Icon(Icons.notes_outlined),
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(0, 18, 12, 14),
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
        ),
        const SizedBox(height: 6),
        Text(
          _messageCtrl.text.trim().isEmpty
              ? 'No file page message will be shown.'
              : 'This message will appear with the files after access is verified.',
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
              _showCustomExpiration = false;
              _customDateCtrl.clear();
              _customTimeCtrl.clear();
            }),
    );
  }

  Widget _buildSummary(ThemeData theme) {
    final files = _readyFiles;
    final client = _nameCtrl.text.trim().isNotEmpty
        ? _nameCtrl.text.trim()
        : (_emailCtrl.text.trim().isNotEmpty ? _emailCtrl.text.trim() : '-');
    final issues = _reviewIssues;
    final primaryLabel = _readyToCreate
        ? (_sendEmail ? 'Send files' : 'Create file link')
        : 'Review missing items';
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
          Text(
            'Send summary',
            style: theme.textTheme.labelMedium?.copyWith(
              color: const Color(0xFF344054),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          _ReviewDetailGrid(
            details: [
              _ReviewDetail(
                icon: Icons.folder_outlined,
                label: 'Files',
                value: '${files.length} selected',
              ),
              _ReviewDetail(
                icon: Icons.person_outline,
                label: 'Recipient',
                value: client,
              ),
              _ReviewDetail(
                icon: Icons.lock_outline,
                label: 'Security',
                value: _detailsProtected
                    ? 'File names and notes are shown only after the password is verified.'
                    : 'Password required for downloads',
              ),
              if (_accessNoteCtrl.text.trim().isNotEmpty)
                _ReviewDetail(
                  icon: Icons.info_outline,
                  label: 'Password Page Message',
                  value: _accessNoteCtrl.text.trim(),
                ),
              _ReviewDetail(
                icon: Icons.schedule_outlined,
                label: 'Expires',
                value: _expirationLabel,
              ),
              _ReviewDetail(
                icon: _sendEmail ? Icons.outgoing_mail : Icons.link_outlined,
                label: 'Delivery',
                value: _sendEmail
                    ? 'Email will be sent'
                    : (_createLinkOnly
                          ? 'Copy link after creation'
                          : 'Choose delivery'),
              ),
              if (_emailCtrl.text.trim().isNotEmpty)
                _ReviewDetail(
                  icon: Icons.mail_outline,
                  label: 'Email',
                  value: _emailCtrl.text.trim(),
                ),
            ],
          ),
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
          LayoutBuilder(
            builder: (context, constraints) {
              final note = Text(
                _readyToCreate
                    ? 'This is the final step before the client receives access.'
                    : 'Resolve the missing items before sending.',
                style: const TextStyle(
                  color: Color(0xFF667085),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              );
              final button = FilledButton.icon(
                onPressed: _submitting ? null : _finish,
                icon: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _readyToCreate
                            ? Icons.send_outlined
                            : Icons.error_outline,
                        size: 16,
                      ),
                label: Text(primaryLabel),
              );
              if (constraints.maxWidth < 560) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    note,
                    const SizedBox(height: 10),
                    Align(alignment: Alignment.centerRight, child: button),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: note),
                  const SizedBox(width: 12),
                  button,
                ],
              );
            },
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
        : step.active
        ? AppColors.brandBlue
        : AppColors.brandBlue;
    final bg = step.attention
        ? const Color(0xFFFFF6F5)
        : step.complete
        ? const Color(0xFFF6FEF9)
        : step.active
        ? const Color(0xFFEAF2FF)
        : const Color(0xFFEAF2FF);
    final border = step.attention
        ? const Color(0xFFFDA29B)
        : step.complete
        ? const Color(0xFFABEFC6)
        : step.active
        ? AppColors.brandBlue
        : const Color(0xFFD6E8FF);
    final icon = step.attention
        ? Icons.error_outline
        : step.complete
        ? Icons.check_circle_outline
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
              step.label,
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
    required this.active,
    required this.complete,
    required this.attention,
    required this.onTap,
    this.optional = false,
  });

  final String label;
  final bool active;
  final bool complete;
  final bool attention;
  final bool optional;
  final VoidCallback onTap;
}

class _WizardNavigationBar extends StatelessWidget {
  const _WizardNavigationBar({
    required this.backEnabled,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.submitting,
    required this.onBack,
    required this.onPrimary,
  });

  final bool backEnabled;
  final String primaryLabel;
  final IconData primaryIcon;
  final bool submitting;
  final VoidCallback? onBack;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 560;
    final backButton = TextButton.icon(
      onPressed: backEnabled ? onBack : null,
      icon: const Icon(Icons.arrow_back, size: 16),
      label: const Text('Back'),
    );
    final primaryButton = FilledButton.icon(
      onPressed: submitting ? null : onPrimary,
      icon: Icon(primaryIcon, size: 16),
      label: Text(primaryLabel),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE4E7EC)),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 8,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: isNarrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 40, child: primaryButton),
                const SizedBox(height: 8),
                SizedBox(height: 38, child: backButton),
              ],
            )
          : Row(
              children: [
                backButton,
                const Spacer(),
                SizedBox(height: 40, child: primaryButton),
              ],
            ),
    );
  }
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
    this.showToggle = true,
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
  final bool showToggle;

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
                  if (showToggle)
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
    required this.maxListHeight,
    required this.onConfirm,
    required this.onClearAll,
    required this.confirmed,
  });

  final List<_SelectedShareFile> files;
  final String Function(int bytes) formatSize;
  final double maxListHeight;
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
        color: Colors.white,
        border: Border.all(
          color: confirmed ? const Color(0xFFD6E8FF) : const Color(0xFFE4E7EC),
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
                  Icons.outbox_outlined,
                  size: 18,
                  color: AppColors.brandBlue,
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
              constraints: BoxConstraints(maxHeight: maxListHeight),
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
                    icon: const Icon(Icons.task_alt_outlined, size: 16),
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

class _FileSourceAction extends StatelessWidget {
  const _FileSourceAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.emphasized,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool emphasized;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = emphasized
        ? AppColors.brandBlue
        : const Color(0xFFD0D5DD);
    final bg = emphasized ? const Color(0xFFEAF2FF) : Colors.white;
    final iconBg = emphasized ? AppColors.brandBlue : const Color(0xFFF2F4F7);
    final iconColor = emphasized ? Colors.white : AppColors.brandBlue;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: borderColor, width: emphasized ? 1.4 : 1),
            borderRadius: BorderRadius.circular(8),
            boxShadow: emphasized
                ? const [
                    BoxShadow(
                      color: Color(0x120B4EA2),
                      blurRadius: 10,
                      offset: Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
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
                      maxLines: 2,
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
            ],
          ),
        ),
      ),
    );
  }
}

class _AddFilesPane extends StatelessWidget {
  const _AddFilesPane({
    required this.source,
    required this.loadingFiles,
    required this.filteredFiles,
    required this.selectedFileKeys,
    required this.submitting,
    required this.searchController,
    required this.search,
    required this.formatSize,
    required this.dragging,
    required this.onChooseDevice,
    required this.onChooseFileBox,
    required this.onHideFileBox,
    required this.onDragEntered,
    required this.onDragExited,
    required this.onDropped,
    required this.onSearchChanged,
    required this.onToggle,
  });

  final String source;
  final bool loadingFiles;
  final List<_ShareableFile> filteredFiles;
  final Set<String> selectedFileKeys;
  final bool submitting;
  final TextEditingController searchController;
  final String search;
  final String Function(int bytes) formatSize;
  final bool dragging;
  final VoidCallback onChooseDevice;
  final VoidCallback onChooseFileBox;
  final VoidCallback onHideFileBox;
  final VoidCallback onDragEntered;
  final VoidCallback onDragExited;
  final Future<void> Function(DropDoneDetails details) onDropped;
  final ValueChanged<String> onSearchChanged;
  final void Function(_ShareableFile file, bool selected) onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE4E7EC)),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.add_to_drive_outlined,
                size: 18,
                color: AppColors.brandBlue,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Add files',
                  style: TextStyle(
                    color: Color(0xFF253858),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh File Box',
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: submitting ? null : onChooseFileBox,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _FileDropZone(
            dragging: dragging,
            enabled: !submitting,
            onChooseFiles: onChooseDevice,
            onDragEntered: onDragEntered,
            onDragExited: onDragExited,
            onDropped: onDropped,
          ),
          const SizedBox(height: 12),
          _FileBoxPickerPanel(
            searchController: searchController,
            search: search,
            loading: loadingFiles,
            files: source == 'fileBox' ? filteredFiles : const [],
            selectedKeys: selectedFileKeys,
            submitting: submitting,
            formatSize: formatSize,
            onBack: source == 'fileBox' && !submitting ? onHideFileBox : null,
            onRefresh: submitting ? null : onChooseFileBox,
            onSearchChanged: onSearchChanged,
            onToggle: onToggle,
            loaded: source == 'fileBox',
          ),
        ],
      ),
    );
  }
}

class _CustomExpirationFields extends StatelessWidget {
  const _CustomExpirationFields({
    required this.dateController,
    required this.timeController,
    required this.period,
    required this.enabled,
    required this.errorText,
    required this.previewText,
    required this.onChanged,
    required this.onPeriodChanged,
    required this.onQuickTime,
    required this.onClear,
  });

  final TextEditingController dateController;
  final TextEditingController timeController;
  final String period;
  final bool enabled;
  final String? errorText;
  final String? previewText;
  final VoidCallback onChanged;
  final ValueChanged<String> onPeriodChanged;
  final void Function(int hour, int minute, String period) onQuickTime;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasError ? const Color(0xFFFFF6F5) : Colors.white,
        border: Border.all(
          color: hasError ? const Color(0xFFFDA29B) : const Color(0xFFE4E7EC),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Custom expiration',
            style: TextStyle(
              color: Color(0xFF344054),
              fontWeight: FontWeight.w900,
            ),
          ),
          if (onClear != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Use quick expiration'),
              ),
            ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 520;
              final dateField = TextFormField(
                controller: dateController,
                enabled: enabled,
                keyboardType: TextInputType.datetime,
                inputFormatters: const [_DateSlashInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Date',
                  hintText: 'MMDDYYYY',
                  helperText: 'Type numbers only.',
                  prefixIcon: Icon(Icons.calendar_month_outlined),
                ),
                onChanged: (_) => onChanged(),
              );
              final timeField = TextFormField(
                controller: timeController,
                enabled: enabled,
                keyboardType: TextInputType.datetime,
                inputFormatters: const [_TimeColonInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Time',
                  hintText: 'HMM',
                  helperText: 'Example: 930',
                  prefixIcon: Icon(Icons.schedule_outlined),
                ),
                onChanged: (_) => onChanged(),
              );
              final periodField = _AmPmSelector(
                value: period,
                enabled: enabled,
                onChanged: onPeriodChanged,
              );

              if (narrow) {
                return Column(
                  children: [
                    dateField,
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: timeField),
                        const SizedBox(width: 8),
                        periodField,
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(flex: 6, child: dateField),
                  const SizedBox(width: 10),
                  Expanded(flex: 4, child: timeField),
                  const SizedBox(width: 8),
                  periodField,
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QuickTimeChip(
                label: '9:00 AM',
                onTap: enabled ? () => onQuickTime(9, 0, 'AM') : null,
              ),
              _QuickTimeChip(
                label: '5:00 PM',
                onTap: enabled ? () => onQuickTime(5, 0, 'PM') : null,
              ),
              _QuickTimeChip(
                label: 'End of day',
                onTap: enabled ? () => onQuickTime(11, 59, 'PM') : null,
              ),
            ],
          ),
          if (hasError) ...[
            const SizedBox(height: 8),
            Text(
              errorText!,
              style: const TextStyle(
                color: Color(0xFFB42318),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            _ExpirationPreviewText(
              text:
                  previewText ??
                  'Enter a date and time, or use a quick expiration above.',
            ),
          ],
        ],
      ),
    );
  }
}

class _DateSlashInputFormatter extends TextInputFormatter {
  const _DateSlashInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limited = digits.length > 8 ? digits.substring(0, 8) : digits;
    final buffer = StringBuffer();

    for (var i = 0; i < limited.length; i++) {
      if (i == 2 || i == 4) buffer.write('/');
      buffer.write(limited[i]);
    }

    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _ExpirationPreviewText extends StatelessWidget {
  const _ExpirationPreviewText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ready = text.startsWith('Expires ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          ready ? Icons.check_circle_outline : Icons.info_outline,
          size: 16,
          color: ready ? const Color(0xFF067647) : const Color(0xFF667085),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: ready ? const Color(0xFF067647) : const Color(0xFF667085),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickTimeChip extends StatelessWidget {
  const _QuickTimeChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      visualDensity: VisualDensity.compact,
      label: Text(label),
      avatar: const Icon(Icons.schedule_outlined, size: 15),
      onPressed: onTap,
      labelStyle: const TextStyle(
        color: Color(0xFF344054),
        fontWeight: FontWeight.w800,
      ),
      backgroundColor: Colors.white,
      side: const BorderSide(color: Color(0xFFE4E7EC)),
    );
  }
}

class _TimeColonInputFormatter extends TextInputFormatter {
  const _TimeColonInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limited = digits.length > 4 ? digits.substring(0, 4) : digits;

    String text;
    if (limited.length <= 2) {
      text = limited;
    } else if (limited.length == 3) {
      text = '${limited.substring(0, 1)}:${limited.substring(1)}';
    } else {
      text = '${limited.substring(0, 2)}:${limited.substring(2)}';
    }

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _MessageTemplateOption extends StatelessWidget {
  const _MessageTemplateOption({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEAF2FF) : Colors.white,
            border: Border.all(
              color: selected ? AppColors.brandBlue : const Color(0xFFE4E7EC),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.check_circle_outline
                    : Icons.description_outlined,
                size: 18,
                color: selected ? AppColors.brandBlue : const Color(0xFF667085),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? AppColors.brandBlue
                        : const Color(0xFF344054),
                    fontWeight: FontWeight.w900,
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

class _AmPmSelector extends StatelessWidget {
  const _AmPmSelector({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'AM', label: Text('AM')),
        ButtonSegment(value: 'PM', label: Text('PM')),
      ],
      selected: {value},
      onSelectionChanged: enabled
          ? (selected) => onChanged(selected.first)
          : null,
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
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
    final color = dragging ? AppColors.brandBlue : const Color(0xFF8BB8F8);
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
          constraints: const BoxConstraints(minHeight: 170),
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
          decoration: BoxDecoration(
            color: dragging ? const Color(0xFFEAF2FF) : const Color(0xFFF5F9FF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color, width: dragging ? 1.8 : 1.3),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0F0B4EA2),
                blurRadius: 12,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: dragging ? AppColors.brandBlue : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD6E8FF)),
                ),
                child: Icon(
                  Icons.cloud_upload_outlined,
                  color: dragging ? Colors.white : AppColors.brandBlue,
                  size: 28,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Drop files here or click to upload',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF253858),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Files selected here are added to the send list.',
                textAlign: TextAlign.center,
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
    this.onRefresh,
    required this.loaded,
  });

  final TextEditingController searchController;
  final String search;
  final bool loading;
  final VoidCallback? onRefresh;
  final bool loaded;
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
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 560;
              return Column(
                children: [
                  if (!compact) ...[
                    Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      color: const Color(0xFFF9FAFB),
                      child: Row(
                        children: const [
                          SizedBox(width: 34),
                          Expanded(child: _PickerHeaderText('Name')),
                          SizedBox(
                            width: 112,
                            child: _PickerHeaderText('Client'),
                          ),
                          SizedBox(width: 72, child: _PickerHeaderText('Size')),
                          SizedBox(width: 44),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE4E7EC)),
                  ],
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: loading
                        ? const _FileBoxPickerLoading()
                        : files.isEmpty
                        ? _FileBoxPickerEmpty(search: search)
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: files.length,
                            separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              color: Color(0xFFE4E7EC),
                            ),
                            itemBuilder: (context, index) {
                              final file = files[index];
                              final selected = selectedKeys.contains(file.key);
                              return _FileBoxPickerRow(
                                file: file,
                                selected: selected,
                                submitting: submitting,
                                formatSize: formatSize,
                                compact: compact,
                                onToggle: (value) => onToggle(file, value),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
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
    required this.compact,
    required this.onToggle,
  });

  final _ShareableFile file;
  final bool selected;
  final bool submitting;
  final String Function(int bytes) formatSize;
  final bool compact;
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
                      maxLines: compact ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF101828),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                            if (businessOrEmail.isNotEmpty) businessOrEmail,
                            if (compact && file.clientName.isNotEmpty)
                              file.clientName,
                            if (compact) formatSize(file.sizeBytes),
                          ].isEmpty
                          ? 'File Box'
                          : [
                              if (businessOrEmail.isNotEmpty) businessOrEmail,
                              if (compact && file.clientName.isNotEmpty)
                                file.clientName,
                              if (compact) formatSize(file.sizeBytes),
                            ].join(' - '),
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
              if (!compact) ...[
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
              ],
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

class _ReviewDetail {
  const _ReviewDetail({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}

class _ReviewDetailGrid extends StatelessWidget {
  const _ReviewDetailGrid({required this.details});

  final List<_ReviewDetail> details;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        border: Border.all(color: const Color(0xFFE4E7EC)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          for (int i = 0; i < details.length; i++) ...[
            _ReviewDetailTile(detail: details[i]),
            if (i != details.length - 1)
              const Divider(height: 1, color: Color(0xFFE4E7EC)),
          ],
        ],
      ),
    );
  }
}

class _ReviewDetailTile extends StatelessWidget {
  const _ReviewDetailTile({required this.detail});

  final _ReviewDetail detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(detail.icon, size: 17, color: AppColors.brandBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.label,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail.value,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF253858),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
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
              'Ready to create file link',
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
                Text(
                  formatSize(file.sizeBytes),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 11.5,
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.verified_user_outlined,
                color: AppColors.brandBlue,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  sendEmail
                      ? 'The file link was emailed to the client.'
                      : 'Copy this file link and provide the password separately.',
                  style: const TextStyle(
                    color: Color(0xFF475467),
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SelectableText(url),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: sendEmail
                ? [
                    FilledButton.icon(
                      onPressed: onDone,
                      icon: const Icon(Icons.send_outlined, size: 16),
                      label: const Text('Sent files'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onCopy,
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy link'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onCreateAnother,
                      icon: const Icon(Icons.add_link_outlined, size: 16),
                      label: const Text('Create another'),
                    ),
                  ]
                : [
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
                    TextButton(
                      onPressed: onDone,
                      child: const Text('Sent files'),
                    ),
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

class _ClientSuggestionPicker extends StatelessWidget {
  const _ClientSuggestionPicker({
    required this.suggestions,
    required this.enabled,
    required this.onSelected,
  });

  final List<_ClientSuggestion> suggestions;
  final bool enabled;
  final ValueChanged<_ClientSuggestion> onSelected;

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          border: Border.all(color: const Color(0xFFE4E7EC)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'No matching recent clients found.',
          style: TextStyle(
            color: Color(0xFF667085),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE4E7EC)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          for (int i = 0; i < suggestions.length; i++) ...[
            _ClientSuggestionRow(
              suggestion: suggestions[i],
              enabled: enabled,
              onTap: () => onSelected(suggestions[i]),
            ),
            if (i != suggestions.length - 1)
              const Divider(height: 1, color: Color(0xFFE4E7EC)),
          ],
        ],
      ),
    );
  }
}

class _ClientSuggestionRow extends StatelessWidget {
  const _ClientSuggestionRow({
    required this.suggestion,
    required this.enabled,
    required this.onTap,
  });

  final _ClientSuggestion suggestion;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (suggestion.businessName.trim().isNotEmpty &&
          suggestion.businessName.trim() != suggestion.displayName)
        suggestion.businessName.trim(),
      if (suggestion.email.trim().isNotEmpty) suggestion.email.trim(),
    ].join(' - ');

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Icon(
              Icons.person_search_outlined,
              size: 18,
              color: AppColors.brandBlue,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suggestion.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF253858),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.north_west_outlined,
              size: 16,
              color: Color(0xFF667085),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClientSuggestion {
  const _ClientSuggestion({
    required this.name,
    required this.email,
    required this.businessName,
  });

  final String name;
  final String email;
  final String businessName;

  String get displayName {
    if (name.trim().isNotEmpty) return name.trim();
    if (businessName.trim().isNotEmpty) return businessName.trim();
    return email.trim();
  }
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
